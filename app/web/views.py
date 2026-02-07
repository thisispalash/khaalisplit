from django.contrib.auth.decorators import login_required
from django.shortcuts import render


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
  return render(request, 'groups/list.html')


@login_required(login_url='/api/auth/login/')
def group_detail(request, group_id):
  """Group detail page."""
  return render(request, 'groups/detail.html', {'group_id': group_id})


@login_required(login_url='/api/auth/login/')
def group_create(request):
  """Create group page."""
  return render(request, 'groups/create.html')


@login_required(login_url='/api/auth/login/')
def settle(request, group_id):
  """Settlement page for a group."""
  return render(request, 'settlement/settle.html', {'group_id': group_id})


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
