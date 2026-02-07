from django.conf import settings
from django.db import models


class CachedGroup(models.Model):
  """
  Cached group from khaaliSplitGroups contract.
  group_id is the on-chain identifier.
  """
  group_id = models.IntegerField(unique=True)
  name = models.CharField(max_length=200, blank=True, default='')
  name_hash = models.CharField(max_length=66, blank=True, default='')
  creator = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='created_groups',
  )
  member_count = models.IntegerField(default=1)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    app_label = 'api'

  def __str__(self):
    return f'Group #{self.group_id}: {self.name or self.name_hash[:12]}'


class CachedGroupMember(models.Model):
  """
  Cached group membership. Each member stores their encrypted
  copy of the group symmetric key.
  """

  class Status(models.TextChoices):
    INVITED = 'invited', 'Invited'
    ACCEPTED = 'accepted', 'Accepted'
    LEFT = 'left', 'Left'

  group = models.ForeignKey(CachedGroup, on_delete=models.CASCADE, related_name='members')
  user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='group_memberships',
  )
  member_address = models.CharField(max_length=42)
  encrypted_key = models.TextField(blank=True, default='')
  status = models.CharField(max_length=20, choices=Status.choices, default=Status.INVITED)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    app_label = 'api'
    unique_together = ['group', 'user']

  def __str__(self):
    return f'{self.user.subname} in Group #{self.group.group_id} ({self.status})'
