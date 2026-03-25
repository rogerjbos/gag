/**
 * DotRot — Frontend Configuration (Polkadot Asset Hub Edition)
 */
const GAG_CONFIG = {
  // ---- Contract ----
  contractAddress: "0x28e3D06239859260688F87C0FF183DB1aFbC2351",
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
  siteUrl: "https://dotrot.dot.li",

  // ---- IPFS gateway for fetching metadata ----
  ipfsGateway: "https://paseo-ipfs.polkadot.io/ipfs/",

  // ---- Social ----
  xProfile: "https://x.com/DotRot",
  githubRepo: "https://github.com/rogerjbos/dotrot",

  // ---- Contract deploy block (used to scope event queries) ----
  deployBlock: 0,

  // ---- Misc ----
  maxMessageLength: 64,
};
