from django import forms

from api.models import CachedExpense


class AddExpenseForm(forms.Form):
  """
  Form for adding an expense. The amount and description are entered
  in plaintext, encrypted client-side, and submitted along with the
  encrypted payload.
  """

  description = forms.CharField(
    max_length=500,
    widget=forms.TextInput(attrs={
      'placeholder': 'What was it for?',
    }),
  )
  amount = forms.DecimalField(
    max_digits=18,
    decimal_places=6,
    widget=forms.NumberInput(attrs={
      'placeholder': '0.00',
      'step': '0.01',
      'min': '0.01',
    }),
  )
  split_type = forms.ChoiceField(
    choices=CachedExpense.SplitType.choices,
    initial=CachedExpense.SplitType.EQUAL,
    widget=forms.Select(),
  )
  category = forms.CharField(
    max_length=50,
    required=False,
    widget=forms.TextInput(attrs={
      'placeholder': 'Category (optional)',
    }),
  )

  # Client-side encryption fields (hidden, filled by crypto.js)
  encrypted_data = forms.CharField(
    required=False,
    widget=forms.HiddenInput(),
  )
  data_hash = forms.CharField(
    required=False,
    widget=forms.HiddenInput(),
  )
