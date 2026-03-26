#!/usr/bin/env bash
#
# deploy-contract.sh — Deploy the DotRot contract to Paseo Asset Hub testnet
#
# Usage:
#   DEPLOYER_PRIVATE_KEY=0x... ./deploy-contract.sh
#
# Prerequisites:
#   - Foundry installed (forge)
#   - DEPLOYER_PRIVATE_KEY env var set
#   - Account funded with PAS tokens from https://faucet.polkadot.io/
#
set -euo pipefail

RPC_URL="${RPC_URL:-https://eth-rpc-testnet.polkadot.io/}"

if [ -z "${DEPLOYER_PRIVATE_KEY:-}" ]; then
  echo "Error: DEPLOYER_PRIVATE_KEY env var is required."
  echo "  export DEPLOYER_PRIVATE_KEY=0x..."
  exit 1
fi

echo "==> Deploying GaG to Paseo Asset Hub"
echo "    RPC: $RPC_URL"
echo ""

DEPLOYER_PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY" \
forge script script/DeployGaG.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  --via-ir

echo ""
echo "==> Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Copy the contract address from the output above"
echo "  2. Update frontend/config.js with the contract address"
echo "  3. Set the metadata updater:"
echo "     cast send <CONTRACT> 'setMetadataUpdater(address)' <UPDATER_ADDRESS> --private-key \$DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL"
echo "  4. Build frontend: cd frontend && node build.js"
echo "  5. Deploy to .dot.li: ./deploy-dotli.sh gag"
echo "  6. Start the listener: cd listener && node index.js"
