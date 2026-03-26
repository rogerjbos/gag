/**
 * GaG — Frontend Configuration (Polkadot Asset Hub Edition)
 */
const GAG_CONFIG = {
  // ---- Contract ----
  contractAddress: "0x5D10ec9754FEa170B376fCfEb370f5f94aa6d6A1",
  chainId: 420420417, // Paseo Asset Hub testnet
  chainName: "Paseo Asset Hub",
  rpcUrl: "https://eth-rpc-testnet.polkadot.io/",
  blockExplorer: "https://blockscout-testnet.polkadot.io",

  // ---- Native token ----
  nativeCurrency: {
    name: "PAS",
    symbol: "PAS",
    decimals: 18,
  },

  // ---- Site ----
  siteUrl: "https://gagged.dot.li",

  // ---- IPFS gateway for fetching metadata ----
  ipfsGateway: "https://paseo-ipfs.polkadot.io/ipfs/",

  // ---- Social ----
  xProfile: "https://x.com/GaG",
  githubRepo: "https://github.com/rogerjbos/gag",

  // ---- Contract deploy block (used to scope event queries) ----
  deployBlock: 0,

  // ---- Misc ----
  maxMessageLength: 64,
};
