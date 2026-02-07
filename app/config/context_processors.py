import os


def goatcounter_url(request):
  """Expose GOATCOUNTER_URL to all templates."""
  return {
    'GOATCOUNTER_URL': os.environ.get('GOATCOUNTER_URL', ''),
  }
