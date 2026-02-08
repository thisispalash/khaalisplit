from django.urls import path

from api.views import auth as auth_views
from api.views import ens_gateway
from api.views import friends as friends_views
from api.views import groups as groups_views
from api.views import expenses as expenses_views
from api.views import profile as profile_views
from api.views import settlement as settlement_views
from api.views import activity as activity_views

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

  # Profile
  path('profile/payment-preferences/', profile_views.payment_preferences, name='payment-preferences'),

  # Friends
  path('friends/search/', friends_views.search, name='friends-search'),
  path('friends/request/<str:subname>/', friends_views.send_request, name='friends-request'),
  path('friends/accept/<str:subname>/', friends_views.accept, name='friends-accept'),
  path('friends/remove/<str:subname>/', friends_views.remove, name='friends-remove'),
  path('friends/pending/', friends_views.pending, name='friends-pending'),

  # Groups
  path('groups/create/', groups_views.create, name='groups-create'),
  path('groups/<int:group_id>/invite/', groups_views.invite, name='groups-invite'),
  path('groups/<int:group_id>/accept/', groups_views.accept_invite, name='groups-accept'),
  path('groups/<int:group_id>/leave/', groups_views.leave, name='groups-leave'),
  path('groups/<int:group_id>/members/', groups_views.members, name='groups-members'),
  path('groups/<int:group_id>/balances/', groups_views.balances, name='groups-balances'),

  # Expenses
  path('expenses/<int:group_id>/add/', expenses_views.add, name='expenses-add'),
  path('expenses/<int:group_id>/list/', expenses_views.expense_list, name='expenses-list'),
  path('expenses/<int:expense_id>/update/', expenses_views.update, name='expenses-update'),

  # Settlement
  path('settle/<int:group_id>/debts/', settlement_views.debts, name='settle-debts'),
  path('settle/<int:group_id>/initiate/', settlement_views.initiate, name='settle-initiate'),
  path('settle/for-user/', settlement_views.settle_for_user, name='settle-for-user'),
  path('settle/status/<str:tx_hash>/', settlement_views.status, name='settle-status'),

  # Activity
  path('activity/load-more/', activity_views.load_more, name='activity-load-more'),

  # ENS Gateway
  path('ens-gateway/<str:sender>/<str:data>.json', ens_gateway.ccip_read, name='ens-gateway'),
]
