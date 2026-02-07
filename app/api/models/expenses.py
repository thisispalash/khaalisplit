from django.conf import settings
from django.db import models


class CachedExpense(models.Model):
  """
  Cached expense from khaaliSplitExpenses contract.
  The encrypted_data field holds AES-256-GCM ciphertext that only
  group members can decrypt with their shared symmetric key.

  The plaintext fields (amount, description, split_type, category,
  participants_json) are populated client-side after decryption and
  sent back to the server for display caching. They may be empty
  if the user hasn't decrypted yet.
  """

  class SplitType(models.TextChoices):
    EQUAL = 'equal', 'Equal'
    EXACT = 'exact', 'Exact amounts'
    PERCENTAGE = 'percentage', 'Percentage'

  expense_id = models.IntegerField(unique=True)  # on-chain ID
  group = models.ForeignKey(
    'api.CachedGroup',
    on_delete=models.CASCADE,
    related_name='expenses',
  )
  creator = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='created_expenses',
  )
  creator_address = models.CharField(max_length=42)
  data_hash = models.CharField(max_length=66, blank=True, default='')
  encrypted_data = models.TextField(blank=True, default='')

  # Decrypted cache fields (populated client-side)
  amount = models.DecimalField(max_digits=18, decimal_places=6, null=True, blank=True)
  description = models.CharField(max_length=500, blank=True, default='')
  split_type = models.CharField(
    max_length=20,
    choices=SplitType.choices,
    default=SplitType.EQUAL,
  )
  category = models.CharField(max_length=50, blank=True, default='')
  participants_json = models.JSONField(default=dict, blank=True)

  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    app_label = 'api'
    ordering = ['-created_at']

  def __str__(self):
    return f'Expense #{self.expense_id} in Group #{self.group.group_id}'
