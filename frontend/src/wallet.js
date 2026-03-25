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
//  Decimal conversion: EVM (18 decimals) ↔ Substrate (10 decimals)
//  Revive.call value parameter is in Substrate units (10 decimals).
//  EVM contracts use 18 decimals. Conversion factor: 10^8.
// ---------------------------------------------------------------------------
const DECIMALS_DIFF = 100_000_000n; // 10^8

function evmToSubstrate(evmValue) {
  return evmValue / DECIMALS_DIFF;
}

function substrateToEvm(subValue) {
  return subValue * DECIMALS_DIFF;
}

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
//  DotNS name resolution
// ---------------------------------------------------------------------------

const DOTNS_REGISTRY = "0x4Da0d37aBe96C06ab19963F31ca2DC0412057a6f";

// ENS-style namehash: keccak256(parent + keccak256(label))
function namehash(name) {
  const labels = name.split(".");
  let node = "0x" + "00".repeat(32);
  for (let i = labels.length - 1; i >= 0; i--) {
    const labelHash = keccak256(new TextEncoder().encode(labels[i]));
    const combined = new Uint8Array(64);
    // Decode parent node hex
    const nodeBytes = hexToBytes(node);
    combined.set(nodeBytes, 0);
    // Decode label hash hex
    const labelBytes = hexToBytes(labelHash);
    combined.set(labelBytes, 32);
    node = keccak256(combined);
  }
  return node;
}

function hexToBytes(hex) {
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(h.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(h.substr(i * 2, 2), 16);
  }
  return bytes;
}

const REGISTRY_ABI = [
  { type: "function", name: "resolver", inputs: [{ name: "node", type: "bytes32" }], outputs: [{ type: "address" }], stateMutability: "view" },
];

const RESOLVER_ABI = [
  { type: "function", name: "addr", inputs: [{ name: "node", type: "bytes32" }], outputs: [{ type: "address" }], stateMutability: "view" },
];

/**
 * Resolve a DotNS name to an H160 address.
 * e.g. "rogerjbos" → looks up "rogerjbos.dot"
 * @param {string} name - Domain name (with or without .dot suffix)
 * @returns {string|null} H160 address or null if not found
 */
export async function resolveDotNS(name) {
  if (!_api) return null;

  // Append .dot if not present
  const fullName = name.includes(".") ? name : name + ".dot";
  const node = namehash(fullName);

  try {
    // Query registry for resolver address
    const resolverData = encodeFunctionData({ abi: REGISTRY_ABI, functionName: "resolver", args: [node] });
    const resolverResult = await _api.apis.ReviveApi.call(
      "5C4hrfjw9DjXZTzV3MwzrrAr9P1MJhSrvWGWqi1eSuyUpnhM", // use a dummy address for reads
      Binary.fromHex(DOTNS_REGISTRY),
      0n, undefined, undefined,
      Binary.fromHex(resolverData),
      { at: "best" },
    );

    const resolverCallResult = resolverResult.result;
    if (!resolverCallResult || ("success" in resolverCallResult && !resolverCallResult.success)) {
      return null;
    }

    const resolverHex = extractHex(resolverCallResult);
    if (!resolverHex || resolverHex === "0x") return null;
    const resolverAddr = decodeFunctionResult({ abi: REGISTRY_ABI, functionName: "resolver", data: resolverHex });
    if (!resolverAddr || resolverAddr === "0x0000000000000000000000000000000000000000") return null;

    // Query resolver for addr
    const addrData = encodeFunctionData({ abi: RESOLVER_ABI, functionName: "addr", args: [node] });
    const addrResult = await _api.apis.ReviveApi.call(
      "5C4hrfjw9DjXZTzV3MwzrrAr9P1MJhSrvWGWqi1eSuyUpnhM",
      Binary.fromHex(resolverAddr),
      0n, undefined, undefined,
      Binary.fromHex(addrData),
      { at: "best" },
    );

    const addrCallResult = addrResult.result;
    if (!addrCallResult || ("success" in addrCallResult && !addrCallResult.success)) {
      return null;
    }

    const addrHex = extractHex(addrCallResult);
    if (!addrHex || addrHex === "0x") return null;
    const addr = decodeFunctionResult({ abi: RESOLVER_ABI, functionName: "addr", data: addrHex });
    if (!addr || addr === "0x0000000000000000000000000000000000000000") return null;

    return addr.toLowerCase();
  } catch (e) {
    console.warn("[DotNS] Resolution failed for", fullName, e);
    return null;
  }
}

function extractHex(callResult) {
  if ("success" in callResult) {
    const valueData = callResult.value?.data || callResult.value;
    if (valueData && typeof valueData.asHex === "function") return valueData.asHex();
    if (typeof valueData === "string") return valueData.startsWith("0x") ? valueData : `0x${valueData}`;
    if (valueData && valueData.bytes) return "0x" + Array.from(valueData.bytes).map(b => b.toString(16).padStart(2, "0")).join("");
  }
  const data = callResult.data || callResult.value?.data || callResult;
  if (data && typeof data.asHex === "function") return data.asHex();
  if (typeof data === "string") return data.startsWith("0x") ? data : `0x${data}`;
  return null;
}

/**
 * Resolve any address input to an H160 address.
 * Supports: H160 (0x...), SS58 (5...), DotNS names (name or name.dot)
 * @returns {{ address: string, type: string, display: string } | null}
 */
