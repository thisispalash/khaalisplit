from django.urls import path

from api.views import auth as auth_views
from api.views import ens_gateway
from api.views import friends as friends_views

app_name = 'api'

urlpatterns = [
  # Auth
  path('auth/signup/', auth_views.signup_view, name='signup'),
  path('auth/login/', auth_views.login_view, name='login'),
  path('auth/logout/', auth_views.logout_view, name='logout'),
  path('auth/onboarding/profile/', auth_views.onboarding_profile_view, name='onboarding-profile'),
  path('auth/onboarding/wallet/', auth_views.onboarding_wallet_view, name='onboarding-wallet'),
  path('auth/address/verify/', auth_views.verify_signature, name='verify-signature'),
  path('auth/pubkey/register/', auth_views.register_pubkey, name='register-pubkey'),

  # Friends
  path('friends/search/', friends_views.search, name='friends-search'),
  path('friends/request/<str:subname>/', friends_views.send_request, name='friends-request'),
  path('friends/accept/<str:address>/', friends_views.accept, name='friends-accept'),
  path('friends/remove/<str:address>/', friends_views.remove, name='friends-remove'),
  path('friends/pending/', friends_views.pending, name='friends-pending'),

  # Groups (Step 8)
  # Expenses (Step 9)
  # Settlement (Step 10)
  # Activity (Step 11)
  # ENS Gateway
  path('ens-gateway/<str:sender>/<str:data>.json', ens_gateway.ccip_read, name='ens-gateway'),
]
