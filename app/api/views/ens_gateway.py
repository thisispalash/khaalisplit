"""
ENS CCIP-Read gateway view.

Implements EIP-3668 offchain data lookup for khaaliSplitResolver.
Resolves subnames like alice.khaalisplit.eth to addresses and text records.

Endpoint: /api/ens-gateway/{sender}/{data}.json
"""
import json
import logging

from django.conf import settings
from django.http import JsonResponse
from django.views.decorators.http import require_GET
from eth_abi import encode as abi_encode

from api.models import LinkedAddress, User
from api.utils.ens_codec import (
  ADDR_SELECTOR,
  TEXT_SELECTOR,
  decode_addr_call,
  decode_text_call,
  dns_decode,
  encode_addr_response,
  encode_gateway_response,
  encode_text_response,
  extract_subname,
)
from api.utils.ens_signer import sign_response

logger = logging.getLogger('wide_event')


@require_GET
def ccip_read(request, sender, data):
  """
  Handle CCIP-Read requests from the resolver contract.

  The URL format is: /api/ens-gateway/{sender}/{data}.json
  - sender: the resolver contract address
  - data: hex-encoded resolve(bytes name, bytes data) call

  Returns JSON: { data: "0x..." } with the ABI-encoded signed response.
  """
  try:
    # Decode the hex data (strip 0x if present)
    call_data = bytes.fromhex(data[2:] if data.startswith('0x') else data)

    # The call_data is: resolve(bytes name, bytes data)
    # Skip the 4-byte function selector
    from eth_abi import decode
    name_bytes, resolver_data = decode(['bytes', 'bytes'], call_data[4:])

    # Extract the subname from the DNS-encoded name
    subname = extract_subname(name_bytes)

    if not subname:
      return JsonResponse({'error': 'Invalid name'}, status=400)

    # Look up the user
    try:
      user = User.objects.get(subname=subname)
    except User.DoesNotExist:
      return JsonResponse({'error': f'User {subname} not found'}, status=404)

    # Determine what's being resolved
    selector = resolver_data[:4]
    result = _resolve_record(user, selector, resolver_data[4:])

    if result is None:
      return JsonResponse({'error': 'Unsupported record type'}, status=400)

    # Sign the response
    contract_address = settings.CONTRACT_RESOLVER
    if not contract_address:
      return JsonResponse({'error': 'Resolver contract not configured'}, status=500)

    # Reconstruct the original request as the contract would
    request_data = abi_encode(
      ['bytes4', 'bytes', 'bytes'],
      [bytes.fromhex('9061b923'), name_bytes, resolver_data],  # IExtendedResolver.resolve.selector
    )
    # Actually, the request is the full resolve() call:
    request_data = call_data

    expires, signature = sign_response(contract_address, request_data, result)

    # Encode the full response: (bytes result, uint64 expires, bytes signature)
    response_data = encode_gateway_response(result, expires, bytes(signature))

    # Enrich wide event
    request._wide_event['extra']['ens_subname'] = subname
    request._wide_event['extra']['ens_selector'] = selector.hex()

    return JsonResponse({'data': '0x' + response_data.hex()})

  except Exception as e:
    logger.exception('CCIP-Read gateway error')
    return JsonResponse({'error': str(e)}, status=500)


def _resolve_record(user, selector: bytes, call_args: bytes):
  """
  Resolve a specific record type for a user.

  Returns ABI-encoded result bytes, or None if unsupported.
  """
  if selector == ADDR_SELECTOR:
    return _resolve_addr(user)
  elif selector == TEXT_SELECTOR:
    return _resolve_text(user, call_args)
  return None


def _resolve_addr(user):
  """Resolve addr(bytes32) → primary address."""
  primary = LinkedAddress.objects.filter(user=user, is_primary=True).first()
  if not primary:
    # Fall back to any linked address
    primary = user.addresses.first()
  if not primary:
    return encode_addr_response('0x' + '00' * 20)

  return encode_addr_response(primary.address)


def _resolve_text(user, call_args: bytes):
  """Resolve text(bytes32,string) → text record value."""
  try:
    _node, key = decode_text_call(call_args)
  except Exception:
    return None

  text_records = {
    'display': user.display_name or user.subname,
    'avatar': user.avatar_url or '',
    'description': f'khaaliSplit user since {user.created_at.strftime("%b %Y")}',
    'com.khaalisplit.reputation': str(user.reputation_score),
    'com.khaalisplit.subname': user.subname,
  }

  # Add Farcaster FID if set
  if user.farcaster_fid:
    text_records['com.farcaster.fid'] = str(user.farcaster_fid)

  # Add payment preferences (primary chain + token)
  primary = LinkedAddress.objects.filter(user=user, is_primary=True).first()
  if primary:
    text_records['com.khaalisplit.payment.chain'] = str(primary.chain_id)
    text_records['com.khaalisplit.payment.token'] = primary.token

  value = text_records.get(key, '')
  return encode_text_response(value)
