# Giggles and Gags (GaG)

A non-transferable, chaotic slot-machine-style ERC-721 gag NFT collection on Base.

Send a cursed on-chain message to any wallet. The slot buffer decides what mints next. Recipients can't transfer it — they can only burn it by paying.

## How It Works

1. You write a message and pick a victim (any wallet address).
2. You pay in stablecoins (USDC, USDS, USDe, GHO, or crvUSD).
3. The contract randomly selects one of 15 slots. Whatever was in that slot gets minted now.
4. Your message takes the slot's place, waiting for the next person to trigger it.

Tokens are fully on-chain SVGs — metadata, artwork, and messages all live on Base. No IPFS dependency for token data.

## Architecture

```
src/               Solidity contracts (Foundry)
  render/          On-chain SVG renderer and metadata
script/            Deploy scripts
test/              Forge tests
frontend/          Static frontend (vanilla JS + ethers.js)
  build.js         Generates multi-page static site for IPFS
```

## Build

```bash
forge build --via-ir
```

## Test

```bash
forge test --via-ir
```

## Deploy

```bash
DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployGigglesAndGags.s.sol \
    --rpc-url https://mainnet.base.org \
    --broadcast --verify --via-ir
```

## Frontend

The frontend is a static site designed for IPFS hosting via ENS contenthash. Build with:

```bash
cd frontend && node build.js
```

Output goes to `dist/`. Upload to IPFS and set the ENS contenthash.

## Contract

The contract is verified on BaseScan. Key properties:

- Non-transferable (soulbound) — `transferFrom`, `approve`, and `setApprovalForAll` permanently blocked
- Stablecoin payments — exact approvals only, no unlimited allowances
- Burn-to-remove — recipients pay to delete, sender earns tribute (if non-anonymous)
- Fully on-chain — SVG and metadata generated in Solidity, no off-chain dependencies
- OpenZeppelin base — ERC-721, Ownable, Pausable, SafeERC20

## License

MIT
