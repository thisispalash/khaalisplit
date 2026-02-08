"""
Settlement views — debt summary, initiation, status polling, and
settle-for-user endpoints (authorization + gateway flows).
"""
import json
import logging

from django.contrib.auth.decorators import login_required
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET, require_POST
from web3 import Web3

from api.models import (
  Activity,
  CachedExpense,
  CachedGroup,
  CachedGroupMember,
  CachedSettlement,
  LinkedAddress,
  User,
)
from api.utils.debt_simplifier import compute_group_debts
from api.utils.ens_codec import subname_node
from api.utils.web3_utils import send_tx

logger = logging.getLogger('wide_event')


def _is_group_member(user, group):
  """Check if user is an accepted member of the group."""
  return CachedGroupMember.objects.filter(
    group=group,
    user=user,
    status=CachedGroupMember.Status.ACCEPTED,
  ).exists()


@login_required(login_url='/api/auth/login/')
@require_GET
def debts(request, group_id):
  """Compute and return simplified debts for a group (HTMX partial)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  if not _is_group_member(request.user, group):
    return HttpResponse('Not a member', status=403)

  expenses = CachedExpense.objects.filter(group=group)
  debt_list = compute_group_debts(expenses)

  # Enrich with user subnames
  address_to_user = {}
  for member in CachedGroupMember.objects.filter(
    group=group
  ).select_related('user'):
    if member.member_address:
      address_to_user[member.member_address.lower()] = member.user

  enriched_debts = []
  for debt in debt_list:
    from_user = address_to_user.get(debt['from_address'].lower())
    to_user = address_to_user.get(debt['to_address'].lower())
    enriched_debts.append({
      **debt,
      'from_subname': from_user.subname if from_user else debt['from_address'][:10] + '...',
      'to_subname': to_user.subname if to_user else debt['to_address'][:10] + '...',
    })

  # Check which debts involve the current user
  primary_addr = request.user.addresses.filter(is_primary=True).first()
  user_address = primary_addr.address.lower() if primary_addr else ''

  for debt in enriched_debts:
    debt['is_payer'] = debt['from_address'].lower() == user_address
    debt['is_payee'] = debt['to_address'].lower() == user_address

  return render(request, 'partials/debt_summary.html', {
    'debts': enriched_debts,
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def initiate(request, group_id):
  """
  Record a settlement initiation. The actual on-chain tx is done
  client-side via wallet.js (settleWithPermit). This endpoint
  receives the tx_hash after submission.
  """
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return JsonResponse({'error': 'Group not found'}, status=404)

  if not _is_group_member(request.user, group):
    return JsonResponse({'error': 'Not a member'}, status=403)

  tx_hash = request.POST.get('tx_hash', '').strip()
  to_address = request.POST.get('to_address', '').strip()
  amount = request.POST.get('amount', '0')
  token = request.POST.get('token', 'usdc')
  source_chain = request.POST.get('source_chain', '11155111')
  dest_chain = request.POST.get('dest_chain', '11155111')

  if not tx_hash:
    return JsonResponse({'error': 'Missing tx_hash'}, status=400)

  primary_addr = request.user.addresses.filter(is_primary=True).first()

  # Look up recipient user
  to_user = None
  to_linked = LinkedAddress.objects.filter(
    address__iexact=to_address
  ).select_related('user').first()
  if to_linked:
    to_user = to_linked.user

  settlement = CachedSettlement.objects.create(
    tx_hash=tx_hash,
    from_user=request.user,
    from_address=primary_addr.address if primary_addr else '',
    to_address=to_address,
    to_user=to_user,
    token=token,
    amount=amount,
    source_chain=int(source_chain),
    dest_chain=int(dest_chain),
    status=CachedSettlement.Status.SUBMITTED,
    group=group,
  )

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.SETTLEMENT_INITIATED,
    group_id=group.group_id,
    settlement_hash=tx_hash,
    message=f'Initiated settlement of {amount} {token} to {to_address[:10]}...',
  )

  request._wide_event['extra']['settlement_initiated'] = tx_hash

  return JsonResponse({
    'status': 'ok',
    'tx_hash': tx_hash,
    'settlement_status': settlement.status,
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def settle_for_user(request):
  """
  POST /api/settle/for-user/

  Backend-relayed settlement. Accepts two types:
  - type=authorization: ERC-3009 transferWithAuthorization flow
    Requires: to_subname, amount, signature, auth_from, valid_after, valid_before, nonce
  - type=gateway: Circle Gateway cross-chain flow
    Requires: to_subname, amount, signed_burn_intent (JSON)

  Both flows call the settlement contract via send_tx().
  """
  try:
    data = json.loads(request.body)
  except (json.JSONDecodeError, AttributeError):
    data = request.POST.dict()

  settle_type = data.get('type', 'authorization')
  to_subname = data.get('to_subname', '')
  amount_str = data.get('amount', '0')
  source_chain = int(data.get('source_chain', 11155111))
  dest_chain = int(data.get('dest_chain', 11155111))
  group_id = data.get('group_id')

  if not to_subname:
    return JsonResponse({'error': 'Missing to_subname'}, status=400)

  # Resolve recipient's ENS node
  recipient_node = subname_node(to_subname)

  # Get sender's address
  primary_addr = request.user.addresses.filter(is_primary=True).first()
  if not primary_addr:
    return JsonResponse({'error': 'No linked wallet'}, status=400)
  sender_address = Web3.to_checksum_address(primary_addr.address)

  # Look up recipient user
  try:
    to_user = User.objects.get(subname=to_subname)
  except User.DoesNotExist:
    to_user = None

  to_linked = to_user.addresses.filter(is_primary=True).first() if to_user else None
  to_address = to_linked.address if to_linked else ''

  # Look up group if provided
  group = None
  if group_id:
    group = CachedGroup.objects.filter(group_id=int(group_id)).first()

  tx_hash = None
  memo = data.get('memo', '').encode('utf-8') if data.get('memo') else b''

  if settle_type == 'authorization':
    # ERC-3009 transferWithAuthorization flow
    signature = data.get('signature', '')
    auth_from = data.get('auth_from', sender_address)
    valid_after = int(data.get('valid_after', 0))
    valid_before = int(data.get('valid_before', 2**256 - 1))
    nonce = data.get('nonce', '')

    if not signature:
      return JsonResponse({'error': 'Missing signature'}, status=400)

    # Convert amount to USDC base units (6 decimals)
    try:
      amount_int = int(float(amount_str) * 1_000_000)
    except (ValueError, TypeError):
      return JsonResponse({'error': 'Invalid amount'}, status=400)

    nonce_bytes = bytes.fromhex(nonce.replace('0x', '')) if nonce else b'\x00' * 32
    sig_bytes = bytes.fromhex(signature.replace('0x', ''))

    auth_tuple = (
      Web3.to_checksum_address(auth_from),
      valid_after,
      valid_before,
      nonce_bytes,
    )

    try:
      tx_hash = send_tx(
        'settlement', 'settleWithAuthorization',
        recipient_node,
        amount_int,
        memo,
        auth_tuple,
        sig_bytes,
        chain_id=source_chain,
        gas=500_000,
      )
      logger.info(f'settleWithAuthorization tx={tx_hash}')
    except Exception as e:
      logger.exception('settleWithAuthorization failed')
      return JsonResponse({'error': f'On-chain settlement failed: {e}'}, status=500)

  elif settle_type == 'gateway':
    # Circle Gateway cross-chain flow
    from api.utils.circle_gateway import get_gateway_attestation

    signed_burn_intent = data.get('signed_burn_intent', {})
    if not signed_burn_intent:
      return JsonResponse({'error': 'Missing signed_burn_intent'}, status=400)

    try:
      attestation_data = get_gateway_attestation(signed_burn_intent)
      attestation_bytes = bytes.fromhex(attestation_data['attestation'].replace('0x', ''))
      attestation_sig = bytes.fromhex(attestation_data['signature'].replace('0x', ''))

      tx_hash = send_tx(
        'settlement', 'settleFromGateway',
        attestation_bytes,
        attestation_sig,
        recipient_node,
        sender_address,
        memo,
        chain_id=dest_chain,
        gas=500_000,
      )
      logger.info(f'settleFromGateway tx={tx_hash}')
    except Exception as e:
      logger.exception('settleFromGateway failed')
      return JsonResponse({'error': f'Gateway settlement failed: {e}'}, status=500)

  else:
    return JsonResponse({'error': f'Unknown type: {settle_type}'}, status=400)

  # Record settlement in DB
  if tx_hash:
    settlement = CachedSettlement.objects.create(
      tx_hash=tx_hash,
      from_user=request.user,
      from_address=sender_address,
      to_address=to_address,
      to_user=to_user,
      token='usdc',
      amount=amount_str,
      source_chain=source_chain,
      dest_chain=dest_chain,
      status=CachedSettlement.Status.SUBMITTED,
      group=group,
    )

    Activity.objects.create(
      user=request.user,
      action_type=Activity.ActionType.SETTLEMENT_INITIATED,
      group_id=group.group_id if group else None,
      settlement_hash=tx_hash,
      message=f'Settled {amount_str} USDC to {to_subname}',
    )

    request._wide_event['extra']['settlement_tx'] = tx_hash

    return JsonResponse({
      'status': 'ok',
      'tx_hash': tx_hash,
      'settlement_status': settlement.status,
      'type': settle_type,
    })

  return JsonResponse({'error': 'Settlement failed'}, status=500)


@login_required(login_url='/api/auth/login/')
@require_GET
def status(request, tx_hash):
  """
  Poll settlement status (HTMX partial with auto-refresh).
  When status reaches confirmed/failed, the polling trigger is omitted
  so HTMX stops.
  """
  settlement = CachedSettlement.objects.filter(
    tx_hash=tx_hash
  ).select_related('from_user', 'to_user', 'group').first()

  if not settlement:
    return HttpResponse('Settlement not found', status=404)

  return render(request, 'lenses/settlement-card.html', {
    'settlement': settlement,
  })
