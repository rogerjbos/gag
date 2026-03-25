/**
 * DotRot — Frontend Application (Polkadot Asset Hub Edition)
 *
 * Pure client-side logic. Connects to the DotRot contract via ethers.js,
 * handles wallet connection, minting (native PAS payment), burning, and claiming.
 */

/* global ethers, GAG_CONFIG, GAG_ABI, DotRotWallet */

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------
let provider = null;
let signer = null;
let gagContract = null;
let gagReadOnly = null;
let userAddress = null;
let anonymize = true;        // ghost mode by default
let mintPrice = 0n;
let burnFeeAmount = 0n;
let walletState = null;      // full wallet state from DotRotWallet.connectWallet

// ---------------------------------------------------------------------------
//  Router — path-based page detection
// ---------------------------------------------------------------------------

function detectPage() {
  const metaEl = document.querySelector('meta[name="gag-page"]');
  if (metaEl) return metaEl.getAttribute("content");

  const path = window.location.pathname.replace(/\/index\.html$/, "").replace(/\/$/, "");
  if (path.endsWith("/send")) return "send";
  if (path.endsWith("/burn")) return "burn";
  if (path.endsWith("/claim")) return "claim";
  if (path.endsWith("/how")) return "how";
  if (path.endsWith("/gag") || path.includes("/gag/")) return "gag";
  return "home";
}

function getScrollTarget() {
  const metaEl = document.querySelector('meta[name="gag-scroll-to"]');
  return metaEl ? metaEl.getAttribute("content") : null;
}

const GAG_CURRENT_PAGE = detectPage();

