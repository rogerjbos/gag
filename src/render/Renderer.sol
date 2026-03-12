// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Templates} from "./Templates.sol";
import {Utils} from "./Utils.sol";

/**
 * @title Renderer
 * @notice Deterministic on-chain SVG renderer for Giggles and Gags NFT images.
 *         Given a token ID and a gag message, this library produces a complete SVG string
 *         and a `RenderData` struct containing all derived visual traits and metadata attributes.
 * @dev All rendering is pure — no storage reads — so it can be called from `tokenURI` views.
 *      Visual parameters (background, frame, text style, mood, badge, rare mode) are derived
 *      deterministically from `keccak256(message)`, making every unique message produce a
 *      unique visual output.
 */
library Renderer {
    /**
     * @notice Aggregated rendering parameters derived from the gag message text.
     * @param seed           keccak256 hash of the raw message bytes; drives all randomness.
     * @param bgVariant      Background style index (0 = Terminal Grid, 1 = Doomwave, 2 = Forum Static).
     * @param frameVariant   Frame style index (0 = Soft Coping, 1 = Double Down, 2 = Badge of Shame).
     * @param textVariant    Text weight/spacing variant index (0 = Deadpan, 1 = Posting, 2 = Meltdown).
     * @param rareMode       True if `seed % 64 == 0` (~1.56% chance); triggers alternate colour palette.
     * @param length         Character/byte count of the original message.
     * @param fontSize       Computed font size in px (range ~38–114) based on visual width scoring.
     * @param twoLines       Whether the message is split across two lines for rendering.
     * @param line1          First (or only) line of text after layout splitting.
     * @param line2          Second line of text (empty string if single-line layout).
     * @param backgroundName Human-readable background trait name for metadata.
     * @param frameName      Human-readable frame trait name for metadata.
     * @param toneName       Human-readable text-tone trait name for metadata.
     * @param moodName       Human-readable mood trait name for metadata.
     * @param badgeLabel     Badge text shown in the top-right corner of the SVG.
     * @param caption        Caption line (always "randomly assigned chaos").
     */
    struct RenderData {
        bytes32 seed;
        uint8 bgVariant;
        uint8 frameVariant;
        uint8 textVariant;
        bool rareMode;
        uint256 length;
        uint256 fontSize;
        bool twoLines;
        string line1;
        string line2;
        string backgroundName;
        string frameName;
        string toneName;
        string moodName;
        string badgeLabel;
        string caption;
    }

    /**
     * @notice Render a complete SVG image for a token.
     * @dev Assembles the SVG by concatenating template fragments (header, styles, background,
     *      frame, logo, badge, text nodes, caption, footer, token ID label).
     *      Text content is XML-escaped before insertion to prevent SVG injection.
     * @param tokenId The token ID (displayed in the bottom-left label).
     * @param text    The raw gag message.
     * @return svg  The complete SVG markup string.
     * @return data The derived `RenderData` struct (useful for metadata attribute generation).
     */
    function renderSVG(
        uint256 tokenId,
        string memory text
    ) internal pure returns (string memory svg, RenderData memory data) {
        data = deriveRenderData(text);

        // Build SVG in two halves to avoid stack-too-deep from 12+ concat args.
        string memory head = string.concat(
            Templates.svgHeader(),
            Templates.textStyleTemplate(data.textVariant, data.rareMode),
            Templates.backgroundTemplate(data.bgVariant, data.seed, data.rareMode),
            Templates.frameTemplate(data.frameVariant, data.rareMode),
            Templates.logoTemplate(data.rareMode),
            Templates.badgeTemplate(data.badgeLabel, data.rareMode),
            Templates.topEnsDomain()
        );

        string memory tail = string.concat(
            Templates.captionLine(data.caption),
            Templates.footerLabel(),
            Templates.tokenIdLabel(tokenId),
            Templates.svgFooter()
        );

        if (data.twoLines) {
            svg = string.concat(
                head,
                Templates.buildTwoLineTextNode(
                    Utils.escapeXML(data.line1),
                    Utils.escapeXML(data.line2),
                    data.fontSize
                ),
                tail
            );
        } else {
            svg = string.concat(
                head,
                Templates.buildSingleLineTextNode(
                    Utils.escapeXML(data.line1),
                    data.fontSize,
                    data.textVariant
                ),
                tail
            );
        }
    }

    /**
     * @notice Derive all visual rendering parameters from a gag message string.
     * @dev The seed is `keccak256(bytes(text))`. Different bit-ranges of the seed select
     *      different traits, keeping derivations independent:
     *        - bits  [0..7]   → bgVariant  (mod 3)
     *        - bits  [8..15]  → frameVariant (mod 3)
     *        - bits [16..23]  → textVariant  (mod 3)
     *        - seed mod 64    → rareMode     (== 0 means rare)
     *        - bits [24..31]  → mood         (mod 4)
     *        - bits [32..39]  → badge        (mod 5)
     * @param text The raw gag message.
     * @return data Fully populated `RenderData`.
     */
    function deriveRenderData(string memory text) internal pure returns (RenderData memory data) {
        bytes memory raw = bytes(text);
        uint256 len = raw.length;
        bytes32 seed = keccak256(raw);

        data.seed = seed;
        data.bgVariant = uint8(uint256(seed) % 3);
        data.frameVariant = uint8((uint256(seed) >> 8) % 3);
        data.textVariant = uint8((uint256(seed) >> 16) % 3);
        data.rareMode = (uint256(seed) % 64 == 0);
        data.length = len;

        // Determine line layout and font sizing.
        _layoutText(text, data);

        // Resolve human-readable trait names.
        data.backgroundName = _backgroundName(data.bgVariant);
        data.frameName = _frameName(data.frameVariant);
        data.toneName = _toneName(data.textVariant);
        data.moodName = _moodName(seed);
        data.badgeLabel = _badgeLabel(seed, data.rareMode);
        data.caption = "randomly assigned chaos";
    }

    /**
     * @notice Build a JSON array of ERC-721 metadata attributes from render data.
     * @param data The `RenderData` struct containing all trait values.
     * @return A JSON string of the form `[{"trait_type":"...","value":"..."}, ...]`.
     */
    function attributesJSON(RenderData memory data) internal pure returns (string memory) {
        // Split into two halves to avoid stack-too-deep from 18 concat args.
        string memory part1 = string.concat(
            '[{"trait_type":"Background","value":"', data.backgroundName, '"},',
            '{"trait_type":"Frame","value":"', data.frameName, '"},',
            '{"trait_type":"Tone","value":"', data.toneName, '"},',
            '{"trait_type":"Mood","value":"', data.moodName, '"},'
        );
        string memory part2 = string.concat(
            '{"trait_type":"Badge","value":"', data.badgeLabel, '"},',
            '{"trait_type":"Caption","value":"', data.caption, '"},',
            '{"trait_type":"Layout","value":"', (data.twoLines ? "Two Lines" : "Single Line"), '"},',
            '{"trait_type":"Rare","value":"', (data.rareMode ? "Yes" : "No"), '"},',
            '{"display_type":"number","trait_type":"Length","value":', _toString(data.length), "}]"
        );
        return string.concat(part1, part2);
    }

    // -------------------------------------------------------------------------
    //  Text layout helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Decide whether to render the message as one or two lines and compute the font size.
     *      Short messages (visual width score <= 110 AND length <= 20) stay single-line.
     *      Everything else is split at the visually-optimal space character (or hard-split at
     *      the midpoint if there are no spaces). An extra font-size shrink is applied for very
     *      long messages (44+ chars) to keep text within the frame.
     * @param text The raw gag message.
     * @param data The `RenderData` struct (mutated in-place with layout fields).
     */
    function _layoutText(string memory text, RenderData memory data) private pure {
        bytes memory raw = bytes(text);
        uint256 totalScore = _visualWidthScore(raw, 0, raw.length);

        // Safe single-line case: short enough that no wrapping is needed.
        if (totalScore <= 110 && raw.length <= 20) {
            data.twoLines = false;
            data.line1 = text;
            data.line2 = "";
            data.fontSize = _fontSizeFromWidth(totalScore, false, data.textVariant);
            return;
        }

        // Two-line layout: find the best space to split on.
        (uint256 splitIndex, bool foundSpace) = _findBestSplit(raw);

        string memory line1;
        string memory line2;

        if (foundSpace) {
            // Split at the space — omit the space itself from both lines.
            line1 = _substring(text, 0, splitIndex);
            line2 = _substring(text, splitIndex + 1, raw.length);
        } else {
            // No spaces found: hard-split at the midpoint.
            line1 = _substring(text, 0, splitIndex);
            line2 = _substring(text, splitIndex, raw.length);
        }

        bytes memory b1 = bytes(line1);
        bytes memory b2 = bytes(line2);

        uint256 score1 = _visualWidthScore(b1, 0, b1.length);
        uint256 score2 = _visualWidthScore(b2, 0, b2.length);
        uint256 maxScore = score1 > score2 ? score1 : score2;

        data.twoLines = true;
        data.line1 = line1;
        data.line2 = line2;
        data.fontSize = _fontSizeFromWidth(maxScore, true, data.textVariant);

        // Extra shrink for long wrapped text to prevent overflow past the frame boundary.
        uint256 totalLen = raw.length;

        if (totalLen >= 60) {
            data.fontSize = data.fontSize > 14 ? data.fontSize - 14 : data.fontSize;
        } else if (totalLen >= 52) {
            data.fontSize = data.fontSize > 10 ? data.fontSize - 10 : data.fontSize;
        } else if (totalLen >= 44) {
            data.fontSize = data.fontSize > 6 ? data.fontSize - 6 : data.fontSize;
        }
    }

    /**
     * @dev Find the optimal space index at which to split a message into two lines.
     *      Uses a prefix-sum array of per-character width scores so that any sub-range
     *      score can be looked up in O(1), making the overall split search O(n) instead
     *      of O(n²). Evaluates every interior space and picks the one that minimises the
     *      visual width of the widest resulting line, with tie-breaking on width balance
     *      and character-count balance.
     * @param raw The raw bytes of the message.
     * @return splitIndex The character index at which to split.
     * @return foundSpace `true` if a space-based split was found; `false` means hard midpoint split.
     */
    function _findBestSplit(bytes memory raw) private pure returns (uint256 splitIndex, bool foundSpace) {
        uint256 len = raw.length;

        // Build prefix-sum array: prefix[i] = sum of width scores for raw[0..i-1].
        // prefix[0] = 0, prefix[len] = total width score.
        uint256[] memory prefix = new uint256[](len + 1);
        for (uint256 i = 0; i < len; i++) {
            prefix[i + 1] = prefix[i] + _charWidthScore(raw[i]);
        }

        uint256 bestIndex = len / 2;
        uint256 bestCost = type(uint256).max;
        bool anySpace = false;

        for (uint256 i = 1; i < len - 1; i++) {
            if (raw[i] != 0x20) continue; // Skip non-space characters.

            anySpace = true;

            // O(1) sub-range lookups via prefix sums.
            uint256 leftScore = prefix[i];                    // score of raw[0..i-1]
            uint256 rightScore = prefix[len] - prefix[i + 1]; // score of raw[i+1..len-1]

            uint256 maxScore = leftScore > rightScore ? leftScore : rightScore;
            uint256 scoreDiff = leftScore > rightScore ? leftScore - rightScore : rightScore - leftScore;

            uint256 leftLen = i;
            uint256 rightLen = len - i - 1;
            uint256 lenDiff = leftLen > rightLen ? leftLen - rightLen : rightLen - leftLen;

            // Cost function: heavily prioritise minimising the widest line,
            // then prefer more balanced visual widths, then balanced char counts.
            uint256 cost = (maxScore * 1000) + (scoreDiff * 10) + lenDiff;

            if (cost < bestCost) {
                bestCost = cost;
                bestIndex = i;
            }
        }

        if (anySpace) {
            return (bestIndex, true);
        }

        // No spaces found: fall back to a hard midpoint split.
        return (len / 2, false);
    }

    /**
     * @dev Compute an approximate visual width score for a byte range of text.
     *      Delegates per-byte scoring to `_charWidthScore` and sums the results.
     *      Characters are bucketed by how wide they render in a monospace-ish font:
     *        - Narrow (4):        space, i, l, I, ., comma, !, :, ;, ', ", |
     *        - Wide (9):          W, M, 0x40, #, &, %, Q, O, G, D, H, N, U
     *        - Medium-narrow (5): (, ), [, ], /, -, _, +, ?
     *        - Default medium (7): everything else
     * @param raw   The raw bytes array.
     * @param start Start index (inclusive).
     * @param end   End index (exclusive).
     * @return score The cumulative width score.
     */
    function _visualWidthScore(
        bytes memory raw,
        uint256 start,
        uint256 end
    ) private pure returns (uint256 score) {
        for (uint256 i = start; i < end; i++) {
            score += _charWidthScore(raw[i]);
        }
    }

    /**
     * @dev Return the visual width score for a single byte.
     *      Factored out of `_visualWidthScore` so that `_findBestSplit` can build
     *      a prefix-sum array without duplicating the scoring logic.
     *        - Narrow (4):        space, i, l, I, ., comma, !, :, ;, ', ", |
     *        - Wide (9):          W, M, 0x40, #, &, %, Q, O, G, D, H, N, U
     *        - Medium-narrow (5): (, ), [, ], /, -, _, +, ?
     *        - Default medium (7): everything else
     * @param c The byte to score.
     * @return The width score for this character.
     */
    function _charWidthScore(bytes1 c) private pure returns (uint256) {
        // space
        if (c == 0x20) return 4;
        // narrow characters
        if (
            c == 0x69 || // i
            c == 0x6C || // l
            c == 0x49 || // I
            c == 0x2E || // .
            c == 0x2C || // ,
            c == 0x21 || // !
            c == 0x3A || // :
            c == 0x3B || // ;
            c == 0x27 || // '
            c == 0x22 || // "
            c == 0x7C    // |
        ) return 4;
        // wide characters
        if (
            c == 0x57 || // W
            c == 0x4D || // M
            c == 0x40 || // @
            c == 0x23 || // #
            c == 0x26 || // &
            c == 0x25 || // %
            c == 0x51 || // Q
            c == 0x4F || // O
            c == 0x47 || // G
            c == 0x44 || // D
            c == 0x48 || // H
            c == 0x4E || // N
            c == 0x55    // U
        ) return 9;
        // medium-narrow punctuation
        if (
            c == 0x28 || // (
            c == 0x29 || // )
            c == 0x5B || // [
            c == 0x5D || // ]
            c == 0x2F || // /
            c == 0x2D || // -
            c == 0x5F || // _
            c == 0x2B || // +
            c == 0x3F    // ?
        ) return 5;
        // default medium
        return 7;
    }

    /**
     * @dev Map a visual width score to a font size in pixels. Two separate scales exist
     *      for single-line (larger) and two-line (smaller) layouts. The `textVariant` applies
     *      a +2/0/-2 px adjustment for visual variety.
     * @param maxLineScore The visual width score of the widest line.
     * @param twoLines     Whether the layout uses two lines.
     * @param textVariant  The text style variant (0, 1, or 2).
     * @return The computed font size in pixels.
     */
    function _fontSizeFromWidth(
        uint256 maxLineScore,
        bool twoLines,
        uint8 textVariant
    ) private pure returns (uint256) {
        uint256 base;

        if (!twoLines) {
            // Single-line font scale: larger sizes.
            if (maxLineScore <= 70) {
                base = 112;
            } else if (maxLineScore <= 90) {
                base = 96;
            } else if (maxLineScore <= 110) {
                base = 84;
            } else if (maxLineScore <= 125) {
                base = 74;
            } else {
                base = 66;
            }
        } else {
            // Two-line font scale: smaller sizes.
            if (maxLineScore <= 50) {
                base = 90;
            } else if (maxLineScore <= 60) {
                base = 80;
            } else if (maxLineScore <= 70) {
                base = 72;
            } else if (maxLineScore <= 80) {
                base = 64;
            } else if (maxLineScore <= 90) {
                base = 58;
            } else {
                base = 52;
            }
        }

        // Variant adjustment: 0 = default, 1 = +2px (bolder feel), 2 = -2px (tighter).
        if (textVariant == 1) {
            return base + 2;
        } else if (textVariant == 2) {
            return base > 2 ? base - 2 : base;
        }

        return base;
    }

    /**
     * @dev Extract a substring from `str` as a new string.
     * @param str   The source string.
     * @param start Start byte index (inclusive).
     * @param end   End byte index (exclusive).
     * @return The extracted substring.
     */
    function _substring(
        string memory str,
        uint256 start,
        uint256 end
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);

        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }

        return string(result);
    }

    // -------------------------------------------------------------------------
    //  Trait name lookups
    // -------------------------------------------------------------------------

    /// @dev Map background variant index to its human-readable trait name.
    function _backgroundName(uint8 variant) private pure returns (string memory) {
        if (variant == 0) return "Terminal Grid";
        if (variant == 1) return "Doomwave";
        return "Forum Static";
    }

    /// @dev Map frame variant index to its human-readable trait name.
    function _frameName(uint8 variant) private pure returns (string memory) {
        if (variant == 0) return "Soft Coping";
        if (variant == 1) return "Double Down";
        return "Badge of Shame";
    }

    /// @dev Map text variant index to its human-readable trait (tone) name.
    function _toneName(uint8 variant) private pure returns (string memory) {
        if (variant == 0) return "Deadpan";
        if (variant == 1) return "Posting";
        return "Meltdown";
    }

    /// @dev Derive mood trait from bits [24..31] of the seed (mod 4).
    function _moodName(bytes32 seed) private pure returns (string memory) {
        uint256 mood = (uint256(seed) >> 24) % 4;
        if (mood == 0) return "Giggly";
        if (mood == 1) return "Snarky";
        if (mood == 2) return "Spicy";
        return "Terminal";
    }

    /**
     * @dev Derive badge label from bits [32..39] of the seed (mod 5).
     *      Rare mode uses an alternate set of labels with more chaotic energy.
     */
    function _badgeLabel(bytes32 seed, bool rareMode) private pure returns (string memory) {
        uint256 badge = (uint256(seed) >> 32) % 5;

        if (rareMode) {
            if (badge == 0) return "UNHINGED";
            if (badge == 1) return "BRAINROT";
            if (badge == 2) return "TERMINAL";
            if (badge == 3) return "ALPHA LEAK";
            return "BAD IDEA";
        }

        if (badge == 0) return "POSTING";
        if (badge == 1) return "CERTIFIED";
        if (badge == 2) return "QUEUE MAXXED";
        if (badge == 3) return "ON-CHAIN";
        return "ABSURD";
    }

    // -------------------------------------------------------------------------
    //  Utility
    // -------------------------------------------------------------------------

    /// @dev Convert a `uint256` to its decimal string representation.
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
