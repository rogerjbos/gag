// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GigglesAndGags} from "../src/GigglesAndGags.sol";
import {GagRenderer} from "../src/render/GagRenderer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title BaseTest
/// @notice Shared test setup and helper utilities for all GigglesAndGags test suites.
abstract contract BaseTest is Test {
    GigglesAndGags public gag;
    MockERC20 public usdc;
    MockERC20 public dai;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public treasury = makeAddr("treasury");

    uint256 public constant MINT_PRICE = 1e6;   // 1 USDC (6 decimals)
    uint256 public constant BURN_FEE = 0.5e6;   // 0.5 USDC
    uint256 public constant DAI_MINT_PRICE = 1e18; // 1 DAI (18 decimals)
    uint256 public constant DAI_BURN_FEE = 0.5e18; // 0.5 DAI
    uint8 public constant QUEUE_SIZE = 15;

    string[15] internal seedMessages = [
        "gm ser",
        "wagmi",
        "ngmi tbh",
        "wen moon",
        "touch grass",
        "this is fine",
        "cope harder",
        "seethe",
        "have fun staying poor",
        "few understand",
        "probably nothing",
        "not financial advice",
        "dyor",
        "lfg",
        "ser this is a Wendys"
    ];

    function setUp() public virtual {
        // Deploy mock stablecoins.
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Build seed arrays.
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(1000 + i)); // Nonzero placeholder addresses.
            seedMsgs[i] = seedMessages[i];
        }

        // Deploy the renderer and then the main contract.
        GagRenderer gagRenderer = new GagRenderer();
        vm.prank(owner);
        gag = new GigglesAndGags(owner, address(gagRenderer), seedRecipients, seedMsgs);

        // Owner configures payment tokens.
        vm.startPrank(owner);
        gag.updatePaymentToken(address(usdc), MINT_PRICE, BURN_FEE);
        gag.updatePaymentToken(address(dai), DAI_MINT_PRICE, DAI_BURN_FEE);
        vm.stopPrank();

        // Fund test accounts with stablecoins.
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(carol, 1_000_000e6);
        dai.mint(alice, 1_000_000e18);
        dai.mint(bob, 1_000_000e18);

        // Approve the contract to spend.
        vm.prank(alice);
        usdc.approve(address(gag), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(gag), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(gag), type(uint256).max);
        vm.prank(alice);
        dai.approve(address(gag), type(uint256).max);
        vm.prank(bob);
        dai.approve(address(gag), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------

    /// @dev Submit a mint intent from `sender` with default USDC payment, non-anonymous.
    function _submitIntent(address sender, address recipient, string memory message) internal {
        vm.prank(sender);
        gag.submitMintIntent(false, recipient, address(usdc), message);
    }

    /// @dev Submit a mint intent from `sender` with anonymity flag and USDC.
    function _submitIntentAnon(address sender, address recipient, string memory message) internal {
        vm.prank(sender);
        gag.submitMintIntent(true, recipient, address(usdc), message);
    }

    /// @dev Submit enough intents to guarantee all seed slots have been minted.
    ///      We need at least `queueSize` submits, but since slots are random we do more.
    function _flushQueue() internal {
        for (uint256 i = 0; i < 60; i++) {
            // Vary the block data to hit different slots.
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 137 + 42)));
            _submitIntent(alice, bob, string.concat("flush ", _uintToStr(i)));
        }
    }

    /// @dev Simple uint to string conversion for generating unique messages.
    function _uintToStr(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
