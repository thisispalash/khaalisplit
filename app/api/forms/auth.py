from django import forms

from api.models import User


class SignupForm(forms.Form):
  """
  Signup is intentionally minimal — just a password.
  The subname is auto-generated server-side.
  """
  password = forms.CharField(
    min_length=8,
    widget=forms.PasswordInput(attrs={
      'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
               'text-foreground placeholder-foreground/40 focus:outline-none '
               'focus:border-foreground/40',
      'placeholder': 'Choose a password (min 8 chars)',
      'autocomplete': 'new-password',
    }),
  )
  password_confirm = forms.CharField(
    widget=forms.PasswordInput(attrs={
      'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
               'text-foreground placeholder-foreground/40 focus:outline-none '
               'focus:border-foreground/40',
      'placeholder': 'Confirm password',
      'autocomplete': 'new-password',
    }),
  )

  def clean(self):
    cleaned = super().clean()
    pw = cleaned.get('password')
    pw2 = cleaned.get('password_confirm')
    if pw and pw2 and pw != pw2:
      raise forms.ValidationError('Passwords do not match.')
    return cleaned


class LoginForm(forms.Form):
  """Login with subname + password."""
  subname = forms.CharField(
    max_length=100,
    widget=forms.TextInput(attrs={
      'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
               'text-foreground placeholder-foreground/40 focus:outline-none '
               'focus:border-foreground/40',
      'placeholder': 'Your subname (e.g. cool-tiger)',
      'autocomplete': 'username',
    }),
  )
  password = forms.CharField(
    widget=forms.PasswordInput(attrs={
      'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
               'text-foreground placeholder-foreground/40 focus:outline-none '
               'focus:border-foreground/40',
      'placeholder': 'Password',
      'autocomplete': 'current-password',
    }),
  )


class ProfileForm(forms.ModelForm):
  """Onboarding profile edit — display name and avatar."""

  class Meta:
    model = User
    fields = ['display_name', 'avatar_url']
    widgets = {
      'display_name': forms.TextInput(attrs={
        'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
                 'text-foreground placeholder-foreground/40 focus:outline-none '
                 'focus:border-foreground/40',
        'placeholder': 'Display name (optional)',
      }),
      'avatar_url': forms.URLInput(attrs={
        'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
                 'text-foreground placeholder-foreground/40 focus:outline-none '
                 'focus:border-foreground/40',
        'placeholder': 'Avatar URL (optional)',
      }),
    }
