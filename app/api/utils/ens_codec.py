"""
ENS codec utilities for CCIP-Read gateway.

Handles DNS name parsing, ABI encode/decode for EIP-3668 responses,
and ENS namehash computation.
"""
from eth_abi import decode, encode
from web3 import Web3


def dns_decode(dns_name: bytes) -> str:
  """
  Decode a DNS-encoded name into a human-readable dotted string.
  DNS encoding: each label is prefixed with its length byte, terminated by 0x00.

  Example: b'\\x05alice\\x0bkhaalisplit\\x03eth\\x00' → 'alice.khaalisplit.eth'
  """
  labels = []
  i = 0
  while i < len(dns_name):
    length = dns_name[i]
    if length == 0:
      break
    i += 1
    label = dns_name[i:i + length].decode('utf-8')
    labels.append(label)
    i += length
  return '.'.join(labels)


def extract_subname(dns_name: bytes, parent_domain: str = 'khaalisplit.eth') -> str:
  """
  Extract the subname from a DNS-encoded name.

  Example: DNS for 'alice.khaalisplit.eth' → 'alice'
  """
  full_name = dns_decode(dns_name)
  if full_name.endswith('.' + parent_domain):
    return full_name[: -(len(parent_domain) + 1)]
  return full_name


def decode_resolve_data(data: bytes) -> tuple[bytes, str]:
  """
  Decode the data field from a resolve(bytes name, bytes data) call.
  The data is an ABI-encoded function call to a standard resolver function.

  Returns:
    (selector, decoded_args) where selector is the 4-byte function selector
  """
  selector = data[:4]
  return selector, data[4:]


# Standard resolver function selectors
ADDR_SELECTOR = bytes.fromhex('3b3b57de')  # addr(bytes32)
TEXT_SELECTOR = bytes.fromhex('59d1d43c')  # text(bytes32,string)


def decode_addr_call(data: bytes) -> bytes:
  """Decode addr(bytes32 node) → returns the node."""
  (node,) = decode(['bytes32'], data)
  return node


def decode_text_call(data: bytes) -> tuple[bytes, str]:
  """Decode text(bytes32 node, string key) → returns (node, key)."""
  node, key = decode(['bytes32', 'string'], data)
  return node, key


def encode_addr_response(address: str) -> bytes:
  """ABI-encode an address for addr(bytes32) response."""
  # addr() returns abi.encode(address)
  addr_bytes = bytes.fromhex(address[2:] if address.startswith('0x') else address)
  return encode(['address'], [addr_bytes.rjust(20, b'\x00')[-20:].hex()])


def encode_text_response(value: str) -> bytes:
  """ABI-encode a string for text(bytes32,string) response."""
  return encode(['string'], [value])


def encode_gateway_response(result: bytes, expires: int, signature: bytes) -> bytes:
  """
  ABI-encode the full gateway response for resolveWithProof callback.
  Format: (bytes result, uint64 expires, bytes signature)
  """
  return encode(['bytes', 'uint64', 'bytes'], [result, expires, signature])


# ─────────────────────────────────────────────────────────────────────────────
# ENS Namehash
# ─────────────────────────────────────────────────────────────────────────────

# Pre-computed: namehash("eth")
_ETH_NODE = bytes.fromhex(
  '93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae'
)

# Pre-computed: namehash("khaalisplit.eth")
#   = keccak256(abi.encodePacked(namehash("eth"), keccak256("khaalisplit")))
PARENT_NODE = Web3.solidity_keccak(
  ['bytes32', 'bytes32'],
  [_ETH_NODE, Web3.keccak(text='khaalisplit')],
)


def ens_namehash(name: str) -> bytes:
  """
  Compute the ENS namehash for a dotted name.

  namehash("") = 0x0000...0000
  namehash("eth") = keccak256(namehash("") + keccak256("eth"))
  namehash("khaalisplit.eth") = keccak256(namehash("eth") + keccak256("khaalisplit"))

  Args:
    name: Dotted ENS name (e.g., "cool-tiger.khaalisplit.eth")

  Returns:
    32-byte namehash
  """
  node = b'\x00' * 32
  if not name:
    return node
  labels = name.split('.')
  for label in reversed(labels):
    label_hash = Web3.keccak(text=label)
    node = Web3.keccak(node + label_hash)
  return node


def subname_node(label: str) -> bytes:
  """
  Compute the namehash for a khaaliSplit subname.

  Equivalent to the on-chain `subnameNode(label)` function:
    keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))))

  Args:
    label: The subname label (e.g., "cool-tiger")

  Returns:
    32-byte namehash for `label.khaalisplit.eth`
  """
  return Web3.solidity_keccak(
    ['bytes32', 'bytes32'],
    [PARENT_NODE, Web3.keccak(text=label)],
  )
