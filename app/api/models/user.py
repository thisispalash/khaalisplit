from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models


class UserManager(BaseUserManager):
  """Custom manager for User model with subname as the identifier."""

  def create_user(self, subname, password=None, **extra_fields):
    if not subname:
      raise ValueError('Users must have a subname')
    user = self.model(subname=subname, **extra_fields)
    if password:
      user.set_password(password)
    else:
      user.set_unusable_password()
    user.save(using=self._db)
    return user

  def create_superuser(self, subname, password=None, **extra_fields):
    extra_fields.setdefault('is_staff', True)
    extra_fields.setdefault('is_superuser', True)
    return self.create_user(subname, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
  """
  khaaliSplit user. The subname is auto-generated at signup,
  immutable, and becomes the ENS subname (e.g. cool-tiger.khaalisplit.eth).
  """
  subname = models.CharField(max_length=100, unique=True)
  display_name = models.CharField(max_length=100, blank=True)
  avatar_url = models.URLField(blank=True, default='')
  reputation_score = models.IntegerField(default=50)
  farcaster_fid = models.IntegerField(blank=True, null=True)
  is_active = models.BooleanField(default=True)
  is_staff = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  objects = UserManager()

  USERNAME_FIELD = 'subname'
  REQUIRED_FIELDS = []

  class Meta:
    app_label = 'api'

  def __str__(self):
    return self.subname


class LinkedAddress(models.Model):
  """
  An Ethereum address linked to a user. Each user can have multiple
  addresses across chains. One is marked primary for settlement.
  """
  user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='addresses')
  address = models.CharField(max_length=42)
  is_primary = models.BooleanField(default=False)
  chain_id = models.IntegerField(default=11155111)  # Sepolia
  token = models.CharField(max_length=10, default='usdc')
  token_addr = models.CharField(max_length=42, blank=True, default='')
  pub_key = models.CharField(max_length=130, blank=True, default='')
  pub_key_registered = models.BooleanField(default=False)
  verified_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    app_label = 'api'
    unique_together = ['user', 'address']

  def __str__(self):
    return f'{self.user.subname}:{self.address[:8]}...{self.address[-4:]}'


class BurntAddress(models.Model):
  """
  Addresses that have been unlinked. Kept to prevent re-linking
  under a different subname (anti-sybil).
  """
  address = models.CharField(max_length=42, unique=True)
  original_subname = models.CharField(max_length=100)
  reason = models.CharField(max_length=200, blank=True, default='')
  burnt_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    app_label = 'api'

  def __str__(self):
    return f'{self.address[:8]}... (was {self.original_subname})'
