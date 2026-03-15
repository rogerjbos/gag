/**
 * Giggles and Gags — Frontend Application
 *
 * Pure client-side logic. Connects to the GaG contract via ethers.js,
 * handles wallet connection, approval flow, minting, burning, and claiming.
 */

/* global ethers, GAG_CONFIG, GAG_ABI, ERC20_ABI */

// ---------------------------------------------------------------------------
//  ERC-8021 Builder Code Attribution
// ---------------------------------------------------------------------------
/**
 * Build the ERC-8021 data suffix for Base Builder Code attribution.
 * Format: <builder code as UTF-8 hex> + 0x80218021802180218021802180218021 (16-byte marker)
 * The EVM ignores trailing calldata, so this is safe for any contract call.
 */
function getBuilderCodeSuffix() {
  if (!GAG_CONFIG.builderCode) return null;
  const codeHex = ethers.hexlify(ethers.toUtf8Bytes(GAG_CONFIG.builderCode));
  const marker = "0x80218021802180218021802180218021";
  // Strip 0x prefixes and concatenate
  return codeHex.slice(2) + marker.slice(2);
}

/**
 * Send a contract transaction with the Builder Code suffix appended to calldata.
 * Uses signer.sendTransaction with manually encoded data.
 */
async function sendWithAttribution(contract, method, args) {
  const suffix = getBuilderCodeSuffix();
  if (!suffix) {
    // No builder code configured — send normally
    return contract[method](...args);
  }
  const calldata = contract.interface.encodeFunctionData(method, args);
  const tx = await signer.sendTransaction({
    to: await contract.getAddress(),
    data: calldata + suffix,
  });
  return tx;
}

// ---------------------------------------------------------------------------
//  Farcaster Mini App Support
// ---------------------------------------------------------------------------
let farcasterSdk = null;
let isMiniApp = false;

/**
 * Initialize Farcaster Mini App — call sdk.actions.ready() to dismiss splash,
 * and get the embedded wallet provider.
 * The UMD bundle from jsdelivr exposes the SDK as window.miniapp.sdk.
 * Calling ready() outside a mini app context is harmless (it just does nothing).
 * Returns the EIP-1193 provider from the mini app, or null.
 */
async function initMiniApp() {
  // The UMD bundle exposes miniapp.sdk globally
  farcasterSdk = (typeof miniapp !== "undefined" && miniapp.sdk) ? miniapp.sdk : null;

  if (!farcasterSdk) {
    console.log("[GaG] Farcaster SDK not available — normal browser mode");
    return null;
  }

  // Detect if we're in an iframe (mini app context)
  try {
    isMiniApp = window !== window.parent;
  } catch (e) {
    isMiniApp = true; // cross-origin iframe = embedded
  }

  console.log("[GaG] Farcaster SDK found, isMiniApp:", isMiniApp, "— calling ready()...");
  try {
    await farcasterSdk.actions.ready();
    console.log("[GaG] sdk.actions.ready() called — splash dismissed");
  } catch (e) {
    console.warn("[GaG] sdk.actions.ready() failed:", e);
  }

  // Only try to get wallet provider if in mini app context
  if (isMiniApp) {
    try {
      const ethProvider = await farcasterSdk.wallet.getEthereumProvider();
      console.log("[GaG] Got mini app Ethereum provider");
      return ethProvider;
    } catch (e) {
      console.warn("[GaG] Could not get mini app wallet provider:", e);
    }
  }

  return null;
}

/** Cached mini app Ethereum provider (set during init). */
let miniAppProvider = null;

/**
 * Get the best available EIP-1193 provider.
 * Prefers the mini app provider, falls back to window.ethereum.
 */
function getEthereumProvider() {
  return miniAppProvider || window.ethereum || null;
}

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------
let provider = null;
let signer = null;
let gagContract = null;
let gagReadOnly = null;
let userAddress = null;
let supportedTokens = [];    // [{ address, symbol, decimals, mintPrice, burnFee }]
let selectedToken = null;
let anonymize = true;        // ghost mode by default
let resolvedRecipient = null; // resolved address from ENS / UD name
let resolvingName = false;    // true while async resolution is in progress
let resolveDebounce = null;   // debounce timer for name resolution
let selectedBurnToken = null; // selected token for burn fee payment

// ---------------------------------------------------------------------------
//  Name Resolution — ENS & Unstoppable Domains
// ---------------------------------------------------------------------------

/** TLDs handled by Unstoppable Domains. */
const UD_TLDS = [
  ".crypto", ".x", ".nft", ".dao", ".wallet", ".blockchain",
  ".bitcoin", ".888", ".polygon", ".zil", ".go", ".klever",
  ".hi", ".kresus", ".anime", ".manga",
];

/** Returns true when `name` ends with an Unstoppable Domains TLD. */
function isUDName(name) {
  const lower = name.toLowerCase();
  return UD_TLDS.some(tld => lower.endsWith(tld));
}

/** Returns true when `name` ends with `.base.eth` (Basename on Base L2). */
function isBasename(name) {
  return name.toLowerCase().endsWith(".base.eth");
}

/** Returns true when `name` ends with `.eth` (but NOT `.base.eth`). */
function isENSName(name) {
  const lower = name.toLowerCase();
  return lower.endsWith(".eth") && !lower.endsWith(".base.eth");
}

/**
 * Mainnet RPC endpoints for ENS / UD resolution.
 * Multiple endpoints for fallback in case one is down or CORS-blocked.
 */
const MAINNET_RPCS = [
  "https://cloudflare-eth.com",
  "https://ethereum-rpc.publicnode.com",
  "https://rpc.ankr.com/eth",
  "https://eth.llamarpc.com",
];

/**
 * Try to create a working mainnet provider from the fallback RPC list.
 * Returns the first provider that successfully responds.
 */
async function getMainnetProvider() {
  for (const url of MAINNET_RPCS) {
    try {
      const p = new ethers.JsonRpcProvider(url, 1, { staticNetwork: true });
      // Quick health check — if this fails, try the next RPC.
      await p.getBlockNumber();
      return p;
    } catch {
      continue;
    }
  }
  return null;
}

/**
 * Resolve an ENS name to an Ethereum address.
 * ENS lives on Ethereum mainnet. Since this dApp runs on Base, we always
 * need to talk to a mainnet RPC to resolve .eth names.
 */
async function resolveENS(name) {
  try {
    const mainnet = await getMainnetProvider();
    if (!mainnet) {
      console.warn("ENS resolution: no mainnet RPC available");
      return null;
    }
    const addr = await mainnet.resolveName(name);
    return addr; // may be null if unregistered
  } catch (e) {
    console.warn("ENS resolution failed:", e);
    return null;
  }
}

/**
 * Resolve a Basename (e.g. "jesse.base.eth") directly on Base L2.
 * Queries the on-chain ENS Registry + L2Resolver deployed on Base.
 * This avoids CCIP-Read / off-chain gateway dependencies.
 */
