/**
 * DotRot — App Entry Point
 *
 * Bundles the wallet + contract module and exposes it as window.DotRotWallet
 * for the vanilla app.js to consume.
 */

import {
  connectWallet,
  readContract,
  writeContract,
  onAccountStatusChange,
  getBalance,
  resolveAddress,
  resolveDotNS,
  resolveUsername,
} from "./wallet.js";

window.DotRotWallet = {
  connectWallet,
  readContract,
  writeContract,
  onAccountStatusChange,
  getBalance,
  resolveAddress,
  resolveDotNS,
  resolveUsername,
};

window.dispatchEvent(new Event("dotrot-wallet-ready"));
