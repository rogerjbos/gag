// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Utils
 * @notice Text validation and XML-escaping utilities for GaG.
 *         Ensures gag messages are safe for on-chain SVG rendering and conform to
 *         the strict ASCII whitelist rules of the collection.
 * @dev Validation is byte-based. Because the whitelist is strict ASCII-only, one byte
 *      always equals one character, so `MAX_TEXT_LENGTH` of 64 bytes means 64 characters.
 */
library Utils {
    /// @notice Thrown when the message length is 0 or exceeds `MAX_TEXT_LENGTH`.
    error InvalidTextLength();

    /// @notice Thrown when the message starts or ends with a space (0x20).
    error InvalidLeadingOrTrailingSpace();

    /// @notice Thrown when the message contains consecutive spaces.
    error InvalidDoubleSpace();

    /**
     * @notice Thrown when the message contains a character not on the ASCII whitelist.
     * @param char_ The offending byte.
     * @param index The byte index where the invalid character was found.
     */
    error InvalidCharacter(bytes1 char_, uint256 index);

    /// @notice Maximum allowed message length in bytes (= characters, since ASCII-only).
    uint256 internal constant MAX_TEXT_LENGTH = 64;

    /**
     * @notice Validate a gag message against the collection's text rules.
     * @dev Rules enforced:
     *      1. Length must be 1–64 bytes.
     *      2. No leading or trailing spaces.
     *      3. No consecutive (double) spaces.
     *      4. Every byte must pass `_isAllowedChar` (strict ASCII whitelist).
     *      Reverts with a specific custom error on the first violation found.
     * @param text The message string to validate.
     */
    function validateText(string memory text) internal pure {
        bytes memory b = bytes(text);
        uint256 len = b.length;

        // Rule 1: length must be in [1, MAX_TEXT_LENGTH].
        if (len == 0 || len > MAX_TEXT_LENGTH) {
            revert InvalidTextLength();
        }

        // Rule 2: no leading or trailing spaces.
        if (b[0] == 0x20 || b[len - 1] == 0x20) {
            revert InvalidLeadingOrTrailingSpace();
        }

        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];

            // Rule 4: character must be on the whitelist.
            if (!_isAllowedChar(c)) {
                revert InvalidCharacter(c, i);
            }

            // Rule 3: no consecutive spaces.
            if (c == 0x20 && i + 1 < len && b[i + 1] == 0x20) {
                revert InvalidDoubleSpace();
            }
        }
    }

    /**
     * @notice Returns the byte-length of a string.
     * @dev Since the collection enforces ASCII-only, byte length == character count.
     * @param text The string to measure.
     * @return The length in bytes.
     */
    function textLength(string memory text) internal pure returns (uint256) {
        return bytes(text).length;
    }

    /**
     * @notice Escape XML special characters so that the string is safe for SVG embedding.
     * @dev Uses a two-pass approach for O(n) memory allocation:
     *      1. Pre-scan to compute exact output length.
     *      2. Single allocation + byte-by-byte write with entity substitutions.
     *      Replaces: `&` → `&amp;`, `"` → `&quot;`, `'` → `&apos;`, `<` → `&lt;`, `>` → `&gt;`.
     * @param text The raw string to escape.
     * @return The XML-safe escaped string.
     */
    function escapeXML(string memory text) internal pure returns (string memory) {
        bytes memory b = bytes(text);
        uint256 len = b.length;

        // Pass 1: compute exact output length.
        uint256 outLen = 0;
        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            if (c == 0x26) outLen += 5; // & → &amp;
            else if (c == 0x22) outLen += 6; // " → &quot;
            else if (c == 0x27) outLen += 6; // ' → &apos;
            else if (c == 0x3C) outLen += 4; // < → &lt;
            else if (c == 0x3E) outLen += 4; // > → &gt;
            else outLen += 1;
        }

        // Pass 2: allocate once and write.
        bytes memory out = new bytes(outLen);
        uint256 j = 0;
        for (uint256 i = 0; i < len; i++) {
            bytes1 c = b[i];
            if (c == 0x26) {
                out[j++] = "&";
                out[j++] = "a";
                out[j++] = "m";
                out[j++] = "p";
                out[j++] = ";";
            } else if (c == 0x22) {
                out[j++] = "&";
                out[j++] = "q";
                out[j++] = "u";
                out[j++] = "o";
                out[j++] = "t";
                out[j++] = ";";
            } else if (c == 0x27) {
                out[j++] = "&";
                out[j++] = "a";
                out[j++] = "p";
                out[j++] = "o";
                out[j++] = "s";
                out[j++] = ";";
            } else if (c == 0x3C) {
                out[j++] = "&";
                out[j++] = "l";
                out[j++] = "t";
                out[j++] = ";";
            } else if (c == 0x3E) {
                out[j++] = "&";
                out[j++] = "g";
                out[j++] = "t";
                out[j++] = ";";
            } else {
                out[j++] = c;
            }
        }

        return string(out);
    }

    /**
     * @dev Check whether a single byte is on the allowed character whitelist.
     *      Allowed set: A-Z, a-z, 0-9, space, and punctuation . , ! ? - _ : ; ' " ( ) [ ] / 0x40 # + &
     * @param c The byte to check.
     * @return `true` if the character is allowed.
     */
    function _isAllowedChar(bytes1 c) internal pure returns (bool) {
        // A-Z (0x41–0x5A)
        if (c >= 0x41 && c <= 0x5A) return true;
        // a-z (0x61–0x7A)
        if (c >= 0x61 && c <= 0x7A) return true;
        // 0-9 (0x30–0x39)
        if (c >= 0x30 && c <= 0x39) return true;

        // space (0x20)
        if (c == 0x20) return true;

        // Allowed punctuation:
        // . , ! ? - _ : ; ' " ( ) [ ] / @ # + &
        if (
            c == 0x2E // .
                || c == 0x2C // ,
                || c == 0x21 // !
                || c == 0x3F // ?
                || c == 0x2D // -
                || c == 0x5F // _
                || c == 0x3A // :
                || c == 0x3B // ;
                || c == 0x27 // '
                || c == 0x22 // "
                || c == 0x28 // (
                || c == 0x29 // )
                || c == 0x5B // [
                || c == 0x5D // ]
                || c == 0x2F // /
                || c == 0x40 // @
                || c == 0x23 // #
                || c == 0x2B // +
                || c == 0x26 // &
        ) {
            return true;
        }

        return false;
    }
}