async function resolveBasename(name) {
  // Base L2 ENS contracts (deployed by Coinbase / Base team)
  const BASE_REGISTRY = "0xb94704422c2a1e396835a571837aa5ae53285a95";
  const REGISTRY_ABI = [
    "function resolver(bytes32 node) view returns (address)",
  ];
  const RESOLVER_ABI = [
    "function addr(bytes32 node) view returns (address)",
  ];

  try {
    const baseProvider = provider; // already connected to Base
    if (!baseProvider) {
      console.warn("Basename resolution: no Base provider available");
      return null;
    }

    const registry = new ethers.Contract(BASE_REGISTRY, REGISTRY_ABI, baseProvider);
    const node = ethers.namehash(name);

    // Look up the resolver assigned to this name
    const resolverAddr = await registry.resolver(node);
    if (!resolverAddr || resolverAddr === ethers.ZeroAddress) {
      return null; // name not registered
    }

    // Query the resolver for the ETH address
    const resolver = new ethers.Contract(resolverAddr, RESOLVER_ABI, baseProvider);
    const addr = await resolver.addr(node);

    if (!addr || addr === ethers.ZeroAddress) {
      return null;
    }
    return addr;
  } catch (e) {
    console.warn("Basename resolution failed:", e);
    return null;
  }
}

/**
 * Resolve an Unstoppable Domains name to an ETH address.
 * Uses the UD ProxyReader smart contract on Ethereum mainnet.
 */
async function resolveUD(name) {
  const UD_PROXY_READER = "0xc3C2BAB5e3e52DBF311b2aAcEf2e40344f19494E";
  const UD_ABI = [
    "function getMany(string[] keys, uint256 tokenId) view returns (string[])",
  ];

  try {
    const mainnet = await getMainnetProvider();
    if (!mainnet) {
      console.warn("UD resolution: no mainnet RPC available");
      return null;
    }
    const reader = new ethers.Contract(UD_PROXY_READER, UD_ABI, mainnet);

    // Compute UD namehash (EIP-137 compatible)
    const namehash = computeUDNamehash(name);
    const keys = ["crypto.ETH.address"];
    const results = await reader.getMany(keys, namehash);

    const ethAddr = results[0];
    if (ethAddr && ethers.isAddress(ethAddr)) {
      return ethAddr;
    }
    return null;
  } catch (e) {
    console.warn("UD resolution failed:", e);
    return null;
  }
}

/**
 * Compute UD/EIP-137 namehash for a domain.
 * e.g. "brad.crypto" → namehash("brad.crypto")
 */
function computeUDNamehash(name) {
  const labels = name.split(".").reverse();
  let node = ethers.ZeroHash;
  for (const label of labels) {
    node = ethers.keccak256(
      ethers.concat([node, ethers.keccak256(ethers.toUtf8Bytes(label))])
    );
  }
  return node;
}

/**
 * Attempt to resolve a name (Basename, ENS, or UD). Returns the address or null.
 */
async function resolveName(name) {
  if (isBasename(name)) {
    return resolveBasename(name);
  }
  if (isENSName(name)) {
    return resolveENS(name);
  }
  if (isUDName(name)) {
    return resolveUD(name);
  }
  return null;
}

// ---------------------------------------------------------------------------
//  Router — path-based page detection
// ---------------------------------------------------------------------------

/**
 * Detect the current page from the <meta name="gag-page"> tag set by the
 * build script, or infer from the URL path.
 * Returns: "home" | "send" | "burn" | "claim" | "how" | "gag"
 */
function detectPage() {
  // Check build-injected meta tag first
  const metaEl = document.querySelector('meta[name="gag-page"]');
  if (metaEl) return metaEl.getAttribute("content");

  // Fallback: infer from URL path (for local dev without build)
  const path = window.location.pathname.replace(/\/index\.html$/, "").replace(/\/$/, "");
  if (path.endsWith("/send")) return "send";
  if (path.endsWith("/burn")) return "burn";
  if (path.endsWith("/claim")) return "claim";
  if (path.endsWith("/how")) return "how";
  if (path.endsWith("/gag") || path.includes("/gag/")) return "gag";
  return "home";
}

/** Get the scroll-to section ID from meta or route config. */
function getScrollTarget() {
  const metaEl = document.querySelector('meta[name="gag-scroll-to"]');
  return metaEl ? metaEl.getAttribute("content") : null;
}

/** Current page identifier. */
const GAG_CURRENT_PAGE = detectPage();

/**
 * Apply page routing: for the token page, hide everything except the token
 * section. For other pages, auto-scroll to the relevant section.
 */
function applyRouting() {
  if (GAG_CURRENT_PAGE === "gag") {
    // Token page — hide all regular sections, show only token page + header/footer
    const sectionsToHide = [
      "hero", "how-it-works", "mint", "burn-info", "burn", "claim", "lore", "trust",
    ];
    for (const id of sectionsToHide) {
      const el = document.getElementById(id);
      if (el) el.style.display = "none";
    }
    // Show token page
    const gagPage = document.getElementById("gag-page");
    if (gagPage) gagPage.style.display = "block";
    // Load token data
    loadGagPage();
  } else {
    // Standard page — auto-scroll to target section after a brief delay
    const scrollTarget = getScrollTarget();
    if (scrollTarget) {
      setTimeout(() => {
        const el = document.getElementById(scrollTarget);
        if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 300);
    }
  }
}

// ---------------------------------------------------------------------------
//  Token Page Logic (/gag/?id=N)
// ---------------------------------------------------------------------------

/** Extract token ID from query string. */
function getGagTokenId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || params.get("tokenId") || null;
}

/** Load and render a specific token's data on the gag page. */
async function loadGagPage() {
  const tokenIdStr = getGagTokenId();
  const svgContainer = document.getElementById("gag-page-svg");
  const idBadge = document.getElementById("gag-page-id");
  const ownerEl = document.getElementById("gag-page-owner");
  const attrEl = document.getElementById("gag-page-attribution");
  const burnCta = document.getElementById("gag-page-burn-cta");

  if (!tokenIdStr) {
    svgContainer.innerHTML = '<div class="preview-placeholder">No token ID specified. Use ?id=N in the URL.</div>';
    return;
  }

  const tokenId = BigInt(tokenIdStr);
  idBadge.textContent = "#" + tokenIdStr;

  // Update page title dynamically
  document.title = `Giggles and Gags #${tokenIdStr}`;

  const contract = gagContract || gagReadOnly;
  if (!contract) {
    svgContainer.innerHTML = '<div class="preview-placeholder">Connecting to Base...</div>';
    // Retry after provider is ready
    setTimeout(loadGagPage, 2000);
    return;
  }

  try {
    // Fetch owner
    const owner = await contract.ownerOf(tokenId);
    ownerEl.textContent = truncateAddress(owner);

    // Fetch tokenURI (contains base64-encoded JSON with SVG image)
    const uri = await contract.tokenURI(tokenId);
    if (uri.startsWith("data:application/json;base64,")) {
      const json = JSON.parse(atob(uri.split(",")[1]));

      // Render the SVG image (use DOMParser to avoid innerHTML XSS)
      if (json.image && json.image.startsWith("data:image/svg+xml;base64,")) {
        const svgData = atob(json.image.split(",")[1]);
        const parsed = new DOMParser().parseFromString(svgData, "image/svg+xml");
        const parsedSvg = parsed.documentElement;
        if (parsedSvg && parsedSvg.tagName === "svg") {
          svgContainer.textContent = "";
          svgContainer.appendChild(document.importNode(parsedSvg, true));
        }
      } else if (json.image) {
        const img = document.createElement("img");
        img.src = json.image;
        img.alt = "Gag #" + tokenIdStr;
        img.style.cssText = "width:100%;border-radius:8px;";
        svgContainer.textContent = "";
        svgContainer.appendChild(img);
      }

      // Extract attribution from attributes if available
      if (json.attributes) {
        const attrInfo = json.attributes.find(a => a.trait_type === "Attribution" || a.trait_type === "Mode");
        if (attrInfo) {
          attrEl.textContent = attrInfo.value;
        } else {
          attrEl.textContent = "Unknown";
        }
      }
    }

    // Show burn CTA if connected wallet owns this token
    if (userAddress && owner.toLowerCase() === userAddress.toLowerCase()) {
      burnCta.style.display = "block";
      const burnLink = document.getElementById("gag-page-burn-link");
      if (burnLink) {
        burnLink.href = `../burn/#token-${tokenIdStr}`;
        burnLink.textContent = "Burn This Gag — Remove It Forever";
      }
    }
  } catch (err) {
    console.error("Failed to load gag page:", err);
    svgContainer.innerHTML = '<div class="preview-placeholder">Token not found or not yet minted.</div>';
    ownerEl.textContent = "—";
  }

  // Bind share buttons for this specific token
  bindGagPageShare(tokenIdStr);
}

