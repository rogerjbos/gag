// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IGigglesAndGagsErrors} from "./IGigglesAndGagsErrors.sol";

/**
 * @title IGigglesAndGagsEvents
 * @notice Custom event definitions for the Giggles and Gags collection.
 * @dev Inherits `IGigglesAndGagsErrors` so that importing this contract provides both
 *      errors and events in a single inheritance path.
 */
interface IGigglesAndGagsEvents is IGigglesAndGagsErrors {
    /**
     * @notice Emitted when the burn-fee origin share is updated by the owner.
     * @param previousBurnFeeOriginShare The old share value in basis points.
     * @param newBurnFeeOriginShare      The new share value in basis points.
     */
    event BurnFeeOriginShareUpdated(uint256 previousBurnFeeOriginShare, uint256 newBurnFeeOriginShare);

    /**
     * @notice Emitted when a payment token is added or its prices are updated.
     * @param token       The ERC-20 address being configured.
     * @param mintingPrice The mint price in `token` units.
     * @param burningFee   The burn fee in `token` units.
     */
    event PaymentTokenUpdated(address indexed token, uint256 mintingPrice, uint256 burningFee);

    /**
     * @notice Emitted when a payment token is removed from the supported set.
     * @param token The ERC-20 address that was removed.
     */
    event PaymentTokenRemoved(address indexed token);
}
