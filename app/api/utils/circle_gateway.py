"""
Circle Gateway API client for khaaliSplit.

Handles cross-chain USDC transfers via Circle's Gateway (CCTP v2).

Flow:
1. Client signs a BurnIntent (EIP-712 typed data) with their wallet.
2. Backend submits the signed BurnIntent to the Gateway API.
3. Gateway returns an attestation + operator signature.
4. Backend calls settleFromGateway() on the settlement contract with
   the attestation data.

API docs: https://developers.circle.com/gateway
Testnet base URL: https://gateway-api-testnet.circle.com
Production base URL: https://gateway-api.circle.com
"""
import json
import logging
import time
import urllib.request
import urllib.error

from django.conf import settings

logger = logging.getLogger('wide_event')

# Circle Gateway domain IDs (not EVM chain IDs)
# https://developers.circle.com/api-reference/gateway/all/get-gateway-info
CHAIN_TO_GATEWAY_DOMAIN = {
  11155111: 0,   # Ethereum (Sepolia → domain 0)
  84532:    6,   # Base (Base Sepolia → domain 6)
  421614:   3,   # Arbitrum (Arbitrum Sepolia → domain 3)
  11155420: 2,   # Optimism (OP Sepolia → domain 2)
  5042002:  26,  # Arc (Arc Testnet → domain 26)
}


class CircleGatewayError(Exception):
  """Raised when the Circle Gateway API returns an error."""
  pass


def _gateway_url() -> str:
  """Get the configured Circle Gateway base URL."""
  return getattr(settings, 'CIRCLE_GATEWAY_URL', '') or 'https://gateway-api-testnet.circle.com'


def _api_key() -> str:
  """Get the Circle API key from settings."""
  key = getattr(settings, 'CIRCLE_API_KEY', '')
  if not key:
    raise CircleGatewayError('CIRCLE_API_KEY not configured')
  return key


def _api_request(method: str, path: str, body: dict | list | None = None) -> dict | list:
  """
  Make an HTTP request to the Circle Gateway API.

  Args:
    method: HTTP method (GET, POST)
    path: API path (e.g., '/v1/transfer')
    body: Request body (JSON-serializable)

  Returns:
    Parsed JSON response
  """
  url = f'{_gateway_url()}{path}'
  headers = {
    'Content-Type': 'application/json',
    'Authorization': f'Bearer {_api_key()}',
  }

  data = json.dumps(body).encode('utf-8') if body is not None else None
  req = urllib.request.Request(url, data=data, headers=headers, method=method)

  try:
    with urllib.request.urlopen(req, timeout=30) as resp:
      return json.loads(resp.read().decode('utf-8'))
  except urllib.error.HTTPError as e:
    error_body = e.read().decode('utf-8', errors='replace')
    logger.error(f'Circle Gateway API error: {e.code} {error_body}')
    raise CircleGatewayError(
      f'Gateway API returned {e.code}: {error_body}'
    ) from e
  except urllib.error.URLError as e:
    logger.error(f'Circle Gateway API connection error: {e.reason}')
    raise CircleGatewayError(f'Gateway API connection failed: {e.reason}') from e


def get_gateway_info() -> dict:
  """
  Fetch Gateway info: supported domains, tokens, contract addresses.

  Returns:
    Gateway info response (domains, tokens, version, etc.)
  """
  return _api_request('GET', '/v1/info')


def estimate_transfer(burn_intents: list[dict]) -> list[dict]:
  """
  Estimate fees and expiration block heights for a transfer.

  This is called BEFORE the user signs, to fill in maxBlockHeight
  and maxFee values for the BurnIntent.

  Args:
    burn_intents: List of PartialBurnIntent dicts, each containing a
                  'spec' (TransferSpec) and optionally maxBlockHeight/maxFee.

  Returns:
    List of complete BurnIntent dicts with calculated maxBlockHeight and maxFee.
  """
  return _api_request('POST', '/v1/estimate', burn_intents)