/** Bind share buttons on the token page. */
function bindGagPageShare(tokenIdStr) {
  const gagUrl = `${GAG_CONFIG.siteUrl}/gag/?id=${tokenIdStr}`;
  const shareText = `Check out Giggles and Gags #${tokenIdStr} — randomly assigned on-chain social damage. ${gagUrl}`;

  const fcBtn = document.getElementById("btn-share-gag-fc");
  const lensBtn = document.getElementById("btn-share-gag-lens");
  const xBtn = document.getElementById("btn-share-gag-x");
  const copyBtn = document.getElementById("btn-share-gag-copy");

  if (fcBtn) {
    fcBtn.onclick = () => {
      window.open(`https://warpcast.com/~/compose?text=${encodeURIComponent(shareText)}`, "_blank", "noopener");
      showToast("Opening Warpcast...", "info");
    };
  }
  if (lensBtn) {
    lensBtn.onclick = () => {
      window.open(`https://hey.xyz/?text=${encodeURIComponent(shareText)}`, "_blank", "noopener");
      showToast("Opening Lens...", "info");
    };
  }
  if (xBtn) {
    xBtn.onclick = () => {
      window.open(`https://x.com/intent/tweet?text=${encodeURIComponent(shareText)}`, "_blank", "noopener");
      showToast("Opening X...", "info");
    };
  }
  if (copyBtn) {
    copyBtn.onclick = async () => {
      try {
        await navigator.clipboard.writeText(gagUrl);
        showToast("Token link copied!", "success");
      } catch {
        showToast("Failed to copy link", "error");
      }
    };
  }
}

// ---------------------------------------------------------------------------
//  Bootstrap
// ---------------------------------------------------------------------------
document.addEventListener("DOMContentLoaded", async () => {
  // Initialize Farcaster/Base mini app if embedded
  miniAppProvider = await initMiniApp();

  initReadOnly();
  bindUI();
  updateContractDisplay();
  initScrollAnimations();
  pollLiveStats();
  applyRouting();

  // Auto-connect: in mini app context always try, otherwise check for existing connection
  const ethProvider = getEthereumProvider();
  if (miniAppProvider) {
    connectWallet();
  } else if (ethProvider && ethProvider.selectedAddress) {
    connectWallet();
  }
});

/** Create a read-only provider + contract for data fetching without wallet. */
function initReadOnly() {
  try {
    provider = new ethers.JsonRpcProvider(GAG_CONFIG.rpcUrl);
    gagReadOnly = new ethers.Contract(GAG_CONFIG.contractAddress, GAG_ABI, provider);
  } catch (e) {
    console.warn("Read-only provider init failed:", e);
  }
}

// ---------------------------------------------------------------------------
//  UI Binding
// ---------------------------------------------------------------------------
function bindUI() {
  // Connect buttons
  document.getElementById("btn-connect").addEventListener("click", connectWallet);
  document.getElementById("btn-connect-form").addEventListener("click", connectWallet);
  document.getElementById("btn-connect-burn").addEventListener("click", connectWallet);
  document.getElementById("btn-switch-network").addEventListener("click", switchToBase);

  // Form inputs
  document.getElementById("recipient").addEventListener("input", onRecipientInput);
  document.getElementById("message").addEventListener("input", onMessageInput);
  document.getElementById("token-select").addEventListener("change", onTokenChange);

  // Toggle
  document.getElementById("btn-ghost").addEventListener("click", () => setMode(true));
  document.getElementById("btn-credit").addEventListener("click", () => setMode(false));

  // Action buttons
  document.getElementById("btn-approve").addEventListener("click", handleApprove);
  document.getElementById("btn-submit").addEventListener("click", handleSubmit);

  // Copy address
  document.getElementById("btn-copy-addr").addEventListener("click", () => {
    navigator.clipboard.writeText(GAG_CONFIG.contractAddress);
    showToast("Address copied to clipboard!", "info");
  });

  // Social share buttons
  document.getElementById("btn-share-farcaster").addEventListener("click", shareOnFarcaster);
  document.getElementById("btn-share-lens").addEventListener("click", shareOnLens);
  document.getElementById("btn-share-x").addEventListener("click", shareOnX);
  document.getElementById("btn-share-copy").addEventListener("click", shareCopyLink);

  // Burn form
  document.getElementById("burn-token-id").addEventListener("change", onBurnTokenIdChange);
  document.getElementById("burn-token-select").addEventListener("change", onBurnTokenChange);
  document.getElementById("btn-burn-approve").addEventListener("click", handleBurnApprove);
  document.getElementById("btn-burn").addEventListener("click", handleBurn);
  document.getElementById("btn-refresh-gags").addEventListener("click", loadOwnedTokens);
}

// ---------------------------------------------------------------------------
//  Wallet Connection
// ---------------------------------------------------------------------------
async function connectWallet() {
  const ethProvider = getEthereumProvider();
  if (!ethProvider) {
    if (isMiniApp) {
      showStatus("Wallet provider not available in this mini app.", "error");
    } else {
      alert("No Ethereum wallet detected. Please install MetaMask or a compatible wallet.");
    }
    return;
  }

  try {
    // 1. Always request accounts first so the wallet popup actually appears
    await ethProvider.request({ method: "eth_requestAccounts" });

    const browserProvider = new ethers.BrowserProvider(ethProvider);
    const network = await browserProvider.getNetwork();

    // 2. If on wrong chain, try to switch automatically before falling back to guard
    if (Number(network.chainId) !== GAG_CONFIG.chainId) {
      try {
        await ethProvider.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + GAG_CONFIG.chainId.toString(16) }],
        });
      } catch (switchErr) {
        // 4902 = chain not added yet — try adding it
        if (switchErr.code === 4902) {
          try {
            await ethProvider.request({
              method: "wallet_addEthereumChain",
              params: [{
                chainId: "0x" + GAG_CONFIG.chainId.toString(16),
                chainName: GAG_CONFIG.chainName,
                rpcUrls: [GAG_CONFIG.rpcUrl],
                blockExplorerUrls: [GAG_CONFIG.blockExplorer],
                nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
              }],
            });
          } catch {
            showNetworkGuard();
            return;
          }
        } else {
          // User rejected the switch — show guard
          showNetworkGuard();
          return;
        }
      }
      // Re-create provider after chain switch
      const updatedProvider = new ethers.BrowserProvider(ethProvider);
      signer = await updatedProvider.getSigner();
      userAddress = await signer.getAddress();
      provider = updatedProvider;
    } else {
      signer = await browserProvider.getSigner();
      userAddress = await signer.getAddress();
      provider = browserProvider;
    }

    gagContract = new ethers.Contract(GAG_CONFIG.contractAddress, GAG_ABI, signer);

    // Update button
    const btn = document.getElementById("btn-connect");
    btn.textContent = truncateAddress(userAddress);
    btn.classList.add("connected");

    showMintForm();
    await loadSupportedTokens();
    await Promise.all([
      loadClaimableBalances(),
      loadOwnedTokens(),
    ]);

    // Listen for account/network changes (not available on all providers)
    if (ethProvider.on) {
      ethProvider.on("accountsChanged", () => window.location.reload());
      ethProvider.on("chainChanged", () => window.location.reload());
    }
  } catch (err) {
    console.error("Wallet connection failed:", err);
    showStatus("Wallet connection failed: " + err.message, "error");
    showToast("Wallet connection failed", "error");
  }
}

