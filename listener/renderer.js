/**
 * @title GaG SVG Renderer (JavaScript port)
 * @notice Faithful port of the Solidity Renderer.sol + Templates.sol + Utils.sol + Metadata.sol
 *         Produces identical SVG output given the same message and tokenId.
 *
 * Deterministic: keccak256(message) → seed → all visual traits
 */

import { keccak256, toUtf8Bytes } from "ethers";

// =========================================================================
//  Utils (from Utils.sol)
// =========================================================================

/**
 * Escape XML special characters for safe SVG embedding.
 * Matches Utils.escapeXML exactly.
 */
export function escapeXML(text) {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "&") out += "&amp;";
    else if (c === '"') out += "&quot;";
    else if (c === "'") out += "&apos;";
    else if (c === "<") out += "&lt;";
    else if (c === ">") out += "&gt;";
    else out += c;
  }
  return out;
}

// =========================================================================
//  Renderer (from Renderer.sol)
// =========================================================================

/**
 * Character width scoring — must match _charWidthScore exactly.
 */
function charWidthScore(c) {
  const code = c.charCodeAt(0);

  // space
  if (code === 0x20) return 4;
  // narrow: i, l, I, ., ,, !, :, ;, ', ", |
  if (
    code === 0x69 || code === 0x6c || code === 0x49 ||
    code === 0x2e || code === 0x2c || code === 0x21 ||
    code === 0x3a || code === 0x3b || code === 0x27 ||
    code === 0x22 || code === 0x7c
  ) return 4;
  // wide: W, M, @, #, &, %, Q, O, G, D, H, N, U
  if (
    code === 0x57 || code === 0x4d || code === 0x40 ||
    code === 0x23 || code === 0x26 || code === 0x25 ||
    code === 0x51 || code === 0x4f || code === 0x47 ||
    code === 0x44 || code === 0x48 || code === 0x4e ||
    code === 0x55
  ) return 9;
  // medium-narrow: (, ), [, ], /, -, _, +, ?
  if (
    code === 0x28 || code === 0x29 || code === 0x5b ||
    code === 0x5d || code === 0x2f || code === 0x2d ||
    code === 0x5f || code === 0x2b || code === 0x3f
  ) return 5;
  // default medium
  return 7;
}

function visualWidthScore(text, start, end) {
  let score = 0;
  for (let i = start; i < end; i++) {
    score += charWidthScore(text[i]);
  }
  return score;
}

function findBestSplit(text) {
  const len = text.length;

  // Build prefix-sum array
  const prefix = new Array(len + 1);
  prefix[0] = 0;
  for (let i = 0; i < len; i++) {
    prefix[i + 1] = prefix[i] + charWidthScore(text[i]);
  }

  let bestIndex = Math.floor(len / 2);
  let bestCost = Number.MAX_SAFE_INTEGER;
  let anySpace = false;

  for (let i = 1; i < len - 1; i++) {
    if (text[i] !== " ") continue;
    anySpace = true;

    const leftScore = prefix[i];
    const rightScore = prefix[len] - prefix[i + 1];
    const maxScore = Math.max(leftScore, rightScore);
    const scoreDiff = Math.abs(leftScore - rightScore);
    const leftLen = i;
    const rightLen = len - i - 1;
    const lenDiff = Math.abs(leftLen - rightLen);

    const cost = maxScore * 1000 + scoreDiff * 10 + lenDiff;
    if (cost < bestCost) {
      bestCost = cost;
      bestIndex = i;
    }
  }

  return { splitIndex: bestIndex, foundSpace: anySpace };
}

