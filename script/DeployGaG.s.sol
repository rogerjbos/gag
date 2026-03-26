// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {GaG} from "../src/GaG.sol";

/**
 * @title DeployGaG
 * @notice Foundry deploy script for the GaG collection on Polkadot Asset Hub.
 *
 * @dev Paseo Asset Hub Testnet:
 *          DEPLOYER_PRIVATE_KEY=0x<key> \
 *          forge script script/DeployGaG.s.sol \
 *              --rpc-url https://eth-rpc-testnet.polkadot.io/ \
 *              --broadcast --via-ir
 *
 * @dev Local (Anvil):
 *      1. Start a local node:
 *             anvil
 *      2. Deploy:
 *             forge script script/DeployGaG.s.sol \
 *                 --rpc-url http://127.0.0.1:8545 \
 *                 --broadcast --via-ir
 */
contract DeployGaG is Script {
    /// @dev Default Anvil account #0 private key — only used in local development.
    uint256 constant ANVIL_KEY_0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Queue size must match the contract's hardcoded value.
    uint8 constant QUEUE_SIZE = 15;

    /// @dev Mint price: 1 PAS (native token, 18 decimals).
    uint256 constant MINT_PRICE = 1 ether;

    /// @dev Burn fee: 2 PAS.
    uint256 constant BURN_FEE = 2 ether;

    /// @dev True when a private key is explicitly provided via env var.
    bool private _usePrivateKey;
    uint256 private _deployerKey;

    function run() public {
        _deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        _usePrivateKey = _deployerKey != 0;

        address deployer;
        if (_usePrivateKey) {
            deployer = vm.addr(_deployerKey);
        } else {
            deployer = msg.sender;
        }

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        // -----------------------------------------------------------------
        //  Seed data — 15 messages and recipients that pre-fill the queue.
        //  Adapted for Polkadot ecosystem addresses.
        // -----------------------------------------------------------------

        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);

        // Use placeholder addresses for testnet. Replace with real Polkadot
        // ecosystem addresses for mainnet deployment.
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(0xdead0000 + i));
        }

        seedMsgs[0] = "gm polkadot. you have been gagged.";
        seedMsgs[1] = "this gag is non-transferable. cope.";
        seedMsgs[2] = "welcome to Asset Hub. your wallet is cursed.";
        seedMsgs[3] = "queue-minted chaos on Polkadot.";
        seedMsgs[4] = "soulbound damage. no escape.";
        seedMsgs[5] = "your PAS tokens funded this curse.";
        seedMsgs[6] = "fully on-chain. fully unhinged.";
        seedMsgs[7] = "this NFT chose you. you did not choose it.";
        seedMsgs[8] = "ported from Base. chaos is multichain.";
        seedMsgs[9] = "dot.li hosted degeneracy.";
        seedMsgs[10] = "bulletin chain stored your doom.";
        seedMsgs[11] = "giggles and gags. no refunds.";
        seedMsgs[12] = "the queue giveth. the queue taketh.";
        seedMsgs[13] = "on-chain social damage. Polkadot edition.";
        seedMsgs[14] = "two chains. one gag. zero remorse.";

        // -----------------------------------------------------------------
        //  Deploy
        // -----------------------------------------------------------------
        if (_usePrivateKey) vm.startBroadcast(_deployerKey);
        else vm.startBroadcast();

        GaG gag = new GaG(deployer, MINT_PRICE, BURN_FEE, seedRecipients, seedMsgs);

        vm.stopBroadcast();

        // -----------------------------------------------------------------
        //  Post-deploy summary
        // -----------------------------------------------------------------
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("GaG:", address(gag));
        console.log("Owner:         ", gag.owner());
        console.log("Queue size:    ", gag.queueSize());
        console.log("Mint price:    ", gag.mintPrice(), "(wei)");
        console.log("Burn fee:      ", gag.burnFee(), "(wei)");
        console.log("Total minted:  ", gag.totalMinted());
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Set metadata updater: gag.setMetadataUpdater(<listener_address>)");
        console.log("2. Start the off-chain SVG listener");
        console.log("3. Deploy frontend to dot.li");
    }
}
