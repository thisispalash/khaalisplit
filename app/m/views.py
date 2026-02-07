from django.contrib.auth.decorators import login_required
from django.shortcuts import render


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
  return render(request, 'groups/list.html')


@login_required(login_url='/api/auth/login/')
def group_detail(request, group_id):
  """Mobile group detail."""
  return render(request, 'groups/detail.html', {'group_id': group_id})


@login_required(login_url='/api/auth/login/')
def group_create(request):
  """Mobile create group."""
  return render(request, 'groups/create.html')


@login_required(login_url='/api/auth/login/')
def settle(request, group_id):
  """Mobile settlement."""
  return render(request, 'settlement/settle.html', {'group_id': group_id})


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