function fontSizeFromWidth(maxLineScore, twoLines, textVariant) {
  let base;

  if (!twoLines) {
    if (maxLineScore <= 70) base = 112;
    else if (maxLineScore <= 90) base = 96;
    else if (maxLineScore <= 110) base = 84;
    else if (maxLineScore <= 125) base = 74;
    else base = 66;
  } else {
    if (maxLineScore <= 50) base = 90;
    else if (maxLineScore <= 60) base = 80;
    else if (maxLineScore <= 70) base = 72;
    else if (maxLineScore <= 80) base = 64;
    else if (maxLineScore <= 90) base = 58;
    else base = 52;
  }

  if (textVariant === 1) return base + 2;
  if (textVariant === 2) return base > 2 ? base - 2 : base;
  return base;
}

function layoutText(text, data) {
  const totalScore = visualWidthScore(text, 0, text.length);

  if (totalScore <= 110 && text.length <= 20) {
    data.twoLines = false;
    data.line1 = text;
    data.line2 = "";
    data.fontSize = fontSizeFromWidth(totalScore, false, data.textVariant);
    return;
  }

  const { splitIndex, foundSpace } = findBestSplit(text);

  let line1, line2;
  if (foundSpace) {
    line1 = text.substring(0, splitIndex);
    line2 = text.substring(splitIndex + 1);
  } else {
    line1 = text.substring(0, splitIndex);
    line2 = text.substring(splitIndex);
  }

  const score1 = visualWidthScore(line1, 0, line1.length);
  const score2 = visualWidthScore(line2, 0, line2.length);
  const maxScore = Math.max(score1, score2);

  data.twoLines = true;
  data.line1 = line1;
  data.line2 = line2;
  data.fontSize = fontSizeFromWidth(maxScore, true, data.textVariant);

  const totalLen = text.length;
  if (totalLen >= 60) {
    data.fontSize = data.fontSize > 14 ? data.fontSize - 14 : data.fontSize;
  } else if (totalLen >= 52) {
    data.fontSize = data.fontSize > 10 ? data.fontSize - 10 : data.fontSize;
  } else if (totalLen >= 44) {
    data.fontSize = data.fontSize > 6 ? data.fontSize - 6 : data.fontSize;
  }
}

function backgroundName(variant) {
  if (variant === 0) return "Terminal Grid";
  if (variant === 1) return "Doomwave";
  return "Forum Static";
}

function frameName(variant) {
  if (variant === 0) return "Soft Coping";
  if (variant === 1) return "Double Down";
  return "Badge of Shame";
}

function toneName(variant) {
  if (variant === 0) return "Deadpan";
  if (variant === 1) return "Posting";
  return "Meltdown";
}

function moodName(seed) {
  const mood = Number((seed >> 24n) % 4n);
  if (mood === 0) return "Giggly";
  if (mood === 1) return "Snarky";
  if (mood === 2) return "Spicy";
  return "Terminal";
}

function badgeLabel(seed, rareMode) {
  const badge = Number((seed >> 32n) % 5n);

  if (rareMode) {
    if (badge === 0) return "UNHINGED";
    if (badge === 1) return "BRAINROT";
    if (badge === 2) return "TERMINAL";
    if (badge === 3) return "ALPHA LEAK";
    return "BAD IDEA";
  }

  if (badge === 0) return "POSTING";
  if (badge === 1) return "CERTIFIED";
  if (badge === 2) return "QUEUE MAXXED";
  if (badge === 3) return "ON-CHAIN";
  return "ABSURD";
}

/**
 * Derive all render data from message text.
 * Must match Renderer.deriveRenderData exactly.
 */
export function deriveRenderData(text) {
  const seedHex = keccak256(toUtf8Bytes(text));
  const seed = BigInt(seedHex);

  const data = {
    seed,
    seedHex,
    bgVariant: Number(seed % 3n),
    frameVariant: Number((seed >> 8n) % 3n),
    textVariant: Number((seed >> 16n) % 3n),
    rareMode: seed % 64n === 0n,
    length: text.length,
    fontSize: 0,
    twoLines: false,
    line1: "",
    line2: "",
    backgroundName: "",
    frameName: "",
    toneName: "",
    moodName: "",
    badgeLabel: "",
    caption: "randomly assigned chaos",
  };

  layoutText(text, data);

  data.backgroundName = backgroundName(data.bgVariant);
  data.frameName = frameName(data.frameVariant);
  data.toneName = toneName(data.textVariant);
  data.moodName = moodName(seed);
  data.badgeLabel = badgeLabel(seed, data.rareMode);

  return data;
}

