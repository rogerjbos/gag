/**
 * @title GaG Metadata Listener
 * @notice Watches for mint events on the GaG contract,
 *         generates SVG + metadata, uploads to Bulletin TransactionStorage
 *         via the dotns CLI, and writes the CID back to the contract.
 *
 * Environment variables:
 *   RPC_URL           — Asset Hub EVM JSON-RPC endpoint
 *   CONTRACT_ADDRESS  — Deployed GaG contract address
 *   UPDATER_KEY       — Private key of the metadata updater account
 *   DOTNS_MNEMONIC    — BIP39 mnemonic for Bulletin TransactionStorage uploads
 *
 * Usage:
 *   RPC_URL=https://eth-rpc-testnet.polkadot.io/ \
 *   CONTRACT_ADDRESS=0x... \
 *   UPDATER_KEY=0x... \
 *   DOTNS_MNEMONIC="word1 word2 ..." \
 *   node index.js
 */

import { ethers } from "ethers";
import { writeFileSync, mkdirSync, rmSync } from "fs";
import { execSync } from "child_process";
import { buildMetadata } from "./renderer.js";

// =========================================================================
//  Configuration
// =========================================================================

const RPC_URL = process.env.RPC_URL || "https://eth-rpc-testnet.polkadot.io/";
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const UPDATER_KEY = process.env.UPDATER_KEY;
const DOTNS_MNEMONIC = process.env.DOTNS_MNEMONIC;
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || "6000", 10);
const DOTNS_CLI = process.env.DOTNS_CLI || "dotns"; // path to dotns CLI, e.g. "node /path/to/cli.js"
const BULLETIN_RPC = process.env.BULLETIN_RPC || "wss://paseo-bulletin-rpc.polkadot.io";

if (!CONTRACT_ADDRESS || !UPDATER_KEY || !DOTNS_MNEMONIC) {
  console.error("Required env vars: CONTRACT_ADDRESS, UPDATER_KEY, DOTNS_MNEMONIC");
  process.exit(1);
}

// Minimal ABI — only what we need
const ABI = [
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
  "function getTokenMessage(uint256 tokenId) view returns (string)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "function setTokenCID(uint256 tokenId, string cid)",
  "function totalMinted() view returns (uint256)",
];

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(UPDATER_KEY, provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, wallet);

// =========================================================================
//  Upload to Bulletin TransactionStorage
// =========================================================================

/**
 * Upload a metadata JSON file to Bulletin TransactionStorage.
 * Returns the IPFS CID.
 */
function uploadToBulletin(filePath) {
  const cmd = `${DOTNS_CLI} bulletin upload "${filePath}" --json --mnemonic "${DOTNS_MNEMONIC}" --bulletin-rpc "${BULLETIN_RPC}"`;
  const result = execSync(cmd, { encoding: "utf-8", timeout: 120000 });
  const parsed = JSON.parse(result);
  return parsed.cid;
}

// =========================================================================
//  Process a single minted token
// =========================================================================

async function processToken(tokenId) {
  const tokenIdNum = Number(tokenId);

  // Check if CID is already set
  try {
    const uri = await contract.tokenURI(tokenIdNum);
    if (uri && uri.length > 0) {
      console.log(`  Token ${tokenIdNum}: CID already set, skipping`);
      return;
    }
  } catch {
    // Token may not exist — skip
    console.log(`  Token ${tokenIdNum}: does not exist or error, skipping`);
    return;
  }

  // Get the message
  let message;
  try {
    message = await contract.getTokenMessage(tokenIdNum);
  } catch (e) {
    console.error(`  Token ${tokenIdNum}: failed to get message: ${e.message}`);
    return;
  }

  console.log(`  Token ${tokenIdNum}: message="${message}"`);

  // Generate metadata
  const metadata = buildMetadata("GaG", tokenIdNum, message);

  // Write to temp file for upload
  const tmpDir = `.tmp-${tokenIdNum}`;
  mkdirSync(tmpDir, { recursive: true });
  const metadataPath = `${tmpDir}/metadata.json`;
  writeFileSync(metadataPath, JSON.stringify(metadata));

  // Upload to Bulletin TransactionStorage
  let cid;
  try {
    cid = uploadToBulletin(metadataPath);
    console.log(`  Token ${tokenIdNum}: uploaded to IPFS, CID=${cid}`);
  } catch (e) {
    console.error(`  Token ${tokenIdNum}: upload failed: ${e.message}`);
    rmSync(tmpDir, { recursive: true, force: true });
    return;
  }

  // Clean up temp files
  rmSync(tmpDir, { recursive: true, force: true });

  // Write CID to contract
  try {
    const tx = await contract.setTokenCID(tokenIdNum, cid);
    console.log(`  Token ${tokenIdNum}: setTokenCID tx=${tx.hash}`);
    await tx.wait();
    console.log(`  Token ${tokenIdNum}: CID set confirmed`);
  } catch (e) {
    console.error(`  Token ${tokenIdNum}: setTokenCID failed: ${e.message}`);
  }
}

// =========================================================================
//  Backfill — process any tokens that don't have CIDs yet
// =========================================================================

async function backfill() {
  const totalMinted = await contract.totalMinted();
  const total = Number(totalMinted);
  console.log(`Backfilling ${total} tokens...`);

  for (let i = 0; i < total; i++) {
    await processToken(i);
  }
  console.log("Backfill complete.");
}

// =========================================================================
//  Event listener — watch for new mints
// =========================================================================

async function startListener() {
  console.log(`Listening for mint events on ${CONTRACT_ADDRESS}`);
  console.log(`RPC: ${RPC_URL}`);
  console.log(`Poll interval: ${POLL_INTERVAL_MS}ms`);

  // Backfill existing tokens first
  await backfill();

  // Poll for new Transfer events (from = address(0) = mint)
  let lastBlock = await provider.getBlockNumber();
  console.log(`Starting poll from block ${lastBlock}`);

  const mintFilter = contract.filters.Transfer(ethers.ZeroAddress);

  setInterval(async () => {
    try {
      const currentBlock = await provider.getBlockNumber();
      if (currentBlock <= lastBlock) return;

      const events = await contract.queryFilter(mintFilter, lastBlock + 1, currentBlock);

      for (const event of events) {
        const tokenId = event.args[2];
        console.log(`New mint detected: token ${tokenId} at block ${event.blockNumber}`);
        await processToken(tokenId);
      }

      lastBlock = currentBlock;
    } catch (e) {
      console.error(`Poll error: ${e.message}`);
    }
  }, POLL_INTERVAL_MS);
}

// =========================================================================
//  Main
// =========================================================================

startListener().catch((e) => {
  console.error("Fatal error:", e);
  process.exit(1);
});
