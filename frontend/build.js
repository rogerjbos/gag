#!/usr/bin/env node
/**
 * Giggles and Gags — Static Build Script
 *
 * Generates a multi-page static site from the single-page source.
 * Each route gets its own index.html with route-specific meta tags,
 * Farcaster embed metadata, and Open Graph tags.
 *
 * Output is IPFS-ready: all asset paths are relative.
 *
 * Usage:
 *   node build.js              (outputs to ../dist)
 *   node build.js --out ./out  (custom output directory)
 */

const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------------------
//  Config
// ---------------------------------------------------------------------------
const SRC_DIR = __dirname;
const DEFAULT_OUT = path.resolve(__dirname, "..", "dist");
const OUT_DIR = process.argv.includes("--out")
  ? path.resolve(process.argv[process.argv.indexOf("--out") + 1])
  : DEFAULT_OUT;

const SITE_URL = "https://gigglesandgags.eth.limo";
const ENS_NAME = "gigglesandgags.eth";

// Assets to copy verbatim
const COPY_FILES = ["app.js", "config.js", "abi.js", "style.css", "favicon.svg"];

// ---------------------------------------------------------------------------
//  Route definitions
// ---------------------------------------------------------------------------
const ROUTES = {
  "/": {
    page: "home",
    title: "Giggles and Gags — Send a cursed onchain message",
    description:
      "A non-transferable prank NFT powered by stablecoins and randomly assigned chaos. On Base.",
    ogImage: "og/default.png",
    fcButton: "Open App",
  },
  "/send": {
    page: "send",
    title: "Send a Gag — Giggles and Gags",
    description:
      "Fund the chaos buffer. Your gag may mint later. Someone else's may mint now.",
    ogImage: "og/default.png",
    scrollTo: "mint",
    fcButton: "Send a Gag",
  },
  "/burn": {
    page: "burn",
    title: "Burn a Gag — Giggles and Gags",
    description:
      "Got pranked? Pay the burn fee to remove a non-transferable gag from your wallet.",
    ogImage: "og/default.png",
    scrollTo: "burn",
    fcButton: "Burn a Gag",
  },
  "/claim": {
    page: "claim",
    title: "Claim Burn Tribute — Giggles and Gags",
    description:
      "If your attributable gag got burned, collect your cut of the burn fee.",
    ogImage: "og/default.png",
    scrollTo: "claim",
    fcButton: "Claim Tribute",
  },
  "/how": {
    page: "how",
    title: "How Giggles and Gags Works",
    description:
      "This is not a normal queue. It is a fixed-size chaos buffer for wallet-to-wallet onchain gags.",
    ogImage: "og/default.png",
    scrollTo: "how-it-works",
    fcButton: "Learn More",
  },
  "/gag": {
    page: "gag",
    title: "Giggles and Gags — Token",
    description:
      "Randomly assigned chaos, permanently attached until someone pays to burn it.",
    ogImage: "og/default.png",
    fcButton: "View Gag",
  },
};

// ---------------------------------------------------------------------------
//  OG Image (inline SVG)
// ---------------------------------------------------------------------------
function generateOGImage() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#07080c"/>
      <stop offset="100%" stop-color="#0d0f15"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect x="30" y="30" width="1140" height="570" rx="16" fill="none" stroke="#ffcc00" stroke-width="2" opacity="0.3"/>
  <text x="600" y="240" text-anchor="middle" fill="#ffcc00" font-family="monospace" font-size="72" font-weight="800">Giggles &amp; Gags</text>
  <text x="600" y="310" text-anchor="middle" fill="#888" font-family="monospace" font-size="24">on-chain social damage on Base</text>
  <text x="600" y="380" text-anchor="middle" fill="#555" font-family="monospace" font-size="18">non-transferable prank NFTs · stablecoin powered · slot buffer chaos</text>
  <text x="600" y="560" text-anchor="middle" fill="#333" font-family="monospace" font-size="14">${ENS_NAME}</text>
