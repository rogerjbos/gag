// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GigglesAndGagsStructs} from "./GigglesAndGagsStructs.sol";
import {IGagRenderer} from "./render/IGagRenderer.sol";
import {Utils} from "./render/Utils.sol";

/**
 * @title Giggles and Gags (GaG)
 * @author GaG Team
 * @notice A non-transferable, chaotic slot-machine-style ERC-721 gag NFT collection on Base.
 *         Users pay in supported stablecoins to submit a mint intent containing a short message.
 *         The contract maintains a fixed-size slot buffer (`queueSize = 15`). Each new submission
 *         randomly selects a slot, mints whatever intent was stored there, then overwrites it with
 *         the new intent. This produces deliberately chaotic, probabilistic minting behaviour.
 * @dev Inherits ERC721 + ERC721Pausable for token logic with emergency pause, Ownable for admin
 *      controls, and GigglesAndGagsStructs for the MintIntent struct definition (which also brings
 *      in events and errors via its inheritance chain).
 *      Tokens are soulbound: transfers are blocked in `_update`, and `approve`/`setApprovalForAll`
 *      revert unconditionally.
 */
contract GigglesAndGags is ERC721, ERC721Pausable, Ownable, GigglesAndGagsStructs {
    using SafeERC20 for IERC20;

    /// @notice Maximum basis points constant (100% = 10 000 bps) used for fee-split arithmetic.
    uint256 public constant MAX_BPTS = 10000;

    /// @notice Number of slots in the mint-intent buffer. Fixed at 15 in the constructor.
    uint8 public immutable queueSize;

    /// @notice External renderer contract for on-chain SVG/metadata generation.
    IGagRenderer public immutable renderer;

    /**
     * @notice Ordered list of currently-supported ERC-20 payment token addresses.
     * @dev Maintained alongside the `supportedToken` mapping; used by `getSupportedTokens()`.
     */
    address[] public supportedTokens;

    /// @notice Running count of tokens minted so far. Also serves as the next `tokenId`.
    uint256 public totalMinted;

    /**
     * @notice Share of the burn fee that is credited to the token's attributable origin, in bps.
     *         Default is 7 500 (75%). The remaining 25% goes to `projectFees`.
     */
    uint256 public burnFeeOriginShare;

    /// @notice Whether a given ERC-20 address is currently accepted for payments.
    mapping (address erc20 => bool supported) public supportedToken;

    /// @notice Mint price denominated in each supported ERC-20 token.
    mapping (address erc20 => uint256 price) public mintPrices;

    /// @notice Burn fee denominated in each supported ERC-20 token.
    mapping (address erc20 => uint256 burnPrice) public burnFees;

    /**
     * @notice The fixed-size slot buffer of pending mint intents, indexed 0 .. `queueSize - 1`.
     * @dev This is **not** a FIFO queue. Slots are selected pseudo-randomly and overwritten.
     */
    mapping (uint8 index => MintIntent intent) public mintingQueue;

    /// @dev Maps each minted `tokenId` to its on-chain gag message.
    mapping (uint256 tokenId => string message) internal tokenMessages;

    /**
     * @dev Maps each minted `tokenId` to its attributable origin address.
     *      `address(0)` means the minter chose to remain anonymous.
     */
    mapping (uint256 tokenId => address origin) internal tokenOrigin;

    /// @dev Tracks claimable burn-fee rewards per origin per ERC-20 token.
    mapping (address recipient => mapping (address token => uint256 fees)) internal earnedFees;

    /**
     * @dev Tracks accumulated project treasury fees per ERC-20 token.
     *      Owner withdrawals via `withdrawFees` must only draw from this balance.
     */
    mapping (address token => uint256 fees) internal projectFees;

    // -------------------------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------------------------

    /**
     * @notice Deploys the GaG collection, seeds all 15 intent slots, and sets defaults.
     * @dev The seed arrays pre-fill every slot so the system behaves uniformly from launch.
     *      Seed intents are anonymous (origin = address(0)) and cost nothing.
     * @param initialOwner   Address that will own the contract (receives `Ownable` privileges).
     * @param rendererAddress Address of the deployed `GagRenderer` contract for on-chain metadata.
     * @param seedRecipients  Array of exactly `queueSize` non-zero recipient addresses for seed slots.
     * @param seedMessages    Array of exactly `queueSize` messages, each passing `Utils.validateText`.
     */
    constructor(
        address initialOwner,
        address rendererAddress,
        address[] memory seedRecipients,
        string[] memory seedMessages
    )
        ERC721("Giggles and Gags", "GaG")
        Ownable(initialOwner)
    {
        if (rendererAddress == address(0)) revert InvalidRecipient();
        renderer = IGagRenderer(rendererAddress);
        queueSize = 15;
        burnFeeOriginShare = 7500;

        // Both seed arrays must match `queueSize` exactly.
        if(seedRecipients.length != seedMessages.length || seedRecipients.length != queueSize) revert IncorrectSeedSize();
        for(uint8 i; i < queueSize; ){
            // Validate seed messages against the same rules as user submissions.
            if(seedRecipients[i] == address(0)) revert InvalidRecipient();
            Utils.validateText(seedMessages[i]);

            // Seed intents are always anonymous (origin = address(0)).
            _placeIntoQueue(i, seedRecipients[i], address(0), seedMessages[i]);

            unchecked {
                ++i;
            }
        }

        emit BurnFeeOriginShareUpdated(0, burnFeeOriginShare);
    }

    // -------------------------------------------------------------------------
    //  View functions
    // -------------------------------------------------------------------------

    /// @notice Returns the full list of currently-supported ERC-20 payment token addresses.
    function getSupportedTokens() public view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Returns fully on-chain metadata (JSON + base64-encoded SVG image) for a token.
     * @dev Reverts via `_requireOwned` if `tokenId` does not exist.
     * @param tokenId The token to query.
     * @return A `data:application/json;base64,...` URI.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        return renderer.buildTokenURI(name(), tokenId, tokenMessages[tokenId]);
    }

    /**
     * @notice Returns the caller's claimable burn-fee rewards denominated in `token`.
     * @param token The ERC-20 address to check.
     * @return The amount of `token` the caller can claim via `claimFees`.
     */
    function claimable(address token) public view returns (uint256) {
        return earnedFees[msg.sender][token];
    }

    // -------------------------------------------------------------------------
    //  User actions
    // -------------------------------------------------------------------------

    /**
     * @notice Submit a new mint intent. Pays the mint price, randomly selects a slot,
     *         mints whatever was previously stored in that slot (if anything), then
     *         overwrites the slot with the caller's new intent.
     * @dev Flow:
     *      1. Validate inputs (supported token, non-zero recipient, valid message text).
     *      2. Pull the mint price from the sender via `safeTransferFrom`.
     *      3. Credit the full mint price to `projectFees`.
     *      4. Compute a pseudo-random slot index.
     *      5. Mint the existing intent in that slot (if populated).
     *      6. Overwrite the slot with the new intent.
     * @param anonymize    If `true`, the origin is stored as `address(0)` — no burn-fee kickback.
     * @param recipient    Address that will receive the NFT when this intent is eventually minted.
     * @param paymentToken Address of the ERC-20 stablecoin used to pay the mint price.
     * @param message      The gag message (1–64 ASCII chars, validated by `Utils.validateText`).
     */
    function submitMintIntent(
        bool anonymize,
        address recipient,
        address paymentToken,
        string memory message
    ) public whenNotPaused {
        if(!supportedToken[paymentToken]) revert UnsupportedToken();
        if(recipient == address(0)) revert InvalidRecipient();

        Utils.validateText(message);

        // Pull stablecoin payment and credit to project treasury.
        _pullPayment(paymentToken, mintPrices[paymentToken]);
        projectFees[paymentToken] += mintPrices[paymentToken];

        // Select a pseudo-random slot, mint whatever is there, then overwrite.
        uint8 intentIndex = _calculateMintIntentIndex(paymentToken);
        _mintFromQueue(intentIndex);
        address origin = anonymize ? address(0) : msg.sender;
        _placeIntoQueue(intentIndex, recipient, origin, message);
    }

    /**
     * @notice Burn a token that the caller owns. Requires paying a burn fee in a supported token.
     *         If the token has an attributable origin, that origin earns `burnFeeOriginShare` of
     *         the fee; the remainder goes to the project treasury.
     * @dev The origin share is computed first; the project share is the residual (`fee - originFee`)
     *      to avoid stranded rounding dust.
     * @param tokenId      The token to burn. Caller must be the current owner.
     * @param paymentToken Address of the ERC-20 used to pay the burn fee.
     */
    function burnToken(
        uint256 tokenId,
        address paymentToken
    ) public {
        if(ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if(!supportedToken[paymentToken]) revert UnsupportedToken();
        _pullPayment(paymentToken, burnFees[paymentToken]);

        // Split the burn fee between origin and project treasury.
        if(tokenOrigin[tokenId] != address(0)) {
            // Attributable origin gets their share; project gets the residual.
            uint256 originFee = burnFees[paymentToken] * burnFeeOriginShare / MAX_BPTS;
            earnedFees[tokenOrigin[tokenId]][paymentToken] += originFee;
            projectFees[paymentToken] += burnFees[paymentToken] - originFee;
            delete tokenOrigin[tokenId];
        } else {
            // Anonymous origin — full burn fee to project treasury.
            projectFees[paymentToken] += burnFees[paymentToken];
        }

        _burn(tokenId);
        delete tokenMessages[tokenId];
    }

    /**
     * @notice Claim all accumulated burn-fee rewards denominated in `token`.
     * @dev Zeroes the caller's balance before transferring (checks-effects-interactions pattern).
     * @param token The ERC-20 address to claim.
     */
    function claimFees(address token) public {
        if(earnedFees[msg.sender][token] == 0) revert NoFees();

        uint256 fee = earnedFees[msg.sender][token];
        earnedFees[msg.sender][token] = 0;

        IERC20(token).safeTransfer(msg.sender, fee);
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
    //  Admin actions (onlyOwner)
    // -------------------------------------------------------------------------

    /**
     * @notice Emergency-pause the contract. Blocks `submitMintIntent`.
     * @dev Only callable by the owner.
     */
    function pause() public onlyOwner {
        _flushQueue();
        _pause();
    }

    /// @notice Resume normal operation after a pause.
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Add a new supported payment token or update the prices for an existing one.
     * @dev If the token is new, it is appended to the `supportedTokens` array.
     *      Neither `mintingPrice` nor `burningFee` may be zero.
     * @param token        The ERC-20 address to configure.
     * @param mintingPrice The price (in `token` units) to submit a mint intent.
     * @param burningFee   The fee (in `token` units) to burn a token.
     */
    function updatePaymentToken(
        address token,
        uint256 mintingPrice,
        uint256 burningFee
    ) public onlyOwner {
        if (token == address(0)) revert InvalidTokenAddress();
        if (mintingPrice == 0) revert InvalidMintingPrice();
        if (burningFee == 0) revert InvalidBurningFee();

        if (!supportedToken[token]) {
            supportedToken[token] = true;
            supportedTokens.push(token);
        }

        mintPrices[token] = mintingPrice;
        burnFees[token] = burningFee;

        emit PaymentTokenUpdated(token, mintingPrice, burningFee);
    }

    /**
     * @notice Remove a payment token from the supported set.
     * @dev Clears the mint price and burn fee. Existing claimable rewards remain withdrawable
     *      because `earnedFees` and `projectFees` balances are not affected.
     */
    function removePaymentToken(address token) public onlyOwner {
        if(!supportedToken[token]) revert UnsupportedToken();

        supportedToken[token] = false;
        // Swap-and-pop removal to keep the array compact.
        for(uint256 i; i < supportedTokens.length; ) {
            if(supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();

                break;
            }

            unchecked {
                ++i;
            }
        }

        mintPrices[token] = 0;
        burnFees[token] = 0;

        emit PaymentTokenRemoved(token);
    }

    /**
     * @notice Update the share (in basis points) of the burn fee credited to attributable origins.
     * @dev Must not exceed `MAX_BPTS` (10 000). Setting to 0 means the project keeps 100%.
     * @param newBurnFeeOriginShare The new share in bps.
     */
    function updateBurnFeeOriginShare(uint256 newBurnFeeOriginShare) public onlyOwner {
        if(newBurnFeeOriginShare > MAX_BPTS) revert IncorrectShare();

        uint256 previousBurnFeeOriginShare = burnFeeOriginShare;
        burnFeeOriginShare = newBurnFeeOriginShare;

        emit BurnFeeOriginShareUpdated(previousBurnFeeOriginShare, newBurnFeeOriginShare);
    }

    /**
     * @notice Withdraw accumulated project treasury fees.
     * @dev Only draws from `projectFees[token]`; user-claimable rewards are never touched.
     *      Passing `amount = 0` withdraws the entire balance.
     * @param token     The ERC-20 to withdraw.
     * @param recipient Where to send the withdrawn fees.
     * @param amount    Amount to withdraw, or 0 for the full balance.
     */
    function withdrawFees(
        address token,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        if (token == address(0)) revert UnsupportedToken();
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount > projectFees[token]) revert InsufficientFees();
        IERC20 tokenContract = IERC20(token);

        // If caller passes 0, withdraw everything available.
        amount = amount == 0 ? projectFees[token] : amount;

        if (amount == 0) revert NoFees();

        projectFees[token] -= amount;

        tokenContract.safeTransfer(recipient, amount);
    }

    // -------------------------------------------------------------------------
    //  Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Pull an ERC-20 payment from `msg.sender` into this contract using `safeTransferFrom`.
     *      Reverts if the token is unsupported or the amount is zero.
     * @param token  The ERC-20 address.
     * @param amount The amount to pull.
     */
    function _pullPayment(
        address token,
        uint256 amount
    ) internal {
        if (!supportedToken[token]) revert UnsupportedToken();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Compute a pseudo-random slot index in [0, queueSize) using weak on-chain entropy.
     *      Intentionally non-secure; the chaos is a feature, not a bug.
     */
    function _calculateMintIntentIndex(address paymentToken) internal view returns (uint8){
        return uint8(
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao,
                        block.number,
                        block.timestamp,
                        totalMinted,
                        projectFees[paymentToken],
                        msg.sender
                    )
                )
            ) % queueSize
        );
    }

    /**
     * @dev Mint the token described by the intent stored in `mintingQueue[index]`.
     *      If the slot is empty (`recipient == address(0)`), this is a no-op.
     *      The newly minted token is assigned `tokenId = totalMinted`, then `totalMinted` is incremented.
     * @param index The slot index to mint from.
     */
    function _mintFromQueue(uint8 index) internal {
        MintIntent memory intent = mintingQueue[index];

        // Empty slot — nothing to mint.
        if (intent.recipient == address(0)) return;

        _mint(intent.recipient, totalMinted);
        tokenMessages[totalMinted] = intent.text;

        // Only store origin if the intent is attributable (non-anonymous).
        if (intent.origin != address(0)) {
            tokenOrigin[totalMinted] = intent.origin;
        }

        ++totalMinted;
    }

    /**
     * @dev Write a new intent into the specified slot, overwriting whatever was there.
     * @param index     Slot index (0 .. queueSize - 1).
     * @param recipient The future NFT recipient.
     * @param origin    The attributable origin, or `address(0)` for anonymous.
     * @param text      The validated gag message.
     */
    function _placeIntoQueue(
        uint8 index,
        address recipient,
        address origin,
        string memory text
    ) internal {
        mintingQueue[index] = MintIntent(recipient, origin, text);
    }

    /**
     * @dev Mint all populated slots in the queue before pausing the contract.
     *      Iterates through every slot in `mintingQueue`: empty slots (recipient == address(0))
     *      are skipped, populated slots are minted and then cleared. Called by `pause()` to ensure
     *      no pending intents are stranded when the contract is paused.
     */
    function _flushQueue() internal {
        for (uint8 i; i < queueSize; ) {
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
     *      minting (`from == address(0)`) and burning (`to == address(0)`) are allowed;
     *      all other transfers revert with `NonTransferable()`.
     *      Burns bypass the pause check so token holders can exit while minting is paused.
     *      Mints go through `ERC721Pausable._update` (respects `whenNotPaused`), except
     *      during `_flushQueue` which is called inside `pause()` before the pause flag is set.
     * @param to      Destination address (address(0) for burns).
     * @param tokenId The token being moved.
     * @param auth    Address authorized for the operation (unused in the override logic).
     * @return The previous owner of the token.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Allow mint (from == address(0))
        // Allow burn (to == address(0))
        // Block all normal transfers
        if (from != address(0) && to != address(0)) {
            revert NonTransferable();
        }

        // Burns bypass the pause check so holders can always exit.
        // Mints still go through ERC721Pausable (respects whenNotPaused).
        if (to == address(0) && from != address(0)) {
            return ERC721._update(to, tokenId, auth);
        }

        return super._update(to, tokenId, auth);
    }
}
