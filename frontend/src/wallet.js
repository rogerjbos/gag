/**
 * DotRot Wallet Module — Triangle Only
 *
 * Connects via Polkadot Product SDK (Spektr) inside the .dot.li host.
 * Derives a deterministic EVM key from the connected Polkadot address
 * so EVM contract interactions can be auto-signed.
 */

import { ethers } from "ethers";
import {
  injectSpektrExtension,
  createNonProductExtensionEnableFactory,
  createAccountsProvider,
  sandboxTransport,
} from "@novasamatech/product-sdk";

// ---------------------------------------------------------------------------
//  EVM key derivation
// ---------------------------------------------------------------------------

function deriveEvmKey(polkadotAddress) {
  const seed = ethers.keccak256(
    ethers.toUtf8Bytes(`dotrot-v1:${polkadotAddress.toLowerCase()}`)
  );
  return new ethers.Wallet(seed);
}

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------
let _accountsProvider = null;
let _providerAccounts = [];

// ---------------------------------------------------------------------------
//  Connect
// ---------------------------------------------------------------------------

/**
 * Connect via Spektr in the .dot.li host.
 *
 * Returns {
 *   evmWallet,          // ethers Wallet connected to RPC
 *   evmAddress,         // derived EVM address
 *   substrateAddress,   // Polkadot SS58 address
 *   accountName,        // display name from Spektr
 *   needsFunding,       // true if derived EVM address has zero balance
 *   accountsProvider,   // SDK accountsProvider (for funding)
 *   providerAccounts,   // raw accounts with publicKey (for funding)
 * }
 */
export async function connectWallet(config) {
  await injectSpektrExtension();

  const enableFactory = await createNonProductExtensionEnableFactory(sandboxTransport);
  if (!enableFactory) {
    throw new Error("Not running inside the Host — open this page at dotrot.dot.li");
  }

  const injected = await enableFactory();
  _accountsProvider = createAccountsProvider(sandboxTransport);

  const accounts = await injected.accounts.get();
  const res = await _accountsProvider.getNonProductAccounts();
  _providerAccounts = res.match(
    (a) => a,
    () => []
  );

  if (accounts.length === 0) {
    throw new Error("No accounts found. Please log in to the Host.");
  }

  const substrateAddress = accounts[0].address;
  const evmWallet = deriveEvmKey(substrateAddress);
  const provider = new ethers.JsonRpcProvider(config.rpcUrl);
  const connectedWallet = evmWallet.connect(provider);

  // Check if derived EVM address has balance
  const balance = await provider.getBalance(evmWallet.address);

  return {
    evmWallet: connectedWallet,
    evmAddress: evmWallet.address,
    substrateAddress,
    accountName: accounts[0].name || "Anonymous",
    needsFunding: balance === 0n,
    accountsProvider: _accountsProvider,
    providerAccounts: _providerAccounts,
  };
}

/**
 * Fund the derived EVM address from the Substrate account.
 */
export async function fundEvmAddress(accountsProvider, providerAccounts, evmAddress, amount) {
  const { createClient } = await import("polkadot-api");
  const { getWsProvider } = await import("polkadot-api/ws-provider");

  const wsUrl = "wss://asset-hub-paseo-rpc.n.dwellir.com";
  const client = createClient(getWsProvider(wsUrl));

  try {
    const api = client.getUnsafeApi();

    const signer = accountsProvider.getNonProductAccountSigner({
      dotNsIdentifier: "",
      derivationIndex: 0,
      publicKey: providerAccounts[0].publicKey,
    });

    const evmBytes = ethers.getBytes(evmAddress);
    const mappedAccount = new Uint8Array(32);
    mappedAccount.fill(0xff, 0, 4);
    mappedAccount.set(evmBytes, 4);

    const tx = api.tx.Balances.transfer_keep_alive({
      dest: { type: "Id", value: mappedAccount },
      value: amount,
    });

    await new Promise((resolve, reject) => {
      tx.signSubmitAndWatch(signer).subscribe({
        next(ev) {
          if (ev.type === "finalized") resolve(ev);
        },
        error: reject,
      });
    });

    return true;
  } finally {
    client.destroy();
  }
}

/**
 * Watch for account connection/disconnection.
 */
export function onAccountStatusChange(callback) {
  if (_accountsProvider) {
    _accountsProvider.subscribeAccountConnectionStatus(callback);
  }
}
