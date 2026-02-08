"""
Profile-related API views.

Handles payment preferences (stored as ENS text records on-chain).
"""
import logging

from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.views.decorators.http import require_http_methods
from web3 import Web3

from api.utils.ens_codec import subname_node
from api.utils.web3_utils import CHAIN_IDS, TOKEN_ADDRESSES, call_view, send_tx

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
  Read payment preferences from on-chain text records.

  Falls back to defaults if records can't be read (e.g., no subname
  registered yet, or RPC unavailable).
  """
  defaults = {
    'payment_flow': 'gateway',
    'payment_chain': '11155111',
    'payment_token': '',
  }

  try:
    node = subname_node(user.subname)

    flow = call_view('subnames', 'text', node, 'com.khaalisplit.payment.flow')
    chain = call_view('subnames', 'text', node, 'com.khaalisplit.payment.chain')
    token = call_view('subnames', 'text', node, 'com.khaalisplit.payment.token')

    if flow:
      defaults['payment_flow'] = flow
    if chain:
      defaults['payment_chain'] = chain
    if token:
      defaults['payment_token'] = token

  except Exception:
    logger.debug(f'Could not read payment prefs for {user.subname}, using defaults')

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
  POST: Update payment preferences on-chain and return updated partial.
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

  # Look up USDC address for the selected chain
  chain_int = int(chain)
  usdc_addr = TOKEN_ADDRESSES.get(chain_int, {}).get('USDC', '')

  node = subname_node(request.user.subname)

  try:
    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.flow', flow)
    send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.chain', chain)
    if usdc_addr:
      send_tx('subnames', 'setText', node, 'com.khaalisplit.payment.token', usdc_addr)

    logger.info(
      f'Payment prefs updated for {request.user.subname}: '
      f'flow={flow} chain={chain} token={usdc_addr}'
    )
  except Exception:
    logger.exception(f'Payment prefs update failed for {request.user.subname}')

  # Return the updated (read-only) partial
  ctx = _prefs_context(request.user, editing=False)
  return render(request, 'partials/payment_preferences.html', ctx)
