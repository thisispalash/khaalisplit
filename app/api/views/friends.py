"""
Friend views — HTMX partial responses for friend management.

All views return HTML partials for HTMX swap targets.
"""
import logging

from django.contrib.auth.decorators import login_required
from django.db.models import Q
from django.http import HttpResponse
from django.shortcuts import render
from django.views.decorators.http import require_GET, require_POST

from api.models import Activity, CachedFriend, User

logger = logging.getLogger('wide_event')


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

  return render(request, 'friends/partials/search_results.html', {
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

  # Get friend's primary address
  friend_addr = friend_user.addresses.filter(is_primary=True).first()
  if not friend_addr:
    friend_addr = friend_user.addresses.first()
  address = friend_addr.address if friend_addr else ''

  # Create outgoing request
  _, created = CachedFriend.objects.get_or_create(
    user=request.user,
    friend_user=friend_user,
    defaults={
      'friend_address': address,
      'status': CachedFriend.Status.PENDING_SENT,
    },
  )

  if created:
    # Create incoming request for the other user
    CachedFriend.objects.get_or_create(
      user=friend_user,
      friend_user=request.user,
      defaults={
        'friend_address': request.user.addresses.filter(is_primary=True).first().address
        if request.user.addresses.filter(is_primary=True).exists()
        else '',
        'status': CachedFriend.Status.PENDING_RECEIVED,
      },
    )

    Activity.objects.create(
      user=request.user,
      action_type=Activity.ActionType.FRIEND_REQUEST,
      message=f'Sent friend request to {friend_user.subname}',
    )

  request._wide_event['extra']['friend_request_to'] = subname

  return render(request, 'friends/partials/friend_card.html', {
    'friend_user': friend_user,
    'status': 'pending_sent',
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def accept(request, address):
  """Accept a friend request from the given address."""
  # Find the incoming request
  incoming = CachedFriend.objects.filter(
    user=request.user,
    friend_address=address,
    status=CachedFriend.Status.PENDING_RECEIVED,
  ).first()

  if not incoming:
    return HttpResponse('No pending request from this address', status=404)

  # Accept both sides
  incoming.status = CachedFriend.Status.ACCEPTED
  incoming.save()

  # Update the outgoing side too
  CachedFriend.objects.filter(
    user=incoming.friend_user,
    friend_user=request.user,
  ).update(status=CachedFriend.Status.ACCEPTED)

  Activity.objects.create(
    user=request.user,
    action_type=Activity.ActionType.FRIEND_ACCEPTED,
    message=f'Accepted friend request from {incoming.friend_user.subname if incoming.friend_user else address[:10]}',
  )

  request._wide_event['extra']['friend_accepted'] = address

  return render(request, 'friends/partials/friend_card.html', {
    'friend_user': incoming.friend_user,
    'status': 'accepted',
  })


@login_required(login_url='/api/auth/login/')
@require_POST
def remove(request, address):
  """Remove a friend relationship."""
  friend = CachedFriend.objects.filter(
    user=request.user,
    friend_address=address,
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

    Activity.objects.create(
      user=request.user,
      action_type=Activity.ActionType.FRIEND_REMOVED,
      message=f'Removed friend {friend.friend_user.subname}',
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

  return render(request, 'friends/partials/pending_requests.html', {
    'pending': pending_requests,
  })