async function switchToBase() {
  const ethProvider = getEthereumProvider();
  if (!ethProvider) return;
  try {
    await ethProvider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x" + GAG_CONFIG.chainId.toString(16) }],
    });
    window.location.reload();
  } catch (err) {
    if (err.code === 4902) {
      await ethProvider.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: "0x" + GAG_CONFIG.chainId.toString(16),
          chainName: GAG_CONFIG.chainName,
          rpcUrls: [GAG_CONFIG.rpcUrl],
          blockExplorerUrls: [GAG_CONFIG.blockExplorer],
          nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
        }],
      });
    }
  }
}

// ---------------------------------------------------------------------------
//  UI State Management
// ---------------------------------------------------------------------------
function showNetworkGuard() {
  document.getElementById("wallet-guard").style.display = "none";
  document.getElementById("network-guard").style.display = "flex";
  document.getElementById("mint-form").style.display = "none";
}

function showMintForm() {
  document.getElementById("wallet-guard").style.display = "none";
  document.getElementById("network-guard").style.display = "none";
  document.getElementById("mint-form").style.display = "block";
  document.getElementById("claim-guard").style.display = "none";
  document.getElementById("claim-content").style.display = "block";
  // Show burn form
  document.getElementById("burn-guard").style.display = "none";
  document.getElementById("burn-form").style.display = "block";
}

function updateContractDisplay() {
  const addr = GAG_CONFIG.contractAddress;
  document.getElementById("contract-address").textContent = addr;
  const scanUrl = `${GAG_CONFIG.blockExplorer}/address/${addr}`;
  document.getElementById("basescan-link").href = scanUrl;
  document.getElementById("footer-basescan").href = scanUrl;
  document.getElementById("footer-ens").textContent = GAG_CONFIG.ensName;

  // Update footer social links from config
  const footerLinks = {
    "footer-warpcast": GAG_CONFIG.farcasterProfile || "https://warpcast.com",
    "footer-lens": GAG_CONFIG.lensProfile || "https://hey.xyz",
    "footer-x": GAG_CONFIG.xProfile || "https://x.com",
    "footer-discord": GAG_CONFIG.discordInvite || "https://discord.gg",
  };
  for (const [id, href] of Object.entries(footerLinks)) {
    const el = document.getElementById(id);
    if (el) el.href = href;
  }

  // GitHub links (footer + trust section)
  const ghEls = [document.getElementById("footer-github"), document.getElementById("github-link")];
  for (const ghEl of ghEls) {
    if (ghEl && GAG_CONFIG.githubRepo) {
      ghEl.href = GAG_CONFIG.githubRepo;
    }
  }
}

// ---------------------------------------------------------------------------
//  Token Loading
// ---------------------------------------------------------------------------
async function loadSupportedTokens() {
  const contract = gagContract || gagReadOnly;
  if (!contract) {
    console.warn("loadSupportedTokens: no contract available");
    populateTokenDropdown(); // shows "No tokens configured"
    return;
  }

  try {
    const addresses = await contract.getSupportedTokens();
    supportedTokens = [];

    for (const addr of addresses) {
      try {
        const info = await getTokenInfo(addr, contract);
        supportedTokens.push(info);
      } catch (tokenErr) {
        // If a single token fails, log it but continue loading the rest
        console.warn(`Failed to load token ${addr}:`, tokenErr);
      }
    }

    populateTokenDropdown();
  } catch (err) {
    console.error("Failed to load supported tokens:", err);
    // Show error in dropdown instead of hanging on "Loading..."
    const select = document.getElementById("token-select");
    select.innerHTML = '<option value="" disabled selected>Failed to load tokens</option>';
    showToast("Could not load payment tokens. Check console for details.", "error");
  }
}

async function getTokenInfo(tokenAddress, gagContract) {
  const known = GAG_CONFIG.knownTokens[tokenAddress];
  let symbol, decimals, icon;

  if (known) {
    symbol = known.symbol;
    decimals = known.decimals;
    icon = known.icon || null;
  } else {
    try {
      const erc20 = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
      symbol = await erc20.symbol();
      decimals = Number(await erc20.decimals());
    } catch {
      symbol = truncateAddress(tokenAddress);
      decimals = 18;
    }
    icon = null;
  }

  const mintPrice = await gagContract.mintPrices(tokenAddress);
  const burnFee = await gagContract.burnFees(tokenAddress);

  return { address: tokenAddress, symbol, decimals, mintPrice, burnFee, icon };
}

function populateTokenDropdown() {
  const select = document.getElementById("token-select");
  const burnSelect = document.getElementById("burn-token-select");
  select.innerHTML = "";
  burnSelect.innerHTML = "";

  if (supportedTokens.length === 0) {
    select.innerHTML = '<option value="" disabled selected>No tokens configured</option>';
    burnSelect.innerHTML = '<option value="" disabled selected>No tokens configured</option>';
    updateTokenIcon(null);
    return;
  }

  supportedTokens.forEach((t) => {
    const opt = document.createElement("option");
    opt.value = t.address;
    opt.textContent = t.symbol;
    select.appendChild(opt);

    const burnOpt = document.createElement("option");
    burnOpt.value = t.address;
    burnOpt.textContent = t.symbol;
    burnSelect.appendChild(burnOpt);
  });

  // Select first by default
  select.selectedIndex = 0;
  burnSelect.selectedIndex = 0;
  onTokenChange();
  onBurnTokenChange();
}

/** Update the token icon displayed next to the dropdown. */
function updateTokenIcon(token) {
  const iconEl = document.getElementById("token-icon");
  if (!iconEl) return;

  if (token && token.icon) {
    iconEl.src = token.icon;
    iconEl.alt = token.symbol;
    iconEl.style.display = "inline-block";
  } else {
    iconEl.style.display = "none";
  }
}

