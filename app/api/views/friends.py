"""
Friend views — HTMX partial responses for friend management.

All views return HTML partials for HTMX swap targets.
On-chain operations use *For relay functions via send_tx().
"""
import logging

from django.contrib.auth.decorators import login_required
from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET, require_POST
from web3 import Web3

from api.models import Activity, CachedFriend, User
from api.utils.web3_utils import send_tx

logger = logging.getLogger('wide_event')


def _get_user_address(user):
  """Get the user's primary checksummed address, or empty string."""
  addr = user.addresses.filter(is_primary=True).first()
  if not addr:
    addr = user.addresses.first()
  return Web3.to_checksum_address(addr.address) if addr else ''


@login_required(login_url='/api/auth/login/')
@require_GET
def search(request):
  """
  Search for users by subname (HTMX partial).
  Triggered by keyup with debounce on the search input.
  """
  q = request.GET.get('q', '').strip()
  if len(q) < 2:
    return HttpResponse('')

  results = (
    User.objects.filter(subname__icontains=q)
    .exclude(pk=request.user.pk)
    [:10]
  )

  # Check existing friend status for each result
  friend_addresses = set(
    CachedFriend.objects.filter(user=request.user)
    .values_list('friend_user_id', flat=True)
  )

  return render(request, 'partials/search_results.html', {
    'results': results,
    'friend_ids': friend_addresses,
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def send_request(request, subname):
  """Send a friend request to a user by subname."""
  try:
    friend_user = User.objects.get(subname=subname)
  except User.DoesNotExist:
    return HttpResponse('User not found', status=404)

  if friend_user == request.user:
    return HttpResponse('Cannot befriend yourself', status=400)

  user_address = _get_user_address(request.user)
  friend_address = _get_user_address(friend_user)

  # Create outgoing request
  _, created = CachedFriend.objects.get_or_create(
    user=request.user,
    friend_user=friend_user,
    defaults={
      'friend_address': friend_address,
      'status': CachedFriend.Status.PENDING_SENT,
    },
  )

  if created:
    # Create incoming request for the other user
    CachedFriend.objects.get_or_create(
      user=friend_user,
      friend_user=request.user,
      defaults={
        'friend_address': user_address,
        'status': CachedFriend.Status.PENDING_RECEIVED,
      },
    )

    # On-chain: requestFriendFor (non-blocking)
    if user_address and friend_address:
      try:
        tx_hash = send_tx('friends', 'requestFriendFor', user_address, friend_address)
        logger.info(f'requestFriendFor tx={tx_hash}')
      except Exception:
        logger.exception('requestFriendFor on-chain call failed')

    Activity.objects.create(
      user=request.user,
      action_type=Activity.ActionType.FRIEND_REQUEST,
      message=f'Sent friend request to {friend_user.subname}',
    )

  request._wide_event['extra']['friend_request_to'] = subname

  return render(request, 'lenses/friend-card.html', {
    'friend_user': friend_user,
    'status': 'pending_sent',
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def accept(request, subname):
  """Accept a friend request from the given subname."""
  # Find the incoming request
  incoming = CachedFriend.objects.filter(
    user=request.user,
    friend_user__subname=subname,
    status=CachedFriend.Status.PENDING_RECEIVED,
  ).first()

  if not incoming:
    return HttpResponse('No pending request from this user', status=404)

  # Accept both sides
  incoming.status = CachedFriend.Status.ACCEPTED
  incoming.save()

  # Update the outgoing side too
  CachedFriend.objects.filter(
    user=incoming.friend_user,
    friend_user=request.user,
  ).update(status=CachedFriend.Status.ACCEPTED)

  # On-chain: acceptFriendFor (non-blocking)
  user_address = _get_user_address(request.user)
  requester_address = _get_user_address(incoming.friend_user)
  if user_address and requester_address:
    try:
      tx_hash = send_tx('friends', 'acceptFriendFor', user_address, requester_address)
      logger.info(f'acceptFriendFor tx={tx_hash}')
    except Exception:
      logger.exception('acceptFriendFor on-chain call failed')

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.FRIEND_ACCEPTED,
    message=f'Accepted friend request from {subname}',
  )

  request._wide_event['extra']['friend_accepted'] = subname

  return render(request, 'lenses/friend-card.html', {
    'friend_user': incoming.friend_user,
    'status': 'accepted',
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def remove(request, subname):
  """Remove a friend relationship."""
  friend = CachedFriend.objects.filter(
    user=request.user,
    friend_user__subname=subname,
  ).first()

  if not friend:
    return HttpResponse('Friend not found', status=404)

  friend.status = CachedFriend.Status.REMOVED
  friend.save()

  # Remove the reverse relationship too
  if friend.friend_user:
    CachedFriend.objects.filter(
      user=friend.friend_user,
      friend_user=request.user,
    ).update(status=CachedFriend.Status.REMOVED)

  # On-chain: removeFriendFor (non-blocking)
  user_address = _get_user_address(request.user)
  friend_addr = _get_user_address(friend.friend_user) if friend.friend_user else ''
  if user_address and friend_addr:
    try:
      tx_hash = send_tx('friends', 'removeFriendFor', user_address, friend_addr)
      logger.info(f'removeFriendFor tx={tx_hash}')
    except Exception:
      logger.exception('removeFriendFor on-chain call failed')

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.FRIEND_REMOVED,
    message=f'Removed friend {subname}',
  )

  return HttpResponse('')  # Empty response removes the card via HTMX swap


@login_required(login_url='/api/auth/login/')
@require_GET
def pending(request):
  """Get pending friend requests (HTMX partial)."""
  pending_requests = CachedFriend.objects.filter(
    user=request.user,
    status=CachedFriend.Status.PENDING_RECEIVED,
  ).select_related('friend_user')

  return render(request, 'partials/pending_requests.html', {
    'pending': pending_requests,
  })
