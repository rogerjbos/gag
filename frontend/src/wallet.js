/**
 * DotRot Wallet + Contract Module — Triangle Only
 *
 * Connects via Product SDK (Spektr), interacts with the EVM contract
 * through polkadot-api's Revive API. No derived keys, no MetaMask.
 *
 * Pattern based on ignite project's WalletContext + useContractPAPI.
 */

import {
  injectSpektrExtension,
  createNonProductExtensionEnableFactory,
  createAccountsProvider,
  sandboxTransport,
} from "@novasamatech/product-sdk";

import { createClient, Binary, AccountId } from "polkadot-api";
import { getWsProvider } from "polkadot-api/ws-provider/web";
import { createInkSdk } from "@polkadot-api/sdk-ink";
import { encodeFunctionData, decodeFunctionResult, keccak256 } from "viem";

// ---------------------------------------------------------------------------
//  Config
// ---------------------------------------------------------------------------
const RPC_ENDPOINTS = [
  "wss://asset-hub-paseo-rpc.n.dwellir.com",
  "wss://asset-hub-paseo-rpc.polkadot.io",
];

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------
let _accountsProvider = null;
let _providerAccounts = [];
let _accounts = [];
let _signer = null;
let _enableFactory = null;
let _client = null;
let _api = null;
let _inkSdk = null;

// ---------------------------------------------------------------------------
//  PAPI Client
// ---------------------------------------------------------------------------

async function initPAPI() {
  if (_client) return;
  const provider = getWsProvider(RPC_ENDPOINTS);
  _client = createClient(provider);
  _api = _client.getUnsafeApi();
  _inkSdk = createInkSdk(_client);
}

// ---------------------------------------------------------------------------
//  SS58 → H160 conversion (local, no RPC needed)
// ---------------------------------------------------------------------------

const h160Cache = new Map();

function ss58ToH160(ss58Address) {
  if (h160Cache.has(ss58Address)) return h160Cache.get(ss58Address);
  const publicKey = AccountId().enc(ss58Address);
  const hash = keccak256(publicKey);
  const h160 = ("0x" + hash.slice(26)).toLowerCase();
  h160Cache.set(ss58Address, h160);
  return h160;
}

// ---------------------------------------------------------------------------
//  Connect wallet via Spektr
//  Returns a Promise that resolves when an account is available.
//  If no account yet, subscribes to status changes and waits.
// ---------------------------------------------------------------------------

export async function connectWallet() {
  await injectSpektrExtension();

  _enableFactory = await createNonProductExtensionEnableFactory(sandboxTransport);
  if (!_enableFactory) {
    throw new Error("Not running inside the Host — open this page at dotrot.dot.li");
  }

  _accountsProvider = createAccountsProvider(sandboxTransport);

  // Try fetching accounts immediately
  const result = await tryFetchAccounts();
  if (result) return result;

  // No accounts yet — wait for the user to log in
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error("Timed out waiting for account. Please log in to the Host."));
    }, 120000); // 2 minute timeout

    _accountsProvider.subscribeAccountConnectionStatus(async (status) => {
      if (status === "connected") {
        const result = await tryFetchAccounts();
        if (result) {
          clearTimeout(timeout);
          resolve(result);
        }
      }
    });
  });
}

async function tryFetchAccounts() {
  const injected = await _enableFactory();
  _accounts = await injected.accounts.get();

  const res = await _accountsProvider.getNonProductAccounts();
  _providerAccounts = res.match(
    (a) => a,
    () => []
  );

  if (_accounts.length === 0) return null;

  // Build signer
  _signer = _accountsProvider.getNonProductAccountSigner({
    dotNsIdentifier: "",
    derivationIndex: 0,
    publicKey: _providerAccounts[0].publicKey,
  });

  // Init PAPI client
  await initPAPI();

  const substrateAddress = _accounts[0].address;
  const h160Address = ss58ToH160(substrateAddress);

  return {
    substrateAddress,
    h160Address,
    accountName: _accounts[0].name || "Anonymous",
  };
}