// ---------------------------------------------------------------------------
//  Form Event Handlers
// ---------------------------------------------------------------------------
function onRecipientInput() {
  const val = document.getElementById("recipient").value.trim();
  const errEl = document.getElementById("recipient-err");
  const resolvedEl = document.getElementById("recipient-resolved");

  // Clear previous resolution
  resolvedRecipient = null;
  resolvingName = false;
  if (resolveDebounce) clearTimeout(resolveDebounce);

  if (!val) {
    errEl.textContent = "";
    if (resolvedEl) resolvedEl.textContent = "";
    document.getElementById("preview-recipient").textContent = "—";
    validateForm();
    return;
  }

  // Direct address input
  if (ethers.isAddress(val)) {
    errEl.textContent = "";
    resolvedRecipient = val;
    if (resolvedEl) resolvedEl.textContent = "";
    document.getElementById("preview-recipient").textContent = truncateAddress(val);
    validateForm();
    return;
  }

  // Check if it looks like a resolvable name (Basename, ENS, or UD)
  const looksLikeName = isBasename(val) || isENSName(val) || isUDName(val);

  if (!looksLikeName) {
    errEl.textContent = "Invalid address or domain name";
    if (resolvedEl) resolvedEl.textContent = "";
    document.getElementById("preview-recipient").textContent = "—";
    validateForm();
    return;
  }

  // Start debounced async resolution
  errEl.textContent = "";
  if (resolvedEl) resolvedEl.textContent = "Resolving...";
  document.getElementById("preview-recipient").textContent = "Resolving...";
  resolvingName = true;
  validateForm();

  resolveDebounce = setTimeout(async () => {
    try {
      const addr = await resolveName(val);
      // Check input hasn't changed during resolution
      if (document.getElementById("recipient").value.trim() !== val) return;

      resolvingName = false;

      if (addr) {
        resolvedRecipient = addr;
        errEl.textContent = "";
        if (resolvedEl) resolvedEl.textContent = truncateAddress(addr);
        document.getElementById("preview-recipient").textContent = truncateAddress(addr);
      } else {
        resolvedRecipient = null;
        errEl.textContent = "Could not resolve name to an address";
        if (resolvedEl) resolvedEl.textContent = "";
        document.getElementById("preview-recipient").textContent = "—";
      }
    } catch {
      resolvingName = false;
      resolvedRecipient = null;
      errEl.textContent = "Name resolution failed";
      if (resolvedEl) resolvedEl.textContent = "";
      document.getElementById("preview-recipient").textContent = "—";
    }
    validateForm();
  }, 600); // 600ms debounce
}

function onMessageInput() {
  const val = document.getElementById("message").value;
  const len = val.length;
  document.getElementById("char-count").textContent = `${len} / ${GAG_CONFIG.maxMessageLength}`;
  document.getElementById("preview-chars").textContent = len;
  document.getElementById("message-err").textContent = "";

  // Update preview SVG
  updatePreviewSVG(val);

  // Client-side validation hints
  const errEl = document.getElementById("message-err");
  if (len > 0) {
    const result = validateMessage(val);
    if (!result.valid) {
      errEl.textContent = result.reason;
    }
  }
  validateForm();
}

function onTokenChange() {
  const addr = document.getElementById("token-select").value;
  selectedToken = supportedTokens.find(t => t.address === addr) || null;

  if (selectedToken) {
    document.getElementById("mint-price").textContent =
      ethers.formatUnits(selectedToken.mintPrice, selectedToken.decimals) + " " + selectedToken.symbol;
    document.getElementById("burn-fee").textContent =
      ethers.formatUnits(selectedToken.burnFee, selectedToken.decimals) + " " + selectedToken.symbol;
    document.getElementById("preview-token").textContent = selectedToken.symbol;
    updateTokenIcon(selectedToken);
    checkAllowance();
  } else {
    updateTokenIcon(null);
  }
}

function setMode(isGhost) {
  anonymize = isGhost;
  document.getElementById("btn-ghost").classList.toggle("active", isGhost);
  document.getElementById("btn-credit").classList.toggle("active", !isGhost);
  document.getElementById("preview-mode").textContent = isGhost ? "Ghost" : "Credit Goblin";
}

