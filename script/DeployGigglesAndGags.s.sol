// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {GigglesAndGags} from "../src/GigglesAndGags.sol";
import {GagRenderer} from "../src/render/GagRenderer.sol";

/**
 * @title DeployGigglesAndGags
 * @notice Foundry deploy script for the Giggles and Gags collection.
 *
 * @dev Local (Anvil):
 *      1. Start a local node:
 *             anvil
 *      2. Deploy:
 *             forge script script/DeployGigglesAndGags.s.sol \
 *                 --rpc-url http://127.0.0.1:8545 \
 *                 --broadcast \
 *                 --via-ir
 *
 *      Anvil prints 10 funded accounts on start. The first private key is used by
 *      default via `vm.envOr`. You can override with:
 *             DEPLOYER_PRIVATE_KEY=0x... forge script ...
 *
 * @dev Base Sepolia (hot wallet):
 *             DEPLOYER_PRIVATE_KEY=0x<key> \
 *             forge script script/DeployGigglesAndGags.s.sol \
 *                 --rpc-url https://sepolia.base.org \
 *                 --broadcast --verify --via-ir
 *
 * @dev Base Mainnet (Ledger):
 *             forge script script/DeployGigglesAndGags.s.sol \
 *                 --rpc-url https://mainnet.base.org \
 *                 --ledger --sender <your_ledger_address> \
 *                 --broadcast --verify --via-ir
 *
 * @dev Base Mainnet (hot wallet):
 *             DEPLOYER_PRIVATE_KEY=0x<key> \
 *             forge script script/DeployGigglesAndGags.s.sol \
 *                 --rpc-url https://mainnet.base.org \
 *                 --broadcast --verify --via-ir
 */
