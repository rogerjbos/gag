// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GaG} from "../src/GaG.sol";

/// @title BaseTest
/// @notice Shared test setup and helper utilities for all GaG test suites.
abstract contract BaseTest is Test {
    GaG public gag;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public treasury = makeAddr("treasury");
    address public updater = makeAddr("updater");

    uint256 public constant MINT_PRICE = 1 ether;
    uint256 public constant BURN_FEE = 2 ether;
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
        // Build seed arrays.
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(1000 + i));
            seedMsgs[i] = seedMessages[i];
        }

        // Deploy the main contract.
        vm.prank(owner);
        gag = new GaG(owner, MINT_PRICE, BURN_FEE, seedRecipients, seedMsgs);

        // Set the metadata updater.
        vm.prank(owner);
        gag.setMetadataUpdater(updater);

        // Fund test accounts with native tokens.
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(carol, 1000 ether);
    }

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------

    /// @dev Submit a mint intent from `sender` with native token payment, non-anonymous.
    function _submitIntent(address sender, address recipient, string memory message) internal {
        vm.prank(sender);
        gag.submitMintIntent{value: MINT_PRICE}(false, recipient, message);
    }

    /// @dev Submit a mint intent from `sender` with anonymity flag.
    function _submitIntentAnon(address sender, address recipient, string memory message) internal {
        vm.prank(sender);
        gag.submitMintIntent{value: MINT_PRICE}(true, recipient, message);
    }

    /// @dev Submit enough intents to guarantee all seed slots have been minted.
    function _flushQueue() internal {
        for (uint256 i = 0; i < 60; i++) {
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