def create_transfer_attestation(
  signed_burn_intents: list[dict],
  max_attestation_size: int | None = None,
) -> dict:
  """
  Submit signed BurnIntent(s) to the Gateway API and get an attestation.

  This is the core function for cross-chain settlement:
  1. The client signs a BurnIntent (EIP-712).
  2. We submit it here.
  3. Gateway returns attestation + operator signature.
  4. We pass those to settleFromGateway() on-chain.

  Args:
    signed_burn_intents: List of SignedBurnIntent dicts. Each contains:
      - 'intent': { maxBlockHeight, maxFee, spec: TransferSpec }
      - 'signature': hex-encoded signature from the user's wallet
    max_attestation_size: Optional max attestation size in bytes.

  Returns:
    dict with:
      - transferId: UUID
      - attestation: hex-encoded attestation bytes
      - signature: hex-encoded operator signature
      - fees: { total, token, perIntent }
      - expirationBlock: string
  """
  path = '/v1/transfer'
  if max_attestation_size:
    path += f'?maxAttestationSize={max_attestation_size}'

  return _api_request('POST', path, signed_burn_intents)


def get_gateway_attestation(
  signed_burn_intent: dict,
) -> dict:
  """
  Convenience wrapper: submit a single signed BurnIntent and return
  the attestation data needed for settleFromGateway().

  Args:
    signed_burn_intent: A SignedBurnIntent dict containing:
      - 'intent': { maxBlockHeight, maxFee, spec: TransferSpec }
      - 'signature': hex-encoded user signature

  Returns:
    dict with:
      - attestation: hex bytes for attestationPayload param
      - signature: hex bytes for attestationSignature param
      - transferId: UUID for tracking
  """
  result = create_transfer_attestation([signed_burn_intent])

  logger.info(
    f'Circle Gateway attestation received: transferId={result.get("transferId")}'
  )

  return {
    'attestation': result['attestation'],
    'signature': result['signature'],
    'transferId': result.get('transferId', ''),
  }


def build_transfer_spec(
  source_chain_id: int,
  dest_chain_id: int,
  depositor_address: str,
  recipient_address: str,
  amount: str,
  source_contract: str = '',
  dest_contract: str = '',
  source_token: str = '',
  dest_token: str = '',
) -> dict:
  """
  Build a TransferSpec dict for a USDC cross-chain transfer.

  Addresses are left-padded to 32 bytes (bytes32) as required by the API.

  Args:
    source_chain_id: Source EVM chain ID
    dest_chain_id: Destination EVM chain ID
    depositor_address: Sender's address (0x...)
    recipient_address: Recipient's address (0x...)
    amount: Transfer amount in token base units (string)
    source_contract: Source Gateway wallet contract (from /v1/info)
    dest_contract: Destination Gateway minter contract (from /v1/info)
    source_token: Source USDC address (from /v1/info)
    dest_token: Destination USDC address (from /v1/info)

  Returns:
    TransferSpec dict ready for estimate or signing.
  """
  from api.utils.web3_utils import TOKEN_ADDRESSES

  source_domain = CHAIN_TO_GATEWAY_DOMAIN.get(source_chain_id)
  dest_domain = CHAIN_TO_GATEWAY_DOMAIN.get(dest_chain_id)

  if source_domain is None:
    raise CircleGatewayError(f'Unsupported source chain: {source_chain_id}')
  if dest_domain is None:
    raise CircleGatewayError(f'Unsupported destination chain: {dest_chain_id}')

  def _pad32(addr: str) -> str:
    """Pad an address to 32 bytes (64 hex chars + 0x prefix)."""
    clean = addr.lower().replace('0x', '')
    return '0x' + clean.zfill(64)

  # Default to USDC addresses from our token registry if not specified
  if not source_token:
    source_token = TOKEN_ADDRESSES.get(source_chain_id, {}).get('USDC', '')
  if not dest_token:
    dest_token = TOKEN_ADDRESSES.get(dest_chain_id, {}).get('USDC', '')

  import os
  salt = '0x' + os.urandom(32).hex()

  return {
    'version': 0,
    'sourceDomain': source_domain,
    'destinationDomain': dest_domain,
    'sourceContract': _pad32(source_contract) if source_contract else _pad32('0' * 40),
    'destinationContract': _pad32(dest_contract) if dest_contract else _pad32('0' * 40),
    'sourceToken': _pad32(source_token),
    'destinationToken': _pad32(dest_token),
    'sourceDepositor': _pad32(depositor_address),
    'destinationRecipient': _pad32(recipient_address),
    'sourceSigner': _pad32(depositor_address),
    'destinationCaller': _pad32('0' * 40),
    'value': str(amount),
    'salt': salt,
  }
