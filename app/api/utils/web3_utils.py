"""
Web3 utilities for khaaliSplit.

Server-side Ethereum interactions:
- Signature verification (recover address from signed message)
- Public key recovery from signature
- Contract interaction helpers (get_contract, send_tx, call_view)
- registerPubKey on-chain call via backend wallet

All on-chain writes go through the backend wallet (BACKEND_PRIVATE_KEY).
"""
import logging

from django.conf import settings
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

logger = logging.getLogger('wide_event')


# ─────────────────────────────────────────────────────────────────────────────
# Chain IDs (testnet only)
# ─────────────────────────────────────────────────────────────────────────────

CHAIN_IDS = {
  11155111: 'sepolia',
  84532: 'baseSepolia',
  421614: 'arbitrumSepolia',
  11155420: 'optimismSepolia',
  5042002: 'arcTestnet',
}

# ─────────────────────────────────────────────────────────────────────────────
# Token addresses by chain ID (USDC only — from contracts/script/tokens.json)
# ─────────────────────────────────────────────────────────────────────────────

TOKEN_ADDRESSES = {
  11155111: {'USDC': '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238'},
  84532:    {'USDC': '0x036CbD53842c5426634e7929541eC2318f3dCF7e'},
  421614:   {'USDC': '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d'},
  11155420: {'USDC': '0x5fd84259d66Cd46123540766Be93DFE6D43130D7'},
  5042002:  {'USDC': '0x3600000000000000000000000000000000000000'},
}

# ─────────────────────────────────────────────────────────────────────────────
# Settlement contract addresses by chain (from contracts/deployments.json)
# ─────────────────────────────────────────────────────────────────────────────

SETTLEMENT_ADDRESSES = {
  11155111: '0xd038e9CD05a71765657Fd3943d41820F5035A6C1',
  84532:    '0xacDbabeDc22BE4eD68D9084Dd3157c27D7154baa',
  421614:   '0x8A20a346a00f809fbd279c1E8B56883998867254',
  11155420: '0x8A20a346a00f809fbd279c1E8B56883998867254',
  5042002:  '0xeB75548245A9C5a31ABF6Eda7CA16977f3Af3690',
}

# ─────────────────────────────────────────────────────────────────────────────
# RPC URL settings key by chain ID
# ─────────────────────────────────────────────────────────────────────────────

CHAIN_RPC_SETTINGS = {
  11155111: 'SEPOLIA_RPC_URL',
  84532:    'BASE_SEPOLIA_RPC_URL',
  421614:   'ARBITRUM_SEPOLIA_RPC_URL',
  11155420: 'OPTIMISM_SEPOLIA_RPC_URL',
  5042002:  'ARC_TESTNET_RPC_URL',
}


# ─────────────────────────────────────────────────────────────────────────────
# Contract ABIs (minimal fragments — only functions the backend needs to call)
# ─────────────────────────────────────────────────────────────────────────────

FRIENDS_ABI = [
  # registerPubKey(address user, bytes pubKey)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'pubKey', 'type': 'bytes'},
    ],
    'name': 'registerPubKey',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # requestFriend(address friend)
  {
    'inputs': [{'name': 'friend', 'type': 'address'}],
    'name': 'requestFriend',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # acceptFriend(address requester)
  {
    'inputs': [{'name': 'requester', 'type': 'address'}],
    'name': 'acceptFriend',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # removeFriend(address friend)
  {
    'inputs': [{'name': 'friend', 'type': 'address'}],
    'name': 'removeFriend',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # getPubKey(address user) → bytes
  {
    'inputs': [{'name': 'user', 'type': 'address'}],
    'name': 'getPubKey',
    'outputs': [{'name': '', 'type': 'bytes'}],
    'stateMutability': 'view',
    'type': 'function',
  },
  # registered(address) → bool
  {
    'inputs': [{'name': '', 'type': 'address'}],
    'name': 'registered',
    'outputs': [{'name': '', 'type': 'bool'}],
    'stateMutability': 'view',
    'type': 'function',
  },
  # ── Relay (backend-only) ──
  # requestFriendFor(address user, address friend)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'friend', 'type': 'address'},
    ],
    'name': 'requestFriendFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # acceptFriendFor(address user, address requester)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'requester', 'type': 'address'},
    ],
    'name': 'acceptFriendFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # removeFriendFor(address user, address friend)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'friend', 'type': 'address'},
    ],
    'name': 'removeFriendFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
]