</svg>`;
}

// ---------------------------------------------------------------------------
//  Meta tag generation
// ---------------------------------------------------------------------------
function buildMetaTags(route, routeConfig) {
  const canonicalUrl = route === "/" ? SITE_URL : `${SITE_URL}${route}`;
  const imageUrl = `${SITE_URL}/${routeConfig.ogImage}`;

  // Farcaster frame embed meta (Mini App launch action)
  const fcFrameJson = JSON.stringify({
    version: "next",
    imageUrl: imageUrl,
    button: {
      title: routeConfig.fcButton || "Open App",
      action: {
        type: "launch_frame",
        name: "Giggles and Gags",
        url: canonicalUrl,
        splashImageUrl: `${SITE_URL}/og/default.png`,
        splashBackgroundColor: "#07080c",
      },
    },
  });

  return `  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${routeConfig.title}</title>
  <meta name="description" content="${routeConfig.description}" />

  <!-- Open Graph -->
  <meta property="og:type" content="website" />
  <meta property="og:title" content="${routeConfig.title}" />
  <meta property="og:description" content="${routeConfig.description}" />
  <meta property="og:url" content="${canonicalUrl}" />
  <meta property="og:image" content="${imageUrl}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:site_name" content="Giggles and Gags" />

  <!-- Twitter / X -->
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${routeConfig.title}" />
  <meta name="twitter:description" content="${routeConfig.description}" />
  <meta name="twitter:image" content="${imageUrl}" />

  <!-- Farcaster Frame Embed -->
  <meta property="fc:frame" content='${fcFrameJson}' />

  <!-- Canonical -->
  <link rel="canonical" href="${canonicalUrl}" />

  <!-- Page identifier (used by client-side router) -->
  <meta name="gag-page" content="${routeConfig.page}" />
  ${routeConfig.scrollTo ? `<meta name="gag-scroll-to" content="${routeConfig.scrollTo}" />` : ""}`;
}

// ---------------------------------------------------------------------------
//  HTML template processing
// ---------------------------------------------------------------------------
function buildPageHTML(sourceHTML, route, routeConfig) {
  // Replace the <head> content between the markers
  // Strategy: replace everything between <head> and </head> with new meta tags
  // but keep the font/css links

  const headContent = buildMetaTags(route, routeConfig);

  // Determine relative path prefix for assets
  let assetPrefix = "";
  if (route !== "/") {
    const depth = route.split("/").filter(Boolean).length;
    assetPrefix = "../".repeat(depth);
  }

  // Build the full head
  const fullHead = `<head>
${headContent}

  <!-- Base Mini App -->
  <meta name="base:app_id" content="69b2ba685600c39dcfa4fe3f" />

  <!-- Favicon -->
  <link rel="icon" href="${assetPrefix}favicon.svg" type="image/svg+xml" />

  <!-- Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700;800&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="${assetPrefix}style.css" />
</head>`;

  // Replace existing <head>...</head>
  let html = sourceHTML.replace(/<head>[\s\S]*?<\/head>/, fullHead);

  // Fix asset paths in script tags
  html = html.replace(
    /src="(style\.css|app\.js|config\.js|abi\.js)"/g,
    `src="${assetPrefix}$1"`
  );
  html = html.replace(
    'src="https://cdnjs.cloudflare.com/ajax/libs/ethers/6.13.4/ethers.umd.min.js"',
    `src="${assetPrefix}vendor/ethers.umd.min.js"`
  );

  // Fix all local script sources for nested paths
  html = html.replace(
    /  <script src="config\.js"><\/script>/,
    `  <script src="${assetPrefix}config.js"></script>`
  );
  html = html.replace(
    /  <script src="abi\.js"><\/script>/,
    `  <script src="${assetPrefix}abi.js"></script>`
  );
  html = html.replace(
    /  <script src="app\.js"><\/script>/,
    `  <script src="${assetPrefix}app.js"></script>`
  );

  return html;
}

// ---------------------------------------------------------------------------
//  Farcaster manifest
// ---------------------------------------------------------------------------
function buildFarcasterManifest() {
  return JSON.stringify(
    {
      accountAssociation: {
        header: "eyJmaWQiOjI5MDI0OTMsInR5cGUiOiJjdXN0b2R5Iiwia2V5IjoiMHg3MTYwMDJBNEUwMTRDZDQ0ODliMzZlQUE5QUU2RjI3NGUxNDFiOTMzIn0",
        payload: "eyJkb21haW4iOiJnaWdnbGVzYW5kZ2Fncy5ldGgubGltbyJ9",
        signature: "SogFqpyG095j7yi3JsYOqu2qQL/wQ2LPyPTcrmMkRz4QkafSmag+uhfsuLNImdjwkfpnW6ygEN32F4NZ03B1Zhs=",
      },
      frame: {
        version: "1",
        name: "Giggles and Gags",
        iconUrl: `${SITE_URL}/og/icon-1024.png`,
        homeUrl: SITE_URL,
        imageUrl: `${SITE_URL}/og/default.png`,
        buttonTitle: "Unleash Chaos",
        splashImageUrl: `${SITE_URL}/og/splash-200.png`,
        splashBackgroundColor: "#07080c",
        subtitle: "On-chain social damage on Base",
        description:
          "Non-transferable prank NFTs. Send a cursed message, fund the chaos, and the slot buffer decides what mints next. Pay to burn. Collect tribute.",
        primaryCategory: "social",
        heroImageUrl: `${SITE_URL}/og/default.png`,
        tags: ["nft", "prank", "base", "social", "meme"],
        tagline: "Send a cursed message.",
        ogTitle: "GaG: On-Chain Social Damage",
        ogDescription: "Non-transferable prank NFTs powered by stablecoins and poor judgment. On Base.",
        ogImageUrl: `${SITE_URL}/og/default.png`,
        castShareUrl: `${SITE_URL}`,
      },
    },
    null,
    2
  );
}

// ---------------------------------------------------------------------------
//  Icon / splash SVGs
// ---------------------------------------------------------------------------
function generateIcon512() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="96" fill="#07080c"/>
  <rect x="16" y="16" width="480" height="480" rx="80" fill="none" stroke="#ffcc00" stroke-width="4" opacity="0.3"/>
  <text x="256" y="220" text-anchor="middle" fill="#ffcc00" font-family="monospace" font-size="120" font-weight="800">G</text>
  <text x="256" y="220" text-anchor="middle" fill="#ffcc00" font-family="monospace" font-size="120" font-weight="800" dx="4" opacity="0.3">G</text>
  <text x="256" y="340" text-anchor="middle" fill="#888" font-family="monospace" font-size="36" font-weight="700">&amp;</text>
  <text x="256" y="400" text-anchor="middle" fill="#ffcc00" font-family="monospace" font-size="100" font-weight="800">G</text>
</svg>`;
}

