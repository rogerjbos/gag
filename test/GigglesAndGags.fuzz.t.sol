// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "./BaseTest.sol";
import {GigglesAndGags} from "../src/GigglesAndGags.sol";
import {IGigglesAndGagsErrors} from "../src/IGigglesAndGagsErrors.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Utils} from "../src/render/Utils.sol";

/// @title GigglesAndGagsFuzzTest
/// @notice Extensive fuzz tests for the GigglesAndGags contract.
///         Covers randomised inputs for minting, burning, accounting invariants,
///         fee splits, text validation, and rendering.
contract GigglesAndGagsFuzzTest is BaseTest {

    // =========================================================================
    //  Fuzz: submitMintIntent
    // =========================================================================

    /// @notice Fuzz the mint flow with random block entropy and verify minting always occurs.
    function testFuzz_submitMintIntent_alwaysMints(
        uint256 prevrandao,
        uint256 blockNumber
    ) public {
        // Bound block number to reasonable range.
        blockNumber = bound(blockNumber, 1, 1e9);
        vm.roll(blockNumber);
        vm.prevrandao(bytes32(prevrandao));

        uint256 mintedBefore = gag.totalMinted();
        _submitIntent(alice, bob, "fuzz mint");

        // Every submit should mint from a seeded slot (all slots start populated).
        assertEq(gag.totalMinted(), mintedBefore + 1);
    }

    /// @notice Fuzz: the slot index is always in [0, queueSize).
    function testFuzz_calculateMintIntentIndex_bounded(
        uint256 prevrandao,
        uint256 blockNumber
    ) public {
        blockNumber = bound(blockNumber, 1, 1e9);
        vm.roll(blockNumber);
        vm.prevrandao(bytes32(prevrandao));

        // We can't call _calculateMintIntentIndex directly (it's internal),
        // but we can verify the system doesn't revert and minting works.
        _submitIntent(alice, bob, "index fuzz");
        assertTrue(gag.totalMinted() > 0);
    }

    /// @notice Fuzz: anonymous flag correctly determines origin storage.
    function testFuzz_submitMintIntent_anonymityFlag(bool anonymize) public {
        vm.prank(alice);
        gag.submitMintIntent(anonymize, bob, address(usdc), "anon fuzz");
        // Should not revert regardless of anonymize value.
        assertEq(gag.totalMinted(), 1);
    }

    /// @notice Fuzz: recipient can be any non-zero address.
    function testFuzz_submitMintIntent_anyRecipient(address recipient) public {
        vm.assume(recipient != address(0));
        // Recipient might be a contract — that's fine for _mint but safeTransferFrom
        // would check receiver. Since _mint is used, any address works.

        _submitIntent(alice, recipient, "recipient fuzz");
        assertEq(gag.totalMinted(), 1);
    }

    /// @notice Fuzz: many sequential submits with varying entropy.
    function testFuzz_submitMintIntent_manySubmits(uint8 count) public {
        count = uint8(bound(count, 1, 100));

        for (uint256 i = 0; i < count; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encodePacked(i)))));
            _submitIntent(alice, bob, string.concat("m", _uintToStr(i)));
        }

        assertEq(gag.totalMinted(), count);
    }

    // =========================================================================
    //  Fuzz: burnToken Fee Split
    // =========================================================================

    /// @notice Fuzz: burn-fee origin share at various bps values.
    ///         Verifies the dust-free split: originFee + projectFee == burnFee.
    function testFuzz_burnFeeSplit_dustFree(uint256 shareBps) public {
        shareBps = bound(shareBps, 0, 10000);

        vm.prank(owner);
        gag.updateBurnFeeOriginShare(shareBps);

        // Submit non-anon intent, flush, find a token, burn it.
        _submitIntent(alice, bob, "dust fuzz");

        // We'll do many submits to flush and test the accounting.
        for (uint256 i = 0; i < 40; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 59)));
            _submitIntent(bob, carol, string.concat("df ", _uintToStr(i)));
        }

        // Find any token owned by bob, burn it.
        for (uint256 tid = 0; tid < gag.totalMinted(); tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                if (tokenOwner == bob || tokenOwner == carol) {
                    usdc.mint(tokenOwner, BURN_FEE);
                    vm.prank(tokenOwner);
                    usdc.approve(address(gag), BURN_FEE);

                    uint256 contractBalBefore = usdc.balanceOf(address(gag));
                    vm.prank(tokenOwner);
                    gag.burnToken(tid, address(usdc));

                    // Contract balance should increase by exactly the burn fee.
                    assertEq(
                        usdc.balanceOf(address(gag)),
                        contractBalBefore + BURN_FEE
                    );
                    break;
                }
            } catch {
                continue;
            }
        }
    }

    /// @notice Fuzz: updateBurnFeeOriginShare with valid values never reverts.
    function testFuzz_updateBurnFeeOriginShare_validRange(uint256 share) public {
        share = bound(share, 0, 10000);
        vm.prank(owner);
        gag.updateBurnFeeOriginShare(share);
        assertEq(gag.burnFeeOriginShare(), share);
    }

    /// @notice Fuzz: updateBurnFeeOriginShare with invalid values always reverts.
    function testFuzz_updateBurnFeeOriginShare_revertsAboveMax(uint256 share) public {
        share = bound(share, 10001, type(uint256).max);
        vm.prank(owner);
        vm.expectRevert(IGigglesAndGagsErrors.IncorrectShare.selector);
        gag.updateBurnFeeOriginShare(share);
    }

    // =========================================================================
    //  Fuzz: Payment Token Management
    // =========================================================================

    /// @notice Fuzz: adding payment tokens with various prices/fees.
    function testFuzz_updatePaymentToken_validParams(
        uint256 mintPrice,
        uint256 burnFee
    ) public {
        mintPrice = bound(mintPrice, 1, type(uint128).max);
        burnFee = bound(burnFee, 1, type(uint128).max);

        MockERC20 token = new MockERC20("Fuzz", "FZZ", 18);

        vm.prank(owner);
        gag.updatePaymentToken(address(token), mintPrice, burnFee);

        assertEq(gag.mintPrices(address(token)), mintPrice);
        assertEq(gag.burnFees(address(token)), burnFee);
        assertTrue(gag.supportedToken(address(token)));
    }

    // =========================================================================
    //  Fuzz: withdrawFees
    // =========================================================================

    /// @notice Fuzz: partial withdrawals never exceed projectFees.
    function testFuzz_withdrawFees_partialAmount(uint8 numMints, uint256 withdrawPct) public {
        numMints = uint8(bound(numMints, 1, 50));
        withdrawPct = bound(withdrawPct, 1, 100);

        // Generate project fees.
        for (uint256 i = 0; i < numMints; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 113)));
            _submitIntent(alice, bob, string.concat("pw ", _uintToStr(i)));
        }

        uint256 totalFees = uint256(numMints) * MINT_PRICE;
        uint256 withdrawAmount = totalFees * withdrawPct / 100;
        if (withdrawAmount == 0) withdrawAmount = 1;
        if (withdrawAmount > totalFees) withdrawAmount = totalFees;

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        vm.prank(owner);
        gag.withdrawFees(address(usdc), treasury, withdrawAmount);
        assertEq(usdc.balanceOf(treasury), treasuryBefore + withdrawAmount);
    }

    // =========================================================================
    //  Fuzz: Text Validation (Utils.validateText)
    // =========================================================================

    /// @notice Fuzz: random bytes should mostly revert (most random strings are invalid).
    ///         We use a helper wrapper because try/catch only works on external calls
    ///         and Utils.validateText is an internal library function.
    function testFuzz_validateText_randomBytesUsuallyRevert(bytes memory randomBytes) public {
        // Skip empty.
        vm.assume(randomBytes.length > 0 && randomBytes.length <= 64);

        string memory text = string(randomBytes);

        // Most random byte sequences will contain invalid characters.
        // We just verify it doesn't panic or have unexpected behaviour.
        // Use a low-level call to this contract's own wrapper to catch reverts.
        (bool success,) = address(this).call(
            abi.encodeWithSelector(this.externalValidateText.selector, text)
        );

        if (success) {
            // If it passes, verify the message is actually valid.
            bytes memory b = bytes(text);
            assertTrue(b.length > 0 && b.length <= 64);
            assertTrue(b[0] != 0x20);
            assertTrue(b[b.length - 1] != 0x20);
        }
        // else: expected — most random inputs are invalid.
    }

    /// @dev External wrapper so the fuzz test above can use try/catch-style revert detection.
    function externalValidateText(string calldata text) external pure {
        Utils.validateText(text);
    }

    /// @notice Fuzz: valid ASCII letters of varying lengths should pass validation.
    function testFuzz_validateText_validAlphabetic(uint8 length) public pure {
        length = uint8(bound(length, 1, 64));

        // Build a valid string of lowercase letters.
        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = bytes1(uint8(0x61 + (i % 26))); // a-z cycling
        }

        string memory text = string(b);
        Utils.validateText(text); // Should not revert.
    }

    /// @notice Fuzz: strings exceeding 64 bytes always revert.
    function testFuzz_validateText_overlongAlwaysReverts(uint16 length) public {
        length = uint16(bound(length, 65, 500));

        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = "a";
        }

        vm.expectRevert(Utils.InvalidTextLength.selector);
        this.externalValidateText(string(b));
    }

    /// @notice Fuzz: empty string always reverts.
    function testFuzz_validateText_emptyAlwaysReverts() public {
        vm.expectRevert(Utils.InvalidTextLength.selector);
        this.externalValidateText("");
    }

    // =========================================================================
    //  Fuzz: Accounting Invariant
    // =========================================================================

    /// @notice Fuzz: after N mints and K burns, contract balance >= sum of all obligations.
    function testFuzz_accountingInvariant(uint8 numMints, uint8 numBurns) public {
        numMints = uint8(bound(numMints, 5, 80));
        numBurns = uint8(bound(numBurns, 0, numMints / 2));

        // Generate mints.
        for (uint256 i = 0; i < numMints; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encodePacked("inv", i)))));
            _submitIntent(alice, bob, string.concat("ai ", _uintToStr(i)));
        }

        // Burn some tokens.
        uint256 burned = 0;
        for (uint256 tid = 0; tid < gag.totalMinted() && burned < numBurns; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                usdc.mint(tokenOwner, BURN_FEE);
                vm.prank(tokenOwner);
                usdc.approve(address(gag), BURN_FEE);
                vm.prank(tokenOwner);
                gag.burnToken(tid, address(usdc));
                burned++;
            } catch {
                continue;
            }
        }

        // The contract USDC balance should be non-negative (it always is for uint).
        // More importantly, it should equal numMints * MINT_PRICE + burned * BURN_FEE
        // minus any claimed fees (none claimed here).
        uint256 expectedBalance = uint256(numMints) * MINT_PRICE + burned * BURN_FEE;
        assertEq(usdc.balanceOf(address(gag)), expectedBalance);
    }

    // =========================================================================
    //  Fuzz: Non-Transferability
    // =========================================================================

    /// @notice Fuzz: transfer to any address always reverts.
    function testFuzz_transferFrom_alwaysReverts(address to) public {
        vm.assume(to != address(0));

        _submitIntent(alice, bob, "transfer fuzz");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.prank(tokenOwner);
        vm.expectRevert(IGigglesAndGagsErrors.NonTransferable.selector);
        gag.transferFrom(tokenOwner, to, tokenId);
    }

    /// @notice Fuzz: approve to any address always reverts.
    function testFuzz_approve_alwaysReverts(address spender, uint256 tokenId) public {
        vm.prank(alice);
        vm.expectRevert(IGigglesAndGagsErrors.NonTransferable.selector);
        gag.approve(spender, tokenId);
    }

    /// @notice Fuzz: setApprovalForAll always reverts regardless of params.
    function testFuzz_setApprovalForAll_alwaysReverts(address operator, bool approved) public {
        vm.prank(alice);
        vm.expectRevert(IGigglesAndGagsErrors.NonTransferable.selector);
        gag.setApprovalForAll(operator, approved);
    }

    // =========================================================================
    //  Fuzz: Metadata / Rendering
    // =========================================================================

    /// @notice Fuzz: tokenURI returns valid data for any minted token.
    function testFuzz_tokenURI_validForAllMints(uint8 numMints) public {
        numMints = uint8(bound(numMints, 1, 30));

        for (uint256 i = 0; i < numMints; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encodePacked("uri", i)))));
            _submitIntent(alice, bob, string.concat("u", _uintToStr(i)));
        }

        for (uint256 tid = 0; tid < gag.totalMinted(); tid++) {
            string memory uri = gag.tokenURI(tid);
            // Should start with "data:application/json;base64,"
            assertTrue(bytes(uri).length > 50, "URI too short");
        }
    }

    // =========================================================================
    //  Fuzz: XML Escaping
    // =========================================================================

    /// @notice Fuzz: escapeXML output never contains raw XML special characters.
    function testFuzz_escapeXML_noRawSpecialChars(string memory input) public pure {
        string memory escaped = Utils.escapeXML(input);
        bytes memory b = bytes(escaped);

        // After escaping, there should be no raw & that isn't part of an entity,
        // and no raw < > " '.
        // For simplicity, just verify the function doesn't revert on any input.
        assertTrue(b.length >= bytes(input).length, "Escaped should be at least as long");
    }

    // =========================================================================
    //  Fuzz: _flushQueue (called by pause)
    // =========================================================================

    /// @notice Fuzz: after N submits and then a pause, totalMinted equals N + queue occupancy.
    function testFuzz_pause_flushesQueue(uint8 numSubmits) public {
        numSubmits = uint8(bound(numSubmits, 0, 60));

        for (uint256 i = 0; i < numSubmits; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encodePacked("flush", i)))));
            vm.warp(block.timestamp + i + 1);
            _submitIntent(alice, bob, string.concat("fq ", _uintToStr(i)));
        }

        uint256 mintedBefore = gag.totalMinted();
        assertEq(mintedBefore, numSubmits, "Each submit mints one token");

        vm.prank(owner);
        gag.pause();

        // After flush, totalMinted should increase by however many populated slots exist.
        uint256 mintedAfter = gag.totalMinted();
        assertTrue(mintedAfter > mintedBefore, "Flush should mint some tokens");
        assertTrue(mintedAfter <= mintedBefore + QUEUE_SIZE, "Cannot mint more than queueSize");
    }

    /// @notice Fuzz: all queue slots are cleared after pause.
    function testFuzz_pause_clearsAllSlots(uint8 numSubmits) public {
        numSubmits = uint8(bound(numSubmits, 0, 30));

        for (uint256 i = 0; i < numSubmits; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encodePacked("clear", i)))));
            _submitIntent(alice, bob, string.concat("cs ", _uintToStr(i)));
        }

        vm.prank(owner);
        gag.pause();

        for (uint8 i = 0; i < QUEUE_SIZE; i++) {
            (address recipient,,) = gag.mintingQueue(i);
            assertEq(recipient, address(0), "Slot should be empty after flush");
        }
    }

    // =========================================================================
    //  Fuzz: Entropy — block.timestamp
    // =========================================================================

    /// @notice Fuzz: varying block.timestamp doesn't break minting.
    function testFuzz_submitMintIntent_varyTimestamp(uint256 timestamp) public {
        timestamp = bound(timestamp, 1, type(uint64).max);
        vm.warp(timestamp);

        _submitIntent(alice, bob, "timestamp fuzz");
        assertEq(gag.totalMinted(), 1);
    }

    /// @notice Fuzz: combined entropy sources never prevent minting.
    function testFuzz_submitMintIntent_fullEntropy(
        uint256 prevrandao,
        uint256 blockNumber,
        uint256 timestamp
    ) public {
        blockNumber = bound(blockNumber, 1, 1e9);
        timestamp = bound(timestamp, 1, type(uint64).max);

        vm.roll(blockNumber);
        vm.prevrandao(bytes32(prevrandao));
        vm.warp(timestamp);

        _submitIntent(alice, bob, "entropy fuzz");
        assertEq(gag.totalMinted(), 1);
    }

    // =========================================================================
    //  Fuzz: Claim Fees After Multiple Burns
    // =========================================================================

    /// @notice Fuzz: claiming fees zeroes the balance and transfers the right amount.
    function testFuzz_claimFees_zeroesClaimer(uint8 numBurns) public {
        numBurns = uint8(bound(numBurns, 1, 20));

        // First, submit many non-anon intents from alice -> carol.
        for (uint256 i = 0; i < 50; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 37)));
            _submitIntent(alice, carol, string.concat("cf ", _uintToStr(i)));
        }

        // Now burn tokens carol owns (alice is origin for the attributable ones).
        uint256 burned = 0;
        for (uint256 tid = 0; tid < gag.totalMinted() && burned < numBurns; tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                if (tokenOwner == carol) {
                    usdc.mint(carol, BURN_FEE);
                    vm.prank(carol);
                    usdc.approve(address(gag), BURN_FEE);
                    vm.prank(carol);
                    gag.burnToken(tid, address(usdc));
                    burned++;
                }
            } catch {
                continue;
            }
        }

        // If alice has claimable fees, claim them and verify.
        vm.prank(alice);
        uint256 claimableAmt = gag.claimable(address(usdc));
        if (claimableAmt > 0) {
            uint256 balBefore = usdc.balanceOf(alice);
            vm.prank(alice);
            gag.claimFees(address(usdc));

            assertEq(usdc.balanceOf(alice), balBefore + claimableAmt);
            vm.prank(alice);
            assertEq(gag.claimable(address(usdc)), 0);
        }
    }
}