// =========================================================================
//  Templates (from Templates.sol)
// =========================================================================

function svgHeader() {
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000" role="img" aria-label="GaG">';
}

function svgFooter() {
  return "</svg>";
}

function textStyleTemplate(variant, rareMode) {
  const fill = rareMode ? "#F7F1E3" : "#F4F1EA";
  const accent2 = rareMode ? "#FF7A59" : "#8BE9FD";
  const accent = rareMode ? "#F2B632" : "#FFC94A";
  const stroke = rareMode ? "#3A2A08" : "#2A2418";

  let fontWeight, letterSpacing;
  if (variant === 0) { fontWeight = "800"; letterSpacing = "0px"; }
  else if (variant === 1) { fontWeight = "900"; letterSpacing = "-1px"; }
  else { fontWeight = "700"; letterSpacing = "1px"; }

  return `<style>.bg-main{fill:#090909;}.stroke-main{stroke:${fill};stroke-width:6;fill:none;}.main-text{fill:${fill};font-family:monospace;font-weight:${fontWeight};letter-spacing:${letterSpacing};}.caption-text{fill:${accent2};font-family:monospace;font-size:20px;letter-spacing:2px;}.footer-text{fill:${accent};font-family:monospace;font-size:22px;letter-spacing:3px;}.outline-text{paint-order:stroke;stroke:${stroke};stroke-width:8;stroke-linejoin:round;}</style>`;
}

function terminalGrid(rareMode) {
  const secondaryFill = rareMode ? "#120F08" : "#111111";
  const accent = rareMode ? "#F2B632" : "#8BE9FD";

  return `<rect width="1000" height="1000" class="bg-main"/><rect x="40" y="40" width="920" height="920" fill="${secondaryFill}"/><g opacity="0.16" stroke="${accent}" stroke-width="4" fill="none"><path d="M200 70V900"/><path d="M400 70V900"/><path d="M600 70V900"/><path d="M800 70V900"/><path d="M70 220H930"/><path d="M70 420H930"/><path d="M70 620H930"/><path d="M70 820H930"/></g>`;
}

function wavePath(y0, c1y, c2y, midY, s1y, endY) {
  return `<path d="M80 ${y0} C240 ${c1y}, 360 ${c2y}, 520 ${midY} S760 ${s1y}, 920 ${endY}"/>`;
}

function doomwave(seed, rareMode) {
  const accent = rareMode ? "#F2B632" : "#7A5A20";

  const a = 180 + Number(seed % 40n);
  const b = 510 + Number((seed >> 8n) % 30n);
  const c = 770 - Number((seed >> 16n) % 40n);

  const wave1 = wavePath(a, a + 70, a - 60, a, a + 75, a);
  const wave2 = wavePath(b, b - 50, b + 45, b, b - 60, b);
  const wave3 = wavePath(c, c + 50, c - 35, c, c + 65, c);

  return `<rect width="1000" height="1000" class="bg-main"/><g opacity="0.45" stroke="${accent}" stroke-width="6" fill="none">${wave1}${wave2}${wave3}</g>`;
}

function dot(seedHex, i) {
  const xSeed = BigInt(keccak256(toUtf8Bytes(seedHex + "x" + i)));
  const ySeed = BigInt(keccak256(toUtf8Bytes(seedHex + "y" + i)));
  const rSeed = BigInt(keccak256(toUtf8Bytes(seedHex + "r" + i)));

  // Wait — the Solidity uses abi.encodePacked(seed, "x", i) where seed is bytes32
  // and i is uint256. We need to match this exactly.
  // Actually, let me re-examine: keccak256(abi.encodePacked(seed, "x", i))
  // seed is bytes32, "x" is a string literal (bytes1 in packed), i is uint256

  // We need to use the raw bytes, not the hex string. Let me fix this.
  return null; // Placeholder — will be replaced by proper implementation
}

