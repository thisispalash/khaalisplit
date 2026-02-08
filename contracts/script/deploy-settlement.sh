#!/usr/bin/env zsh
set -euo pipefail

# Deploy khaaliSplitSettlement to all testnet chains.
# Usage: ./script/deploy-settlement.sh
#
# Requires .env with: DEPLOYER_PRIVATE_KEY, OWNER_ADDRESS, ETHERSCAN_API_KEY,
#   SEPOLIA_RPC_URL, BASE_SEPOLIA_RPC_URL, ARBITRUM_SEPOLIA_RPC_URL,
#   OPTIMISM_SEPOLIA_RPC_URL, ARC_TESTNET_RPC_URL
#
# Optional .env: SUBNAME_REGISTRY, REPUTATION_CONTRACT
#   (only relevant for Sepolia — the chain where Subnames/Reputation live)
#
# Requires: jq

if ! command -v jq &> /dev/null; then
  echo "jq is required but not installed. Install with: brew install jq"
  exit 1
fi

SCRIPT="script/DeploySettlement.s.sol:DeploySettlement"
DEPLOYMENTS="deployments.json"
TMP_FILE="deployments-settlement-tmp.json"

# Network type (testnet for all testnet chains)
export NETWORK_TYPE="${NETWORK_TYPE:-testnet}"

# Chain name:chain_id pairs
typeset -A CHAIN_IDS
CHAIN_IDS=(
  sepolia           11155111
  base_sepolia      84532
  arbitrum_sepolia  421614
  optimism_sepolia  11155420
  arc_testnet       5042002
)

CHAINS=(
  sepolia
  base_sepolia
  arbitrum_sepolia
  optimism_sepolia
  arc_testnet
)

# Ensure deployments.json exists
if [ ! -f "$DEPLOYMENTS" ]; then
  echo "{}" > "$DEPLOYMENTS"
fi

for chain in "${CHAINS[@]}"; do
  chain_id="${CHAIN_IDS[$chain]}"

  # Skip if settlement already deployed for this chain
  if jq -e ".\"${chain_id}\".settlement" "$DEPLOYMENTS" > /dev/null 2>&1; then
    echo "  $chain (chain $chain_id) — settlement already in $DEPLOYMENTS, skipping"
    continue
  fi

  echo ""
  echo "============================================"
  echo "  Deploying to: $chain (chain $chain_id)"
  echo "============================================"

  # arc_testnet has no block explorer, skip --verify
  if [ "$chain" = "arc_testnet" ]; then
    forge script "$SCRIPT" --rpc-url "$chain" --broadcast
  else
    forge script "$SCRIPT" --rpc-url "$chain" --broadcast --verify
  fi

  # Merge temp settlement file into deployments.json
  if [ -f "$TMP_FILE" ]; then
    jq -s '.[0] * .[1]' "$DEPLOYMENTS" "$TMP_FILE" > "${DEPLOYMENTS}.tmp"
    mv "${DEPLOYMENTS}.tmp" "$DEPLOYMENTS"
    rm "$TMP_FILE"
    echo "  Merged into $DEPLOYMENTS"
  fi

  echo "  $chain done"
done

echo ""
echo "============================================"
echo "  All deployments complete!"
echo "  Check $DEPLOYMENTS for addresses."
echo "============================================"