function applyRouting() {
  if (GAG_CURRENT_PAGE === "gag") {
    const sectionsToHide = [
      "hero", "how-it-works", "mint", "burn-info", "burn", "claim", "lore", "trust",
    ];
    for (const id of sectionsToHide) {
      const el = document.getElementById(id);
      if (el) el.style.display = "none";
    }
    const gagPage = document.getElementById("gag-page");
    if (gagPage) gagPage.style.display = "block";
    loadGagPage();
  } else {
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

function getGagTokenId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id") || params.get("tokenId") || null;
}

/**
 * Resolve an IPFS URI to a fetchable URL via the configured gateway.
 */
function resolveIPFS(uri) {
  if (!uri) return null;
  if (uri.startsWith("ipfs://")) {
    return GAG_CONFIG.ipfsGateway + uri.slice(7);
  }
  if (uri.startsWith("data:")) return uri;
  return uri;
}

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
  document.title = `DotRot #${tokenIdStr}`;

  const contract = gagContract || gagReadOnly;
  if (!contract) {
    svgContainer.innerHTML = '<div class="preview-placeholder">Connecting to Asset Hub...</div>';
    setTimeout(loadGagPage, 2000);
    return;
  }

  try {
    const owner = await contract.ownerOf(tokenId);
    ownerEl.textContent = truncateAddress(owner);

    const uri = await contract.tokenURI(tokenId);

    if (!uri || uri.length === 0) {
      svgContainer.innerHTML = '<div class="preview-placeholder">Metadata not yet uploaded. Check back soon.</div>';
      return;
    }

    // Handle IPFS URIs
    const fetchUrl = resolveIPFS(uri);

    let json;
    if (uri.startsWith("data:application/json;base64,")) {
      json = JSON.parse(atob(uri.split(",")[1]));
    } else if (fetchUrl) {
      const resp = await fetch(fetchUrl);
      json = await resp.json();
    }

    if (json) {
      // Render the SVG image
      if (json.image && json.image.startsWith("data:image/svg+xml;base64,")) {
        const svgData = atob(json.image.split(",")[1]);
        const parsed = new DOMParser().parseFromString(svgData, "image/svg+xml");
        const parsedSvg = parsed.documentElement;
        if (parsedSvg && parsedSvg.tagName === "svg") {
          svgContainer.textContent = "";
          svgContainer.appendChild(document.importNode(parsedSvg, true));
        }
      } else if (json.image) {
        const imgUrl = resolveIPFS(json.image);
        const img = document.createElement("img");
        img.src = imgUrl;
        img.alt = "Gag #" + tokenIdStr;
        img.style.cssText = "width:100%;border-radius:8px;";
        svgContainer.textContent = "";
        svgContainer.appendChild(img);
      }

      if (json.attributes) {
        const moodAttr = json.attributes.find(a => a.trait_type === "Mood");
        if (moodAttr) attrEl.textContent = moodAttr.value;
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

  bindGagPageShare(tokenIdStr);
}

function bindGagPageShare(tokenIdStr) {
  const gagUrl = `${GAG_CONFIG.siteUrl}/gag/?id=${tokenIdStr}`;
  const shareText = `Check out DotRot #${tokenIdStr} — randomly assigned on-chain social damage on Polkadot. ${gagUrl}`;

  const xBtn = document.getElementById("btn-share-gag-x");
  const copyBtn = document.getElementById("btn-share-gag-copy");

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
  initReadOnly();
  bindUI();
  updateContractDisplay();
  initScrollAnimations();
  pollLiveStats();
  applyRouting();

  // Auto-connect via Spektr (Triangle host)
  connectWallet();
});

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
  const connectFormBtn = document.getElementById("btn-connect-form");
  if (connectFormBtn) connectFormBtn.addEventListener("click", connectWallet);
  const connectBurnBtn = document.getElementById("btn-connect-burn");
  if (connectBurnBtn) connectBurnBtn.addEventListener("click", connectWallet);

  // Form inputs
  document.getElementById("recipient").addEventListener("input", onRecipientInput);
  document.getElementById("message").addEventListener("input", onMessageInput);

  // Toggle
  document.getElementById("btn-ghost").addEventListener("click", () => setMode(true));
  document.getElementById("btn-credit").addEventListener("click", () => setMode(false));

  // Action buttons
  document.getElementById("btn-submit").addEventListener("click", handleSubmit);

  // Copy address
  const copyAddrBtn = document.getElementById("btn-copy-addr");
  if (copyAddrBtn) {
    copyAddrBtn.addEventListener("click", () => {
      navigator.clipboard.writeText(GAG_CONFIG.contractAddress);
      showToast("Address copied to clipboard!", "info");
    });
  }

  // Social share buttons
  const shareX = document.getElementById("btn-share-x");
  if (shareX) shareX.addEventListener("click", shareOnX);
  const shareCopy = document.getElementById("btn-share-copy");
  if (shareCopy) shareCopy.addEventListener("click", shareCopyLink);

  // Burn form
  const burnTokenId = document.getElementById("burn-token-id");
  if (burnTokenId) burnTokenId.addEventListener("change", onBurnTokenIdChange);
  const btnBurn = document.getElementById("btn-burn");
  if (btnBurn) btnBurn.addEventListener("click", handleBurn);
  const btnRefresh = document.getElementById("btn-refresh-gags");
  if (btnRefresh) btnRefresh.addEventListener("click", loadOwnedTokens);
}

// ---------------------------------------------------------------------------
//  Wallet Connection (Triangle / Spektr only)
// ---------------------------------------------------------------------------
async function connectWallet() {
  try {
    walletState = await DotRotWallet.connectWallet(GAG_CONFIG);
    signer = walletState.evmWallet;
    userAddress = walletState.evmAddress;

    gagContract = new ethers.Contract(GAG_CONFIG.contractAddress, GAG_ABI, signer);

    // Update button
    const btn = document.getElementById("btn-connect");
    btn.textContent = walletState.accountName || truncateAddress(userAddress);
    btn.classList.add("connected");

    // If derived EVM address needs funding, show prompt
    if (walletState.needsFunding) {
      showFundingPrompt();
      return;
    }

    showMintForm();
    await loadPrices();
    await Promise.all([
      loadClaimableBalance(),
      loadOwnedTokens(),
    ]);

    // Watch for account changes
    DotRotWallet.onAccountStatusChange(async (status) => {
      if (status === "disconnected") {
        window.location.reload();
      }
    });
  } catch (err) {
    console.error("Wallet connection failed:", err);
    showStatus("Wallet connection failed: " + err.message, "error");
    showToast("Wallet connection failed", "error");
  }
}

/** Show a prompt to fund the derived EVM address from the Substrate account */
function showFundingPrompt() {
  const mintForm = document.getElementById("mint-form");
  if (mintForm) mintForm.style.display = "none";

  showStatus(
    `Your DotRot address (${truncateAddress(userAddress)}) needs PAS to interact with the contract. Click "Fund Wallet" to transfer PAS from your Polkadot account.`,
    "info"
  );

  const txStatus = document.getElementById("tx-status");
  if (txStatus) {
    const fundBtn = document.createElement("button");
    fundBtn.className = "btn btn-accent";
    fundBtn.textContent = "Fund Wallet (5 PAS)";
    fundBtn.style.marginTop = "12px";
    fundBtn.onclick = async () => {
      fundBtn.disabled = true;
      fundBtn.textContent = "Funding...";
      try {
        await DotRotWallet.fundEvmAddress(
          walletState.accountsProvider,
          walletState.providerAccounts,
          walletState.evmAddress,
          5000000000000000000n // 5 PAS
        );
        showStatus("Funded! Reloading...", "success");
        setTimeout(() => window.location.reload(), 2000);
      } catch (e) {
        showStatus("Funding failed: " + e.message, "error");
        fundBtn.disabled = false;
        fundBtn.textContent = "Fund Wallet (5 PAS)";
      }
    };
    txStatus.appendChild(fundBtn);
  }
}

// ---------------------------------------------------------------------------
//  Price Loading
// ---------------------------------------------------------------------------
async function loadPrices() {
  const contract = gagContract || gagReadOnly;
  if (!contract) return;

  try {
    mintPrice = await contract.mintPrice();
    burnFeeAmount = await contract.burnFee();

    const mintEl = document.getElementById("mint-price");
    if (mintEl) mintEl.textContent = ethers.formatEther(mintPrice) + " PAS";
    const burnEl = document.getElementById("burn-fee");
    if (burnEl) burnEl.textContent = ethers.formatEther(burnFeeAmount) + " PAS";
    const burnFeeDisplay = document.getElementById("burn-fee-display");
    if (burnFeeDisplay) burnFeeDisplay.textContent = ethers.formatEther(burnFeeAmount) + " PAS";
  } catch (err) {
    console.error("Failed to load prices:", err);
  }
}

// ---------------------------------------------------------------------------
//  UI State Management
// ---------------------------------------------------------------------------
function showMintForm() {
  const walletGuard = document.getElementById("wallet-guard");
  if (walletGuard) walletGuard.style.display = "none";
  const mintForm = document.getElementById("mint-form");
  if (mintForm) mintForm.style.display = "block";
  const claimGuard = document.getElementById("claim-guard");
  if (claimGuard) claimGuard.style.display = "none";
  const claimContent = document.getElementById("claim-content");
  if (claimContent) claimContent.style.display = "block";
  const burnGuard = document.getElementById("burn-guard");
  if (burnGuard) burnGuard.style.display = "none";
  const burnForm = document.getElementById("burn-form");
  if (burnForm) burnForm.style.display = "block";
}

function updateContractDisplay() {
  const addr = GAG_CONFIG.contractAddress;
  const contractAddrEl = document.getElementById("contract-address");
  if (contractAddrEl) contractAddrEl.textContent = addr;
  const scanUrl = `${GAG_CONFIG.blockExplorer}/address/${addr}`;

  const scanLink = document.getElementById("blockscout-link");
  if (scanLink) scanLink.href = scanUrl;
  const footerScan = document.getElementById("footer-blockscout");
  if (footerScan) footerScan.href = scanUrl;
  const footerEns = document.getElementById("footer-ens");
  if (footerEns) footerEns.textContent = GAG_CONFIG.siteUrl.replace("https://", "");

  const ghEls = [document.getElementById("footer-github"), document.getElementById("github-link")];
  for (const ghEl of ghEls) {
    if (ghEl && GAG_CONFIG.githubRepo) ghEl.href = GAG_CONFIG.githubRepo;
  }
}

// ---------------------------------------------------------------------------
//  Form Event Handlers
// ---------------------------------------------------------------------------
function onRecipientInput() {
  const val = document.getElementById("recipient").value.trim();
  const errEl = document.getElementById("recipient-err");

  if (!val) {
    errEl.textContent = "";
    document.getElementById("preview-recipient").textContent = "—";
    validateForm();
    return;
  }

  if (ethers.isAddress(val)) {
    errEl.textContent = "";
    document.getElementById("preview-recipient").textContent = truncateAddress(val);
  } else {
    errEl.textContent = "Enter a valid Ethereum address (0x...)";
    document.getElementById("preview-recipient").textContent = "—";
  }

  validateForm();
}

function onMessageInput() {
  const val = document.getElementById("message").value;
  const len = val.length;
  document.getElementById("char-count").textContent = `${len} / ${GAG_CONFIG.maxMessageLength}`;
  const previewChars = document.getElementById("preview-chars");
  if (previewChars) previewChars.textContent = len;
  document.getElementById("message-err").textContent = "";

  updatePreviewSVG(val);

  const errEl = document.getElementById("message-err");
  if (len > 0) {
    const result = validateMessage(val);
    if (!result.valid) errEl.textContent = result.reason;
  }
  validateForm();
}

function setMode(isGhost) {
  anonymize = isGhost;
  document.getElementById("btn-ghost").classList.toggle("active", isGhost);
  document.getElementById("btn-credit").classList.toggle("active", !isGhost);
  const previewMode = document.getElementById("preview-mode");
  if (previewMode) previewMode.textContent = isGhost ? "Ghost" : "Credit Goblin";
}

// ---------------------------------------------------------------------------
//  Validation
// ---------------------------------------------------------------------------
function validateMessage(text) {
  if (text.length === 0 || text.length > 64) {
    return { valid: false, reason: "Message must be 1–64 characters" };
  }
  if (text[0] === " ") return { valid: false, reason: "No leading spaces" };
  if (text[text.length - 1] === " ") return { valid: false, reason: "No trailing spaces" };
  if (text.includes("  ")) return { valid: false, reason: "No double spaces" };

  const allowed = /^[a-zA-Z0-9 .,!?\-_:;'"()\[\]\/@#+&]+$/;
  if (!allowed.test(text)) {
    return { valid: false, reason: "Message rejected. Keep it ASCII. Keep it evil." };
  }

  return { valid: true, reason: "" };
}

function validateForm() {
  const recipient = document.getElementById("recipient").value.trim();
  const message = document.getElementById("message").value;

  const hasValidRecipient = ethers.isAddress(recipient);
  const isValid = hasValidRecipient && validateMessage(message).valid;

  document.getElementById("btn-submit").disabled = !isValid;
}

// ---------------------------------------------------------------------------
//  Submit Handler
// ---------------------------------------------------------------------------
async function handleSubmit() {
  if (!gagContract) return;

  const recipient = document.getElementById("recipient").value.trim();
  const message = document.getElementById("message").value;

  if (!ethers.isAddress(recipient)) return;

  const btn = document.getElementById("btn-submit");
  btn.disabled = true;
  btn.textContent = "Submitting...";
  showStatus("Sending your gag into the chaos buffer...", "info");

  try {
    const tx = await gagContract.submitMintIntent(anonymize, recipient, message, {
      value: mintPrice,
    });
    showStatus("Transaction submitted. Waiting for confirmation...", "info");
    showToast("Transaction submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showStatus("Your gag has entered the live chaos buffer. You funded the machine. May the slots be cruel.", "success");
    showToast("Gag submitted! The chaos buffer has been fed.", "success", 6000);

    const sharePanel = document.getElementById("share-panel");
    if (sharePanel) sharePanel.style.display = "block";

    pollLiveStats();

    // Reset form
    document.getElementById("recipient").value = "";
    document.getElementById("message").value = "";
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
async function loadClaimableBalance() {
  const container = document.getElementById("claim-balances");
  if (!gagContract || !userAddress || !container) return;

  try {
    const claimableAmount = await gagContract.claimable();
    const formatted = ethers.formatEther(claimableAmount);

    container.innerHTML = `
      <div class="claim-row">
        <span class="claim-token">PAS</span>
        <span class="claim-amount">${escapeHtml(formatted)}</span>
        <button class="btn btn-accent btn-sm claim-btn"
                ${claimableAmount === 0n ? "disabled" : ""}>
          Claim
        </button>
      </div>`;

    const claimBtn = container.querySelector(".claim-btn");
    if (claimBtn) {
      claimBtn.addEventListener("click", handleClaim);
    }

    if (claimableAmount === 0n) {
      container.innerHTML += '<p class="note">No claimable rewards yet. Send some gags and wait for burns.</p>';
    }
  } catch (err) {
    console.error("Failed to load claimable balance:", err);
    container.innerHTML = "<p>Failed to load balance.</p>";
  }
}

async function handleClaim() {
  if (!gagContract) return;

  showStatus("Claiming burn tribute...", "info");

  try {
    const tx = await gagContract.claimFees();
    showStatus("Claim submitted. Waiting for confirmation...", "info");
    await tx.wait();
    showStatus("Burn tribute claimed. You have been compensated for your menace.", "success");
    await loadClaimableBalance();
  } catch (err) {
    console.error("Claim failed:", err);
    showStatus("Claim failed: " + (err.reason || err.message), "error");
  }
}

// ---------------------------------------------------------------------------
//  Burn Section
// ---------------------------------------------------------------------------

let ownedTokens = [];

async function loadOwnedTokens() {
  const select = document.getElementById("burn-token-id");
  const emptyState = document.getElementById("burn-empty-state");
  const errEl = document.getElementById("burn-token-err");

  if (!select) return;

  select.innerHTML = '<option value="" disabled selected>Scanning wallet...</option>';
  if (emptyState) emptyState.style.display = "none";
  if (errEl) errEl.textContent = "";
  ownedTokens = [];

  const contract = gagContract || gagReadOnly;
  if (!contract || !userAddress) {
    select.innerHTML = '<option value="" disabled selected>Connect wallet first</option>';
    return;
  }

  try {
    const fromBlock = GAG_CONFIG.deployBlock || 0;
    const filter = contract.filters.Transfer(null, userAddress);
    const events = await contract.queryFilter(filter, fromBlock, "latest");

    const candidateIds = [...new Set(events.map(e => e.args.tokenId))];

    const verified = [];
    for (const tokenId of candidateIds) {
      try {
        const owner = await contract.ownerOf(tokenId);
        if (owner.toLowerCase() === userAddress.toLowerCase()) {
          verified.push(tokenId);
        }
      } catch {
        // ownerOf reverts if token was burned
      }
    }

    for (const tokenId of verified) {
      let message = "";
      try {
        message = await contract.getTokenMessage(tokenId);
      } catch {
        // If getTokenMessage fails, just show the ID
      }
      ownedTokens.push({ tokenId, message });
    }

    populateBurnTokenDropdown();
  } catch (err) {
    console.error("Failed to scan owned tokens:", err);
    select.innerHTML = '<option value="" disabled selected>Failed to scan</option>';
    if (errEl) errEl.textContent = "Could not scan wallet. You can try refreshing.";
    showToast("Failed to scan owned tokens", "error");
  }
}

function populateBurnTokenDropdown() {
  const select = document.getElementById("burn-token-id");
  const emptyState = document.getElementById("burn-empty-state");

  select.innerHTML = "";

  if (ownedTokens.length === 0) {
    select.innerHTML = '<option value="" disabled selected>No gags found</option>';
    if (emptyState) emptyState.style.display = "flex";
    validateBurnForm();
    return;
  }

  if (emptyState) emptyState.style.display = "none";

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

function onBurnTokenIdChange() {
  const val = document.getElementById("burn-token-id").value;
  const infoEl = document.getElementById("burn-token-info");
  const errEl = document.getElementById("burn-token-err");

  if (errEl) errEl.textContent = "";
  if (infoEl) infoEl.textContent = val ? "Token #" + val + " selected" : "";

  validateBurnForm();
}

function validateBurnForm() {
  const tokenIdEl = document.getElementById("burn-token-id");
  const btnBurn = document.getElementById("btn-burn");
  if (!tokenIdEl || !btnBurn) return;

  const tokenId = tokenIdEl.value;
  btnBurn.disabled = !tokenId;
}

async function handleBurn() {
  if (!gagContract) return;

  const tokenIdStr = document.getElementById("burn-token-id").value;
  if (!tokenIdStr) return;

  const tokenId = BigInt(tokenIdStr);

  const btn = document.getElementById("btn-burn");
  btn.disabled = true;
  btn.textContent = "Burning...";
  showBurnStatus("Sending burn transaction...", "info");

  try {
    const tx = await gagContract.burnToken(tokenId, { value: burnFeeAmount });
    showBurnStatus("Burn submitted. Waiting for confirmation...", "info");
    showToast("Burn transaction submitted...", "info");
    await tx.wait();
    showBurnStatus("Token #" + tokenIdStr + " has been incinerated. The curse is lifted.", "success");
    showToast("Gag burned! The wallet pollution has been cleansed.", "success", 6000);

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

function showBurnStatus(message, type) {
  const el = document.getElementById("burn-tx-status");
  if (!el) return;
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
  if (!container) return;

  if (!text) {
    container.innerHTML = '<div class="preview-placeholder">Your gag preview will appear here</div>';
    return;
  }

  const escaped = escapeHtml(text);
  const seed = simpleHash(text);
  const bgVariant = seed % 3;
  const rareMode = seed % 64 === 0;

  const bgColors = ["#0a0e17", "#1a0525", "#0f1510"];
  const accentColors = rareMode ? ["#ff00ff", "#00ffff"] : ["#ffcc00", "#00ffcc"];
  const bg = bgColors[bgVariant];
  const accent = accentColors[seed % 2];

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
      <text x="200" y="55" text-anchor="middle" fill="${accent}" font-size="11" font-family="monospace" opacity="0.7">DOTROT</text>
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
  if (!el) return;
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
  if (msg.includes("InsufficientPayment")) return "Insufficient PAS sent";
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
function showToast(message, type = "info", duration = 4500) {
  const container = document.getElementById("toast-container");
  if (!container) return;

  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);

  setTimeout(() => { toast.remove(); }, duration + 400);
}

// ---------------------------------------------------------------------------
//  Social Sharing
// ---------------------------------------------------------------------------
function buildShareText() {
  const site = GAG_CONFIG.siteUrl || window.location.href;
  return `I just loaded the chaos buffer on DotRot — on-chain social damage on Polkadot Asset Hub. Send a cursed soulbound NFT to your friends (or enemies). ${site}`;
}

function shareOnX() {
  const text = encodeURIComponent(buildShareText());
  window.open(`https://x.com/intent/tweet?text=${text}`, "_blank", "noopener");
  showToast("Opening X...", "info");
}

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
      // Silently ignore
    }
  }

  await fetchStat();
  setInterval(fetchStat, 30_000);
}

// ---------------------------------------------------------------------------
//  Scroll Animations
// ---------------------------------------------------------------------------
function initScrollAnimations() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  }, {
    threshold: 0.15,
    rootMargin: "0px 0px -40px 0px",
  });

  document.querySelectorAll(".fade-in").forEach(el => observer.observe(el));
}