contract DeployGigglesAndGags is Script {
    /// @dev Default Anvil account #0 private key — only used in local development.
    uint256 constant ANVIL_KEY_0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Queue size must match the contract's hardcoded value.
    uint8 constant QUEUE_SIZE = 15;

    /// @dev True when a private key is explicitly provided via env var.
    bool private _usePrivateKey;
    uint256 private _deployerKey;

    function run() public {
        // If DEPLOYER_PRIVATE_KEY is set, use it (local/hot wallet).
        // Otherwise, fall through to CLI-based signer (--ledger, --trezor, etc.).
        _deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        _usePrivateKey = _deployerKey != 0;

        address deployer;
        if (_usePrivateKey) {
            deployer = vm.addr(_deployerKey);
        } else {
            // When using --ledger/--sender, msg.sender is set by Foundry.
            deployer = msg.sender;
        }

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        // -----------------------------------------------------------------
        //  Seed data — 15 messages and recipients that pre-fill the queue.
        //
        //  Seed recipients are publicly-known wallets from the Base, Farcaster,
        //  and Ethereum ecosystem. Seed intents are anonymous (origin = address(0)),
        //  so burn tribute goes to the project treasury.
        // -----------------------------------------------------------------

        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);

        // ----  Slot 0  ----
        // vitalik.eth — Vitalik Buterin (Ethereum creator)
        seedRecipients[0]  = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        seedMsgs[0]        = "vitalik you have been gagged. no rollback for this.";

        // ----  Slot 1  ----
        // jesse.base.eth — Jesse Pollak (Base creator, Head of Protocols @ Coinbase)
        seedRecipients[1]  = 0x2211d1D0020DAEA8039E46Cf1367962070d77DA9;
        seedMsgs[1]        = "jesse we built this on your chain. sorry in advance.";

        // ----  Slot 2  ----
        // dwr.eth — Dan Romero (Farcaster co-founder)
        seedRecipients[2]  = 0xD7029BDEa1c17493893AAfE29AAD69EF892B8ff2;
        seedMsgs[2]        = "dan this is your fault. you built the social graph.";

        // ----  Slot 3  ----
        // balajis.eth — Balaji Srinivasan (angel investor, former a16z/Coinbase CTO)
        seedRecipients[3]  = 0x0916C04994849c676ab2667Ce5bbDF7CcC94310a;
        seedMsgs[3]        = "the network state just got a little more chaotic.";

        // ----  Slot 4  ----
        // punk6529 — genesis.punk6529.eth (legendary NFT collector)
        seedRecipients[4]  = 0xfD22004806A6846EA67ad883356be810F0428793;
        seedMsgs[4]        = "this one is non-transferable. not even you can move it.";

        // ----  Slot 5  ----
        // dwr.eth secondary — Dan Romero verified custody address
        seedRecipients[5]  = 0x187c7B0393eBE86378128f2653D0930E33218899;
        seedMsgs[5]        = "gm ser. you have been permanently onchain pranked.";

        // ----  Slot 6  ----
        // Clanker Factory — the AI token launchpad on Base (contract)
        seedRecipients[6]  = 0xE85A59c628F7d27878ACeB4bf3b35733630083a9;
        seedMsgs[6]        = "dear clanker: you deploy tokens. we deploy chaos.";

        // ----  Slot 7  ----
        // zora-base.eth — Zora protocol (NFT infrastructure on Base)
        seedRecipients[7]  = 0xA10164b85f22eb1086602D8Ed0F2e2a6473d2980;
        seedMsgs[7]        = "zora mints art. we mint damage. different vibes.";

        // ----  Slot 8  ----
        // Zora Deployer — official Zora deployer wallet
        seedRecipients[8]  = 0x7A6f726121030CaDf9923333d5b6F29277024027;
        seedMsgs[8]        = "your wallet will never be the same. you are welcome.";

        // ----  Slot 9  ----
        // social.6529.eth — punk6529 social wallet
        seedRecipients[9]  = 0x6DAA633C23615a29471dEaFae351727867E7dAD1;
        seedMsgs[9]        = "collecting this one is not optional. it collected you.";

        // ----  Slot 10 ----
        // dcbuilder.eth — notable Ethereum dev / Worldcoin research engineer
        seedRecipients[10] = 0x642C7F7040C656d633A9267284B338FF41051541;
        seedMsgs[10]       = "devpill.me didn't prepare you for this one ser.";

        // ----  Slot 11 ----
        // ser.base.eth — popular Base community name
        seedRecipients[11] = 0x9F59Fa05A4aD952Ba90b101555fB5E2709C9d8bB;
        seedMsgs[11]       = "ser this is not a drill. this is permanent.";

        // ----  Slot 12 ----
        // Base bridge contract — technically an address, meme target
        seedRecipients[12] = 0x849151d7D0bF1F34b70d5caD5149D28CC2308bf1;
        seedMsgs[12]       = "you bridged to Base. Base gagged you back.";

        // ----  Slot 13 ----
        // Coinbase attestation service signer on Base
        seedRecipients[13] = 0xe1C5CF1E30251cd4342467eb8C332613f7E6AEB1;
        seedMsgs[13]       = "on-chain social damage. fully verified. no take-backs.";

        // ----  Slot 14 ----
        // vitalik.eth again — double gag for maximum chaos
        seedRecipients[14] = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        seedMsgs[14]       = "two gags. one wallet. zero remorse. welcome to GaG.";

        // -----------------------------------------------------------------
        //  Deploy Step 1 — Renderer
        //  Separate broadcast so the renderer tx is confirmed before the
        //  main contract references its address.
        // -----------------------------------------------------------------
        if (_usePrivateKey) vm.startBroadcast(_deployerKey);
        else vm.startBroadcast();

        GagRenderer gagRenderer = new GagRenderer();
        vm.stopBroadcast();

        console.log("GagRenderer deployed at:", address(gagRenderer));

        // -----------------------------------------------------------------
        //  Deploy Step 2 — Main contract + configure payment tokens
        // -----------------------------------------------------------------
        if (_usePrivateKey) vm.startBroadcast(_deployerKey);
        else vm.startBroadcast();
        GigglesAndGags gag = new GigglesAndGags(deployer, address(gagRenderer), seedRecipients, seedMsgs);

        // Top 5 stablecoins on Base.
        // Mint price = $1 worth, Burn fee = $2 worth.
        //
        //  Token   Address                                      Decimals  Mint       Burn
        //  ─────   ──────────────────────────────────────────   ────────  ─────────  ─────────
        //  USDC    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913   6        1e6        2e6
        //  USDS    0x820C137fa70C8691f0e44Dc420a5e53c168921Dc   18       1e18       2e18
        //  USDe    0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34   18       1e18       2e18
        //  GHO     0x6Bb7a212910682DCFdBd5BCBb3e28FB4E8da10Ee   18       1e18       2e18
        //  crvUSD  0x417Ac0e078398C154EdFadD9Ef675d30Be60AF93   18       1e18       2e18

        // USDC (Circle native)
        gag.updatePaymentToken(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 1e6,  2e6);
        // USDS (Sky / MakerDAO)
        gag.updatePaymentToken(0x820C137fa70C8691f0e44Dc420a5e53c168921Dc, 1e18, 2e18);
        // USDe (Ethena)
        gag.updatePaymentToken(0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34, 1e18, 2e18);
        // GHO (Aave)
        gag.updatePaymentToken(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee, 1e18, 2e18);
        // crvUSD (Curve)
        gag.updatePaymentToken(0x417Ac0e078398C154EdFadD9Ef675d30Be60Af93, 1e18, 2e18);

        vm.stopBroadcast();

        // -----------------------------------------------------------------
        //  Post-deploy summary
        // -----------------------------------------------------------------
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("GagRenderer:   ", address(gagRenderer));
        console.log("GigglesAndGags:", address(gag));
        console.log("Owner:         ", gag.owner());
        console.log("Queue size:    ", gag.queueSize());
        console.log("Total minted:  ", gag.totalMinted());
        console.log("");
        console.log("=== Payment Tokens Configured ===");
        console.log("  USDC   - mint: 1.00  burn: 2.00  (6 decimals)");
        console.log("  USDS   - mint: 1.00  burn: 2.00  (18 decimals)");
        console.log("  USDe   - mint: 1.00  burn: 2.00  (18 decimals)");
        console.log("  GHO    - mint: 1.00  burn: 2.00  (18 decimals)");
        console.log("  crvUSD - mint: 1.00  burn: 2.00  (18 decimals)");
    }
}
