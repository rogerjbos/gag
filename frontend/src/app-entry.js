/**
 * DotRot — App Entry Point
 *
 * Bundles the wallet module and exposes it as window.DotRotWallet
 * for the vanilla app.js to consume.
 */

import { connectWallet, fundEvmAddress, onAccountStatusChange } from "./wallet.js";

window.DotRotWallet = {
  connectWallet,
  fundEvmAddress,
  onAccountStatusChange,
};

window.dispatchEvent(new Event("dotrot-wallet-ready"));
