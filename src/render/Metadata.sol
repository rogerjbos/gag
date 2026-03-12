// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Renderer} from "./Renderer.sol";

/**
 * @title Metadata
 * @notice Builds fully on-chain ERC-721 metadata for Giggles and Gags tokens.
 *         Returns a `data:application/json;base64,...` URI containing name, description,
 *         attributes, and a `data:image/svg+xml;base64,...` embedded SVG image.
 * @dev Pure library — no storage reads. Delegates SVG generation to `Renderer` and
 *      Base64 encoding to OpenZeppelin's `Base64` library.
 */
library Metadata {
    /**
     * @notice Build a complete ERC-721 `tokenURI` data URI for a given token.
     * @dev The returned string is a base64-encoded JSON document that embeds a
     *      base64-encoded SVG image, making both metadata and artwork fully on-chain.
     * @param collectionName The collection's ERC-721 `name()` (e.g. "Giggles and Gags").
     * @param tokenId        The numeric token identifier.
     * @param text           The gag message stored for this token.
     * @return A `data:application/json;base64,...` URI suitable for `tokenURI()`.
     */
    function buildTokenURI(
        string memory collectionName,
        uint256 tokenId,
        string memory text
    ) internal pure returns (string memory) {
        // Render the SVG and extract trait data in one call.
        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(tokenId, text);

        // Base64-encode the raw SVG into a data URI for the `image` field.
        string memory image = string.concat(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        );

        // Assemble the JSON metadata document in two halves to avoid stack-too-deep.
        string memory jsonHead = string.concat(
            '{"name":"', collectionName, " #", _toString(tokenId), '",',
            '"description":"Giggles and Gags is a queue-minted on-chain gag collectible. The message and image are rendered fully on-chain.",'
        );
        string memory json = string.concat(
            jsonHead,
            '"attributes":', Renderer.attributesJSON(data), ',',
            '"image":"', image, '"}'
        );

        // Base64-encode the JSON and wrap it in a data URI.
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        );
    }

    /**
     * @dev Convert a `uint256` to its decimal string representation.
     * @param value The unsigned integer to convert.
     * @return The decimal string.
     */
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
