# Giggles and Gags — Frontend

Static frontend for the GaG on-chain prank NFT collection on Base.

## Stack

Vanilla HTML/CSS/JS + ethers.js. No framework, no build dependencies (except Node.js for the static site generator).

## Files

- `index.html` — single-page layout with all sections
- `style.css` — dark terminal-style theme
- `config.js` — contract address, chain ID, RPC URL, token metadata
- `abi.js` — minimal contract ABI (GaG + ERC-20)
- `app.js` — wallet connection, form logic, approval flow, minting, burning, claiming
- `build.js` — generates multi-page static site with per-route meta tags

## Local Development

```bash
python3 -m http.server 8080
```

For local testing against a forked Base state:

```bash
anvil --fork-url https://mainnet.base.org --chain-id 8453
```

Then update `config.js` to point `rpcUrl` to `http://127.0.0.1:8545` and deploy the contract to the fork.

## Production Build

```bash
node build.js
```

Output goes to `../dist/`. This generates per-route HTML files with unique OG/Farcaster meta tags, OG images, and a Farcaster manifest template.

Before uploading, place the ethers.js vendor bundle in `dist/vendor/`:

```bash
cd ../dist/vendor
curl -O https://cdnjs.cloudflare.com/ajax/libs/ethers/6.13.4/ethers.umd.min.js
```

## Deployment

Upload `dist/` to IPFS and set the ENS contenthash on `gigglesandgags.eth`. The site is then reachable at `gigglesandgags.eth.limo`.

## Wallet Support

Any injected Ethereum wallet (MetaMask, Rabby, Coinbase Wallet). Must be connected to Base (chain ID 8453). Network switching is prompted automatically.
