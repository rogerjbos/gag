// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";

import {GaGStructs} from "./GaGStructs.sol";
import {Utils} from "./render/Utils.sol";

/**
 * @title GaG — Polkadot Asset Hub Edition
 * @author GaG Team
 * @notice A non-transferable, chaotic slot-machine-style ERC-721 gag NFT collection.
 *         Ported from Base to Polkadot Asset Hub, using native PAS tokens for payment
 *         and off-chain SVG rendering with IPFS storage via Bulletin TransactionStorage.
 *
 *         Users pay in native PAS tokens to submit a mint intent containing a short message.
 *         The contract maintains a fixed-size slot buffer (`queueSize = 15`). Each new submission
 *         randomly selects a slot, mints whatever intent was stored there, then overwrites it with
 *         the new intent. This produces deliberately chaotic, probabilistic minting behaviour.
 *
 *         After minting, an off-chain listener generates the SVG artwork deterministically,
 *         uploads it to Bulletin TransactionStorage (IPFS), and writes the CID back to the contract.
 *
 * @dev Inherits ERC721 + ERC721Pausable for token logic with emergency pause, Ownable for admin
 *      controls, and GaGStructs for the MintIntent struct definition.
 *      Tokens are soulbound: transfers are blocked in `_update`, and `approve`/`setApprovalForAll`
 *      revert unconditionally.
 */
