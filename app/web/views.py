from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import render

from api.forms.groups import CreateGroupForm
from api.models import CachedGroup, CachedGroupMember


def home(request):
  """Home page — activity feed for logged-in users, landing for anonymous."""
  if request.user.is_authenticated:
    return render(request, 'activity/feed.html')
  return render(request, 'auth/signup.html')


@login_required(login_url='/api/auth/login/')
def friends_list(request):
  """Friends list page."""
  return render(request, 'friends/list.html')


@login_required(login_url='/api/auth/login/')
def groups_list(request):
  """Groups list page."""
  groups = CachedGroup.objects.filter(
    members__user=request.user,
    members__status=CachedGroupMember.Status.ACCEPTED,
  ).distinct().order_by('-updated_at')

  invited_groups = CachedGroup.objects.filter(
    members__user=request.user,
    members__status=CachedGroupMember.Status.INVITED,
  ).distinct().order_by('-updated_at')

  return render(request, 'groups/list.html', {
    'groups': groups,
    'invited_groups': invited_groups,
  })


@login_required(login_url='/api/auth/login/')
def group_detail(request, group_id):
  """Group detail page."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    raise Http404('Group not found')

  is_member = CachedGroupMember.objects.filter(
    group=group,
    user=request.user,
    status=CachedGroupMember.Status.ACCEPTED,
  ).exists()

  return render(request, 'groups/detail.html', {
    'group': group,
    'is_member': is_member,
  })


@login_required(login_url='/api/auth/login/')
def group_create(request):
  """Create group page."""
  form = CreateGroupForm()
  return render(request, 'groups/create.html', {'form': form})


@login_required(login_url='/api/auth/login/')
def settle(request, group_id):
  """Settlement page for a group."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    raise Http404('Group not found')
  return render(request, 'settlement/settle.html', {
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
def profile(request):
  """Own profile page."""
  return render(request, 'auth/onboarding/profile.html', {
    'form': None,  # will be replaced with ProfileForm in later step
  })


def profile_public(request, subname):
  """Public profile page for a user."""
  return render(request, 'auth/onboarding/profile.html', {
    'subname': subname,
  })
