"""
Greedy min-cash-flow debt simplification algorithm.

Given a list of expenses in a group, compute the minimum set of
settlement transactions needed to balance all debts.
"""
from collections import defaultdict
from decimal import Decimal
import heapq


def compute_net_balances(expenses):
  """
  Compute net balances from a list of expense dicts.

  Each expense should have:
    - creator_address: str (who paid)
    - amount: Decimal (total amount)
    - split_type: 'equal' | 'exact' | 'percentage'
    - participants_json: dict mapping address -> share

  Returns:
    dict[str, Decimal]: net balance per address (positive = owed, negative = owes)
  """
  balances = defaultdict(Decimal)

  for expense in expenses:
    payer = expense['creator_address']
    amount = Decimal(str(expense['amount']))
    participants = expense.get('participants_json', {})
    split_type = expense.get('split_type', 'equal')

    if not participants:
      # If no participants recorded, the payer paid for themselves only
      continue

    if split_type == 'equal':
      count = len(participants)
      if count == 0:
        continue
      share = amount / count
      # Payer is owed by everyone else
      balances[payer] += amount
      for addr in participants:
        balances[addr] -= share

    elif split_type == 'exact':
      # participants_json maps address -> exact amount owed
      balances[payer] += amount
      for addr, owed in participants.items():
        balances[addr] -= Decimal(str(owed))

    elif split_type == 'percentage':
      # participants_json maps address -> percentage (0-100)
      balances[payer] += amount
      for addr, pct in participants.items():
        share = amount * Decimal(str(pct)) / Decimal('100')
        balances[addr] -= share

  return dict(balances)


def simplify_debts(balances):
  """
  Greedy min-cash-flow algorithm to minimize number of transactions.

  Input:
    balances: dict[str, Decimal] — net balance per address
      Positive = is owed money, Negative = owes money

  Returns:
    list[dict] — settlement transactions, each with:
      - from_address: str (debtor)
      - to_address: str (creditor)
      - amount: Decimal (always positive)
  """
  # Filter out zero balances (within tolerance)
  tolerance = Decimal('0.000001')
  creditors = []  # (amount, address) — max-heap (negate for min-heap)
  debtors = []    # (amount, address) — max-heap of debts (negate for min-heap)

  for addr, balance in balances.items():
    if balance > tolerance:
      # This person is owed money
      heapq.heappush(creditors, (-balance, addr))
    elif balance < -tolerance:
      # This person owes money
      heapq.heappush(debtors, (balance, addr))  # balance is already negative

  settlements = []

  while creditors and debtors:
    credit_neg, creditor = heapq.heappop(creditors)
    debt_neg, debtor = heapq.heappop(debtors)

    credit = -credit_neg  # positive: amount owed to creditor
    debt = -debt_neg       # positive: amount debtor owes

    transfer = min(credit, debt)

    settlements.append({
      'from_address': debtor,
      'to_address': creditor,
      'amount': transfer.quantize(Decimal('0.000001')),
    })

    remaining_credit = credit - transfer
    remaining_debt = debt - transfer

    if remaining_credit > tolerance:
      heapq.heappush(creditors, (-remaining_credit, creditor))
    if remaining_debt > tolerance:
      heapq.heappush(debtors, (-remaining_debt, debtor))

  return settlements


def compute_group_debts(expenses_queryset):
  """
  Convenience function: given a queryset of CachedExpense objects,
  compute simplified debts.

  Returns:
    list[dict] with from_address, to_address, amount
  """
  expenses = []
  for exp in expenses_queryset:
    if exp.amount is None:
      continue
    expenses.append({
      'creator_address': exp.creator_address,
      'amount': exp.amount,
      'split_type': exp.split_type,
      'participants_json': exp.participants_json or {},
    })

  balances = compute_net_balances(expenses)
  return simplify_debts(balances)
