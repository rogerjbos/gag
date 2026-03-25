/**
 * Bundle the wallet module (Product SDK + polkadot-api + ethers) into a single
 * JS file that can be loaded before app.js.
 *
 * Output: dist-bundle/wallet-bundle.js
 */
import { build } from "esbuild";
import { mkdirSync } from "fs";

mkdirSync("dist-bundle", { recursive: true });

await build({
  entryPoints: ["src/app-entry.js"],
  bundle: true,
  format: "iife",
  outfile: "dist-bundle/wallet-bundle.js",
  minify: true,
  target: "es2020",
  define: {
    "process.env.NODE_ENV": '"production"',
  },
});

console.log("Bundled → dist-bundle/wallet-bundle.js");
