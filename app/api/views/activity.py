"""
Activity feed views — paginated HTMX partials with infinite scroll.
"""
import logging

from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.views.decorators.http import require_GET

from api.models import Activity

logger = logging.getLogger('wide_event')

PAGE_SIZE = 20


@login_required(login_url='/api/auth/login/')
@require_GET
def load_more(request):
  """
  Load activity feed page (HTMX partial with infinite scroll).

  Uses `hx-trigger="revealed"` on the last item to auto-load
  the next page when it scrolls into view.
  """
  try:
    page = int(request.GET.get('page', 1))
  except (ValueError, TypeError):
    page = 1

  offset = (page - 1) * PAGE_SIZE
  activities = Activity.objects.filter(
    user=request.user,
  ).order_by('-created_at')[offset:offset + PAGE_SIZE + 1]

  # Check if there are more items
  activity_list = list(activities)
  has_more = len(activity_list) > PAGE_SIZE
  if has_more:
    activity_list = activity_list[:PAGE_SIZE]

  request._wide_event['extra']['activity_page'] = page
  request._wide_event['extra']['activity_count'] = len(activity_list)

  return render(request, 'activity/partials/activity_list.html', {
    'activities': activity_list,
    'has_more': has_more,
    'next_page': page + 1,
  })
