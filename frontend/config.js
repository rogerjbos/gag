/**
 * Giggles and Gags — Frontend Configuration
 */
const GAG_CONFIG = {
  // ---- Contract ----
  contractAddress: "0x96b757bDcECd43624B0CD5f5E7B96E57A642484B",
  chainId: 8453, // Base mainnet
  chainName: "Base",
  rpcUrl: "https://mainnet.base.org",
  // rpcUrl: "http://127.0.0.1:8545",
  blockExplorer: "https://basescan.org",

  // ---- ENS ----
  ensName: "gigglesandgags.eth",

  // ---- Known tokens (fallback labels — the contract is the source of truth) ----
  knownTokens: {
    "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913": { symbol: "USDC",   decimals: 6,  icon: "https://assets.coingecko.com/coins/images/6319/small/usdc.png" },
    "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc": { symbol: "USDS",   decimals: 18, icon: "https://assets.coingecko.com/coins/images/39926/small/usds.png" },
    "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34": { symbol: "USDe",   decimals: 18, icon: "https://assets.coingecko.com/coins/images/33613/small/usde.png" },
    "0x6Bb7a212910682DCFdBd5BCBb3e28FB4E8da10Ee": { symbol: "GHO",    decimals: 18, icon: "https://assets.coingecko.com/coins/images/30663/small/gho.png" },
    "0x417Ac0e078398C154EdFadD9Ef675d30Be60AF93": { symbol: "crvUSD", decimals: 18, icon: "https://assets.coingecko.com/coins/images/28206/small/crvusd.png" },
  },

  // ---- Site ----
  siteUrl: "https://gigglesandgags.eth.limo",

  // ---- Social ----
  farcasterProfile: "https://warpcast.com/gigglesandgags",
  lensProfile: "https://hey.xyz/u/gigglesandgags",
  xProfile: "https://x.com/GigglsNGags",
  githubRepo: "https://github.com/GigglesAndGags/gag",
  discordInvite: "https://discord.gg/y3mS4weF",

  // ---- Contract deploy block (used to scope event queries) ----
  deployBlock: 43261068,

  // ---- Misc ----
  maxMessageLength: 64,
};