/**
 * Watch for account connection/disconnection.
 */
export function onAccountStatusChange(callback) {
  if (_accountsProvider) {
    _accountsProvider.subscribeAccountConnectionStatus(callback);
  }
}

// ---------------------------------------------------------------------------
//  Contract Read via ReviveApi.call
// ---------------------------------------------------------------------------

export async function readContract(callerSS58, contractAddress, abi, functionName, args = []) {
  if (!_api) throw new Error("PAPI client not initialized");

  const data = encodeFunctionData({ abi, functionName, args });

  const result = await _api.apis.ReviveApi.call(
    callerSS58,
    Binary.fromHex(contractAddress),
    0n,
    undefined,
    undefined,
    Binary.fromHex(data),
    { at: "best" },
  );

  const callResult = result.result;
  if (!callResult) throw new Error(`No result for ${functionName}`);

  if ("success" in callResult) {
    if (!callResult.success) {
      throw new Error(`Contract read failed: ${functionName}`);
    }
    const valueData = callResult.value?.data || callResult.value;
    let resultData;
    if (valueData && typeof valueData.asHex === "function") {
      resultData = valueData.asHex();
    } else if (typeof valueData === "string") {
      resultData = valueData.startsWith("0x") ? valueData : `0x${valueData}`;
    } else if (valueData && valueData.bytes) {
      resultData = "0x" + Array.from(valueData.bytes)
        .map((b) => b.toString(16).padStart(2, "0")).join("");
    } else {
      throw new Error(`Cannot extract data for ${functionName}`);
    }
    return safeDecode(abi, functionName, resultData);
  }

  if (callResult.type === "Reverted" || callResult.type === "Error") {
    throw new Error(`Contract call ${callResult.type}`);
  }

  const responseData = callResult.data || callResult.value?.data || callResult;
  let resultData;
  if (responseData && typeof responseData.asHex === "function") {
    resultData = responseData.asHex();
  } else if (typeof responseData === "string") {
    resultData = responseData.startsWith("0x") ? responseData : `0x${responseData}`;
  } else {
    throw new Error(`Cannot extract data for ${functionName}`);
  }
  return safeDecode(abi, functionName, resultData);
}

// ---------------------------------------------------------------------------
//  Contract Write via tx.Revive.call
// ---------------------------------------------------------------------------

