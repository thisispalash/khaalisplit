from django import forms


class CreateGroupForm(forms.Form):
  """Form for creating a new group."""
  name = forms.CharField(
    max_length=200,
    widget=forms.TextInput(attrs={
      'class': 'w-full px-3 py-2 bg-background border border-foreground/20 rounded-md '
               'text-foreground placeholder-foreground/40 focus:outline-none '
               'focus:border-foreground/40',
      'placeholder': 'Group name (e.g. Trip to Bali)',
    }),
  )
