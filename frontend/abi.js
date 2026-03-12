/**
 * Giggles and Gags — Minimal ABI
 *
 * Only the functions and events required by the frontend are included.
 * Regenerate from the full compilation artefact if the contract changes.
 */
const GAG_ABI = [
  // ---- Views ----
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function queueSize() view returns (uint8)",
  "function totalMinted() view returns (uint256)",
  "function burnFeeOriginShare() view returns (uint256)",
  "function MAX_BPTS() view returns (uint256)",
  "function supportedToken(address) view returns (bool)",
  "function mintPrices(address) view returns (uint256)",
  "function burnFees(address) view returns (uint256)",
  "function getSupportedTokens() view returns (address[])",
  "function claimable(address token) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function paused() view returns (bool)",
  "function mintingQueue(uint8 index) view returns (address recipient, address origin, string text)",

  // ---- Mutations ----
  "function submitMintIntent(bool anonymize, address recipient, address paymentToken, string message)",
  "function burnToken(uint256 tokenId, address paymentToken)",
  "function claimFees(address token)",

  // ---- ERC-721 standard ----
  "function balanceOf(address owner) view returns (uint256)",

  // ---- Events ----
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
  "event BurnFeeOriginShareUpdated(uint256 previousBurnFeeOriginShare, uint256 newBurnFeeOriginShare)",
  "event PaymentTokenUpdated(address indexed token, uint256 mintingPrice, uint256 burningFee)",
  "event PaymentTokenRemoved(address indexed token)",
];

const ERC20_ABI = [
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];
