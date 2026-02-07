from django.conf import settings
from django.db import models


class CachedFriend(models.Model):
  """
  Cached friend relationship. Source of truth is on-chain via
  khaaliSplitFriends contract. This cache enables fast lookups.
  """

  class Status(models.TextChoices):
    PENDING_SENT = 'pending_sent', 'Pending (sent)'
    PENDING_RECEIVED = 'pending_received', 'Pending (received)'
    ACCEPTED = 'accepted', 'Accepted'
    REMOVED = 'removed', 'Removed'

  user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='cached_friends',
  )
  friend_address = models.CharField(max_length=42)
  friend_user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.SET_NULL,
    null=True,
    blank=True,
    related_name='cached_friend_of',
  )
  status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING_SENT)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    app_label = 'api'
    unique_together = ['user', 'friend_address']

  def __str__(self):
    return f'{self.user.subname} → {self.friend_address[:8]}... ({self.status})'