function generateSplash200() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <rect width="200" height="200" fill="#07080c"/>
  <text x="100" y="90" text-anchor="middle" fill="#ffcc00" font-family="monospace" font-size="48" font-weight="800">GaG</text>
  <text x="100" y="130" text-anchor="middle" fill="#555" font-family="monospace" font-size="12">on-chain social damage</text>
</svg>`;
}

// ---------------------------------------------------------------------------
//  Main build
// ---------------------------------------------------------------------------
function main() {
  console.log(`Building static site → ${OUT_DIR}\n`);

  // Read source
  const sourceHTML = fs.readFileSync(path.join(SRC_DIR, "index.html"), "utf8");

  // Create directories (skip clean — IPFS/mounted dirs may have permission issues)
  const dirs = [
    OUT_DIR,
    path.join(OUT_DIR, "send"),
    path.join(OUT_DIR, "burn"),
    path.join(OUT_DIR, "claim"),
    path.join(OUT_DIR, "how"),
    path.join(OUT_DIR, "gag"),
    path.join(OUT_DIR, ".well-known"),
    path.join(OUT_DIR, "og"),
    path.join(OUT_DIR, "vendor"),
  ];
  for (const dir of dirs) {
    fs.mkdirSync(dir, { recursive: true });
  }

  // Generate per-route HTML
  for (const [route, config] of Object.entries(ROUTES)) {
    const html = buildPageHTML(sourceHTML, route, config);
    const outPath =
      route === "/"
        ? path.join(OUT_DIR, "index.html")
        : path.join(OUT_DIR, route.slice(1), "index.html");
    fs.writeFileSync(outPath, html);
    console.log(`  ✓ ${route} → ${path.relative(OUT_DIR, outPath)}`);
  }

  // Copy static assets
  for (const file of COPY_FILES) {
    fs.copyFileSync(path.join(SRC_DIR, file), path.join(OUT_DIR, file));
    console.log(`  ✓ ${file}`);
  }

  // Generate OG images
  // Pre-built PNGs (platforms reject SVG for og:image, icons, and splash)
  fs.copyFileSync(path.join(SRC_DIR, "og", "default.png"), path.join(OUT_DIR, "og", "default.png"));
  fs.copyFileSync(path.join(SRC_DIR, "og", "icon-1024.png"), path.join(OUT_DIR, "og", "icon-1024.png"));
  fs.copyFileSync(path.join(SRC_DIR, "og", "splash-200.png"), path.join(OUT_DIR, "og", "splash-200.png"));
  // Keep SVGs as fallback
  fs.writeFileSync(path.join(OUT_DIR, "og", "default.svg"), generateOGImage());
  fs.writeFileSync(path.join(OUT_DIR, "og", "icon-512.svg"), generateIcon512());
  fs.writeFileSync(
    path.join(OUT_DIR, "og", "splash-200.svg"),
    generateSplash200()
  );
  console.log("  ✓ og/default.png");
  console.log("  ✓ og/icon-1024.png");
  console.log("  ✓ og/splash-200.png");
  console.log("  ✓ og/default.svg");
  console.log("  ✓ og/icon-512.svg");
  console.log("  ✓ og/splash-200.svg");

  // Farcaster manifest
  fs.writeFileSync(
    path.join(OUT_DIR, ".well-known", "farcaster.json"),
    buildFarcasterManifest()
  );
  console.log("  ✓ .well-known/farcaster.json");

  // Vendor: download ethers note
  fs.writeFileSync(
    path.join(OUT_DIR, "vendor", "README.md"),
    `# Vendor Dependencies\n\nethers.js v6 UMD bundle:\n\`\`\`\ncurl -o ethers.umd.min.js https://cdnjs.cloudflare.com/ajax/libs/ethers/6.13.4/ethers.umd.min.js\n\`\`\`\n`
  );
  // Also create a shim that loads from CDN if vendor file is missing
  fs.writeFileSync(
    path.join(OUT_DIR, "vendor", "ethers.umd.min.js"),
    `/* ethers.js v6.13.4 — place the real UMD bundle here before deploying */\n` +
      `console.error("ethers.js vendor bundle missing.");\n`
  );
  console.log("  ✓ vendor/ethers.umd.min.js (stub)");

  console.log(`\nBuild complete. ${Object.keys(ROUTES).length} routes generated → dist/`);
}

main();
