"""
ENS gateway response signer.

Signs CCIP-Read responses using the scheme expected by khaaliSplitResolver:
  keccak256(abi.encodePacked(
    0x1900,
    contractAddress,
    expires,
    keccak256(request),
    keccak256(result)
  ))
"""
import time

from django.conf import settings
from eth_abi import encode as abi_encode
from eth_account import Account
from web3 import Web3


# Default response validity: 5 minutes
DEFAULT_TTL = 300


def sign_response(
  contract_address: str,
  request_data: bytes,
  result: bytes,
  ttl: int = DEFAULT_TTL,
) -> tuple[int, bytes]:
  """
  Sign a CCIP-Read response using the gateway signer key.

  The signing scheme matches khaaliSplitResolver.resolveWithProof:
    keccak256(abi.encodePacked(
      0x1900,
      address(this),  // contract_address
      expires,        // uint64
      keccak256(request),
      keccak256(result)
    ))

  Args:
    contract_address: The resolver contract address
    request_data: The original resolve() call data
    result: The ABI-encoded resolution result
    ttl: Response validity in seconds

  Returns:
    (expires, signature) tuple
  """
  signer_key = settings.GATEWAY_SIGNER_KEY
  if not signer_key:
    raise ValueError('GATEWAY_SIGNER_KEY not configured')

  expires = int(time.time()) + ttl

  # Build the message hash matching the contract's verification:
  # keccak256(abi.encodePacked(0x1900, contractAddress, expires, keccak256(request), keccak256(result)))
  request_hash = Web3.solidity_keccak(['bytes'], [request_data])
  result_hash = Web3.solidity_keccak(['bytes'], [result])

  # Pack exactly as the contract does
  message_hash = Web3.solidity_keccak(
    ['bytes2', 'address', 'uint64', 'bytes32', 'bytes32'],
    [
      b'\x19\x00',
      Web3.to_checksum_address(contract_address),
      expires,
      request_hash,
      result_hash,
    ],
  )

  # Sign the hash directly (not as an EIP-191 message — this is a raw hash sign)
  account = Account.from_key(signer_key)
  signed = account.signHash(message_hash)

  return expires, signed.signature
