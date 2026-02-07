from django.conf import settings
from django.db import models


class Activity(models.Model):
  """
  Activity feed entries. Each action (expense added, friend request,
  settlement, etc.) creates an Activity record for the relevant user.
  """

  class ActionType(models.TextChoices):
    EXPENSE_ADDED = 'expense_added', 'Expense added'
    EXPENSE_UPDATED = 'expense_updated', 'Expense updated'
    SETTLEMENT_INITIATED = 'settlement_initiated', 'Settlement initiated'
    SETTLEMENT_CONFIRMED = 'settlement_confirmed', 'Settlement confirmed'
    SETTLEMENT_FAILED = 'settlement_failed', 'Settlement failed'
    FRIEND_REQUEST = 'friend_request', 'Friend request sent'
    FRIEND_ACCEPTED = 'friend_accepted', 'Friend request accepted'
    FRIEND_REMOVED = 'friend_removed', 'Friend removed'
    GROUP_CREATED = 'group_created', 'Group created'
    GROUP_INVITE = 'group_invite', 'Group invitation'
    GROUP_JOINED = 'group_joined', 'Joined group'
    GROUP_LEFT = 'group_left', 'Left group'
    WALLET_LINKED = 'wallet_linked', 'Wallet linked'
    PUBKEY_REGISTERED = 'pubkey_registered', 'Public key registered'

  user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='activities',
  )
  action_type = models.CharField(max_length=50, choices=ActionType.choices)
  group_id = models.IntegerField(null=True, blank=True)
  expense_id = models.IntegerField(null=True, blank=True)
  settlement_hash = models.CharField(max_length=66, blank=True, default='')
  metadata = models.JSONField(default=dict, blank=True)
  message = models.TextField(blank=True, default='')
  is_synced = models.BooleanField(default=True)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    app_label = 'api'
    ordering = ['-created_at']
    verbose_name_plural = 'activities'

  def __str__(self):
    return f'{self.user.subname}: {self.action_type} ({self.created_at:%Y-%m-%d})'
