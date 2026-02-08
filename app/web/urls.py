from django.urls import path

from web import views

app_name = 'web'

urlpatterns = [
  path('', views.home, name='home'),
  path('friends/', views.friends_list, name='friends'),
  path('groups/', views.groups_list, name='groups'),
  path('groups/create/', views.group_create, name='group-create'),
  path('groups/<int:group_id>/', views.group_detail, name='group-detail'),
  path('settle/<int:group_id>/', views.settle, name='settle'),
  path('profile/', views.profile, name='profile'),
  path('profile/<str:subname>/', views.profile_public, name='profile-public'),
  path('u/<str:subname>/', views.profile_public, name='profile-short'),
]
