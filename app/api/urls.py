from django.urls import path

from api.views import auth as auth_views

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

  # Friends (Step 7)
  # Groups (Step 8)
  # Expenses (Step 9)
  # Settlement (Step 10)
  # Activity (Step 11)
  # ENS Gateway (Step 6)
]
