<div align="center">

# GaG

**Non-transferable prank NFTs on Polkadot Asset Hub.**
**15-slot chaos buffer · off-chain SVG via Bulletin IPFS · PAS token powered.**

1 PAS to curse. 2 PAS to escape.

[![Website](https://img.shields.io/badge/Website-gagged.dot.li-E6007A?style=for-the-badge)](https://gagged.dot.li)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-363636?style=flat-square&logo=solidity&logoColor=white)](https://soliditylang.org/)
[![Polkadot](https://img.shields.io/badge/Chain-Paseo_Asset_Hub-E6007A?style=flat-square)](https://docs.polkadot.com/smart-contracts/connect/)

</div>

---

> **Fork notice:** GaG is a port of [Giggles & Gags](https://github.com/GigglesAndGags/gag) (originally on Base) to the Polkadot ecosystem. The core slot-buffer game mechanic is preserved, with key changes: native PAS token payments instead of stablecoins, off-chain SVG rendering stored on Bulletin TransactionStorage (IPFS) instead of on-chain rendering, and .dot.li hosting instead of ENS.

---

Send a cursed on-chain message to any wallet. The slot buffer decides what mints next. Recipients can't transfer it — they can only burn it by paying.

## How It Works

1. You write a message and pick a victim (any wallet address).
2. You pay in PAS (native token on Paseo Asset Hub testnet).
3. The contract randomly selects one of 15 slots. Whatever was in that slot gets minted now.
4. Your message takes the slot's place, waiting for the next person to trigger it.

After minting, an off-chain listener generates the SVG artwork deterministically, uploads it to IPFS via Bulletin TransactionStorage, and writes the CID back to the contract.

## Architecture

```
src/               Solidity contracts (Foundry)
  render/Utils.sol Text validation library
script/            Deploy scripts
test/              Forge tests (124 passing)
frontend/          Static frontend (vanilla JS + ethers.js)
  build.js         Generates multi-page static site for .dot.li
listener/          Off-chain metadata service
  renderer.js      JS port of the Solidity SVG renderer
  index.js         Event listener + Bulletin uploader + CID writer
  generate.js      Standalone SVG generator for testing
```

## Changes from the Original

| Aspect | Giggles & Gags (Base) | GaG (Asset Hub) |
|--------|----------------------|-------------------|
| Chain | Base (8453) | Paseo Asset Hub (420420417) |
| Payment | ERC-20 stablecoins | Native PAS tokens |
| SVG rendering | On-chain (Solidity) | Off-chain (JS) + IPFS via Bulletin |
| Metadata storage | On-chain base64 | IPFS CID reference |
| Domain | gigglesandgags.eth.limo | gagged.dot.li |
| Name resolution | ENS / Basenames / UD | Direct address only |
| Token symbol | GaG | GAG |

## Build

```bash
forge build
```

## Test

```bash
forge test
```

## Deploy

### 1. Contract

```bash
DEPLOYER_PRIVATE_KEY=0x... ./deploy-contract.sh
```

### 2. Set metadata updater

```bash
cast send <CONTRACT> 'setMetadataUpdater(address)' <UPDATER_ADDRESS> \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --rpc-url https://eth-rpc-testnet.polkadot.io/
```

### 3. Frontend

```bash
cd frontend && node build.js
DOTNS_MNEMONIC="..." ./deploy-dotli.sh gag
```

### 4. Listener

```bash
cd listener && npm install
RPC_URL=https://eth-rpc-testnet.polkadot.io/ \
CONTRACT_ADDRESS=0x... \
UPDATER_KEY=0x... \
DOTNS_MNEMONIC="..." \
node index.js
```

The listener can run on any server. Set `DOTNS_CLI="node ./cli.js"` if using a local copy of the dotns CLI instead of a global install.

## Contract

Deployed on Paseo Asset Hub testnet. Key properties:

- Non-transferable (soulbound) — `transferFrom`, `approve`, and `setApprovalForAll` permanently blocked
- Native token payments — no ERC-20 approvals needed
- Burn-to-remove — recipients pay to delete, sender earns tribute (if non-anonymous)
- Off-chain SVG — deterministic rendering uploaded to IPFS, contract stores CID reference
- OpenZeppelin base — ERC-721, Ownable, Pausable

## License

MIT
