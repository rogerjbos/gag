# GaG Metadata Listener

Off-chain service that watches for mint events on the GaG contract, generates SVG artwork + ERC-721 metadata, uploads to Bulletin TransactionStorage (IPFS), and writes the CID back to the contract.

## Architecture

```
Mint event on Asset Hub
  → Listener detects Transfer(from=0x0) event
  → Reads message from contract.getTokenMessage(tokenId)
  → Generates SVG deterministically (keccak256(message) → seed → traits)
  → Generates ERC-721 JSON metadata with embedded SVG
  → Uploads to Bulletin TransactionStorage via `dotns bulletin upload` → gets IPFS CID
  → Calls contract.setTokenCID(tokenId, cid)
  → tokenURI(tokenId) now returns ipfs://<CID>
```

## Setup

```bash
npm install
```

Prerequisites:
- `dotns` CLI installed (`cd dotns-sdk/packages/cli && bun install && bun run build && npm link`)
- Bulletin account authorized (`dotns bulletin authorize <address>`)

## Usage

### Generate test SVGs

```bash
node generate.js <tokenId> <message>
node generate.js 0 "gm ser"
```

Outputs `output/<tokenId>.svg` and `output/<tokenId>.json`.

### Run the listener

```bash
export RPC_URL=https://eth-rpc-testnet.polkadot.io/
export CONTRACT_ADDRESS=0x...
export UPDATER_KEY=0x...            # Private key of the metadata updater account
export DOTNS_MNEMONIC="word1 ..."   # Mnemonic for Bulletin uploads

node index.js
```

The listener will:
1. Backfill any existing tokens that don't have CIDs
2. Poll for new mint events every 6 seconds (configurable via `POLL_INTERVAL_MS`)
3. Generate + upload + set CID for each new token

## Files

- `renderer.js` — Faithful JS port of the Solidity rendering stack (Renderer.sol + Templates.sol + Utils.sol)
- `generate.js` — Standalone SVG generator for testing
- `index.js` — Event listener + Bulletin uploader + contract CID writer
