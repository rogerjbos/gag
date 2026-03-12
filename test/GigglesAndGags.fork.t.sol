// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GigglesAndGags} from "../src/GigglesAndGags.sol";
import {GagRenderer} from "../src/render/GagRenderer.sol";
import {IGigglesAndGagsErrors} from "../src/IGigglesAndGagsErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title GigglesAndGagsForkTest
/// @notice Fork tests against Base mainnet using real USDC and USDT contracts.
///         Validates that the GigglesAndGags contract integrates correctly with
///         production stablecoin implementations (approval, transferFrom, decimals, etc.).
/// @dev Run with: forge test --match-contract GigglesAndGagsForkTest --fork-url $BASE_RPC_URL
///      or: forge test --match-contract GigglesAndGagsForkTest --rpc-url $BASE_RPC_URL
///      Requires a Base mainnet RPC endpoint (e.g. from Alchemy, Infura, or a public RPC).
contract GigglesAndGagsForkTest is Test {

    // -------------------------------------------------------------------------
    //  Base Mainnet Token Addresses
    // -------------------------------------------------------------------------

    /// @dev USDC on Base (Bridged USDC via Circle, 6 decimals).
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev USDT (Tether) on Base (6 decimals, bridged via Stargate/LayerZero).
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    // -------------------------------------------------------------------------
    //  State
    // -------------------------------------------------------------------------

    GigglesAndGags public gag;
    IERC20 public usdc;
    IERC20 public usdt;

    address public owner = makeAddr("forkOwner");
    address public alice = makeAddr("forkAlice");
    address public bob   = makeAddr("forkBob");
    address public carol = makeAddr("forkCarol");
    address public treasury = makeAddr("forkTreasury");

    uint256 public constant USDC_MINT_PRICE = 1e6;    // 1 USDC
    uint256 public constant USDC_BURN_FEE   = 0.5e6;  // 0.5 USDC
    uint256 public constant USDT_MINT_PRICE = 1e6;     // 1 USDT
    uint256 public constant USDT_BURN_FEE   = 0.5e6;   // 0.5 USDT
    uint8   public constant QUEUE_SIZE = 15;

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

    // -------------------------------------------------------------------------
    //  Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // If not running against a fork, skip the entire setUp so tests
        // are silently skipped via the `onlyFork` modifier.
        if (USDC.code.length == 0) return;

        usdc = IERC20(USDC);
        usdt = IERC20(USDT);

        // Build seed arrays.
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(5000 + i));
            seedMsgs[i] = seedMessages[i];
        }

        // Deploy the renderer and then GigglesAndGags.
        GagRenderer gagRenderer = new GagRenderer();
        vm.prank(owner);
        gag = new GigglesAndGags(owner, address(gagRenderer), seedRecipients, seedMsgs);

        // Owner configures USDC and USDT as payment tokens.
        vm.startPrank(owner);
        gag.updatePaymentToken(USDC, USDC_MINT_PRICE, USDC_BURN_FEE);
        gag.updatePaymentToken(USDT, USDT_MINT_PRICE, USDT_BURN_FEE);
        vm.stopPrank();

        // Deal real stablecoins to test accounts using Foundry's `deal`.
        deal(USDC, alice, 100_000e6);
        deal(USDC, bob,   100_000e6);
        deal(USDC, carol, 100_000e6);
        deal(USDT, alice, 100_000e6);
        deal(USDT, bob,   100_000e6);
        deal(USDT, carol, 100_000e6);

        // Approve GaG to spend tokens.
        vm.prank(alice);
        usdc.approve(address(gag), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(gag), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(gag), type(uint256).max);

        vm.prank(alice);
        usdt.approve(address(gag), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(gag), type(uint256).max);
        vm.prank(carol);
        usdt.approve(address(gag), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    //  Modifier to skip if not on a fork
    // -------------------------------------------------------------------------

    modifier onlyFork() {
        if (USDC.code.length == 0) {
            return; // Silently skip — not running against a fork.
        }
        _;
    }

    // -------------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------------

    function _uintToStr(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) { digits -= 1; buffer[digits] = bytes1(uint8(48 + uint256(value % 10))); value /= 10; }
        return string(buffer);
    }

    // =========================================================================
    //  USDC Fork Tests
    // =========================================================================

    /// @notice Submit a mint intent paying with real USDC on Base.
    function test_fork_submitMintIntent_USDC() public onlyFork {
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDC, "fork usdc mint");

        assertEq(usdc.balanceOf(alice), balBefore - USDC_MINT_PRICE);
        assertEq(gag.totalMinted(), 1);
    }

    /// @notice Multiple USDC mints produce correct token count and payment pulls.
    function test_fork_multipleMints_USDC() public onlyFork {
        uint256 balBefore = usdc.balanceOf(alice);

        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(i * 31)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDC, string.concat("fm ", _uintToStr(i)));
        }

        assertEq(gag.totalMinted(), 10);
        assertEq(usdc.balanceOf(alice), balBefore - (10 * USDC_MINT_PRICE));
    }

    /// @notice Burn a token paying the burn fee in real USDC.
    function test_fork_burnToken_USDC() public onlyFork {
        // Mint a token first.
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDC, "fork burn usdc");

        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        deal(USDC, tokenOwner, USDC_BURN_FEE);
        vm.prank(tokenOwner);
        usdc.approve(address(gag), USDC_BURN_FEE);

        uint256 balBefore = usdc.balanceOf(tokenOwner);
        vm.prank(tokenOwner);
        gag.burnToken(tokenId, USDC);

        assertEq(usdc.balanceOf(tokenOwner), balBefore - USDC_BURN_FEE);
        vm.expectRevert();
        gag.ownerOf(tokenId);
    }

    /// @notice Withdraw USDC project fees to treasury.
    function test_fork_withdrawFees_USDC() public onlyFork {
        // Generate some project fees.
        for (uint256 i = 0; i < 5; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDC, string.concat("fw ", _uintToStr(i)));
        }

        uint256 expectedFees = 5 * USDC_MINT_PRICE;
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.prank(owner);
        gag.withdrawFees(USDC, treasury, expectedFees);

        assertEq(usdc.balanceOf(treasury), treasuryBefore + expectedFees);
    }

    /// @notice Attributable burn rewards are claimable in real USDC.
    function test_fork_claimFees_USDC() public onlyFork {
        // Submit non-anon from alice to carol.
        vm.prank(alice);
        gag.submitMintIntent(false, carol, USDC, "claim fork usdc");

        // Flush queue.
        for (uint256 i = 0; i < 50; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 73)));
            vm.prank(bob);
            gag.submitMintIntent(false, carol, USDC, string.concat("cf ", _uintToStr(i)));
        }

        // Burn tokens carol owns.
        bool claimed = false;
        for (uint256 tid = 0; tid < gag.totalMinted() && !claimed; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                if (tokenOwner == carol) {
                    deal(USDC, carol, USDC_BURN_FEE);
                    vm.prank(carol);
                    usdc.approve(address(gag), USDC_BURN_FEE);
                    vm.prank(carol);
                    gag.burnToken(tid, USDC);

                    vm.prank(alice);
                    uint256 claimableAmt = gag.claimable(USDC);
                    if (claimableAmt > 0) {
                        uint256 aliceBal = usdc.balanceOf(alice);
                        vm.prank(alice);
                        gag.claimFees(USDC);
                        assertEq(usdc.balanceOf(alice), aliceBal + claimableAmt);
                        claimed = true;
                    }
                }
            } catch {
                continue;
            }
        }
    }

    // =========================================================================
    //  USDT Fork Tests
    // =========================================================================

    /// @notice Submit a mint intent paying with real USDT on Base.
    function test_fork_submitMintIntent_USDT() public onlyFork {
        uint256 balBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDT, "fork usdt mint");

        assertEq(usdt.balanceOf(alice), balBefore - USDT_MINT_PRICE);
        assertEq(gag.totalMinted(), 1);
    }

    /// @notice Multiple USDT mints produce correct token count and payment pulls.
    function test_fork_multipleMints_USDT() public onlyFork {
        uint256 balBefore = usdt.balanceOf(alice);

        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(i * 41)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDT, string.concat("tu ", _uintToStr(i)));
        }

        assertEq(gag.totalMinted(), 10);
        assertEq(usdt.balanceOf(alice), balBefore - (10 * USDT_MINT_PRICE));
    }

    /// @notice Burn a token paying the burn fee in real USDT.
    function test_fork_burnToken_USDT() public onlyFork {
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDT, "fork burn usdt");

        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        deal(USDT, tokenOwner, USDT_BURN_FEE);
        vm.prank(tokenOwner);
        usdt.approve(address(gag), USDT_BURN_FEE);

        uint256 balBefore = usdt.balanceOf(tokenOwner);
        vm.prank(tokenOwner);
        gag.burnToken(tokenId, USDT);

        assertEq(usdt.balanceOf(tokenOwner), balBefore - USDT_BURN_FEE);
        vm.expectRevert();
        gag.ownerOf(tokenId);
    }

    /// @notice Withdraw USDT project fees to treasury.
    function test_fork_withdrawFees_USDT() public onlyFork {
        for (uint256 i = 0; i < 5; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDT, string.concat("tw ", _uintToStr(i)));
        }

        uint256 expectedFees = 5 * USDT_MINT_PRICE;
        uint256 treasuryBefore = usdt.balanceOf(treasury);

        vm.prank(owner);
        gag.withdrawFees(USDT, treasury, expectedFees);

        assertEq(usdt.balanceOf(treasury), treasuryBefore + expectedFees);
    }

    /// @notice Claimable rewards work with real USDT.
    function test_fork_claimFees_USDT() public onlyFork {
        vm.prank(alice);
        gag.submitMintIntent(false, carol, USDT, "claim fork usdt");

        for (uint256 i = 0; i < 50; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 89)));
            vm.prank(bob);
            gag.submitMintIntent(false, carol, USDT, string.concat("ct ", _uintToStr(i)));
        }

        bool claimed = false;
        for (uint256 tid = 0; tid < gag.totalMinted() && !claimed; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                if (tokenOwner == carol) {
                    deal(USDT, carol, USDT_BURN_FEE);
                    vm.prank(carol);
                    usdt.approve(address(gag), USDT_BURN_FEE);
                    vm.prank(carol);
                    gag.burnToken(tid, USDT);

                    vm.prank(alice);
                    uint256 claimableAmt = gag.claimable(USDT);
                    if (claimableAmt > 0) {
                        uint256 aliceBal = usdt.balanceOf(alice);
                        vm.prank(alice);
                        gag.claimFees(USDT);
                        assertEq(usdt.balanceOf(alice), aliceBal + claimableAmt);
                        claimed = true;
                    }
                }
            } catch {
                continue;
            }
        }
    }

    // =========================================================================
    //  Cross-Token Tests
    // =========================================================================

    /// @notice Mint with USDC, burn with USDT (different payment tokens for each action).
    function test_fork_crossToken_mintUSDC_burnUSDT() public onlyFork {
        // Mint paying USDC.
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDC, "cross token");

        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        // Burn paying USDT.
        deal(USDT, tokenOwner, USDT_BURN_FEE);
        vm.prank(tokenOwner);
        usdt.approve(address(gag), USDT_BURN_FEE);

        vm.prank(tokenOwner);
        gag.burnToken(tokenId, USDT);

        vm.expectRevert();
        gag.ownerOf(tokenId);
    }

    /// @notice Interleaved USDC and USDT mints work correctly.
    function test_fork_interleavedMints() public onlyFork {
        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(i * 53)));

            address token = (i % 2 == 0) ? USDC : USDT;
            vm.prank(alice);
            gag.submitMintIntent(false, bob, token, string.concat("il ", _uintToStr(i)));
        }

        assertEq(gag.totalMinted(), 10);
    }

    /// @notice tokenURI works for tokens minted via both USDC and USDT payments.
    function test_fork_tokenURI_bothTokens() public onlyFork {
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDC, "usdc uri");

        vm.roll(block.number + 1);
        vm.prevrandao(bytes32(uint256(42)));
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDT, "usdt uri");

        for (uint256 tid = 0; tid < gag.totalMinted(); tid++) {
            string memory uri = gag.tokenURI(tid);
            assertTrue(bytes(uri).length > 100, "URI should be valid");
        }
    }

    // =========================================================================
    //  Fork Accounting Invariants
    // =========================================================================

    /// @notice After many operations, contract token balances match internal accounting.
    function test_fork_accountingInvariant_USDC() public onlyFork {
        // Generate 20 mints.
        for (uint256 i = 0; i < 20; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 67)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDC, string.concat("ai ", _uintToStr(i)));
        }

        // Burn 5 tokens.
        uint256 burned = 0;
        for (uint256 tid = 0; tid < gag.totalMinted() && burned < 5; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                deal(USDC, tokenOwner, USDC_BURN_FEE);
                vm.prank(tokenOwner);
                usdc.approve(address(gag), USDC_BURN_FEE);
                vm.prank(tokenOwner);
                gag.burnToken(tid, USDC);
                burned++;
            } catch {
                continue;
            }
        }

        // Contract balance = 20 * MINT_PRICE + burned * BURN_FEE.
        uint256 expected = 20 * USDC_MINT_PRICE + burned * USDC_BURN_FEE;
        assertEq(usdc.balanceOf(address(gag)), expected);
    }

    /// @notice After many operations, contract USDT balances match internal accounting.
    function test_fork_accountingInvariant_USDT() public onlyFork {
        for (uint256 i = 0; i < 20; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 71)));
            vm.prank(alice);
            gag.submitMintIntent(false, bob, USDT, string.concat("at ", _uintToStr(i)));
        }

        uint256 burned = 0;
        for (uint256 tid = 0; tid < gag.totalMinted() && burned < 5; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                deal(USDT, tokenOwner, USDT_BURN_FEE);
                vm.prank(tokenOwner);
                usdt.approve(address(gag), USDT_BURN_FEE);
                vm.prank(tokenOwner);
                gag.burnToken(tid, USDT);
                burned++;
            } catch {
                continue;
            }
        }

        uint256 expected = 20 * USDT_MINT_PRICE + burned * USDT_BURN_FEE;
        assertEq(usdt.balanceOf(address(gag)), expected);
    }

    // =========================================================================
    //  Non-Transferability on Fork
    // =========================================================================

    /// @notice Non-transferability holds with real token interactions.
    function test_fork_nonTransferable() public onlyFork {
        vm.prank(alice);
        gag.submitMintIntent(false, bob, USDC, "fork soulbound");

        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.prank(tokenOwner);
        vm.expectRevert(IGigglesAndGagsErrors.NonTransferable.selector);
        gag.transferFrom(tokenOwner, alice, tokenId);

        vm.prank(tokenOwner);
        vm.expectRevert(IGigglesAndGagsErrors.NonTransferable.selector);
        gag.approve(alice, tokenId);
    }
}
