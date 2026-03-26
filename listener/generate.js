/**
 * @title generate.js — Standalone SVG + metadata generator for testing
 *
 * Usage:
 *   node generate.js <tokenId> <message>
 *   node generate.js 0 "gm ser"
 *
 * Outputs:
 *   output/<tokenId>.svg      — Raw SVG file
 *   output/<tokenId>.json     — ERC-721 metadata JSON
 */

import { writeFileSync, mkdirSync } from "fs";
import { renderSVG, buildMetadata } from "./renderer.js";

const tokenId = parseInt(process.argv[2], 10);
const message = process.argv[3];

if (isNaN(tokenId) || !message) {
  console.error("Usage: node generate.js <tokenId> <message>");
  console.error('  e.g. node generate.js 0 "gm ser"');
  process.exit(1);
}

mkdirSync("output", { recursive: true });

const { svg } = renderSVG(tokenId, message);
const metadata = buildMetadata("GaG", tokenId, message);

writeFileSync(`output/${tokenId}.svg`, svg);
writeFileSync(`output/${tokenId}.json`, JSON.stringify(metadata, null, 2));

console.log(`Generated output/${tokenId}.svg (${svg.length} bytes)`);
console.log(`Generated output/${tokenId}.json`);
console.log(`Traits: ${metadata.attributes.map(a => `${a.trait_type}=${a.value}`).join(", ")}`);
