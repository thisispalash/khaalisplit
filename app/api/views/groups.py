"""
Group views — HTMX partial responses for group management.
"""
import json
import logging

from django.contrib.auth.decorators import login_required
from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_GET, require_POST
from web3 import Web3

from api.forms.groups import CreateGroupForm
from api.models import Activity, CachedGroup, CachedGroupMember, User

logger = logging.getLogger('wide_event')


@login_required(login_url='/api/auth/login/')
@require_POST
def create(request):
  """Create a new group. Returns redirect to group detail."""
  form = CreateGroupForm(request.POST)
  if not form.is_valid():
    return render(request, 'groups/create.html', {'form': form})

  name = form.cleaned_data['name']
  name_hash = Web3.solidity_keccak(['string'], [name]).hex()

  # For now, create locally. The on-chain createGroup will be called
  # from the client via wallet.js, then the backend caches the result.
  # Use a placeholder group_id (will be updated when on-chain tx confirms)
  import time
  placeholder_id = int(time.time())  # temporary until on-chain

  group = CachedGroup.objects.create(
    group_id=placeholder_id,
    name=name,
    name_hash=name_hash,
    creator=request.user,
    member_count=1,
  )

  # Add creator as first member
  primary_addr = request.user.addresses.filter(is_primary=True).first()
  CachedGroupMember.objects.create(
    group=group,
    user=request.user,
    member_address=primary_addr.address if primary_addr else '',
    status=CachedGroupMember.Status.ACCEPTED,
  )

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_CREATED,
    group_id=group.group_id,
    message=f'Created group "{name}"',
  )

  request._wide_event['extra']['group_created'] = group.group_id
  return redirect(f'/groups/{group.group_id}/')


@login_required(login_url='/api/auth/login/')
@require_POST
def invite(request, group_id):
  """Invite a user to a group (HTMX)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  # Check if requester is a member
  if not CachedGroupMember.objects.filter(
    group=group, user=request.user, status=CachedGroupMember.Status.ACCEPTED
  ).exists():
    return HttpResponse('Not a member of this group', status=403)

  subname = request.POST.get('subname', '').strip()
  if not subname:
    return HttpResponse('Missing subname', status=400)

  try:
    invite_user = User.objects.get(subname=subname)
  except User.DoesNotExist:
    return HttpResponse('User not found', status=404)

  # Check if already a member
  if CachedGroupMember.objects.filter(group=group, user=invite_user).exists():
    return HttpResponse('User already in group', status=409)

  primary_addr = invite_user.addresses.filter(is_primary=True).first()
  CachedGroupMember.objects.create(
    group=group,
    user=invite_user,
    member_address=primary_addr.address if primary_addr else '',
    status=CachedGroupMember.Status.INVITED,
  )

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_INVITE,
    group_id=group.group_id,
    message=f'Invited {subname} to group "{group.name}"',
  )

  # Return updated member list
  members = group.members.select_related('user').all()
  return render(request, 'groups/partials/member_list.html', {
    'members': members,
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def accept_invite(request, group_id):
  """Accept a group invitation (HTMX)."""
  membership = CachedGroupMember.objects.filter(
    group__group_id=group_id,
    user=request.user,
    status=CachedGroupMember.Status.INVITED,
  ).select_related('group').first()

  if not membership:
    return HttpResponse('No pending invitation', status=404)

  membership.status = CachedGroupMember.Status.ACCEPTED
  membership.save()

  group = membership.group
  group.member_count = group.members.filter(
    status=CachedGroupMember.Status.ACCEPTED
  ).count()
  group.save()

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_JOINED,
    group_id=group.group_id,
    message=f'Joined group "{group.name}"',
  )

  return render(request, 'groups/partials/group_card.html', {'group': group})


@login_required(login_url='/api/auth/login/')
@require_POST
def leave(request, group_id):
  """Leave a group (HTMX)."""
  membership = CachedGroupMember.objects.filter(
    group__group_id=group_id,
    user=request.user,
    status=CachedGroupMember.Status.ACCEPTED,
  ).select_related('group').first()

  if not membership:
    return HttpResponse('Not a member', status=404)

  membership.status = CachedGroupMember.Status.LEFT
  membership.save()

  group = membership.group
  group.member_count = group.members.filter(
    status=CachedGroupMember.Status.ACCEPTED
  ).count()
  group.save()

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_LEFT,
    group_id=group.group_id,
    message=f'Left group "{group.name}"',
  )

  return HttpResponse('')


@login_required(login_url='/api/auth/login/')
@require_GET
def members(request, group_id):
  """Get group members (HTMX partial)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  member_list = group.members.select_related('user').all()
  return render(request, 'groups/partials/member_list.html', {
    'members': member_list,
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
@require_GET
def balances(request, group_id):
  """Get group balance summary (HTMX partial)."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    return HttpResponse('Group not found', status=404)

  # Balance calculation will be enriched in Step 10
  return render(request, 'groups/partials/balance_summary.html', {
    'group': group,
  })
