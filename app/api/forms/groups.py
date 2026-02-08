from django import forms


class CreateGroupForm(forms.Form):
  """Form for creating a new group."""
  name = forms.CharField(
    max_length=200,
    widget=forms.TextInput(attrs={
      'placeholder': 'Group name (e.g. Trip to Bali)',
    }),
  )