contract GaG is ERC721, ERC721Pausable, Ownable, GaGStructs {
    /// @notice Maximum basis points constant (100% = 10 000 bps) used for fee-split arithmetic.
    uint256 public constant MAX_BPTS = 10000;

    /// @notice Number of slots in the mint-intent buffer. Fixed at 15 in the constructor.
    uint8 public immutable queueSize;

    /// @notice Running count of tokens minted so far. Also serves as the next `tokenId`.
    uint256 public totalMinted;

    /// @notice Price in native tokens (PAS) to submit a mint intent.
    uint256 public mintPrice;

    /// @notice Fee in native tokens (PAS) to burn a token (escape a gag).
    uint256 public burnFee;

    /**
     * @notice Share of the burn fee that is credited to the token's attributable origin, in bps.
     *         Default is 7 500 (75%). The remaining 25% goes to `projectFees`.
     */
    uint256 public burnFeeOriginShare;

    /// @notice Address authorized to set token CIDs (the off-chain metadata listener).
    address public metadataUpdater;

    /**
     * @notice The fixed-size slot buffer of pending mint intents, indexed 0 .. `queueSize - 1`.
     * @dev This is **not** a FIFO queue. Slots are selected pseudo-randomly and overwritten.
     */
    mapping(uint8 index => MintIntent intent) public mintingQueue;

    /// @dev Maps each minted `tokenId` to its on-chain gag message.
    mapping(uint256 tokenId => string message) internal tokenMessages;

    /**
     * @dev Maps each minted `tokenId` to its attributable origin address.
     *      `address(0)` means the minter chose to remain anonymous.
     */
    mapping(uint256 tokenId => address origin) internal tokenOrigin;

    /// @dev Maps each minted `tokenId` to its IPFS CID for off-chain metadata.
    mapping(uint256 tokenId => string cid) internal tokenCIDs;

    /// @dev Tracks claimable burn-fee rewards per origin address.
    mapping(address recipient => uint256 fees) internal earnedFees;

    /// @dev Accumulated project treasury fees in native tokens.
    uint256 internal projectFees;

    // -------------------------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys the GaG collection, seeds all 15 intent slots, and sets defaults.
     * @param initialOwner    Address that will own the contract.
     * @param initialMintPrice  Price in native tokens to submit a mint intent.
     * @param initialBurnFee    Fee in native tokens to burn a token.
     * @param seedRecipients  Array of exactly `queueSize` non-zero recipient addresses for seed slots.
     * @param seedMessages    Array of exactly `queueSize` messages, each passing `Utils.validateText`.
     */
    constructor(
        address initialOwner,
        uint256 initialMintPrice,
        uint256 initialBurnFee,
        address[] memory seedRecipients,
        string[] memory seedMessages
    ) ERC721("GaG", "GAG") Ownable(initialOwner) {
        if (initialMintPrice == 0) revert InvalidMintingPrice();
        if (initialBurnFee == 0) revert InvalidBurningFee();

        queueSize = 15;
        mintPrice = initialMintPrice;
        burnFee = initialBurnFee;
        burnFeeOriginShare = 7500;

        // Both seed arrays must match `queueSize` exactly.
        if (seedRecipients.length != seedMessages.length || seedRecipients.length != queueSize) {
            revert IncorrectSeedSize();
        }
        for (uint8 i; i < queueSize;) {
            if (seedRecipients[i] == address(0)) revert InvalidRecipient();
            Utils.validateText(seedMessages[i]);

            // Seed intents are always anonymous (origin = address(0)).
            _placeIntoQueue(i, seedRecipients[i], address(0), seedMessages[i]);

            unchecked {
                ++i;
            }
        }

        emit BurnFeeOriginShareUpdated(0, burnFeeOriginShare);
        emit PricesUpdated(initialMintPrice, initialBurnFee);
    }

    // -------------------------------------------------------------------------
    //  View functions
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the IPFS URI for a token's metadata, or empty if CID not yet set.
     * @dev Reverts via `_requireOwned` if `tokenId` does not exist.
     * @param tokenId The token to query.
     * @return An `ipfs://<CID>` URI, or empty string if metadata not yet uploaded.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        bytes memory cidBytes = bytes(tokenCIDs[tokenId]);
        if (cidBytes.length == 0) {
            return "";
        }

        return string.concat("ipfs://", tokenCIDs[tokenId]);
    }

    /**
     * @notice Returns the on-chain gag message for a token.
     * @param tokenId The token to query.
     * @return The message text.
     */
    function getTokenMessage(uint256 tokenId) public view returns (string memory) {
        _requireOwned(tokenId);
        return tokenMessages[tokenId];
    }

    /**
     * @notice Returns the caller's claimable burn-fee rewards in native tokens.
     * @return The amount the caller can claim via `claimFees`.
     */
    function claimable() public view returns (uint256) {
        return earnedFees[msg.sender];
    }

    /**
     * @notice Returns the accumulated project treasury fees.
     * @return The project fee balance in native tokens.
     */
    function getProjectFees() public view returns (uint256) {
        return projectFees;
    }

    // -------------------------------------------------------------------------
    //  User actions
    // -------------------------------------------------------------------------

    /**
     * @notice Submit a new mint intent. Pays the mint price in native tokens (PAS),
     *         randomly selects a slot, mints whatever was previously stored in that slot
     *         (if anything), then overwrites the slot with the caller's new intent.
     * @param anonymize If `true`, the origin is stored as `address(0)` — no burn-fee kickback.
     * @param recipient Address that will receive the NFT when this intent is eventually minted.
     * @param message   The gag message (1–64 ASCII chars, validated by `Utils.validateText`).
     */
    function submitMintIntent(bool anonymize, address recipient, string memory message) public payable whenNotPaused {
        if (msg.value < mintPrice) revert InsufficientPayment();
        if (recipient == address(0)) revert InvalidRecipient();

        Utils.validateText(message);

        // Credit mint payment to project treasury.
        projectFees += mintPrice;

        // Refund any excess payment.
        uint256 excess = msg.value - mintPrice;
        if (excess > 0) {
            (bool sent,) = msg.sender.call{value: excess}("");
            if (!sent) revert TransferFailed();
        }

        // Select a pseudo-random slot, mint whatever is there, then overwrite.
        uint8 intentIndex = _calculateMintIntentIndex();
        _mintFromQueue(intentIndex);
        address origin = anonymize ? address(0) : msg.sender;
        _placeIntoQueue(intentIndex, recipient, origin, message);
    }

    /**
     * @notice Burn a token that the caller owns. Requires paying the burn fee in native tokens.
     *         If the token has an attributable origin, that origin earns `burnFeeOriginShare` of
     *         the fee; the remainder goes to `projectFees`.
     * @param tokenId The token to burn. Caller must be the current owner.
     */
    function burnToken(uint256 tokenId) public payable {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (msg.value < burnFee) revert InsufficientPayment();

        // Refund any excess payment.
        uint256 excess = msg.value - burnFee;
        if (excess > 0) {
            (bool sent,) = msg.sender.call{value: excess}("");
            if (!sent) revert TransferFailed();
        }

        // Split the burn fee between origin and project treasury.
        if (tokenOrigin[tokenId] != address(0)) {
            uint256 originFee = burnFee * burnFeeOriginShare / MAX_BPTS;
            earnedFees[tokenOrigin[tokenId]] += originFee;
            projectFees += burnFee - originFee;
            delete tokenOrigin[tokenId];
        } else {
            projectFees += burnFee;
        }

        _burn(tokenId);
        delete tokenMessages[tokenId];
        delete tokenCIDs[tokenId];
    }

    /**
     * @notice Claim all accumulated burn-fee rewards in native tokens.
     * @dev Zeroes the caller's balance before transferring (checks-effects-interactions pattern).
     */
    function claimFees() public {
        uint256 fee = earnedFees[msg.sender];
        if (fee == 0) revert NoFees();

        earnedFees[msg.sender] = 0;

        (bool sent,) = msg.sender.call{value: fee}("");
        if (!sent) revert TransferFailed();
    }

    /**
     * @notice Blocked — tokens are non-transferable.
     * @dev Always reverts with `NonTransferable()`.
     */
    function approve(address, uint256) public pure override {
        revert NonTransferable();
    }

    /**
     * @notice Blocked — tokens are non-transferable.
     * @dev Always reverts with `NonTransferable()`.
     */
    function setApprovalForAll(address, bool) public pure override {
        revert NonTransferable();
    }

    // -------------------------------------------------------------------------
    //  Metadata updater actions
    // -------------------------------------------------------------------------

    /**
     * @notice Set the IPFS CID for a token's metadata. Callable only by the metadata updater.
     * @dev Called by the off-chain listener after generating and uploading SVG + JSON to IPFS.
     * @param tokenId The token to update.
     * @param cid     The IPFS CID (e.g. "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi").
     */
    function setTokenCID(uint256 tokenId, string calldata cid) public {
        if (msg.sender != metadataUpdater) revert NotMetadataUpdater();
        _requireOwned(tokenId);

        tokenCIDs[tokenId] = cid;
        emit TokenCIDSet(tokenId, cid);
    }

    // -------------------------------------------------------------------------
    //  Admin actions (onlyOwner)
    // -------------------------------------------------------------------------

    /// @notice Emergency-pause the contract. Blocks `submitMintIntent`.
    function pause() public onlyOwner {
        _flushQueue();
        _pause();
    }

    /// @notice Resume normal operation after a pause.
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Set the metadata updater address (the off-chain listener).
     * @param updater The new metadata updater address. Can be address(0) to disable.
     */
    function setMetadataUpdater(address updater) public onlyOwner {
        metadataUpdater = updater;
        emit MetadataUpdaterSet(updater);
    }

    /**
     * @notice Update the mint price and burn fee in native tokens.
     * @param newMintPrice The new mint price. Must not be zero.
     * @param newBurnFee   The new burn fee. Must not be zero.
     */
    function updatePrices(uint256 newMintPrice, uint256 newBurnFee) public onlyOwner {
        if (newMintPrice == 0) revert InvalidMintingPrice();
        if (newBurnFee == 0) revert InvalidBurningFee();

        mintPrice = newMintPrice;
        burnFee = newBurnFee;

        emit PricesUpdated(newMintPrice, newBurnFee);
    }

    /**
     * @notice Update the share (in basis points) of the burn fee credited to attributable origins.
     * @param newBurnFeeOriginShare The new share in bps. Must not exceed `MAX_BPTS`.
     */
    function updateBurnFeeOriginShare(uint256 newBurnFeeOriginShare) public onlyOwner {
        if (newBurnFeeOriginShare > MAX_BPTS) revert IncorrectShare();

        uint256 previousBurnFeeOriginShare = burnFeeOriginShare;
        burnFeeOriginShare = newBurnFeeOriginShare;

        emit BurnFeeOriginShareUpdated(previousBurnFeeOriginShare, newBurnFeeOriginShare);
    }

    /**
     * @notice Withdraw accumulated project treasury fees in native tokens.
     * @param recipient Where to send the withdrawn fees.
     * @param amount    Amount to withdraw, or 0 for the full balance.
     */
    function withdrawFees(address recipient, uint256 amount) public onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount > projectFees) revert InsufficientFees();

        amount = amount == 0 ? projectFees : amount;
        if (amount == 0) revert NoFees();

        projectFees -= amount;

        (bool sent,) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed();
    }

    // -------------------------------------------------------------------------
    //  Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Compute a pseudo-random slot index in [0, queueSize) using weak on-chain entropy.
     *      Intentionally non-secure; the chaos is a feature, not a bug.
     */
    function _calculateMintIntentIndex() internal view returns (uint8) {
        return uint8(
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao, block.number, block.timestamp, totalMinted, projectFees, msg.sender
                    )
                )
            ) % queueSize
        );
    }

    /**
     * @dev Mint the token described by the intent stored in `mintingQueue[index]`.
     *      If the slot is empty (`recipient == address(0)`), this is a no-op.
     */
    function _mintFromQueue(uint8 index) internal {
        MintIntent memory intent = mintingQueue[index];

        if (intent.recipient == address(0)) return;

        _mint(intent.recipient, totalMinted);
        tokenMessages[totalMinted] = intent.text;

        if (intent.origin != address(0)) {
            tokenOrigin[totalMinted] = intent.origin;
        }

        ++totalMinted;
    }

    /**
     * @dev Write a new intent into the specified slot, overwriting whatever was there.
     */
    function _placeIntoQueue(uint8 index, address recipient, address origin, string memory text) internal {
        mintingQueue[index] = MintIntent(recipient, origin, text);
    }

    /**
     * @dev Mint all populated slots in the queue before pausing the contract.
     */
    function _flushQueue() internal {
        for (uint8 i; i < queueSize;) {
            MintIntent memory intent = mintingQueue[i];
            if (intent.recipient == address(0)) {
                ++i;
                continue;
            }

            _mintFromQueue(i);
            delete mintingQueue[i];

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Override required by ERC721Pausable. Enforces non-transferability:
     *      minting and burning are allowed; all other transfers revert.
     *      Burns bypass the pause check so token holders can exit while minting is paused.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }

        // Burns bypass the pause check so holders can always exit.
        if (to == address(0) && from != address(0)) {
            return ERC721._update(to, tokenId, auth);
        }

        return super._update(to, tokenId, auth);
    }

    /// @notice Allow the contract to receive native tokens.
    receive() external payable {}
}
