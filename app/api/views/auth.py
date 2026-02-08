import json
import logging

from django.conf import settings
from django.contrib.auth import authenticate, login, logout
from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_http_methods, require_POST
from unique_names_generator import get_random_name
from unique_names_generator.data import ADJECTIVES, ANIMALS
from web3 import Web3

from api.forms.auth import LoginForm, ProfileForm, SignupForm
from api.models import Activity, User
from api.utils.ens_codec import subname_node
from api.utils.web3_utils import TOKEN_ADDRESSES, send_tx

logger = logging.getLogger('wide_event')


def _generate_subname():
  """Generate a unique subname like 'cool-tiger' using unique-names-generator."""
  for _ in range(100):  # safety: avoid infinite loop
    name = get_random_name(combo=[ADJECTIVES, ANIMALS], separator='-', style='lowercase')
    if not User.objects.filter(subname=name).exists():
      return name
  raise RuntimeError('Could not generate a unique subname after 100 attempts')


def _get_backend_address() -> str:
  """Derive the backend wallet address from BACKEND_PRIVATE_KEY."""
  from eth_account import Account
  pk = settings.BACKEND_PRIVATE_KEY
  if not pk:
    return ''
  return Account.from_key(pk).address


def _register_subname_onchain(user):
  """
  Register a subname on-chain after signup.

  Calls khaaliSplitSubnames.register(label, owner) where owner is
  the backend address (user hasn't linked a wallet yet).

  Non-blocking: if the tx fails, signup still succeeds.
  """
  try:
    backend_addr = _get_backend_address()
    if not backend_addr:
      logger.warning(f'Skipping subname registration — no BACKEND_PRIVATE_KEY')
      return

    # Register the subname with the backend as initial owner
    tx_hash = send_tx(
      'subnames', 'register',
      user.subname,
      Web3.to_checksum_address(backend_addr),
    )

    Activity.objects.create(
      user=user,
      action_type=Activity.ActionType.FRIEND_REQUEST,  # reuse until we add a SUBNAME_REGISTERED type
      message=f'Subname {user.subname}.khaalisplit.eth registered on-chain',
      metadata={'tx_hash': tx_hash},
    )

    logger.info(f'Subname registered: {user.subname} tx={tx_hash}')

    # If display_name is set, also store it as a text record
    if user.display_name:
      node = subname_node(user.subname)
      send_tx('subnames', 'setText', node, 'display_name', user.display_name)

  except Exception:
    logger.exception(f'Subname registration failed for {user.subname}')


def _set_onchain_wallet_records(user, address: str, chain_id: int):
  """
  After wallet linking, set on-chain records:
  1. setAddr — so the subname resolves to the user's wallet
  2. setText — default payment preferences (flow, token, chain)
  3. setUserNode — link wallet to ENS node in reputation contract

  Non-blocking: if any tx fails, the wallet link still succeeds.
  """
  node = subname_node(user.subname)

  try:
    # 1. Set addr record so subname resolves to user's wallet
    tx_hash = send_tx(
      'subnames', 'setAddr',
      node,
      Web3.to_checksum_address(address),
    )
    logger.info(f'setAddr tx={tx_hash} for {user.subname}')
  except Exception:
    logger.exception(f'setAddr failed for {user.subname}')

  try:
    # 2. Set default payment preferences as text records
    usdc_addr = TOKEN_ADDRESSES.get(chain_id, {}).get('USDC', '')

    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.flow', 'gateway')
    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.chain', str(chain_id))
    if usdc_addr:
      send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.token', usdc_addr)

    logger.info(f'Payment prefs set for {user.subname} chain={chain_id}')
  except Exception:
    logger.exception(f'Payment prefs setText failed for {user.subname}')

  try:
    # 3. Link wallet to ENS node in reputation contract
    send_tx(
      'reputation', 'setUserNode',
      Web3.to_checksum_address(address),
      node,
    )
    logger.info(f'setUserNode tx for {user.subname}')
  except Exception:
    logger.exception(f'setUserNode failed for {user.subname}')


@require_http_methods(['GET', 'POST'])
def signup_view(request):
  """Render signup page (GET) or process signup (POST)."""
  if request.user.is_authenticated:
    return redirect('/')

  if request.method == 'GET':
    return render(request, 'pages/signup.html', {'form': SignupForm()})

  form = SignupForm(request.POST)
  if not form.is_valid():
    return render(request, 'pages/signup.html', {'form': form})

  subname = _generate_subname()
  user = User.objects.create_user(
    subname=subname,
    password=form.cleaned_data['password'],
  )

  # Register subname on-chain (non-blocking — signup succeeds even if tx fails)
  _register_subname_onchain(user)

  # Log activity
  Activity.objects.create(
    user=user,
    action_type=Activity.ActionType.FRIEND_REQUEST,  # reuse for "account created"
    message=f'Welcome to khaaliSplit, {subname}!',
  )

  # Log the user in and enrich wide event
  login(request, user)
  request._wide_event['extra']['signup_subname'] = subname

  return redirect('/api/auth/onboarding/profile/')


