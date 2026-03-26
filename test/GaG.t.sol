// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "./BaseTest.sol";
import {GaG} from "../src/GaG.sol";
import {IGaGErrors} from "../src/IGaGErrors.sol";
import {IGaGEvents} from "../src/IGaGEvents.sol";
import {Utils} from "../src/render/Utils.sol";

/// @title GaGTest
/// @notice Comprehensive unit tests for the GaG contract (Polkadot Asset Hub edition).
contract GaGTest is BaseTest {
    // =========================================================================
    //  Constructor / Deployment
    // =========================================================================

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(gag.name(), "GaG");
        assertEq(gag.symbol(), "GAG");
    }

    function test_constructor_setsOwner() public view {
        assertEq(gag.owner(), owner);
    }

    function test_constructor_setsQueueSize() public view {
        assertEq(gag.queueSize(), QUEUE_SIZE);
    }

    function test_constructor_setsBurnFeeOriginShare() public view {
        assertEq(gag.burnFeeOriginShare(), 7500);
    }

    function test_constructor_setsPrices() public view {
        assertEq(gag.mintPrice(), MINT_PRICE);
        assertEq(gag.burnFee(), BURN_FEE);
    }

    function test_constructor_seedsAllSlots() public view {
        for (uint8 i = 0; i < QUEUE_SIZE; i++) {
            (address recipient,,) = gag.mintingQueue(i);
            assertTrue(recipient != address(0), "Seed slot should be populated");
        }
    }

    function test_constructor_seedOriginsAreAnonymous() public view {
        for (uint8 i = 0; i < QUEUE_SIZE; i++) {
            (, address origin,) = gag.mintingQueue(i);
            assertEq(origin, address(0), "Seed origin should be anonymous");
        }
    }

    function test_constructor_emitsBurnFeeOriginShareUpdated() public {
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(2000 + i));
            seedMsgs[i] = seedMessages[i];
        }

        vm.expectEmit(false, false, false, true);
        emit IGaGEvents.BurnFeeOriginShareUpdated(0, 7500);
        new GaG(owner, MINT_PRICE, BURN_FEE, seedRecipients, seedMsgs);
    }

    function test_constructor_revertsOnMismatchedSeedArrays() public {
        address[] memory badRecipients = new address[](10);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedMsgs[i] = seedMessages[i];
        }
        for (uint256 i = 0; i < 10; i++) {
            badRecipients[i] = address(uint160(3000 + i));
        }

        vm.expectRevert(IGaGErrors.IncorrectSeedSize.selector);
        new GaG(owner, MINT_PRICE, BURN_FEE, badRecipients, seedMsgs);
    }

    function test_constructor_revertsOnEmptySeedArrays() public {
        address[] memory empty = new address[](0);
        string[] memory emptyMsgs = new string[](0);

        vm.expectRevert(IGaGErrors.IncorrectSeedSize.selector);
        new GaG(owner, MINT_PRICE, BURN_FEE, empty, emptyMsgs);
    }

    function test_constructor_revertsOnZeroMintPrice() public {
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(2000 + i));
            seedMsgs[i] = seedMessages[i];
        }

        vm.expectRevert(IGaGErrors.InvalidMintingPrice.selector);
        new GaG(owner, 0, BURN_FEE, seedRecipients, seedMsgs);
    }

    function test_constructor_revertsOnZeroBurnFee() public {
        address[] memory seedRecipients = new address[](QUEUE_SIZE);
        string[] memory seedMsgs = new string[](QUEUE_SIZE);
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            seedRecipients[i] = address(uint160(2000 + i));
            seedMsgs[i] = seedMessages[i];
        }

        vm.expectRevert(IGaGErrors.InvalidBurningFee.selector);
        new GaG(owner, MINT_PRICE, 0, seedRecipients, seedMsgs);
    }

    function test_constructor_noTokensMintedInitially() public view {
        assertEq(gag.totalMinted(), 0);
    }

    // =========================================================================
    //  View Functions
    // =========================================================================

    function test_claimable_returnsZeroByDefault() public {
        vm.prank(alice);
        assertEq(gag.claimable(), 0);
    }

    function test_getProjectFees_returnsZeroInitially() public view {
        assertEq(gag.getProjectFees(), 0);
    }

    // =========================================================================
    //  submitMintIntent — Happy Paths
    // =========================================================================

    function test_submitMintIntent_acceptsPayment() public {
        uint256 balanceBefore = alice.balance;
        _submitIntent(alice, bob, "hello world");
        assertEq(alice.balance, balanceBefore - MINT_PRICE);
    }

    function test_submitMintIntent_creditsProjectFees() public {
        _submitIntent(alice, bob, "hello world");
        assertEq(gag.getProjectFees(), MINT_PRICE);
    }

    function test_submitMintIntent_mintsFromSeededSlot() public {
        uint256 mintedBefore = gag.totalMinted();
        _submitIntent(alice, bob, "test message");
        assertEq(gag.totalMinted(), mintedBefore + 1);
    }

    function test_submitMintIntent_refundsExcess() public {
        uint256 balanceBefore = alice.balance;
        uint256 overpay = 0.5 ether;
        vm.prank(alice);
        gag.submitMintIntent{value: MINT_PRICE + overpay}(false, bob, "overpay test");
        assertEq(alice.balance, balanceBefore - MINT_PRICE);
    }

    function test_submitMintIntent_multipleMints() public {
        for (uint256 i = 0; i < 20; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(i * 31)));
            _submitIntent(alice, bob, string.concat("msg ", _uintToStr(i)));
        }
        assertEq(gag.totalMinted(), 20);
    }

    // =========================================================================
    //  submitMintIntent — Reverts
    // =========================================================================

    function test_submitMintIntent_revertsOnInsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert(IGaGErrors.InsufficientPayment.selector);
        gag.submitMintIntent{value: MINT_PRICE - 1}(false, bob, "hello");
    }

    function test_submitMintIntent_revertsOnZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(IGaGErrors.InvalidRecipient.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, address(0), "hello");
    }

    function test_submitMintIntent_revertsOnEmptyMessage() public {
        vm.prank(alice);
        vm.expectRevert(Utils.InvalidTextLength.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "");
    }

    function test_submitMintIntent_revertsOnOverlongMessage() public {
        string memory longMsg = "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghijk";
        assertEq(bytes(longMsg).length, 65);

        vm.prank(alice);
        vm.expectRevert(Utils.InvalidTextLength.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, longMsg);
    }

    function test_submitMintIntent_revertsOnLeadingSpace() public {
        vm.prank(alice);
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, " hello");
    }

    function test_submitMintIntent_revertsOnTrailingSpace() public {
        vm.prank(alice);
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "hello ");
    }

    function test_submitMintIntent_revertsOnDoubleSpace() public {
        vm.prank(alice);
        vm.expectRevert(Utils.InvalidDoubleSpace.selector);
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "hello  world");
    }

    function test_submitMintIntent_revertsOnInvalidCharacter() public {
        vm.prank(alice);
        vm.expectRevert();
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "hello\x01world");
    }

    function test_submitMintIntent_revertsWhenPaused() public {
        vm.prank(owner);
        gag.pause();

        vm.prank(alice);
        vm.expectRevert();
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "hello");
    }

    // =========================================================================
    //  Non-Transferability
    // =========================================================================

    function test_transferFrom_reverts() public {
        _submitIntent(alice, bob, "nontransfer test");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.prank(tokenOwner);
        vm.expectRevert(IGaGErrors.NonTransferable.selector);
        gag.transferFrom(tokenOwner, alice, tokenId);
    }

    function test_approve_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IGaGErrors.NonTransferable.selector);
        gag.approve(bob, 0);
    }

    function test_setApprovalForAll_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IGaGErrors.NonTransferable.selector);
        gag.setApprovalForAll(bob, true);
    }

    // =========================================================================
    //  burnToken — Happy Paths
    // =========================================================================

    function test_burnToken_burnsByOwner() public {
        _submitIntent(alice, bob, "burn test");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.deal(tokenOwner, BURN_FEE);
        vm.prank(tokenOwner);
        gag.burnToken{value: BURN_FEE}(tokenId);

        vm.expectRevert();
        gag.ownerOf(tokenId);
    }

    function test_burnToken_chargesBurnFee() public {
        _submitIntent(alice, bob, "burn fee test");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.deal(tokenOwner, 10 ether);
        uint256 balBefore = tokenOwner.balance;
        vm.prank(tokenOwner);
        gag.burnToken{value: BURN_FEE}(tokenId);
        assertEq(tokenOwner.balance, balBefore - BURN_FEE);
    }

    function test_burnToken_anonymousFullFeeToProject() public {
        _submitIntentAnon(alice, bob, "anon burn test");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        uint256 projectBefore = gag.getProjectFees();
        vm.deal(tokenOwner, BURN_FEE);
        vm.prank(tokenOwner);
        gag.burnToken{value: BURN_FEE}(tokenId);

        assertEq(gag.getProjectFees(), projectBefore + BURN_FEE);
    }

    function test_burnToken_refundsExcess() public {
        _submitIntent(alice, bob, "refund burn");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.deal(tokenOwner, 10 ether);
        uint256 balBefore = tokenOwner.balance;
        vm.prank(tokenOwner);
        gag.burnToken{value: BURN_FEE + 0.5 ether}(tokenId);
        assertEq(tokenOwner.balance, balBefore - BURN_FEE);
    }

    // =========================================================================
    //  burnToken — Reverts
    // =========================================================================

    function test_burnToken_revertsForNonOwner() public {
        _submitIntent(alice, bob, "nonowner burn");
        uint256 tokenId = 0;

        vm.prank(alice);
        vm.expectRevert(IGaGErrors.NotTokenOwner.selector);
        gag.burnToken{value: BURN_FEE}(tokenId);
    }

    function test_burnToken_revertsOnInsufficientPayment() public {
        _submitIntent(alice, bob, "cheap burn");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.deal(tokenOwner, 10 ether);
        vm.prank(tokenOwner);
        vm.expectRevert(IGaGErrors.InsufficientPayment.selector);
        gag.burnToken{value: BURN_FEE - 1}(tokenId);
    }

    // =========================================================================
    //  claimFees
    // =========================================================================

    function test_claimFees_revertsWhenNoFees() public {
        vm.prank(alice);
        vm.expectRevert(IGaGErrors.NoFees.selector);
        gag.claimFees();
    }

    // =========================================================================
    //  Metadata — tokenURI and setTokenCID
    // =========================================================================

    function test_tokenURI_returnsEmptyWhenNoCID() public {
        _submitIntent(alice, bob, "uri test");
        string memory uri = gag.tokenURI(0);
        assertEq(bytes(uri).length, 0);
    }

    function test_tokenURI_returnsIPFSURIWhenCIDSet() public {
        _submitIntent(alice, bob, "cid test");
        uint256 tokenId = 0;

        vm.prank(updater);
        gag.setTokenCID(tokenId, "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi");

        string memory uri = gag.tokenURI(tokenId);
        assertEq(uri, "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi");
    }

    function test_tokenURI_revertsForNonexistentToken() public {
        vm.expectRevert();
        gag.tokenURI(999);
    }

    function test_setTokenCID_emitsEvent() public {
        _submitIntent(alice, bob, "event test");

        vm.prank(updater);
        vm.expectEmit(true, false, false, true);
        emit IGaGEvents.TokenCIDSet(0, "bafytest");
        gag.setTokenCID(0, "bafytest");
    }

    function test_setTokenCID_revertsForNonUpdater() public {
        _submitIntent(alice, bob, "auth test");

        vm.prank(alice);
        vm.expectRevert(IGaGErrors.NotMetadataUpdater.selector);
        gag.setTokenCID(0, "bafytest");
    }

    function test_setTokenCID_revertsForNonexistentToken() public {
        vm.prank(updater);
        vm.expectRevert();
        gag.setTokenCID(999, "bafytest");
    }

    function test_getTokenMessage_returnsMessage() public {
        _submitIntent(alice, bob, "message check");
        // Token 0 was minted from a seed slot, so its message is one of the seed messages.
        string memory msg0 = gag.getTokenMessage(0);
        assertTrue(bytes(msg0).length > 0);
    }

    // =========================================================================
    //  Admin — setMetadataUpdater
    // =========================================================================

    function test_setMetadataUpdater_setsAddress() public {
        address newUpdater = makeAddr("newUpdater");
        vm.prank(owner);
        gag.setMetadataUpdater(newUpdater);
        assertEq(gag.metadataUpdater(), newUpdater);
    }

    function test_setMetadataUpdater_emitsEvent() public {
        address newUpdater = makeAddr("newUpdater");
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit IGaGEvents.MetadataUpdaterSet(newUpdater);
        gag.setMetadataUpdater(newUpdater);
    }

    function test_setMetadataUpdater_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        gag.setMetadataUpdater(alice);
    }

    // =========================================================================
    //  Admin — updatePrices
    // =========================================================================

    function test_updatePrices_updates() public {
        vm.prank(owner);
        gag.updatePrices(0.5 ether, 1 ether);
        assertEq(gag.mintPrice(), 0.5 ether);
        assertEq(gag.burnFee(), 1 ether);
    }

    function test_updatePrices_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IGaGEvents.PricesUpdated(0.5 ether, 1 ether);
        gag.updatePrices(0.5 ether, 1 ether);
    }

    function test_updatePrices_revertsOnZeroMintPrice() public {
        vm.prank(owner);
        vm.expectRevert(IGaGErrors.InvalidMintingPrice.selector);
        gag.updatePrices(0, 1 ether);
    }

    function test_updatePrices_revertsOnZeroBurnFee() public {
        vm.prank(owner);
        vm.expectRevert(IGaGErrors.InvalidBurningFee.selector);
        gag.updatePrices(1 ether, 0);
    }

    function test_updatePrices_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        gag.updatePrices(1 ether, 1 ether);
    }

    // =========================================================================
    //  Admin — updateBurnFeeOriginShare
    // =========================================================================

    function test_updateBurnFeeOriginShare_updates() public {
        vm.prank(owner);
        gag.updateBurnFeeOriginShare(5000);
        assertEq(gag.burnFeeOriginShare(), 5000);
    }

    function test_updateBurnFeeOriginShare_canSetToZero() public {
        vm.prank(owner);
        gag.updateBurnFeeOriginShare(0);
        assertEq(gag.burnFeeOriginShare(), 0);
    }

    function test_updateBurnFeeOriginShare_canSetToMax() public {
        vm.prank(owner);
        gag.updateBurnFeeOriginShare(10000);
        assertEq(gag.burnFeeOriginShare(), 10000);
    }

    function test_updateBurnFeeOriginShare_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IGaGEvents.BurnFeeOriginShareUpdated(7500, 5000);
        gag.updateBurnFeeOriginShare(5000);
    }

    function test_updateBurnFeeOriginShare_revertsOverMax() public {
        vm.prank(owner);
        vm.expectRevert(IGaGErrors.IncorrectShare.selector);
        gag.updateBurnFeeOriginShare(10001);
    }

    // =========================================================================
    //  Admin — withdrawFees
    // =========================================================================

    function test_withdrawFees_withdrawsProjectFees() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 17)));
            _submitIntent(alice, bob, string.concat("wf ", _uintToStr(i)));
        }

        uint256 expectedFees = 5 * MINT_PRICE;
        uint256 treasuryBalBefore = treasury.balance;

        vm.prank(owner);
        gag.withdrawFees(treasury, expectedFees);

        assertEq(treasury.balance, treasuryBalBefore + expectedFees);
    }

    function test_withdrawFees_zeroAmountWithdrawsAll() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i)));
            _submitIntent(alice, bob, string.concat("wa ", _uintToStr(i)));
        }

        uint256 treasuryBalBefore = treasury.balance;

        vm.prank(owner);
        gag.withdrawFees(treasury, 0);

        assertTrue(treasury.balance > treasuryBalBefore);
    }

    function test_withdrawFees_revertsOnZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(IGaGErrors.InvalidRecipient.selector);
        gag.withdrawFees(address(0), 0);
    }

    function test_withdrawFees_revertsOnExcessAmount() public {
        _submitIntent(alice, bob, "excess test");

        vm.prank(owner);
        vm.expectRevert(IGaGErrors.InsufficientFees.selector);
        gag.withdrawFees(treasury, 999 ether);
    }

    function test_withdrawFees_revertsWhenNoFees() public {
        vm.prank(owner);
        vm.expectRevert(IGaGErrors.NoFees.selector);
        gag.withdrawFees(treasury, 0);
    }

    function test_withdrawFees_revertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        gag.withdrawFees(treasury, 0);
    }

    // =========================================================================
    //  Admin — Pause / Unpause
    // =========================================================================

    function test_pause_blocksSubmitMintIntent() public {
        vm.prank(owner);
        gag.pause();

        vm.prank(alice);
        vm.expectRevert();
        gag.submitMintIntent{value: MINT_PRICE}(false, bob, "paused");
    }

    function test_unpause_resumesSubmitMintIntent() public {
        vm.prank(owner);
        gag.pause();
        uint256 mintedAfterPause = gag.totalMinted();
        assertEq(mintedAfterPause, QUEUE_SIZE, "Flush should mint all seed slots");

        vm.prank(owner);
        gag.unpause();

        _submitIntent(alice, bob, "unpaused");
        assertEq(gag.totalMinted(), mintedAfterPause, "Empty slot mint is a no-op");
    }

    function test_pause_doesNotBlockBurn() public {
        _submitIntent(alice, bob, "pre-pause burn");
        uint256 tokenId = 0;
        address tokenOwner = gag.ownerOf(tokenId);

        vm.prank(owner);
        gag.pause();

        vm.deal(tokenOwner, BURN_FEE);
        vm.prank(tokenOwner);
        gag.burnToken{value: BURN_FEE}(tokenId);

        vm.expectRevert();
        gag.ownerOf(tokenId);
    }

    function test_pause_flushesQueue_mintsAllSeedSlots() public {
        assertEq(gag.totalMinted(), 0);

        vm.prank(owner);
        gag.pause();

        assertEq(gag.totalMinted(), QUEUE_SIZE);
    }

    function test_pause_flushesQueue_clearsAllSlots() public {
        vm.prank(owner);
        gag.pause();

        for (uint8 i = 0; i < QUEUE_SIZE; i++) {
            (address recipient,,) = gag.mintingQueue(i);
            assertEq(recipient, address(0), "Slot should be cleared after flush");
        }
    }

    // =========================================================================
    //  Edge Cases
    // =========================================================================

    function test_maxLengthMessage_succeeds() public {
        string memory maxMsg = "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghij";
        assertEq(bytes(maxMsg).length, 64);

        _submitIntent(alice, bob, maxMsg);
        assertEq(gag.totalMinted(), 1);
    }

    function test_singleCharMessage_succeeds() public {
        _submitIntent(alice, bob, "a");
        assertEq(gag.totalMinted(), 1);
    }

    function test_specialCharactersInMessage() public {
        _submitIntent(alice, bob, "hello! @world #test (1) [2] /3");
        assertEq(gag.totalMinted(), 1);
    }

    function test_allPunctuationCharacters() public {
        _submitIntent(alice, bob, ".,!?-_:;'\"()[]/@#+&");
        assertEq(gag.totalMinted(), 1);
    }

    // =========================================================================
    //  Accounting Invariants
    // =========================================================================

    function test_accountingInvariant_contractBalanceCoversObligations() public {
        for (uint256 i = 0; i < 30; i++) {
            vm.roll(block.number + i + 1);
            vm.prevrandao(bytes32(uint256(i * 67)));
            _submitIntent(alice, bob, string.concat("inv ", _uintToStr(i)));
        }

        // Burn a few tokens.
        for (uint256 tid = 0; tid < 5 && tid < gag.totalMinted(); tid++) {
            try gag.ownerOf(tid) returns (address tokenOwner) {
                vm.deal(tokenOwner, BURN_FEE);
                vm.prank(tokenOwner);
                gag.burnToken{value: BURN_FEE}(tid);
            } catch {
                continue;
            }
        }

        assertTrue(address(gag).balance > 0);
    }

    // =========================================================================
    //  Receive
    // =========================================================================

    function test_receive_acceptsNativeTokens() public {
        (bool sent,) = address(gag).call{value: 1 ether}("");
        assertTrue(sent);
    }
}
