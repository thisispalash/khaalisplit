import os


def goatcounter_url(request):
  """Expose GOATCOUNTER_URL to all templates."""
  return {
    'GOATCOUNTER_URL': os.environ.get('GOATCOUNTER_URL', ''),
  }


def active_tab(request):
  """Expose active_tab for bottom-nav highlighting."""
  path = request.path.rstrip('/')
  if path.startswith('/friends'):
    return {'active_tab': 'friends'}
  if path.startswith('/groups'):
    return {'active_tab': 'groups'}
  if path.startswith('/profile') or path.startswith('/u/'):
    return {'active_tab': 'profile'}
  return {'active_tab': 'activity'}
