# khaaliSplit Contracts

Smart contracts for khaaliSplit, built with [Foundry](https://getfoundry.sh/).

## Architecture

| Contract | Chain | Description |
|----------|-------|-------------|
| `khaaliSplitFriends` | Sepolia | Social graph — ECDH pubkey registry + friend requests |
| `khaaliSplitGroups` | Sepolia | Group registry with encrypted group keys |
| `khaaliSplitExpenses` | Sepolia | Expense registry (hashes on-chain, encrypted data in events) |
| `khaaliSplitResolver` | Sepolia | CCIP-Read (EIP-3668) ENS resolver for `*.khaalisplit.eth` |
| `khaaliSplitSettlement` | All chains | Multi-token settlement (USDC, EURC) with EIP-2612 permit |
| `kdioDeployer` | All chains | CREATE2 factory for deterministic proxy addresses |

All contracts (except `kdioDeployer`) use the **UUPS upgradeable proxy pattern**.

## Build & Test

```bash
# Build
forge build

# Run all tests
forge test -vvv

# Gas report
forge test --gas-report
```

## Deployment

Set up your `.env` file:

```bash
DEPLOYER_PRIVATE_KEY=0x...
BACKEND_ADDRESS=0x...
GATEWAY_URL="https://your-gateway.example.com/{sender}/{data}.json"
GATEWAY_SIGNER=0x...
OWNER_ADDRESS=0x...
USDC_ADDRESS=0x...
EURC_ADDRESS=0x...
ETHERSCAN_API_KEY=...
SEPOLIA_RPC_URL=...
BASE_RPC_URL=...
ARBITRUM_RPC_URL=...
```

Then source it and deploy:

```bash
source .env

# Deploy core contracts to Sepolia
forge script script/DeployCore.s.sol:DeployCore --rpc-url sepolia --broadcast --verify

# Deploy settlement to each chain (adds USDC + EURC as allowed tokens)
USDC_ADDRESS=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 EURC_ADDRESS=0x... \
  forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url sepolia --broadcast

USDC_ADDRESS=0x... EURC_ADDRESS=0x... \
  forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url arc_testnet --broadcast

USDC_ADDRESS=0x... EURC_ADDRESS=0x... \
  forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url base --broadcast

USDC_ADDRESS=0x... EURC_ADDRESS=0x... \
  forge script script/DeploySettlement.s.sol:DeploySettlement --rpc-url arbitrum --broadcast
```
