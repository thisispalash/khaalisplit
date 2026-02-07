from django.contrib import admin

from api.models import (
  Activity,
  BurntAddress,
  CachedExpense,
  CachedFriend,
  CachedGroup,
  CachedGroupMember,
  CachedSettlement,
  LinkedAddress,
  User,
)


@admin.register(User)
class UserAdmin(admin.ModelAdmin):
  list_display = ['subname', 'display_name', 'reputation_score', 'is_active', 'created_at']
  search_fields = ['subname', 'display_name']
  list_filter = ['is_active', 'is_staff']
  readonly_fields = ['created_at', 'updated_at']


@admin.register(LinkedAddress)
class LinkedAddressAdmin(admin.ModelAdmin):
  list_display = ['user', 'address', 'is_primary', 'chain_id', 'pub_key_registered']
  search_fields = ['address', 'user__subname']
  list_filter = ['is_primary', 'pub_key_registered', 'chain_id']


@admin.register(BurntAddress)
class BurntAddressAdmin(admin.ModelAdmin):
  list_display = ['address', 'original_subname', 'burnt_at']
  search_fields = ['address', 'original_subname']


@admin.register(CachedFriend)
class CachedFriendAdmin(admin.ModelAdmin):
  list_display = ['user', 'friend_address', 'status', 'updated_at']
  search_fields = ['user__subname', 'friend_address']
  list_filter = ['status']


@admin.register(CachedGroup)
class CachedGroupAdmin(admin.ModelAdmin):
  list_display = ['group_id', 'name', 'creator', 'member_count', 'updated_at']
  search_fields = ['name', 'creator__subname']


@admin.register(CachedGroupMember)
class CachedGroupMemberAdmin(admin.ModelAdmin):
  list_display = ['group', 'user', 'status', 'updated_at']
  search_fields = ['user__subname', 'member_address']
  list_filter = ['status']


@admin.register(CachedExpense)
class CachedExpenseAdmin(admin.ModelAdmin):
  list_display = ['expense_id', 'group', 'creator', 'amount', 'category', 'created_at']
  search_fields = ['creator__subname', 'description']
  list_filter = ['split_type', 'category']


@admin.register(CachedSettlement)
class CachedSettlementAdmin(admin.ModelAdmin):
  list_display = ['tx_hash', 'from_user', 'to_address', 'amount', 'status', 'created_at']
  search_fields = ['tx_hash', 'from_user__subname', 'to_address']
  list_filter = ['status', 'source_chain', 'dest_chain']


@admin.register(Activity)
class ActivityAdmin(admin.ModelAdmin):
  list_display = ['user', 'action_type', 'message', 'is_synced', 'created_at']
  search_fields = ['user__subname', 'message']
  list_filter = ['action_type', 'is_synced']
