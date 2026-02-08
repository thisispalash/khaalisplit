"""
Hasura GraphQL client for khaaliSplit.

Queries the Envio HyperIndex data via Hasura's GraphQL endpoint.
Degrades gracefully if Hasura is not reachable or the envio schema
is not tracked yet.

The indexer writes to the 'envio' schema in khaalisplit_db.
Hasura exposes this via GraphQL at HASURA_URL/v1/graphql.
"""
import json
import logging
import urllib.request
import urllib.error

from django.conf import settings

logger = logging.getLogger('wide_event')


class HasuraError(Exception):
  """Raised when Hasura returns an error or is unreachable."""
  pass


def _hasura_url() -> str:
  """Get Hasura GraphQL endpoint URL."""
  return getattr(settings, 'HASURA_GRAPHQL_URL', '') or 'http://kdio_hasura:8080/v1/graphql'


def _admin_secret() -> str:
  """Get Hasura admin secret for auth."""
  return getattr(settings, 'HASURA_ADMIN_SECRET', '')


def graphql_query(query: str, variables: dict | None = None) -> dict:
  """
  Execute a GraphQL query against Hasura.

  Args:
    query: GraphQL query string
    variables: Optional variables dict

  Returns:
    The 'data' portion of the response

  Raises:
    HasuraError: If the request fails or returns errors
  """
  url = _hasura_url()
  if not url:
    raise HasuraError('HASURA_GRAPHQL_URL not configured')

  headers = {
    'Content-Type': 'application/json',
  }
  secret = _admin_secret()
  if secret:
    headers['x-hasura-admin-secret'] = secret

  body = {'query': query}
  if variables:
    body['variables'] = variables

  data = json.dumps(body).encode('utf-8')
  req = urllib.request.Request(url, data=data, headers=headers, method='POST')

  try:
    with urllib.request.urlopen(req, timeout=10) as resp:
      result = json.loads(resp.read().decode('utf-8'))

    if 'errors' in result:
      error_msg = result['errors'][0].get('message', 'Unknown GraphQL error')
      logger.warning(f'Hasura GraphQL error: {error_msg}')
      raise HasuraError(error_msg)

    return result.get('data', {})

  except urllib.error.URLError as e:
    logger.debug(f'Hasura not reachable: {e.reason}')
    raise HasuraError(f'Hasura connection failed: {e.reason}') from e
  except urllib.error.HTTPError as e:
    error_body = e.read().decode('utf-8', errors='replace')
    logger.warning(f'Hasura HTTP error: {e.code} {error_body}')
    raise HasuraError(f'Hasura returned {e.code}') from e


def is_available() -> bool:
  """Check if Hasura is reachable and the envio schema is queryable."""
  try:
    graphql_query('{ __typename }')
    return True
  except (HasuraError, Exception):
    return False


# ─── Convenience query functions ──────────────────────────────────────────────

def get_friend_requests(user_address: str) -> list:
  """Get friend requests for a user address from the indexer."""
  try:
    query = '''
      query FriendRequests($user: String!) {
        FriendRequest(where: {user: {_eq: $user}}) {
          id
          user
          friend
          status
          timestamp
        }
      }
    '''
    data = graphql_query(query, {'user': user_address.lower()})
    return data.get('FriendRequest', [])
  except HasuraError:
    return []


def get_user_groups(user_address: str) -> list:
  """Get groups a user belongs to from the indexer."""
  try:
    query = '''
      query UserGroups($member: String!) {
        GroupMember(where: {member: {_eq: $member}, status: {_eq: "accepted"}}) {
          id
          groupId
          member
          group {
            id
            groupId
            nameHash
            creator
            memberCount
          }
        }
      }
    '''
    data = graphql_query(query, {'member': user_address.lower()})
    return data.get('GroupMember', [])
  except HasuraError:
    return []


def get_group_expenses(group_id: int) -> list:
  """Get expenses for a group from the indexer."""
  try:
    query = '''
      query GroupExpenses($groupId: numeric!) {
        Expense(where: {groupId: {_eq: $groupId}}, order_by: {timestamp: desc}) {
          id
          expenseId
          creator
          groupId
          dataHash
          encryptedData
          timestamp
        }
      }
    '''
    data = graphql_query(query, {'groupId': group_id})
    return data.get('Expense', [])
  except HasuraError:
    return []


def get_settlements(user_address: str) -> list:
  """Get settlements involving a user address from the indexer."""
  try:
    query = '''
      query UserSettlements($address: String!) {
        Settlement(
          where: {_or: [
            {sender: {_eq: $address}},
            {recipientNode: {_eq: $address}}
          ]},
          order_by: {timestamp: desc},
          limit: 50
        ) {
          id
          sender
          recipientNode
          amount
          token
          sourceChain
          destChain
          txHash
          timestamp
          status
        }
      }
    '''
    data = graphql_query(query, {'address': user_address.lower()})
    return data.get('Settlement', [])
  except HasuraError:
    return []


def get_settlement_by_tx(tx_hash: str) -> dict | None:
  """Get a specific settlement by transaction hash."""
  try:
    query = '''
      query SettlementByTx($txHash: String!) {
        Settlement(where: {txHash: {_eq: $txHash}}, limit: 1) {
          id
          sender
          recipientNode
          amount
          token
          sourceChain
          destChain
          txHash
          timestamp
          status
        }
      }
    '''
    data = graphql_query(query, {'txHash': tx_hash})
    settlements = data.get('Settlement', [])
    return settlements[0] if settlements else None
  except HasuraError:
    return None


def get_subname_records(node: str) -> dict:
  """Get ENS text and addr records for a subname node."""
  try:
    query = '''
      query SubnameRecords($node: String!) {
        TextRecord(where: {node: {_eq: $node}}) {
          key
          value
        }
        AddrRecord(where: {node: {_eq: $node}}, limit: 1) {
          addr
        }
      }
    '''
    data = graphql_query(query, {'node': node})
    text_records = {r['key']: r['value'] for r in data.get('TextRecord', [])}
    addr_records = data.get('AddrRecord', [])
    addr = addr_records[0]['addr'] if addr_records else ''
    return {'text': text_records, 'addr': addr}
  except HasuraError:
    return {'text': {}, 'addr': ''}
