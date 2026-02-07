"""
Web3 utilities for khaaliSplit.

Server-side Ethereum interactions:
- Signature verification (recover address from signed message)
- Public key recovery from signature
- registerPubKey on-chain call via backend wallet
"""
import logging

from django.conf import settings
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

logger = logging.getLogger('wide_event')

# ABI for khaaliSplitFriends.registerPubKey(address user, bytes pubKey)
REGISTER_PUBKEY_ABI = [
  {
    'inputs': [
      {'internalType': 'address', 'name': 'user', 'type': 'address'},
      {'internalType': 'bytes', 'name': 'pubKey', 'type': 'bytes'},
    ],
    'name': 'registerPubKey',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  }
]

# Chain IDs
CHAIN_IDS = {
  11155111: 'sepolia',
  8453: 'baseSepolia',
  42161: 'arbitrumSepolia',
  43113: 'avalancheFuji',
  1397: 'arc_testnet',
  11155420: 'optimismSepolia',
}

# Token addresses by chain ID
TOKEN_ADDRESSES = {
  11155111: {
    'USDC': '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
    'EURC': '0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4',
  },
  8453: {
    'USDC': '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
    'EURC': '0x808456652fdb597867f38412077A9182bf77359F',
  },
  42161: {
    'USDC': '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
  },
  43113: {
    'USDC': '0x5425890298aed601595a70AB815c96711a31Bc65',
    'EURC': '0x5E44db7996c682E92a960b65AC713a54AD815c6B',
  },
  1397: {
    'USDC': '0x3600000000000000000000000000000000000000',
    'EURC': '0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a',
  },
  11155420: {
    'USDC': '0x5fd84259d66Cd46123540766Be93DFE6D43130D7',
  },
}


def get_w3():
  """Get a Web3 instance connected to Sepolia."""
  rpc_url = settings.SEPOLIA_RPC_URL
  if not rpc_url:
    raise ValueError('SEPOLIA_RPC_URL not configured')
  return Web3(Web3.HTTPProvider(rpc_url))


def recover_address(message: str, signature: str) -> str:
  """
  Recover the signer's address from a signed message.
  Uses EIP-191 personal_sign format.

  Args:
    message: The original message that was signed
    signature: The hex-encoded signature (0x-prefixed)

  Returns:
    Checksummed Ethereum address of the signer
  """
  msg = encode_defunct(text=message)
  return Account.recover_message(msg, signature=signature)


def recover_pubkey(message: str, signature: str) -> str:
  """
  Recover the uncompressed public key from a signed message.
  This is used for ECDH key exchange.

  Args:
    message: The original message that was signed
    signature: The hex-encoded signature (0x-prefixed)

  Returns:
    Hex-encoded uncompressed public key (130 chars, no 0x prefix)
  """
  msg = encode_defunct(text=message)
  # recover_message returns an address; we need the full public key
  # Use ecrecover via eth_keys
  from eth_keys import keys

  sig_bytes = bytes.fromhex(signature[2:] if signature.startswith('0x') else signature)
  # Adjust v value if needed (27/28 → 0/1)
  v = sig_bytes[64]
  if v >= 27:
    v -= 27
  adjusted_sig = sig_bytes[:64] + bytes([v])

  signature_obj = keys.Signature(signature_bytes=adjusted_sig)
  msg_hash = Account._hash_eip191_message(msg)
  pubkey = signature_obj.recover_public_key_from_msg_hash(msg_hash)
  return pubkey.to_hex()[2:]  # strip 0x prefix, returns 130 hex chars


def verify_signature(address: str, message: str, signature: str) -> bool:
  """
  Verify that a signature was produced by the claimed address.

  Args:
    address: Expected signer address
    message: The original message
    signature: The hex-encoded signature

  Returns:
    True if the recovered address matches
  """
  try:
    recovered = recover_address(message, signature)
    return recovered.lower() == address.lower()
  except Exception:
    logger.exception('Signature verification failed')
    return False


def register_pubkey_onchain(user_address: str, pub_key_hex: str) -> str:
  """
  Call registerPubKey on the khaaliSplitFriends contract.
  Sends a transaction from the backend wallet.

  Args:
    user_address: The Ethereum address of the user
    pub_key_hex: The uncompressed public key (hex, no 0x prefix)

  Returns:
    Transaction hash (hex string)
  """
  w3 = get_w3()
  contract_address = settings.CONTRACT_FRIENDS
  private_key = settings.BACKEND_PRIVATE_KEY

  if not contract_address or not private_key:
    raise ValueError('CONTRACT_FRIENDS or BACKEND_PRIVATE_KEY not configured')

  contract = w3.eth.contract(
    address=Web3.to_checksum_address(contract_address),
    abi=REGISTER_PUBKEY_ABI,
  )

  backend_account = Account.from_key(private_key)
  pub_key_bytes = bytes.fromhex(pub_key_hex)

  tx = contract.functions.registerPubKey(
    Web3.to_checksum_address(user_address),
    pub_key_bytes,
  ).build_transaction({
    'from': backend_account.address,
    'nonce': w3.eth.get_transaction_count(backend_account.address),
    'gas': 200_000,
    'gasPrice': w3.eth.gas_price,
    'chainId': 11155111,  # Sepolia
  })

  signed_tx = w3.eth.account.sign_transaction(tx, private_key)
  tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

  logger.info(f'registerPubKey tx sent: {tx_hash.hex()} for {user_address}')
  return tx_hash.hex()
