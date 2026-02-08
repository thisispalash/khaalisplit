from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.shortcuts import render

from api.forms.auth import ProfileForm
from api.forms.groups import CreateGroupForm
from api.models import CachedGroup, CachedGroupMember, User


def home(request):
  """Home page — activity feed for logged-in users, signup for anonymous."""
  if request.user.is_authenticated:
    return render(request, 'pages/home.html')
  return render(request, 'pages/signup.html')


@login_required(login_url='/api/auth/login/')
def friends_list(request):
  """Friends list page."""
  return render(request, 'pages/friends.html')


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

  return render(request, 'pages/groups-list.html', {
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

  return render(request, 'pages/group-detail.html', {
    'group': group,
    'is_member': is_member,
  })


@login_required(login_url='/api/auth/login/')
def group_create(request):
  """Create group page."""
  form = CreateGroupForm()
  return render(request, 'pages/group-create.html', {'form': form})


@login_required(login_url='/api/auth/login/')
def settle(request, group_id):
  """Settlement page for a group."""
  group = CachedGroup.objects.filter(group_id=group_id).first()
  if not group:
    raise Http404('Group not found')
  return render(request, 'pages/settle.html', {
    'group': group,
  })


@login_required(login_url='/api/auth/login/')
def profile(request):
  """Own profile page — editable form."""
  form = ProfileForm(instance=request.user)
  return render(request, 'pages/profile.html', {
    'profile_user': request.user,
    'is_own_profile': True,
    'form': form,
  })


def profile_public(request, subname):
  """Public profile page for a user by subname."""
  try:
    profile_user = User.objects.get(subname=subname)
  except User.DoesNotExist:
    raise Http404('User not found')

  # If viewing own profile, show editable version
  if request.user.is_authenticated and request.user == profile_user:
    form = ProfileForm(instance=request.user)
    return render(request, 'pages/profile.html', {
      'profile_user': profile_user,
      'is_own_profile': True,
      'form': form,
    })

  return render(request, 'pages/profile.html', {
    'profile_user': profile_user,
    'is_own_profile': False,
  })
