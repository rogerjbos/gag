// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IGigglesAndGagsErrors
 * @notice Custom error definitions shared across the Giggles and Gags contracts.
 * @dev Using custom errors instead of `require` strings saves deployment and runtime gas.
 */
interface IGigglesAndGagsErrors {
    /// @notice Thrown when a proposed burn-fee origin share exceeds `MAX_BPTS` (10 000).
    error IncorrectShare();

    /// @notice Thrown when a fee withdrawal `amount` exceeds the available `projectFees` balance.
    error InsufficientFees();

    /// @notice Thrown when a payment amount resolves to zero (e.g. a zero-priced token).
    error InvalidAmount();

    /// @notice Thrown when attempting to set a burn fee to zero.
    error InvalidBurningFee();

    /// @notice Thrown when attempting to set a mint price to zero.
    error InvalidMintingPrice();

    /// @notice Thrown when a recipient address is `address(0)`.
    error InvalidRecipient();

    /// @notice Thrown when constructor seed arrays do not match `queueSize`.
    error IncorrectSeedSize();

    /// @notice Thrown when `address(0)` is passed as a payment token address.
    error InvalidTokenAddress();

    /// @notice Thrown when claiming or withdrawing fees and the balance is zero.
    error NoFees();

    /// @notice Thrown on any transfer, approve, or setApprovalForAll attempt — tokens are soulbound.
    error NonTransferable();

    /// @notice Thrown when a caller tries to burn a token they do not own.
    error NotTokenOwner();

    /// @notice Thrown when a payment token is not in the supported set.
    error UnsupportedToken();
}
