#!/usr/bin/env bash
#
# deploy-dotli.sh — Deploy the DotRot frontend to Polkadot Bulletin via DotNS
#
# Usage:
#   ./deploy-dotli.sh              # deploys dist/ → dotrot.dot
#   ./deploy-dotli.sh myname       # deploys dist/ → myname.dot
#
# Prerequisites:
#   - dotns-sdk checked out at ../dotns-sdk (with CLI built)
#   - DOTNS_MNEMONIC env var set (BIP39 mnemonic)
#   - jq installed
#   - ipfs (Kubo) installed for CAR mode
#   - Frontend built: cd frontend && node build.js
#
set -euo pipefail

NAME="${1:-dotrot}"
BUILD_DIR="./dist"
BULLETIN_RPC="wss://paseo-bulletin-rpc.polkadot.io"
DOTNS_RPC="wss://asset-hub-paseo-rpc.n.dwellir.com"

# Locate dotns CLI — prefer local dotns-sdk build, fall back to global
DOTNS_SDK="${DOTNS_SDK:-../dotns-sdk}"
if [ -f "$DOTNS_SDK/packages/cli/dist/cli.js" ]; then
  DOTNS="node $DOTNS_SDK/packages/cli/dist/cli.js"
  echo "Using dotns CLI from $DOTNS_SDK"
else
  DOTNS="dotns"
  echo "Using global dotns CLI ($(which dotns 2>/dev/null || echo 'not found'))"
fi

if [ -z "${DOTNS_MNEMONIC:-}" ]; then
  echo "Error: DOTNS_MNEMONIC env var is required."
  echo "  export DOTNS_MNEMONIC=\"your twelve word mnemonic ...\""
  exit 1
fi

# Check dist exists
if [ ! -d "$BUILD_DIR" ]; then
  echo "Error: $BUILD_DIR not found. Run 'cd frontend && node build.js' first."
  exit 1
fi

# Check ethers vendor bundle
if grep -q "vendor bundle missing" "$BUILD_DIR/vendor/ethers.umd.min.js" 2>/dev/null; then
  echo "--- Downloading ethers.js UMD bundle ---"
  curl -sL -o "$BUILD_DIR/vendor/ethers.umd.min.js" \
    "https://cdnjs.cloudflare.com/ajax/libs/ethers/6.13.4/ethers.umd.min.js"
  echo "Downloaded ethers.js to dist/vendor/"
fi

echo "==> Deploying ${BUILD_DIR} to ${NAME}.dot"

# 1. Authorize account for Bulletin TransactionStorage
echo ""
echo "--- Step 1: Authorize account for Bulletin ---"
ADDRESS=$($DOTNS account address -m "$DOTNS_MNEMONIC" --rpc "$DOTNS_RPC")
echo "Account: $ADDRESS"

$DOTNS bulletin authorize "$ADDRESS" -m "$DOTNS_MNEMONIC" --bulletin-rpc "$BULLETIN_RPC" --rpc "$DOTNS_RPC" || {
  echo "(already authorized — continuing)"
}

# 2. Upload to Bulletin
echo ""
echo "--- Step 2: Upload to Bulletin ---"

RESULT=$(NODE_OPTIONS="--max-old-space-size=4096" $DOTNS bulletin upload "$BUILD_DIR" --json --parallel -m "$DOTNS_MNEMONIC" --bulletin-rpc "$BULLETIN_RPC" --rpc "$DOTNS_RPC")
CID=$(echo "$RESULT" | jq -r '.cid')
echo "CID: $CID"

# 3. Register domain (and subdomain if needed)
echo ""
echo "--- Step 3: Register domain (if needed) ---"

if [[ "$NAME" == *.* ]]; then
  SUB="${NAME%%.*}"
  PARENT="${NAME#*.}"

  $DOTNS register domain --name "$PARENT" --status full -m "$DOTNS_MNEMONIC" --rpc "$DOTNS_RPC" 2>/dev/null || echo "${PARENT}.dot already registered — skipping"

  echo "Registering subdomain ${SUB}.${PARENT}.dot ..."
  $DOTNS register subname --name "$SUB" --parent "$PARENT" -m "$DOTNS_MNEMONIC" --rpc "$DOTNS_RPC"
else
  $DOTNS register domain --name "$NAME" --status full -m "$DOTNS_MNEMONIC" --rpc "$DOTNS_RPC" 2>/dev/null || echo "${NAME}.dot already registered — skipping"
fi

# 4. Set contenthash
echo ""
echo "--- Step 4: Set contenthash ---"
$DOTNS content set "$NAME" "$CID" -m "$DOTNS_MNEMONIC" --rpc "$DOTNS_RPC"

# 5. Verify
echo ""
echo "--- Step 5: Verify ---"
$DOTNS content view "$NAME" --rpc "$DOTNS_RPC" || true

echo ""
echo "==> Done! Your site is live at:"
echo "    https://${NAME}.dot.li"
echo ""
echo "==> IPFS gateway:"
echo "    https://paseo-ipfs.polkadot.io/ipfs/${CID}"