export async function writeContract(callerSS58, contractAddress, abi, functionName, args = [], value = 0n) {
  if (!_api || !_signer) throw new Error("Wallet not connected");

  const data = encodeFunctionData({ abi, functionName, args });

  const [needsMapping, dryRun] = await Promise.all([
    _inkSdk.addressIsMapped(callerSS58).then((mapped) => !mapped),
    _api.apis.ReviveApi.call(
      callerSS58,
      Binary.fromHex(contractAddress),
      value,
      undefined,
      undefined,
      Binary.fromHex(data),
      { at: "best" },
    ).catch((err) => { console.warn(`[Contract] dry-run failed for ${functionName}:`, err); return null; }),
  ]);

  let refTime = 50_000_000_000n;
  let proofSize = 2_000_000n;
  let storageDeposit = 10_000_000_000n;

  if (dryRun) {
    const callResult = dryRun.result;
    // Only throw on revert if account is already mapped — unmapped accounts
    // always fail dry-run since Revive can't resolve the caller
    if (!needsMapping && callResult && "success" in callResult && !callResult.success) {
      // Try to extract the Solidity revert reason
      const revertData = callResult.value?.data;
      let revertHex = null;
      if (revertData && typeof revertData.asHex === "function") {
        revertHex = revertData.asHex();
      } else if (typeof revertData === "string") {
        revertHex = revertData.startsWith("0x") ? revertData : `0x${revertData}`;
      }
      console.error(`[Contract] dry-run revert for ${functionName}:`, {
        callResult: JSON.stringify(callResult, (_, v) => typeof v === "bigint" ? v.toString() : v),
        revertHex,
        needsMapping,
        value: value.toString(),
      });

      // Try to decode Error(string) selector 0x08c379a0
      let reason = functionName;
      if (revertHex && revertHex.startsWith("0x08c379a0") && revertHex.length > 10) {
        try {
          const msgHex = revertHex.slice(10);
          const bytes = new Uint8Array(msgHex.match(/.{1,2}/g).map(b => parseInt(b, 16)));
          const len = Number(BigInt("0x" + msgHex.slice(64, 128)));
          reason = new TextDecoder().decode(bytes.slice(64, 64 + len));
        } catch {}
      }
      // Try to match custom error selectors from the ABI
      if (revertHex) {
        const selector = revertHex.slice(0, 10);
        const knownErrors = {
          "0xf4844814": "InsufficientPayment",
          "0x8baa579f": "InvalidRecipient",
          "0xa04d15b5": "NonTransferable",
          "0x49e27cff": "NotTokenOwner",
        };
        if (knownErrors[selector]) reason = knownErrors[selector];
      }
      throw new Error(`Contract call reverted: ${reason}`);
    }
    if (dryRun.gas_required) {
      refTime = BigInt(dryRun.gas_required.ref_time) * 5n / 4n;
      proofSize = BigInt(dryRun.gas_required.proof_size) * 5n / 4n;
      if (proofSize > 3_500_000n) proofSize = 3_500_000n;
    }
    if (dryRun.storage_deposit?.Charge) {
      const estimated = BigInt(dryRun.storage_deposit.Charge) * 5n / 4n;
      storageDeposit = estimated > 10_000_000_000n ? estimated : 10_000_000_000n;
    }
  }

  const contractCall = _api.tx.Revive.call({
    dest: Binary.fromHex(contractAddress),
    value,
    weight_limit: { ref_time: refTime, proof_size: proofSize },
    storage_deposit_limit: storageDeposit,
    data: Binary.fromHex(data),
  });

  let txToSubmit;
  if (needsMapping) {
    txToSubmit = _api.tx.Utility.batch_all({
      calls: [
        _api.tx.Revive.map_account().decodedCall,
        contractCall.decodedCall,
      ],
    });
  } else {
    txToSubmit = contractCall;
  }

  const result = await new Promise((resolve, reject) => {
    let isResolved = false;
    const timeoutId = setTimeout(() => {
      if (isResolved) return;
      isResolved = true;
      reject(new Error("Transaction timed out. Please retry."));
    }, 60000);

    const subscription = txToSubmit.signSubmitAndWatch(_signer, {
      mortality: { mortal: true, period: 256 },
    }).subscribe({
      next(event) {
        if (isResolved) return;
        if (event.type === "invalid" || event.type === "Invalid" || event.type === "dropped") {
          isResolved = true;
          clearTimeout(timeoutId);
          subscription.unsubscribe();
          reject(new Error(`Transaction rejected: ${event.value?.type || "unknown"}`));
          return;
        }
        if (event.type === "txBestBlocksState" && event.found) {
          const failed = event.events?.find(
            (e) => e.type === "System" && e.value?.type === "ExtrinsicFailed"
          );
          if (failed) {
            isResolved = true;
            clearTimeout(timeoutId);
            subscription.unsubscribe();
            reject(new Error("Transaction failed on-chain"));
            return;
          }
          isResolved = true;
          clearTimeout(timeoutId);
          subscription.unsubscribe();
          resolve({ receipt: event });
        }
      },
      error(err) {
        if (isResolved) return;
        isResolved = true;
        clearTimeout(timeoutId);
        reject(err);
      },
    });
  });

  return result;
}

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

function safeDecode(abi, functionName, data) {
  if (!data || data === "0x") {
    const fn = abi.find((item) => item.type === "function" && item.name === functionName);
    const outputCount = fn?.outputs?.length || 1;
    const zeroPadded = "0x" + "00".repeat(32).repeat(outputCount);
    return decodeFunctionResult({ abi, functionName, data: zeroPadded });
  }
  return decodeFunctionResult({ abi, functionName, data });
}