@require_http_methods(['GET', 'POST'])
def login_view(request):
  """Render login page (GET) or process login (POST)."""
  if request.user.is_authenticated:
    return redirect('/')

  if request.method == 'GET':
    return render(request, 'pages/login.html', {'form': LoginForm()})

  form = LoginForm(request.POST)
  if not form.is_valid():
    return render(request, 'pages/login.html', {'form': form})

  user = authenticate(
    request,
    username=form.cleaned_data['subname'],
    password=form.cleaned_data['password'],
  )
  if user is None:
    form.add_error(None, 'Invalid subname or password.')
    return render(request, 'pages/login.html', {'form': form})

  login(request, user)
  request._wide_event['extra']['login_subname'] = user.subname
  return redirect('/')


@require_POST
def logout_view(request):
  """Log the user out and redirect to home."""
  if request.user.is_authenticated:
    request._wide_event['extra']['logout_subname'] = request.user.subname
  logout(request)
  return redirect('/')


@require_http_methods(['GET', 'POST'])
def onboarding_profile_view(request):
  """Onboarding step 1: edit profile (display name, avatar)."""
  if not request.user.is_authenticated:
    return redirect('/api/auth/signup/')

  if request.method == 'GET':
    form = ProfileForm(instance=request.user)
    return render(request, 'pages/onboarding-profile.html', {'form': form})

  form = ProfileForm(request.POST, instance=request.user)
  if form.is_valid():
    form.save()
    return redirect('/api/auth/onboarding/wallet/')
  return render(request, 'pages/onboarding-profile.html', {'form': form})


def onboarding_wallet_view(request):
  """Onboarding step 2: connect and verify wallet."""
  if not request.user.is_authenticated:
    return redirect('/api/auth/signup/')
  return render(request, 'pages/onboarding-wallet.html')


@require_POST
def verify_signature(request):
  """
  Verify a signed message to link a wallet address.
  Expects JSON body: { address, signature, message }
  """
  if not request.user.is_authenticated:
    return HttpResponse(status=401)

  try:
    data = json.loads(request.body)
    address = data.get('address', '')
    signature = data.get('signature', '')
    message = data.get('message', '')
  except (json.JSONDecodeError, AttributeError):
    return HttpResponse('Invalid JSON', status=400)

  if not all([address, signature, message]):
    return HttpResponse('Missing address, signature, or message', status=400)

  # Verify the signature matches the claimed address
  from api.models import BurntAddress, LinkedAddress
  from api.utils.web3_utils import recover_pubkey, verify_signature as verify_sig

  if not verify_sig(address, message, signature):
    return HttpResponse('Signature verification failed', status=400)

  # Recover public key for ECDH
  try:
    pub_key = recover_pubkey(message, signature)
  except Exception:
    pub_key = ''

  # Check if address is burnt
  if BurntAddress.objects.filter(address=address).exists():
    return HttpResponse('This address has been burnt and cannot be re-linked', status=403)

  # Check if already linked to another user
  existing = LinkedAddress.objects.filter(address=address).exclude(user=request.user).first()
  if existing:
    return HttpResponse('Address already linked to another account', status=409)

  # Create or update the linked address
  is_first_address = not request.user.addresses.filter(is_primary=True).exists()
  linked, created = LinkedAddress.objects.update_or_create(
    user=request.user,
    address=address,
    defaults={
      'is_primary': is_first_address,
      'pub_key': pub_key,
    },
  )

  # If this is the primary address, set on-chain records
  if linked.is_primary:
    chain_id = linked.chain_id  # defaults to 11155111 (Sepolia)
    _set_onchain_wallet_records(request.user, address, chain_id)

  # Log activity
  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.WALLET_LINKED,
    message=f'Linked wallet {address[:8]}...{address[-4:]}',
    metadata={'address': address, 'created': created},
  )

  request._wide_event['extra']['linked_address'] = address

  if request.htmx:
    return render(request, 'pages/onboarding-wallet.html', {
      'linked_address': linked,
      'success': True,
    })
  return redirect('/')


@require_POST
def register_pubkey(request):
  """
  Register a user's public key on-chain via the backend wallet.
  Expects JSON body: { address }
  The pub_key is already stored from verify_signature.
  """
  if not request.user.is_authenticated:
    return HttpResponse(status=401)

  try:
    data = json.loads(request.body)
    address = data.get('address', '')
  except (json.JSONDecodeError, AttributeError):
    return HttpResponse('Invalid JSON', status=400)

  if not address:
    return HttpResponse('Missing address', status=400)

  from api.models import LinkedAddress
  from api.utils.web3_utils import register_pubkey_onchain

  linked = LinkedAddress.objects.filter(user=request.user, address=address).first()
  if not linked:
    return HttpResponse('Address not linked to your account', status=404)

  if linked.pub_key_registered:
    return HttpResponse('Public key already registered', status=409)

  if not linked.pub_key:
    return HttpResponse('No public key found. Re-verify your signature.', status=400)

  try:
    tx_hash = register_pubkey_onchain(address, linked.pub_key)
    linked.pub_key_registered = True
    linked.save()

    Activity.objects.create(
      user=request.user,
      action_type=Activity.ActionType.PUBKEY_REGISTERED,
      message=f'Public key registered for {address[:8]}...{address[-4:]}',
      metadata={'address': address, 'tx_hash': tx_hash},
    )

    request._wide_event['extra']['pubkey_tx'] = tx_hash
    return HttpResponse(json.dumps({'tx_hash': tx_hash}), content_type='application/json')
  except Exception as e:
    logger.exception('registerPubKey failed')
    return HttpResponse(f'Registration failed: {e}', status=500)
