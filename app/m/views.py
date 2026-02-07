from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import render

from api.forms.groups import CreateGroupForm
from api.models import CachedGroup, CachedGroupMember


def home(request):
  """Mobile home — activity feed or landing."""
  if request.user.is_authenticated:
    return render(request, 'activity/feed.html')
  return render(request, 'auth/signup.html')


@login_required(login_url='/api/auth/login/')
def friends_list(request):
  """Mobile friends list."""
  return render(request, 'friends/list.html')


@login_required(login_url='/api/auth/login/')
def groups_list(request):
  """Mobile groups list."""
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
  """Mobile group detail."""
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
  """Mobile create group."""
  form = CreateGroupForm()
  return render(request, 'groups/create.html', {'form': form})


@login_required(login_url='/api/auth/login/')
def settle(request, group_id):
  """Mobile settlement."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    raise Http404('Group not found')
  return render(request, 'settlement/settle.html', {
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
def profile(request):
  """Mobile own profile."""
  return render(request, 'auth/onboarding/profile.html', {
    'form': None,
  })


def profile_public(request, subname):
  """Mobile public profile."""
  return render(request, 'auth/onboarding/profile.html', {
    'subname': subname,
  })
