import json
import logging

from django.contrib.auth import authenticate, login, logout
from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_http_methods, require_POST
from unique_names_generator import get_random_name
from unique_names_generator.data import ADJECTIVES, ANIMALS

from api.forms.auth import LoginForm, ProfileForm, SignupForm
from api.models import Activity, User

logger = logging.getLogger('wide_event')


def _generate_subname():
  """Generate a unique subname like 'cool-tiger' using unique-names-generator."""
  for _ in range(100):  # safety: avoid infinite loop
    name = get_random_name(combo=[ADJECTIVES, ANIMALS], separator='-', style='lowercase')
    if not User.objects.filter(subname=name).exists():
      return name
  raise RuntimeError('Could not generate a unique subname after 100 attempts')


@require_http_methods(['GET', 'POST'])
def signup_view(request):
  """Render signup page (GET) or process signup (POST)."""
  if request.user.is_authenticated:
    return redirect('/')

  if request.method == 'GET':
    return render(request, 'auth/signup.html', {'form': SignupForm()})

  form = SignupForm(request.POST)
  if not form.is_valid():
    return render(request, 'auth/signup.html', {'form': form})

  subname = _generate_subname()
  user = User.objects.create_user(
    subname=subname,
    password=form.cleaned_data['password'],
  )

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
    return render(request, 'auth/login.html', {'form': LoginForm()})

  form = LoginForm(request.POST)
  if not form.is_valid():
    return render(request, 'auth/login.html', {'form': form})

  user = authenticate(
    request,
    username=form.cleaned_data['subname'],
    password=form.cleaned_data['password'],
  )
  if user is None:
    form.add_error(None, 'Invalid subname or password.')
    return render(request, 'auth/login.html', {'form': form})

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
    return render(request, 'auth/onboarding/profile.html', {'form': form})

  form = ProfileForm(request.POST, instance=request.user)
  if form.is_valid():
    form.save()
    return redirect('/api/auth/onboarding/wallet/')
  return render(request, 'auth/onboarding/profile.html', {'form': form})


def onboarding_wallet_view(request):
  """Onboarding step 2: connect and verify wallet."""
  if not request.user.is_authenticated:
    return redirect('/api/auth/signup/')
  return render(request, 'auth/onboarding/wallet.html')


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

  # Signature verification is implemented in Step 5 (web3_utils)
  # For now, accept the address and create a LinkedAddress
  from api.models import BurntAddress, LinkedAddress

  # Check if address is burnt
  if BurntAddress.objects.filter(address=address).exists():
    return HttpResponse('This address has been burnt and cannot be re-linked', status=403)

  # Check if already linked to another user
  existing = LinkedAddress.objects.filter(address=address).exclude(user=request.user).first()
  if existing:
    return HttpResponse('Address already linked to another account', status=409)

  # Create or update the linked address
  linked, created = LinkedAddress.objects.update_or_create(
    user=request.user,
    address=address,
    defaults={
      'is_primary': not request.user.addresses.filter(is_primary=True).exists(),
    },
  )

  # Log activity
  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.WALLET_LINKED,
    message=f'Linked wallet {address[:8]}...{address[-4:]}',
    metadata={'address': address, 'created': created},
  )

  request._wide_event['extra']['linked_address'] = address

  if request.htmx:
    return render(request, 'auth/onboarding/wallet.html', {
      'linked_address': linked,
      'success': True,
    })
  return redirect('/')
