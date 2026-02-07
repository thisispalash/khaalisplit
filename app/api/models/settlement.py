from django.conf import settings
from django.db import models


class CachedSettlement(models.Model):
  """
  Cached settlement transaction. Tracks the lifecycle of a USDC
  payment from initiation through optional bridging to confirmation.
  """

  class Status(models.TextChoices):
    PENDING = 'pending', 'Pending'
    SUBMITTED = 'submitted', 'Submitted'
    BRIDGING = 'bridging', 'Bridging'
    CONFIRMED = 'confirmed', 'Confirmed'
    FAILED = 'failed', 'Failed'

  tx_hash = models.CharField(max_length=66, unique=True)
  from_user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.CASCADE,
    related_name='sent_settlements',
  )
  from_address = models.CharField(max_length=42)
  to_address = models.CharField(max_length=42)
  to_user = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.SET_NULL,
    null=True,
    blank=True,
    related_name='received_settlements',
  )
  token = models.CharField(max_length=10, default='usdc')
  amount = models.DecimalField(max_digits=18, decimal_places=6)
  source_chain = models.IntegerField()
  dest_chain = models.IntegerField()
  status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
  group = models.ForeignKey(
    'api.CachedGroup',
    on_delete=models.SET_NULL,
    null=True,
    blank=True,
    related_name='settlements',
  )
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    app_label = 'api'
    ordering = ['-created_at']

  def __str__(self):
    return f'{self.tx_hash[:10]}... ({self.amount} {self.token} {self.status})'
