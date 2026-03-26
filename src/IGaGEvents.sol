// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IGaGErrors} from "./IGaGErrors.sol";

/**
 * @title IGaGEvents
 * @notice Custom event definitions for the GaG collection.
 * @dev Inherits `IGaGErrors` so that importing this contract provides both
 *      errors and events in a single inheritance path.
 */
interface IGaGEvents is IGaGErrors {
    /**
     * @notice Emitted when the burn-fee origin share is updated by the owner.
     * @param previousBurnFeeOriginShare The old share value in basis points.
     * @param newBurnFeeOriginShare      The new share value in basis points.
     */
    event BurnFeeOriginShareUpdated(uint256 previousBurnFeeOriginShare, uint256 newBurnFeeOriginShare);

    /**
     * @notice Emitted when the mint price or burn fee is updated.
     * @param mintPrice The new mint price in native token units.
     * @param burnFee   The new burn fee in native token units.
     */
    event PricesUpdated(uint256 mintPrice, uint256 burnFee);

    /**
     * @notice Emitted when a token's IPFS CID is set by the metadata updater.
     * @param tokenId The token whose CID was set.
     * @param cid     The IPFS CID pointing to the token's metadata.
     */
    event TokenCIDSet(uint256 indexed tokenId, string cid);

    /**
     * @notice Emitted when the metadata updater address is changed.
     * @param updater The new metadata updater address.
     */
    event MetadataUpdaterSet(address indexed updater);
}
