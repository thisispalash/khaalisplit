"""
Profile-related API views.

Handles payment preferences (stored locally + mirrored to ENS text records on-chain).
Local DB is the source of truth for UI; on-chain is async/fire-and-forget.
"""
import logging

from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.views.decorators.http import require_http_methods

from api.utils.ens_codec import subname_node
from api.utils.web3_utils import TOKEN_ADDRESSES, send_tx

logger = logging.getLogger('wide_event')

# Human-readable chain names for the UI
CHAIN_OPTIONS = [
  ('11155111', 'Sepolia'),
  ('84532', 'Base Sepolia'),
  ('421614', 'Arbitrum Sepolia'),
  ('11155420', 'Optimism Sepolia'),
  ('5042002', 'Arc Testnet'),
]

FLOW_OPTIONS = [
  ('gateway', 'Gateway (cross-chain)'),
  ('authorization', 'Direct (same-chain)'),
]

CHAIN_DISPLAY = {v: label for v, label in CHAIN_OPTIONS}


def _read_payment_prefs(user) -> dict:
  """
  Read payment preferences from local DB (LinkedAddress model).
  This is instant and doesn't depend on RPC availability.
  """
  defaults = {
    'payment_flow': 'gateway',
    'payment_chain': '11155111',
    'payment_token': '',
  }

  primary = user.addresses.filter(is_primary=True).first()
  if primary:
    defaults['payment_chain'] = str(primary.chain_id)
    if primary.token_addr:
      defaults['payment_token'] = primary.token_addr
    else:
      # Look up USDC for the chain
      usdc = TOKEN_ADDRESSES.get(primary.chain_id, {}).get('USDC', '')
      if usdc:
        defaults['payment_token'] = usdc

  return defaults


def _prefs_context(user, editing=False) -> dict:
  """Build template context for payment preferences partial."""
  prefs = _read_payment_prefs(user)
  has_wallet = user.addresses.filter(is_primary=True).exists()

  return {
    'payment_flow': prefs['payment_flow'],
    'payment_chain': prefs['payment_chain'],
    'payment_token': prefs['payment_token'],
    'chain_display': CHAIN_DISPLAY.get(prefs['payment_chain'], 'Unknown'),
    'chain_options': CHAIN_OPTIONS,
    'flow_options': FLOW_OPTIONS,
    'has_wallet': has_wallet,
    'editing': editing,
  }


@login_required(login_url='/api/auth/login/')
@require_http_methods(['GET', 'POST'])
def payment_preferences(request):
  """
  GET:  Render the payment preferences partial (read-only or edit mode).
  POST: Update payment preferences locally and mirror to chain (non-blocking).
  """
  if request.method == 'GET':
    editing = request.GET.get('edit') == '1'
    ctx = _prefs_context(request.user, editing=editing)
    return render(request, 'partials/payment_preferences.html', ctx)

  # POST — update preferences
  flow = request.POST.get('payment_flow', 'gateway')
  chain = request.POST.get('payment_chain', '11155111')

  # Validate
  valid_flows = {v for v, _ in FLOW_OPTIONS}
  valid_chains = {v for v, _ in CHAIN_OPTIONS}

  if flow not in valid_flows:
    flow = 'gateway'
  if chain not in valid_chains:
    chain = '11155111'

  chain_int = int(chain)
  usdc_addr = TOKEN_ADDRESSES.get(chain_int, {}).get('USDC', '')

  # Save locally first (instant, reliable)
  primary = request.user.addresses.filter(is_primary=True).first()
  if primary:
    primary.chain_id = chain_int
    if usdc_addr:
      primary.token_addr = usdc_addr
    primary.save(update_fields=['chain_id', 'token_addr'])

  # Mirror to chain (fire-and-forget, non-blocking)
  node = subname_node(request.user.subname)
  try:
    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.flow', flow)
  except Exception:
    logger.exception(f'setText payment.flow failed for {request.user.subname}')

  try:
    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.chain', chain)
  except Exception:
    logger.exception(f'setText payment.chain failed for {request.user.subname}')

  try:
    if usdc_addr:
      send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.token', usdc_addr)
  except Exception:
    logger.exception(f'setText payment.token failed for {request.user.subname}')

  logger.info(
    f'Payment prefs updated for {request.user.subname}: '
    f'flow={flow} chain={chain} token={usdc_addr}'
  )

  # Return the updated (read-only) partial — reads from local DB, instant
  ctx = _prefs_context(request.user, editing=False)
  return render(request, 'partials/payment_preferences.html', ctx)
