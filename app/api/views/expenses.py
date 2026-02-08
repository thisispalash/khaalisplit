"""
Expense views — HTMX partial responses for expense management.
On-chain operations use *For relay functions via send_tx().
"""
import json
import logging
import time

from django.contrib.auth.decorators import login_required
from django.http import HttpResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET, require_POST
from web3 import Web3

from api.forms.expenses import AddExpenseForm
from api.models import (
  Activity,
  CachedExpense,
  CachedGroup,
  CachedGroupMember,
)
from api.utils.web3_utils import send_tx

logger = logging.getLogger('wide_event')


def _get_user_address(user):
  """Get the user's primary checksummed address, or empty string."""
  addr = user.addresses.filter(is_primary=True).first()
  if not addr:
    addr = user.addresses.first()
  return Web3.to_checksum_address(addr.address) if addr else ''


def _is_group_member(user, group):
  """Check if user is an accepted member of the group."""
  return CachedGroupMember.objects.filter(
    group=group,
    user=user,
    status=CachedGroupMember.Status.ACCEPTED,
  ).exists()


@login_required(login_url='/api/auth/login/')
@require_POST
def add(request, group_id):
  """Add an expense to a group (HTMX)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  if not _is_group_member(request.user, group):
    return HttpResponse('Not a member of this group', status=403)

  form = AddExpenseForm(request.POST)
  if not form.is_valid():
    return render(request, 'partials/expense_form.html', {
      'form': form,
      'group': group,
    })

  creator_address = _get_user_address(request.user)

  # Build participants — for equal splits, all accepted members
  members = CachedGroupMember.objects.filter(
    group=group,
    status=CachedGroupMember.Status.ACCEPTED,
  ).select_related('user')

  if form.cleaned_data['split_type'] == CachedExpense.SplitType.EQUAL:
    per_person = float(form.cleaned_data['amount']) / members.count()
    participants = {
      m.member_address or m.user.subname: round(per_person, 6)
      for m in members
    }
  else:
    # For exact/percentage splits, expect participants from POST body
    participants_raw = request.POST.get('participants', '{}')
    try:
      participants = json.loads(participants_raw)
    except json.JSONDecodeError:
      participants = {}

  # Placeholder expense_id until on-chain tx confirms
  placeholder_id = int(time.time() * 1000) % (2**31)

  data_hash = form.cleaned_data.get('data_hash', '')
  encrypted_data = form.cleaned_data.get('encrypted_data', '')

  # On-chain: addExpenseFor (non-blocking)
  if creator_address and data_hash:
    try:
      data_hash_bytes = bytes.fromhex(data_hash.replace('0x', '') if data_hash.startswith('0x') else data_hash)
      encrypted_data_bytes = bytes.fromhex(encrypted_data.replace('0x', '') if encrypted_data.startswith('0x') else encrypted_data) if encrypted_data else b'\x00'
      tx_hash = send_tx(
        'expenses', 'addExpenseFor',
        creator_address, group.group_id, data_hash_bytes, encrypted_data_bytes,
      )
      logger.info(f'addExpenseFor tx={tx_hash}')
    except Exception:
      logger.exception('addExpenseFor on-chain call failed')

  expense = CachedExpense.objects.create(
    expense_id=placeholder_id,
    group=group,
    creator=request.user,
    creator_address=creator_address,
    data_hash=data_hash,
    encrypted_data=encrypted_data,
    amount=form.cleaned_data['amount'],
    description=form.cleaned_data['description'],
    split_type=form.cleaned_data['split_type'],
    category=form.cleaned_data.get('category', ''),
    participants_json=participants,
  )

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.EXPENSE_ADDED,
    group_id=group.group_id,
    expense_id=expense.expense_id,
    message=f'Added expense "{expense.description}" ({expense.amount})',
  )

  request._wide_event['extra']['expense_added'] = expense.expense_id

  # Return updated expense list
  expenses = CachedExpense.objects.filter(group=group).order_by('-created_at')
  return render(request, 'partials/expense_list.html', {
    'expenses': expenses,
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
@require_GET
def expense_list(request, group_id):
  """List expenses for a group (HTMX partial)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  expenses = CachedExpense.objects.filter(group=group).order_by('-created_at')
  form = AddExpenseForm()

  return render(request, 'partials/expense_list.html', {
    'expenses': expenses,
    'group': group,
    'form': form,
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def update(request, expense_id):
  """Update an expense's cached decrypted data (HTMX)."""
  expense = CachedExpense.objects.filter(expense_id=expense_id).select_related('group').first()
  if not expense:
    return HttpResponse('Expense not found', status=404)

  if not _is_group_member(request.user, expense.group):
    return HttpResponse('Not a member of this group', status=403)

  # Update decrypted cache fields from client
  if 'amount' in request.POST:
    try:
      expense.amount = request.POST['amount']
    except (ValueError, TypeError):
      pass
  if 'description' in request.POST:
    expense.description = request.POST['description']
  if 'split_type' in request.POST:
    expense.split_type = request.POST['split_type']
  if 'category' in request.POST:
    expense.category = request.POST['category']
  if 'participants' in request.POST:
    try:
      expense.participants_json = json.loads(request.POST['participants'])
    except json.JSONDecodeError:
      pass

  expense.save()

  request._wide_event['extra']['expense_updated'] = expense.expense_id

  return render(request, 'lenses/expense-card.html', {
    'expense': expense,
    'group': expense.group,
  })