GROUPS_ABI = [
  # createGroup(bytes32 nameHash, bytes encryptedKey) → uint256
  {
    'inputs': [
      {'name': 'nameHash', 'type': 'bytes32'},
      {'name': 'encryptedKey', 'type': 'bytes'},
    ],
    'name': 'createGroup',
    'outputs': [{'name': 'groupId', 'type': 'uint256'}],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # inviteMember(uint256 groupId, address member, bytes encryptedKey)
  {
    'inputs': [
      {'name': 'groupId', 'type': 'uint256'},
      {'name': 'member', 'type': 'address'},
      {'name': 'encryptedKey', 'type': 'bytes'},
    ],
    'name': 'inviteMember',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # acceptGroupInvite(uint256 groupId)
  {
    'inputs': [{'name': 'groupId', 'type': 'uint256'}],
    'name': 'acceptGroupInvite',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # leaveGroup(uint256 groupId)
  {
    'inputs': [{'name': 'groupId', 'type': 'uint256'}],
    'name': 'leaveGroup',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # getMembers(uint256 groupId) → address[]
  {
    'inputs': [{'name': 'groupId', 'type': 'uint256'}],
    'name': 'getMembers',
    'outputs': [{'name': '', 'type': 'address[]'}],
    'stateMutability': 'view',
    'type': 'function',
  },
  # ── Relay (backend-only) ──
  # createGroupFor(address user, bytes32 nameHash, bytes encryptedKey) → uint256
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'nameHash', 'type': 'bytes32'},
      {'name': 'encryptedKey', 'type': 'bytes'},
    ],
    'name': 'createGroupFor',
    'outputs': [{'name': 'groupId', 'type': 'uint256'}],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # inviteMemberFor(address inviter, uint256 groupId, address member, bytes encryptedKey)
  {
    'inputs': [
      {'name': 'inviter', 'type': 'address'},
      {'name': 'groupId', 'type': 'uint256'},
      {'name': 'member', 'type': 'address'},
      {'name': 'encryptedKey', 'type': 'bytes'},
    ],
    'name': 'inviteMemberFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # acceptGroupInviteFor(address user, uint256 groupId)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'groupId', 'type': 'uint256'},
    ],
    'name': 'acceptGroupInviteFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # leaveGroupFor(address user, uint256 groupId)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'groupId', 'type': 'uint256'},
    ],
    'name': 'leaveGroupFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
]

EXPENSES_ABI = [
  # addExpense(uint256 groupId, bytes32 dataHash, bytes encryptedData) → uint256
  {
    'inputs': [
      {'name': 'groupId', 'type': 'uint256'},
      {'name': 'dataHash', 'type': 'bytes32'},
      {'name': 'encryptedData', 'type': 'bytes'},
    ],
    'name': 'addExpense',
    'outputs': [{'name': 'expenseId', 'type': 'uint256'}],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # updateExpense(uint256 expenseId, bytes32 newDataHash, bytes newEncryptedData)
  {
    'inputs': [
      {'name': 'expenseId', 'type': 'uint256'},
      {'name': 'newDataHash', 'type': 'bytes32'},
      {'name': 'newEncryptedData', 'type': 'bytes'},
    ],
    'name': 'updateExpense',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # ── Relay (backend-only) ──
  # addExpenseFor(address creator, uint256 groupId, bytes32 dataHash, bytes encryptedData) → uint256
  {
    'inputs': [
      {'name': 'creator', 'type': 'address'},
      {'name': 'groupId', 'type': 'uint256'},
      {'name': 'dataHash', 'type': 'bytes32'},
      {'name': 'encryptedData', 'type': 'bytes'},
    ],
    'name': 'addExpenseFor',
    'outputs': [{'name': 'expenseId', 'type': 'uint256'}],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # updateExpenseFor(address creator, uint256 expenseId, bytes32 newDataHash, bytes newEncryptedData)
  {
    'inputs': [
      {'name': 'creator', 'type': 'address'},
      {'name': 'expenseId', 'type': 'uint256'},
      {'name': 'newDataHash', 'type': 'bytes32'},
      {'name': 'newEncryptedData', 'type': 'bytes'},
    ],
    'name': 'updateExpenseFor',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
]

SUBNAMES_ABI = [
  # register(string label, address owner)
  {
    'inputs': [
      {'name': 'label', 'type': 'string'},
      {'name': 'owner', 'type': 'address'},
    ],
    'name': 'register',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # setText(bytes32 node, string key, string value)
  {
    'inputs': [
      {'name': 'node', 'type': 'bytes32'},
      {'name': 'key', 'type': 'string'},
      {'name': 'value', 'type': 'string'},
    ],
    'name': 'setText',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # setAddr(bytes32 node, address _addr)
  {
    'inputs': [
      {'name': 'node', 'type': 'bytes32'},
      {'name': '_addr', 'type': 'address'},
    ],
    'name': 'setAddr',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # text(bytes32 node, string key) → string
  {
    'inputs': [
      {'name': 'node', 'type': 'bytes32'},
      {'name': 'key', 'type': 'string'},
    ],
    'name': 'text',
    'outputs': [{'name': '', 'type': 'string'}],
    'stateMutability': 'view',
    'type': 'function',
  },
  # addr(bytes32 node) → address
  {
    'inputs': [{'name': 'node', 'type': 'bytes32'}],
    'name': 'addr',
    'outputs': [{'name': '', 'type': 'address'}],
    'stateMutability': 'view',
    'type': 'function',
  },
]

REPUTATION_ABI = [
  # getReputation(address user) → uint256
  {
    'inputs': [{'name': 'user', 'type': 'address'}],
    'name': 'getReputation',
    'outputs': [{'name': '', 'type': 'uint256'}],
    'stateMutability': 'view',
    'type': 'function',
  },
  # setUserNode(address user, bytes32 node)
  {
    'inputs': [
      {'name': 'user', 'type': 'address'},
      {'name': 'node', 'type': 'bytes32'},
    ],
    'name': 'setUserNode',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
]

SETTLEMENT_ABI = [
  # settleWithAuthorization(bytes32 recipientNode, uint256 amount, bytes memo, Authorization auth, bytes signature)
  {
    'inputs': [
      {'name': 'recipientNode', 'type': 'bytes32'},
      {'name': 'amount', 'type': 'uint256'},
      {'name': 'memo', 'type': 'bytes'},
      {
        'name': 'auth',
        'type': 'tuple',
        'components': [
          {'name': 'from', 'type': 'address'},
          {'name': 'validAfter', 'type': 'uint256'},
          {'name': 'validBefore', 'type': 'uint256'},
          {'name': 'nonce', 'type': 'bytes32'},
        ],
      },
      {'name': 'signature', 'type': 'bytes'},
    ],
    'name': 'settleWithAuthorization',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
  # settleFromGateway(bytes attestationPayload, bytes attestationSignature, bytes32 recipientNode, address sender, bytes memo)
  {
    'inputs': [
      {'name': 'attestationPayload', 'type': 'bytes'},
      {'name': 'attestationSignature', 'type': 'bytes'},
      {'name': 'recipientNode', 'type': 'bytes32'},
      {'name': 'sender', 'type': 'address'},
      {'name': 'memo', 'type': 'bytes'},
    ],
    'name': 'settleFromGateway',
    'outputs': [],
    'stateMutability': 'nonpayable',
    'type': 'function',
  },
]


# ─────────────────────────────────────────────────────────────────────────────
# Contract registry — maps name → (settings key for address, ABI)
# Settlement uses per-chain addresses from SETTLEMENT_ADDRESSES dict.
# ─────────────────────────────────────────────────────────────────────────────

CONTRACT_REGISTRY = {
  'friends':    ('CONTRACT_FRIENDS',    FRIENDS_ABI),
  'groups':     ('CONTRACT_GROUPS',     GROUPS_ABI),
  'expenses':   ('CONTRACT_EXPENSES',   EXPENSES_ABI),
  'subnames':   ('CONTRACT_SUBNAMES',   SUBNAMES_ABI),
  'reputation': ('CONTRACT_REPUTATION', REPUTATION_ABI),
  'settlement': ('CONTRACT_SETTLEMENT', SETTLEMENT_ABI),
}


# ─────────────────────────────────────────────────────────────────────────────
# Web3 provider helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_w3(chain_id: int = 11155111):
  """Get a Web3 instance connected to the given chain."""
  rpc_setting = CHAIN_RPC_SETTINGS.get(chain_id)
  if not rpc_setting:
    raise ValueError(f'Unsupported chain ID: {chain_id}')

  rpc_url = getattr(settings, rpc_setting, '')
  if not rpc_url:
    raise ValueError(f'{rpc_setting} not configured in settings')

  return Web3(Web3.HTTPProvider(rpc_url))


# ─────────────────────────────────────────────────────────────────────────────
# Contract interaction helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_contract(name: str, chain_id: int = 11155111):
  """
  Get a web3 contract instance by name.

  For settlement on non-Sepolia chains, uses per-chain addresses
  from SETTLEMENT_ADDRESSES. All other contracts are Sepolia-only.

  Args:
    name: Contract name ('friends', 'groups', 'expenses', 'subnames',
          'reputation', 'settlement')
    chain_id: Chain ID (default Sepolia). Only settlement supports
              non-Sepolia chains.

  Returns:
    (web3_instance, contract_instance) tuple
  """
  if name not in CONTRACT_REGISTRY:
    raise ValueError(f'Unknown contract: {name}. '
                     f'Available: {", ".join(CONTRACT_REGISTRY.keys())}')

  settings_key, abi = CONTRACT_REGISTRY[name]
  w3 = get_w3(chain_id)

  # Get the contract address
  if name == 'settlement':
    address = SETTLEMENT_ADDRESSES.get(chain_id)
    if not address:
      raise ValueError(f'No settlement contract for chain {chain_id}')
  else:
    # Non-settlement contracts are Sepolia-only
    if chain_id != 11155111:
      raise ValueError(f'{name} contract only exists on Sepolia (11155111), '
                       f'got chain_id={chain_id}')
    address = getattr(settings, settings_key, '')
    if not address:
      raise ValueError(f'{settings_key} not configured in settings')

  contract = w3.eth.contract(
    address=Web3.to_checksum_address(address),
    abi=abi,
  )
  return w3, contract


def send_tx(
  contract_name: str,
  fn_name: str,
  *args,
  chain_id: int = 11155111,
  gas: int = 300_000,
) -> str:
  """
  Build, sign, and send a transaction from the backend wallet.

  Args:
    contract_name: Contract name (see CONTRACT_REGISTRY)
    fn_name: Function name on the contract
    *args: Positional arguments for the contract function
    chain_id: Chain ID (default Sepolia)
    gas: Gas limit (default 300k)

  Returns:
    Transaction hash (hex string, 0x-prefixed)
  """
  private_key = settings.BACKEND_PRIVATE_KEY
  if not private_key:
    raise ValueError('BACKEND_PRIVATE_KEY not configured')

  w3, contract = get_contract(contract_name, chain_id)
  backend_account = Account.from_key(private_key)

  fn = getattr(contract.functions, fn_name)
  tx = fn(*args).build_transaction({
    'from': backend_account.address,
    'nonce': w3.eth.get_transaction_count(backend_account.address),
    'gas': gas,
    'gasPrice': w3.eth.gas_price,
    'chainId': chain_id,
  })

  signed_tx = w3.eth.account.sign_transaction(tx, private_key)
  tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

  logger.info(f'send_tx({contract_name}.{fn_name}) tx={tx_hash.hex()} '
              f'chain={chain_id}')
  return tx_hash.hex()


def call_view(contract_name: str, fn_name: str, *args, chain_id: int = 11155111):
  """
  Call a view/pure function on a contract. Returns the result.

  Args:
    contract_name: Contract name (see CONTRACT_REGISTRY)
    fn_name: Function name on the contract
    *args: Positional arguments for the contract function
    chain_id: Chain ID (default Sepolia)

  Returns:
    The return value from the contract call
  """
  _w3, contract = get_contract(contract_name, chain_id)
  fn = getattr(contract.functions, fn_name)
  return fn(*args).call()


# ─────────────────────────────────────────────────────────────────────────────
# Signature helpers (unchanged from original)
# ─────────────────────────────────────────────────────────────────────────────

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
  pub_key_bytes = bytes.fromhex(pub_key_hex)
  return send_tx(
    'friends',
    'registerPubKey',
    Web3.to_checksum_address(user_address),
    pub_key_bytes,
    gas=200_000,
  )