/**
 * Replicate abi.encodePacked(bytes32, string, uint256) for dot generation.
 * In Solidity: keccak256(abi.encodePacked(seed, "x", i))
 * seed is bytes32 (32 bytes), "x" is packed as 1 byte, i is uint256 (32 bytes)
 */
function dotHash(seedHex, suffix, i) {
  // seedHex is "0x..." (66 chars = 32 bytes)
  // suffix is "x", "y", or "r" (1 byte)
  // i is a number (uint256 = 32 bytes, big-endian)
  const seedBytes = seedHex.slice(2); // remove "0x"
  const suffixHex = suffix.charCodeAt(0).toString(16).padStart(2, "0");
  const iHex = BigInt(i).toString(16).padStart(64, "0");
  return BigInt(keccak256("0x" + seedBytes + suffixHex + iHex));
}

function dotElement(seedHex, i) {
  const x = 90 + Number(dotHash(seedHex, "x", i) % 820n);
  const y = 120 + Number(dotHash(seedHex, "y", i) % 720n);
  const r = 3 + Number(dotHash(seedHex, "r", i) % 6n);
  return `<circle cx="${x}" cy="${y}" r="${r}"/>`;
}

function forumStatic(seedHex, rareMode) {
  const accent = rareMode ? "#FF7A59" : "#A78BFA";

  let dots = "";
  for (let i = 0; i < 16; i++) {
    dots += dotElement(seedHex, i);
  }

  return `<rect width="1000" height="1000" class="bg-main"/><g opacity="0.38" fill="${accent}">${dots}</g>`;
}

function backgroundTemplate(variant, seed, seedHex, rareMode) {
  if (variant === 0) return terminalGrid(rareMode);
  if (variant === 1) return doomwave(seed, rareMode);
  return forumStatic(seedHex, rareMode);
}

function softCopingFrame(rareMode) {
  const accent = rareMode ? "#F2B632" : "#FFC94A";
  return `<rect x="52" y="52" width="896" height="896" rx="36" class="stroke-main"/><rect x="74" y="74" width="852" height="836" rx="28" stroke="${accent}" stroke-width="2" fill="none" opacity="0.55"/>`;
}

function doubleDownFrame(rareMode) {
  const accent = rareMode ? "#FF7A59" : "#A78BFA";
  return `<rect x="48" y="48" width="904" height="904" rx="18" class="stroke-main"/><rect x="82" y="82" width="836" height="828" rx="12" stroke="${accent}" stroke-width="4" fill="none" opacity="0.72"/>`;
}

function badgeOfShameFrame(rareMode) {
  const accent = rareMode ? "#F2B632" : "#FFC94A";
  return `<rect x="56" y="56" width="888" height="888" rx="12" class="stroke-main"/><path d="M180 74H820" stroke="${accent}" stroke-width="8" opacity="0.8"/><path d="M180 908H820" stroke="${accent}" stroke-width="8" opacity="0.8"/>`;
}

function frameTemplate(variant, rareMode) {
  if (variant === 0) return softCopingFrame(rareMode);
  if (variant === 1) return doubleDownFrame(rareMode);
  return badgeOfShameFrame(rareMode);
}

function logoTemplate(rareMode) {
  const accent = rareMode ? "#F2B632" : "#FFC94A";
  const fill = rareMode ? "#F7F1E3" : "#F4F1EA";
  return `<g transform="translate(108 108)"><circle cx="0" cy="0" r="18" fill="none" stroke="${accent}" stroke-width="4"/><circle cx="42" cy="0" r="18" fill="none" stroke="${accent}" stroke-width="4"/><text x="84" y="8" fill="${fill}" font-family="monospace" font-size="30" font-weight="900">GaG</text></g>`;
}

