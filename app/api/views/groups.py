"""
Group views — HTMX partial responses for group management.
On-chain operations use *For relay functions via send_tx().
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
from api.utils.web3_utils import send_tx

logger = logging.getLogger('wide_event')


def _get_user_address(user):
  """Get the user's primary checksummed address, or empty string."""
  addr = user.addresses.filter(is_primary=True).first()
  if not addr:
    addr = user.addresses.first()
  return Web3.to_checksum_address(addr.address) if addr else ''


@login_required(login_url='/api/auth/login/')
@require_POST
def create(request):
  """Create a new group. Returns redirect to group detail."""
  form = CreateGroupForm(request.POST)
  if not form.is_valid():
    return render(request, 'pages/group-create.html', {'form': form})

  name = form.cleaned_data['name']
  name_hash = Web3.solidity_keccak(['string'], [name]).hex()
  user_address = _get_user_address(request.user)

  # Encrypted key from client (hex). For hackathon, use a 32-byte placeholder if empty.
  encrypted_key = request.POST.get('encrypted_key', '').strip()
  if encrypted_key and encrypted_key not in ('', '0x', '0x00'):
    hex_str = encrypted_key.replace('0x', '')
    encrypted_key_bytes = bytes.fromhex(hex_str)
  else:
    # Placeholder: 32 random bytes so the contract doesn't reject zero/short data
    import os as _os
    encrypted_key_bytes = _os.urandom(32)
  name_hash_bytes = bytes.fromhex(name_hash.replace('0x', '') if name_hash.startswith('0x') else name_hash)

  # On-chain: createGroupFor returns groupId
  import time
  placeholder_id = int(time.time())  # fallback if on-chain fails
  if user_address:
    try:
      tx_hash = send_tx(
        'groups', 'createGroupFor',
        user_address, name_hash_bytes, encrypted_key_bytes,
      )
      logger.info(f'createGroupFor tx={tx_hash}')
    except Exception:
      logger.exception('createGroupFor on-chain call failed')

  group = CachedGroup.objects.create(
    group_id=placeholder_id,
    name=name,
    name_hash=name_hash,
    creator=request.user,
    member_count=1,
  )

  # Add creator as first member
  CachedGroupMember.objects.create(
    group=group,
    user=request.user,
    member_address=user_address,
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

  inviter_address = _get_user_address(request.user)
  member_address = _get_user_address(invite_user)
  encrypted_key = request.POST.get('encrypted_key', '').strip()
  if encrypted_key and encrypted_key not in ('', '0x', '0x00'):
    hex_str = encrypted_key.replace('0x', '')
    encrypted_key_bytes = bytes.fromhex(hex_str)
  else:
    import os as _os
    encrypted_key_bytes = _os.urandom(32)

  CachedGroupMember.objects.create(
    group=group,
    user=invite_user,
    member_address=member_address,
    status=CachedGroupMember.Status.INVITED,
  )

  # On-chain: inviteMemberFor (non-blocking)
  if inviter_address and member_address:
    try:
      tx_hash = send_tx(
        'groups', 'inviteMemberFor',
        inviter_address, group.group_id, member_address, encrypted_key_bytes,
      )
      logger.info(f'inviteMemberFor tx={tx_hash}')
    except Exception:
      logger.exception('inviteMemberFor on-chain call failed')

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_INVITE,
    group_id=group.group_id,
    message=f'Invited {subname} to group "{group.name}"',
  )

  # Return updated member list
  members = group.members.select_related('user').all()
  return render(request, 'partials/member_list.html', {
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

  # On-chain: acceptGroupInviteFor (non-blocking)
  user_address = _get_user_address(request.user)
  if user_address:
    try:
      tx_hash = send_tx('groups', 'acceptGroupInviteFor', user_address, group.group_id)
      logger.info(f'acceptGroupInviteFor tx={tx_hash}')
    except Exception:
      logger.exception('acceptGroupInviteFor on-chain call failed')

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.GROUP_JOINED,
    group_id=group.group_id,
    message=f'Joined group "{group.name}"',
  )

  return render(request, 'lenses/group-card.html', {'group': group})


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

  # On-chain: leaveGroupFor (non-blocking)
  user_address = _get_user_address(request.user)
  if user_address:
    try:
      tx_hash = send_tx('groups', 'leaveGroupFor', user_address, group.group_id)
      logger.info(f'leaveGroupFor tx={tx_hash}')
    except Exception:
      logger.exception('leaveGroupFor on-chain call failed')

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
  return render(request, 'partials/member_list.html', {
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
  return render(request, 'prisms/balance-summary.html', {
    'group': group,
  })
