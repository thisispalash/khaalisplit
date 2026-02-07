"""
Settlement views — debt summary, initiation, and status polling.
"""
import json
import logging

from django.contrib.auth.decorators import login_required
from django.http import HttpResponse, JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET, require_POST

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

  return render(request, 'settlement/partials/debt_summary.html', {
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

  return render(request, 'settlement/partials/settlement_status.html', {
    'settlement': settlement,
  })