function badgeTemplate(label, rareMode) {
  const fill = rareMode ? "#F2B632" : "#FFC94A";
  return `<g transform="translate(740 90)"><rect x="0" y="0" width="170" height="44" rx="22" fill="${fill}"/><text x="85" y="28" text-anchor="middle" fill="#111111" font-family="monospace" font-size="18" font-weight="900">${label}</text></g>`;
}

function topEnsDomain() {
  return '<text x="500" y="34" text-anchor="middle" class="footer-text">gagged.dot.li</text>';
}

function buildSingleLineTextNode(escapedText, fontSize, variant) {
  const y = variant === 2 ? "484" : "492";
  return `<text x="500" y="${y}" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="${fontSize}">${escapedText}</text>`;
}

function buildTwoLineTextNode(escapedLine1, escapedLine2, fontSize) {
  return `<text x="500" y="448" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="${fontSize}">${escapedLine1}</text><text x="500" y="560" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="${fontSize}">${escapedLine2}</text>`;
}

function captionLine(caption) {
  return `<text x="500" y="875" text-anchor="middle" class="caption-text">${caption}</text>`;
}

function footerLabel() {
  return '<text x="500" y="982" text-anchor="middle" class="footer-text">GAG</text>';
}

function tokenIdLabel(tokenId) {
  return `<text x="76" y="982" text-anchor="start" class="footer-text">#${tokenId}</text>`;
}

// =========================================================================
//  Public API
// =========================================================================

/**
 * Render the complete SVG for a given tokenId and message.
 * Must match Renderer.renderSVG exactly.
 */
export function renderSVG(tokenId, text) {
  const data = deriveRenderData(text);

  const head = [
    svgHeader(),
    textStyleTemplate(data.textVariant, data.rareMode),
    backgroundTemplate(data.bgVariant, data.seed, data.seedHex, data.rareMode),
    frameTemplate(data.frameVariant, data.rareMode),
    logoTemplate(data.rareMode),
    badgeTemplate(data.badgeLabel, data.rareMode),
    topEnsDomain(),
  ].join("");

  const tail = [
    captionLine(data.caption),
    footerLabel(),
    tokenIdLabel(tokenId),
    svgFooter(),
  ].join("");

  let svg;
  if (data.twoLines) {
    svg = head + buildTwoLineTextNode(
      escapeXML(data.line1), escapeXML(data.line2), data.fontSize
    ) + tail;
  } else {
    svg = head + buildSingleLineTextNode(
      escapeXML(data.line1), data.fontSize, data.textVariant
    ) + tail;
  }

  return { svg, data };
}

/**
 * Build the JSON attributes array matching Renderer.attributesJSON.
 */
export function attributesJSON(data) {
  return [
    { trait_type: "Background", value: data.backgroundName },
    { trait_type: "Frame", value: data.frameName },
    { trait_type: "Tone", value: data.toneName },
    { trait_type: "Mood", value: data.moodName },
    { trait_type: "Badge", value: data.badgeLabel },
    { trait_type: "Caption", value: data.caption },
    { trait_type: "Layout", value: data.twoLines ? "Two Lines" : "Single Line" },
    { trait_type: "Rare", value: data.rareMode ? "Yes" : "No" },
    { display_type: "number", trait_type: "Length", value: data.length },
  ];
}

/**
 * Build complete ERC-721 metadata JSON for a token.
 */
export function buildMetadata(collectionName, tokenId, text) {
  const { svg, data } = renderSVG(tokenId, text);

  const svgBase64 = Buffer.from(svg).toString("base64");
  const image = `data:image/svg+xml;base64,${svgBase64}`;

  return {
    name: `${collectionName} #${tokenId}`,
    description: "GaG is a queue-minted on-chain gag collectible. The message and image are rendered fully on-chain.",
    attributes: attributesJSON(data),
    image,
  };
}