// ---------------------------------------------------------------------------
//  Validation
// ---------------------------------------------------------------------------
function validateMessage(text) {
  if (text.length === 0 || text.length > 64) {
    return { valid: false, reason: "Message must be 1–64 characters" };
  }
  if (text[0] === " ") {
    return { valid: false, reason: "No leading spaces" };
  }
  if (text[text.length - 1] === " ") {
    return { valid: false, reason: "No trailing spaces" };
  }
  if (text.includes("  ")) {
    return { valid: false, reason: "No double spaces" };
  }

  // Allowed ASCII ranges
  const allowed = /^[a-zA-Z0-9 .,!?\-_:;'"()\[\]\/@#+&]+$/;
  if (!allowed.test(text)) {
    return { valid: false, reason: "Message rejected. Keep it ASCII. Keep it evil." };
  }

  return { valid: true, reason: "" };
}

function validateForm() {
  const message = document.getElementById("message").value;
  const token = document.getElementById("token-select").value;

  const hasValidRecipient = resolvedRecipient && ethers.isAddress(resolvedRecipient) && !resolvingName;
  const isValid = hasValidRecipient && validateMessage(message).valid && token !== "";

  document.getElementById("btn-submit").disabled = !isValid;
}

// ---------------------------------------------------------------------------
//  Allowance Check
// ---------------------------------------------------------------------------
async function checkAllowance() {
  if (!signer || !selectedToken) return;

  try {
    const erc20 = new ethers.Contract(selectedToken.address, ERC20_ABI, signer);
    const allowance = await erc20.allowance(userAddress, GAG_CONFIG.contractAddress);

    const approveBtn = document.getElementById("btn-approve");
    const submitBtn = document.getElementById("btn-submit");

    if (allowance < selectedToken.mintPrice) {
      approveBtn.style.display = "block";
      updateApproveButtonText();
      submitBtn.textContent = "First approve the stablecoin. Then unleash the nonsense.";
      submitBtn.disabled = true;
    } else {
      approveBtn.style.display = "none";
      submitBtn.textContent = "Send the Gag";
      validateForm();
    }
  } catch (err) {
    console.error("Allowance check failed:", err);
  }
}

/** Update the approve button text to show the exact amount needed. */
function updateApproveButtonText() {
  if (!selectedToken) return;
  const formatted = ethers.formatUnits(selectedToken.mintPrice, selectedToken.decimals);
  document.getElementById("btn-approve").textContent =
    `Approve ${formatted} ${selectedToken.symbol}`;
}

// ---------------------------------------------------------------------------
//  Approve Handler
// ---------------------------------------------------------------------------
async function handleApprove() {
  if (!signer || !selectedToken) return;

  const btn = document.getElementById("btn-approve");
  btn.disabled = true;
  btn.textContent = "Approving...";

  const approvalAmount = selectedToken.mintPrice;
  const formatted = ethers.formatUnits(approvalAmount, selectedToken.decimals);
  showStatus(`Requesting approval for exactly ${formatted} ${selectedToken.symbol}...`, "info");

  try {
    const erc20 = new ethers.Contract(selectedToken.address, ERC20_ABI, signer);

    // Check current allowance — if non-zero but insufficient, reset to 0 first
    // (some tokens like USDT require this)
    const currentAllowance = await erc20.allowance(userAddress, GAG_CONFIG.contractAddress);
    if (currentAllowance > 0n && currentAllowance < approvalAmount) {
      showStatus("Resetting previous allowance to zero first...", "info");
      const resetTx = await sendWithAttribution(erc20, "approve", [GAG_CONFIG.contractAddress, 0]);
      await resetTx.wait();
    }

    const tx = await sendWithAttribution(erc20, "approve", [GAG_CONFIG.contractAddress, approvalAmount]);
    showStatus("Approval submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showStatus(`Approved exactly ${formatted} ${selectedToken.symbol}. Ready to send.`, "success");
    await checkAllowance();
  } catch (err) {
    console.error("Approve failed:", err);
    showStatus("Approval failed: " + (err.reason || err.message), "error");
  } finally {
    btn.disabled = false;
    updateApproveButtonText();
  }
}

// ---------------------------------------------------------------------------
//  Submit Handler
// ---------------------------------------------------------------------------
async function handleSubmit() {
  if (!gagContract || !selectedToken || !resolvedRecipient) return;

  const recipient = resolvedRecipient;
  const message = document.getElementById("message").value;
  const token = selectedToken.address;

  const btn = document.getElementById("btn-submit");
  btn.disabled = true;
  btn.textContent = "Submitting...";
  showStatus("Sending your gag into the chaos buffer...", "info");

  try {
    const tx = await sendWithAttribution(gagContract, "submitMintIntent", [anonymize, recipient, token, message]);
    showStatus("Transaction submitted. Waiting for confirmation...", "info");
    showToast("Transaction submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showStatus("Your gag has entered the live chaos buffer. You funded the machine. May the slots be cruel.", "success");
    showToast("Gag submitted! The chaos buffer has been fed.", "success", 6000);

    // Show the share panel
    const sharePanel = document.getElementById("share-panel");
    if (sharePanel) sharePanel.style.display = "block";

    // Refresh live stats
    pollLiveStats();

    // Reset form
    document.getElementById("recipient").value = "";
    document.getElementById("message").value = "";
    resolvedRecipient = null;
    resolvingName = false;
    const resolvedEl = document.getElementById("recipient-resolved");
    if (resolvedEl) resolvedEl.textContent = "";
    onRecipientInput();
    onMessageInput();
  } catch (err) {
    console.error("Submit failed:", err);
    const reason = parseRevertReason(err);
    showStatus("Submit failed: " + reason, "error");
  } finally {
    btn.disabled = false;
    btn.textContent = "Send the Gag";
    validateForm();
  }
}

// ---------------------------------------------------------------------------
//  Claim Section
// ---------------------------------------------------------------------------
async function loadClaimableBalances() {
  const container = document.getElementById("claim-balances");
  if (!gagContract || !userAddress) return;

  try {
    let html = "";
    let hasAny = false;

    for (const token of supportedTokens) {
      const claimable = await gagContract.claimable(token.address);
      const formatted = ethers.formatUnits(claimable, token.decimals);

      html += `
        <div class="claim-row">
          <span class="claim-token">${escapeHtml(token.symbol)}</span>
          <span class="claim-amount">${escapeHtml(formatted)}</span>
          <button class="btn btn-accent btn-sm claim-btn"
                  data-token="${escapeHtml(token.address)}"
                  ${claimable === 0n ? "disabled" : ""}>
            Claim
          </button>
        </div>`;

      if (claimable > 0n) hasAny = true;
    }

    if (!html) {
      html = "<p>No supported tokens found.</p>";
    }

    container.innerHTML = html;

    // Bind claim buttons
    container.querySelectorAll(".claim-btn").forEach(btn => {
      btn.addEventListener("click", () => handleClaim(btn.dataset.token));
    });

    if (!hasAny) {
      container.innerHTML += '<p class="note">No claimable rewards yet. Send some gags and wait for burns.</p>';
    }
  } catch (err) {
    console.error("Failed to load claimable balances:", err);
    container.innerHTML = "<p>Failed to load balances.</p>";
  }
}

async function handleClaim(tokenAddress) {
  if (!gagContract) return;

  showStatus("Claiming burn tribute...", "info");

  try {
    const tx = await sendWithAttribution(gagContract, "claimFees", [tokenAddress]);
    showStatus("Claim submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showStatus("Burn tribute claimed. You have been compensated for your menace.", "success");
    await loadClaimableBalances();
  } catch (err) {
    console.error("Claim failed:", err);
    showStatus("Claim failed: " + (err.reason || err.message), "error");
  }
}

// ---------------------------------------------------------------------------
//  Burn Section
// ---------------------------------------------------------------------------

let ownedTokens = []; // [{ tokenId, message }]

/**
 * Discover tokens owned by the connected user.
 * Strategy: query Transfer events where `to = userAddress`, then verify
 * each candidate still belongs to the user via `ownerOf`.
 * For non-transferable tokens this is efficient — tokens only leave via burn.
 */
async function loadOwnedTokens() {
  const select = document.getElementById("burn-token-id");
  const emptyState = document.getElementById("burn-empty-state");
  const infoEl = document.getElementById("burn-token-info");
  const errEl = document.getElementById("burn-token-err");

  select.innerHTML = '<option value="" disabled selected>Scanning wallet...</option>';
  emptyState.style.display = "none";
  errEl.textContent = "";
  infoEl.textContent = "";
  ownedTokens = [];

  const contract = gagContract || gagReadOnly;
  if (!contract || !userAddress) {
    select.innerHTML = '<option value="" disabled selected>Connect wallet first</option>';
    return;
  }

  try {
    // Query Transfer events where `to` is the user (minted to them)
    // Use deploy block to avoid scanning from genesis (public RPCs reject huge ranges)
    const fromBlock = GAG_CONFIG.deployBlock || 0;
    const filter = contract.filters.Transfer(null, userAddress);
    const events = await contract.queryFilter(filter, fromBlock, "latest");

    // Collect unique candidate token IDs
    const candidateIds = [...new Set(events.map(e => e.args.tokenId))];

    // Verify ownership for each (some may have been burned)
    const verified = [];
    for (const tokenId of candidateIds) {
      try {
        const owner = await contract.ownerOf(tokenId);
        if (owner.toLowerCase() === userAddress.toLowerCase()) {
          verified.push(tokenId);
        }
      } catch {
        // ownerOf reverts if token was burned — skip
      }
    }

    // Try to fetch a message snippet for each owned token via tokenURI
    for (const tokenId of verified) {
      let message = "";
      try {
        const uri = await contract.tokenURI(tokenId);
        // tokenURI returns a data:application/json;base64,... string
        if (uri.startsWith("data:application/json;base64,")) {
          const json = JSON.parse(atob(uri.split(",")[1]));
          message = json.name || "";
        }
      } catch {
        // If tokenURI fails, just show the ID
      }
      ownedTokens.push({ tokenId, message });
    }

    populateBurnTokenDropdown();
  } catch (err) {
    console.error("Failed to scan owned tokens:", err);
    select.innerHTML = '<option value="" disabled selected>Failed to scan</option>';
    errEl.textContent = "Could not scan wallet. You can try refreshing.";
    showToast("Failed to scan owned tokens", "error");
  }
}

/** Populate the burn token dropdown with owned tokens. */
function populateBurnTokenDropdown() {
  const select = document.getElementById("burn-token-id");
  const emptyState = document.getElementById("burn-empty-state");

  select.innerHTML = "";

  if (ownedTokens.length === 0) {
    select.innerHTML = '<option value="" disabled selected>No gags found</option>';
    emptyState.style.display = "flex";
    validateBurnForm();
    return;
  }

  emptyState.style.display = "none";

  // Add a prompt option
  const prompt = document.createElement("option");
  prompt.value = "";
  prompt.disabled = true;
  prompt.selected = true;
  prompt.textContent = `Select a gag to burn (${ownedTokens.length} found)`;
  select.appendChild(prompt);

  for (const t of ownedTokens) {
    const opt = document.createElement("option");
    opt.value = t.tokenId.toString();
    const label = t.message ? `#${t.tokenId} — ${t.message}` : `#${t.tokenId}`;
    opt.textContent = label.length > 50 ? label.slice(0, 47) + "..." : label;
    select.appendChild(opt);
  }

  validateBurnForm();
}

/** Called when the user selects a gag token from the dropdown. */
function onBurnTokenIdChange() {
  const val = document.getElementById("burn-token-id").value;
  const infoEl = document.getElementById("burn-token-info");
  const errEl = document.getElementById("burn-token-err");

  errEl.textContent = "";

  if (val) {
    infoEl.textContent = "Token #" + val + " selected";
  } else {
    infoEl.textContent = "";
  }

  validateBurnForm();
}

/** Called when the burn payment token selector changes. */
function onBurnTokenChange() {
  const addr = document.getElementById("burn-token-select").value;
  selectedBurnToken = supportedTokens.find(t => t.address === addr) || null;

  const iconEl = document.getElementById("burn-token-icon");
  if (selectedBurnToken) {
    document.getElementById("burn-fee-display").textContent =
      ethers.formatUnits(selectedBurnToken.burnFee, selectedBurnToken.decimals) + " " + selectedBurnToken.symbol;
    if (iconEl && selectedBurnToken.icon) {
      iconEl.src = selectedBurnToken.icon;
      iconEl.alt = selectedBurnToken.symbol;
      iconEl.style.display = "inline-block";
    } else if (iconEl) {
      iconEl.style.display = "none";
    }
    checkBurnAllowance();
  } else {
    document.getElementById("burn-fee-display").textContent = "--";
    if (iconEl) iconEl.style.display = "none";
  }
}

/** Validate the burn form and enable/disable the burn button. */
function validateBurnForm() {
  const tokenId = document.getElementById("burn-token-id").value;
  const token = document.getElementById("burn-token-select").value;

  const hasTokenId = tokenId !== "" && tokenId !== null;
  const isValid = hasTokenId && token !== "";

  document.getElementById("btn-burn").disabled = !isValid;
}

/** Check if the user has approved enough tokens for the burn fee. */
async function checkBurnAllowance() {
  if (!signer || !selectedBurnToken) return;

  try {
    const erc20 = new ethers.Contract(selectedBurnToken.address, ERC20_ABI, signer);
    const allowance = await erc20.allowance(userAddress, GAG_CONFIG.contractAddress);

    const approveBtn = document.getElementById("btn-burn-approve");
    const burnBtn = document.getElementById("btn-burn");

    if (allowance < selectedBurnToken.burnFee) {
      approveBtn.style.display = "block";
      const formatted = ethers.formatUnits(selectedBurnToken.burnFee, selectedBurnToken.decimals);
      approveBtn.textContent = `Approve ${formatted} ${selectedBurnToken.symbol}`;
      burnBtn.textContent = "First approve the burn fee";
      burnBtn.disabled = true;
    } else {
      approveBtn.style.display = "none";
      burnBtn.textContent = "Burn This Gag";
      validateBurnForm();
    }
  } catch (err) {
    console.error("Burn allowance check failed:", err);
  }
}

/** Handle approval for the burn fee. */
async function handleBurnApprove() {
  if (!signer || !selectedBurnToken) return;

  const btn = document.getElementById("btn-burn-approve");
  btn.disabled = true;
  btn.textContent = "Approving...";

  const approvalAmount = selectedBurnToken.burnFee;
  const formatted = ethers.formatUnits(approvalAmount, selectedBurnToken.decimals);
  showBurnStatus(`Requesting approval for ${formatted} ${selectedBurnToken.symbol}...`, "info");

  try {
    const erc20 = new ethers.Contract(selectedBurnToken.address, ERC20_ABI, signer);

    // Reset allowance if needed (USDT-style tokens)
    const currentAllowance = await erc20.allowance(userAddress, GAG_CONFIG.contractAddress);
    if (currentAllowance > 0n && currentAllowance < approvalAmount) {
      showBurnStatus("Resetting previous allowance to zero first...", "info");
      const resetTx = await sendWithAttribution(erc20, "approve", [GAG_CONFIG.contractAddress, 0]);
      await resetTx.wait();
    }

    const tx = await sendWithAttribution(erc20, "approve", [GAG_CONFIG.contractAddress, approvalAmount]);
    showBurnStatus("Approval submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showBurnStatus(`Approved ${formatted} ${selectedBurnToken.symbol}. Ready to burn.`, "success");
    await checkBurnAllowance();
  } catch (err) {
    console.error("Burn approve failed:", err);
    showBurnStatus("Approval failed: " + (err.reason || err.message), "error");
  } finally {
    btn.disabled = false;
    if (selectedBurnToken) {
      const f = ethers.formatUnits(selectedBurnToken.burnFee, selectedBurnToken.decimals);
      btn.textContent = `Approve ${f} ${selectedBurnToken.symbol}`;
    }
  }
}

/** Handle burning a token. */
async function handleBurn() {
  if (!gagContract || !selectedBurnToken) return;

  const tokenIdStr = document.getElementById("burn-token-id").value;
  if (!tokenIdStr) return;

  const tokenId = BigInt(tokenIdStr);
  const paymentToken = selectedBurnToken.address;

  const btn = document.getElementById("btn-burn");
  btn.disabled = true;
  btn.textContent = "Burning...";
  showBurnStatus("Sending burn transaction...", "info");

  try {
    const tx = await sendWithAttribution(gagContract, "burnToken", [tokenId, paymentToken]);
    showBurnStatus("Burn submitted. Waiting for confirmation...", "info");
    showToast("Burn transaction submitted...", "info");
    await tx.wait();
    showBurnStatus("Token #" + tokenIdStr + " has been incinerated. The curse is lifted.", "success");
    showToast("Gag burned! The wallet pollution has been cleansed.", "success", 6000);

    // Refresh stats and re-scan owned tokens
    pollLiveStats();
    await loadOwnedTokens();
  } catch (err) {
    console.error("Burn failed:", err);
    const reason = parseRevertReason(err);
    showBurnStatus("Burn failed: " + reason, "error");
  } finally {
    btn.disabled = false;
    btn.textContent = "Burn This Gag";
    validateBurnForm();
  }
}

/** Show status message in the burn section. */
function showBurnStatus(message, type) {
  const el = document.getElementById("burn-tx-status");
  el.style.display = "block";
  el.className = "tx-status " + type;
  el.textContent = message;

  if (type === "success" || type === "info") {
    setTimeout(() => { el.style.display = "none"; }, 8000);
  }
}

// ---------------------------------------------------------------------------
//  Preview SVG
// ---------------------------------------------------------------------------
function updatePreviewSVG(text) {
  const container = document.getElementById("preview-svg");

  if (!text) {
    container.innerHTML = '<div class="preview-placeholder">Your gag preview will appear here</div>';
    return;
  }

  // Simplified SVG preview mimicking the on-chain render style
  const escaped = escapeHtml(text);
  const seed = simpleHash(text);
  const bgVariant = seed % 3;
  const rareMode = seed % 64 === 0;

  const bgColors = ["#0a0e17", "#1a0525", "#0f1510"];
  const accentColors = rareMode ? ["#ff00ff", "#00ffff"] : ["#ffcc00", "#00ffcc"];
  const bg = bgColors[bgVariant];
  const accent = accentColors[seed % 2];

  // Determine if two lines needed
  const fontSize = text.length > 20 ? 14 : 18;
  let textNode;
  if (text.length > 25 && text.includes(" ")) {
    const mid = text.lastIndexOf(" ", Math.floor(text.length / 2));
    const splitIdx = mid > 0 ? mid : Math.floor(text.length / 2);
    const l1 = text.substring(0, splitIdx);
    const l2 = text.substring(splitIdx + 1);
    textNode = `
      <text x="200" y="185" text-anchor="middle" fill="${accent}" font-size="${fontSize}" font-family="monospace" font-weight="700">${escapeHtml(l1)}</text>
      <text x="200" y="210" text-anchor="middle" fill="${accent}" font-size="${fontSize}" font-family="monospace" font-weight="700">${escapeHtml(l2)}</text>`;
  } else {
    textNode = `<text x="200" y="200" text-anchor="middle" fill="${accent}" font-size="${fontSize}" font-family="monospace" font-weight="700">${escaped}</text>`;
  }

  container.innerHTML = `
    <svg viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg" style="width:100%;border-radius:8px;">
      <rect width="400" height="400" fill="${bg}" />
      <rect x="15" y="15" width="370" height="370" rx="8" fill="none" stroke="${accent}" stroke-width="2" opacity="0.5" />
      <text x="200" y="55" text-anchor="middle" fill="${accent}" font-size="11" font-family="monospace" opacity="0.7">GIGGLES AND GAGS</text>
      ${textNode}
      <text x="200" y="360" text-anchor="middle" fill="#888" font-size="9" font-family="monospace">randomly assigned chaos</text>
      ${rareMode ? '<text x="350" y="55" text-anchor="end" fill="#ff00ff" font-size="9" font-family="monospace">RARE</text>' : ''}
    </svg>`;
}

// ---------------------------------------------------------------------------
//  Utility Functions
// ---------------------------------------------------------------------------
function truncateAddress(addr) {
  if (!addr || addr.length < 10) return addr;
  return addr.slice(0, 6) + "..." + addr.slice(-4);
}

function showStatus(message, type) {
  const el = document.getElementById("tx-status");
  el.style.display = "block";
  el.className = "tx-status " + type;
  el.textContent = message;

  if (type === "success" || type === "info") {
    setTimeout(() => { el.style.display = "none"; }, 8000);
  }
}

function parseRevertReason(err) {
  if (err.reason) return err.reason;
  const msg = err.message || "";
  if (msg.includes("UnsupportedToken")) return "Token not supported";
  if (msg.includes("InvalidRecipient")) return "Invalid recipient address";
  if (msg.includes("NonTransferable")) return "Tokens are non-transferable";
  if (msg.includes("NotTokenOwner")) return "You don't own this token";
  if (msg.includes("NoFees")) return "No fees to claim";
  if (msg.includes("InvalidTextLength")) return "Message must be 1–64 characters";
  if (msg.includes("InvalidLeadingOrTrailingSpace")) return "No leading or trailing spaces";
  if (msg.includes("InvalidDoubleSpace")) return "No double spaces allowed";
  if (msg.includes("InvalidCharacter")) return "That input is too cursed for the renderer";
  if (msg.includes("user rejected")) return "Transaction rejected by user";
  return msg.slice(0, 120);
}

function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function simpleHash(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash + str.charCodeAt(i)) | 0;
  }
  return Math.abs(hash);
}

// ---------------------------------------------------------------------------
//  Toast Notifications
// ---------------------------------------------------------------------------
/**
 * Show a toast notification that auto-dismisses.
 * @param {string} message
 * @param {"success"|"info"|"error"} type
 * @param {number} duration  ms before auto-dismiss (default 4500)
 */
function showToast(message, type = "info", duration = 4500) {
  const container = document.getElementById("toast-container");
  if (!container) return;

  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);

  // Remove after animation completes
  setTimeout(() => {
    toast.remove();
  }, duration + 400); // extra buffer for the out animation
}

// ---------------------------------------------------------------------------
//  Social Sharing
// ---------------------------------------------------------------------------

/** Build the share text for social posts. */
function buildShareText() {
  const site = GAG_CONFIG.siteUrl || window.location.href;
  return `I just loaded the chaos buffer on Giggles and Gags — on-chain social damage on Base. Send a cursed soulbound NFT to your friends (or enemies). ${site}`;
}

/** Share on Farcaster via Warpcast compose intent. */
function shareOnFarcaster() {
  const text = encodeURIComponent(buildShareText());
  const url = `https://warpcast.com/~/compose?text=${text}`;
  window.open(url, "_blank", "noopener");
  showToast("Opening Warpcast...", "info");
}

/** Share on Lens via Hey.xyz compose intent. */
function shareOnLens() {
  const text = encodeURIComponent(buildShareText());
  const url = `https://hey.xyz/?text=${text}`;
  window.open(url, "_blank", "noopener");
  showToast("Opening Hey (Lens)...", "info");
}

/** Share on X/Twitter via intent URL. */
function shareOnX() {
  const text = encodeURIComponent(buildShareText());
  const url = `https://x.com/intent/tweet?text=${text}`;
  window.open(url, "_blank", "noopener");
  showToast("Opening X...", "info");
}

/** Copy the site link to clipboard. */
async function shareCopyLink() {
  const site = GAG_CONFIG.siteUrl || window.location.href;
  try {
    await navigator.clipboard.writeText(site);
    showToast("Link copied — spread the chaos!", "success");
  } catch {
    showToast("Failed to copy link", "error");
  }
}

// ---------------------------------------------------------------------------
//  Live Stats Polling
// ---------------------------------------------------------------------------

/** Fetch totalMinted and update the header stat badge. */
async function pollLiveStats() {
  const el = document.getElementById("stat-minted");
  if (!el) return;

  async function fetchStat() {
    try {
      const contract = gagContract || gagReadOnly;
      if (!contract) return;
      const total = await contract.totalMinted();
      el.textContent = total.toString();
    } catch {
      // Silently ignore — read-only provider may not be ready yet
    }
  }

  // Initial fetch
  await fetchStat();

  // Poll every 30 seconds
  setInterval(fetchStat, 30_000);
}

// ---------------------------------------------------------------------------
//  Scroll Animations
// ---------------------------------------------------------------------------

/** Observe `.fade-in` elements and add `.visible` when they enter the viewport. */
function initScrollAnimations() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target); // Only animate once
      }
    });
  }, {
    threshold: 0.15,
    rootMargin: "0px 0px -40px 0px",
  });

  document.querySelectorAll(".fade-in").forEach(el => observer.observe(el));
}
