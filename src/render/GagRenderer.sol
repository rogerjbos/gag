// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Metadata} from "./Metadata.sol";

/**
 * @title GagRenderer
 * @notice Separately deployed contract that handles all on-chain metadata and SVG
 *         rendering for Giggles and Gags. Extracted to keep the main GaG contract
 *         under the EIP-170 contract size limit (24 576 bytes).
 * @dev All functions are pure — no state, no storage. This contract is essentially
 *      a bytecode sink for the heavy Metadata/Renderer/Templates/Utils libraries.
 */
contract GagRenderer {
    /**
     * @notice Build a complete ERC-721 `tokenURI` data URI.
     * @param collectionName The collection's ERC-721 `name()`.
     * @param tokenId        The numeric token identifier.
     * @param text           The gag message stored for this token.
     * @return A `data:application/json;base64,...` URI.
     */
    function buildTokenURI(
        string calldata collectionName,
        uint256 tokenId,
        string calldata text
    ) external pure returns (string memory) {
        return Metadata.buildTokenURI(collectionName, tokenId, text);
    }
}