export async function resolveAddress(input) {
  const trimmed = input.trim();

  // H160 address
  if (/^0x[a-fA-F0-9]{40}$/i.test(trimmed)) {
    return { address: trimmed.toLowerCase(), type: "h160", display: trimmed };
  }

  // SS58 address (starts with 1, 5, or other prefix, 46-48 chars, base58)
  if (/^[1-9A-HJ-NP-Za-km-z]{46,48}$/.test(trimmed)) {
    try {
      const h160 = ss58ToH160(trimmed);
      return { address: h160, type: "ss58", display: `${trimmed.slice(0, 8)}... → ${h160.slice(0, 10)}...` };
    } catch {
      // Not a valid SS58, fall through to DotNS
    }
  }

  // People Chain username (e.g. "rogerjbos.39" — name + dot + number)
  if (/^[a-zA-Z0-9_-]+\.\d+$/.test(trimmed)) {
    try {
      const ss58 = await resolveUsername(trimmed);
      if (ss58) {
        const h160 = ss58ToH160(ss58);
        return { address: h160, type: "username", display: `${trimmed} → ${h160.slice(0, 10)}...` };
      }
    } catch {}
  }

  // DotNS name (alphanumeric, may contain dots and hyphens, but not name.number pattern)
  if (/^[a-zA-Z0-9][a-zA-Z0-9.\-]*$/.test(trimmed) && trimmed.length <= 64) {
    // Try DotNS first
    const resolved = await resolveDotNS(trimmed);
    if (resolved) {
      const displayName = trimmed.includes(".") ? trimmed : trimmed + ".dot";
      return { address: resolved, type: "dotns", display: `${displayName} → ${resolved.slice(0, 10)}...` };
    }

    // If DotNS fails, try as People Chain username anyway
    try {
      const ss58 = await resolveUsername(trimmed);
      if (ss58) {
        const h160 = ss58ToH160(ss58);
        return { address: h160, type: "username", display: `${trimmed} → ${h160.slice(0, 10)}...` };
      }
    } catch {}
  }

  return null;
}

// ---------------------------------------------------------------------------
//  People Chain username resolution (e.g. "rogerjbos.39" → SS58 → H160)
// ---------------------------------------------------------------------------

const PEOPLE_CHAIN_RPC = "wss://pop3-testnet.parity-lab.parity.io/people";
let _peopleClient = null;
let _peopleApi = null;

async function initPeopleChain() {
  if (_peopleClient) return;
  const provider = getWsProvider(PEOPLE_CHAIN_RPC);
  _peopleClient = createClient(provider);
  _peopleApi = _peopleClient.getUnsafeApi();
}

/**
 * Resolve a People Chain username to an SS58 address.
 * e.g. "rogerjbos.39" → "5DeuwLo5xm8Js6aEA2SCjtn2iCshYN1poJv2t1AUVvPfmRm6"
 * @param {string} username - People Chain username (e.g. "rogerjbos.39")
 * @returns {string|null} SS58 address or null
 */
export async function resolveUsername(username) {
  try {
    await initPeopleChain();
    console.log("[People] Resolving username:", username);

    // Convert username to hex bytes
    const hexUsername = "0x" + Array.from(new TextEncoder().encode(username))
      .map(b => b.toString(16).padStart(2, "0")).join("");
    console.log("[People] Hex:", hexUsername);

    // Try Identity.UsernameOf first, then Resources.UsernameOwnerOf
    const queries = [
      { pallet: "Identity", storage: "UsernameOf" },
      { pallet: "Identity", storage: "UsernameAuthorityOf" },
      { pallet: "Resources", storage: "UsernameOwnerOf" },
      { pallet: "Resources", storage: "usernameOwnerOf" },
    ];

    for (const { pallet, storage } of queries) {
      try {
        const q = _peopleApi.query[pallet]?.[storage];
        if (!q) {
          console.log(`[People] ${pallet}.${storage} not found, skipping`);
          continue;
        }
        console.log(`[People] Trying ${pallet}.${storage}...`);
        const result = await q.getValue(Binary.fromHex(hexUsername));
        console.log(`[People] ${pallet}.${storage} result:`, result);
        if (result) {
          const ss58 = result.toString ? result.toString() : String(result);
          if (ss58 && ss58 !== "null" && ss58 !== "undefined") {
            console.log("[People] Resolved to:", ss58);
            return ss58;
          }
        }
      } catch (e) {
        console.log(`[People] ${pallet}.${storage} failed:`, e.message);
      }
    }

    console.warn("[People] All resolution attempts failed for", username);
    return null;
  } catch (e) {
    console.error("[People] Username resolution error:", e);
    return null;
  }
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

/**
 * Get the PAS balance for an SS58 account on Asset Hub.
 * Returns balance in Substrate units (10 decimals).
 */
export async function getBalance(ss58Address) {
  if (!_api) throw new Error("PAPI client not initialized");
  const accountInfo = await _api.query.System.Account.getValue(ss58Address);
  return accountInfo?.data?.free || 0n;
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

  // Convert value from EVM 18 decimals to Substrate 10 decimals
  const substrateValue = evmToSubstrate(value);
  console.log(`[Contract] ${functionName}: EVM value=${value}, Substrate value=${substrateValue}`);

  const data = encodeFunctionData({ abi, functionName, args });

  const [needsMapping, dryRun] = await Promise.all([
    _inkSdk.addressIsMapped(callerSS58).then((mapped) => !mapped),
    _api.apis.ReviveApi.call(
      callerSS58,
      Binary.fromHex(contractAddress),
      substrateValue,
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
    value: substrateValue,
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
