// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IGagRenderer
 * @notice Interface for the external renderer contract. Using an interface instead of
 *         the concrete GagRenderer type prevents the Solidity compiler from pulling
 *         the heavy Metadata/Renderer/Templates bytecode into GigglesAndGags.
 */
interface IGagRenderer {
    function buildTokenURI(
        string calldata collectionName,
        uint256 tokenId,
        string calldata text
    ) external pure returns (string memory);
}
