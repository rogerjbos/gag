// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Templates
 * @notice SVG template fragment library for Giggles and Gags on-chain NFT images.
 *         Each function returns a self-contained SVG fragment that is concatenated by the
 *         `Renderer` to build the final 1000 x 1000 SVG artwork.
 * @dev All functions are `pure` — no storage interaction. Colour palettes switch between
 *      a normal and a "rare" mode to give rare tokens a distinct visual identity.
 *      Normal palette: creams (#F4F1EA), golds (#FFC94A), cyans (#8BE9FD), darks (#2A2418).
 *      Rare palette:   ivory (#F7F1E3), orange-gold (#F2B632), orange-red (#FF7A59), darker (#3A2A08).
 */
library Templates {

    // -------------------------------------------------------------------------
    //  SVG root elements
    // -------------------------------------------------------------------------

    /// @notice Opening `<svg>` tag with a 1000 x 1000 viewBox and ARIA label.
    function svgHeader() internal pure returns (string memory) {
        return
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000" role="img" aria-label="Giggles and Gags">';
    }

    /// @notice Closing `</svg>` tag.
    function svgFooter() internal pure returns (string memory) {
        return "</svg>";
    }

    // -------------------------------------------------------------------------
    //  CSS styles
    // -------------------------------------------------------------------------

    /**
     * @notice Inline `<style>` block defining CSS classes for the SVG.
     * @dev Colours adapt to `rareMode`. The `variant` parameter adjusts font-weight and
     *      letter-spacing for visual variety:
     *        - 0 → 800 / 0px (Deadpan)
     *        - 1 → 900 / -1px (Posting, tighter)
     *        - 2 → 700 / 1px (Meltdown, wider)
     * @param variant  Text style variant (0, 1, or 2).
     * @param rareMode Whether to use the rare colour palette.
     */
    function textStyleTemplate(uint8 variant, bool rareMode) internal pure returns (string memory) {
        string memory fill = rareMode ? "#F7F1E3" : "#F4F1EA";
        string memory accent = rareMode ? "#F2B632" : "#FFC94A";
        string memory accent2 = rareMode ? "#FF7A59" : "#8BE9FD";
        string memory stroke = rareMode ? "#3A2A08" : "#2A2418";

        string memory fontWeight;
        string memory letterSpacing;

        if (variant == 0) {
            fontWeight = "800";
            letterSpacing = "0px";
        } else if (variant == 1) {
            fontWeight = "900";
            letterSpacing = "-1px";
        } else {
            fontWeight = "700";
            letterSpacing = "1px";
        }

        // Split into two halves to avoid stack-too-deep.
        string memory styles1 = string.concat(
            "<style>",
            ".bg-main{fill:#090909;}",
            ".stroke-main{stroke:", fill, ";stroke-width:6;fill:none;}",
            ".main-text{fill:", fill, ";font-family:monospace;font-weight:", fontWeight, ";letter-spacing:", letterSpacing, ";}"
        );
        return string.concat(
            styles1,
            ".caption-text{fill:", accent2, ";font-family:monospace;font-size:20px;letter-spacing:2px;}",
            ".footer-text{fill:", accent, ";font-family:monospace;font-size:22px;letter-spacing:3px;}",
            ".outline-text{paint-order:stroke;stroke:", stroke, ";stroke-width:8;stroke-linejoin:round;}",
            "</style>"
        );
    }

    // -------------------------------------------------------------------------
    //  Background variants
    // -------------------------------------------------------------------------

    /**
     * @notice Render one of three background variants based on `variant` index.
     * @param variant  0 = Terminal Grid, 1 = Doomwave, 2 = Forum Static.
     * @param seed     Hash seed used by Doomwave and Forum Static for pseudo-random positioning.
     * @param rareMode Whether to use the rare colour palette.
     */
    function backgroundTemplate(uint8 variant, bytes32 seed, bool rareMode) internal pure returns (string memory) {
        if (variant == 0) {
            return _terminalGrid(rareMode);
        } else if (variant == 1) {
            return _doomwave(seed, rareMode);
        } else {
            return _forumStatic(seed, rareMode);
        }
    }

    // -------------------------------------------------------------------------
    //  Frame variants
    // -------------------------------------------------------------------------

    /**
     * @notice Render one of three frame variants based on `variant` index.
     * @param variant  0 = Soft Coping, 1 = Double Down, 2 = Badge of Shame.
     * @param rareMode Whether to use the rare colour palette.
     */
    function frameTemplate(uint8 variant, bool rareMode) internal pure returns (string memory) {
        if (variant == 0) {
            return _softCopingFrame(rareMode);
        } else if (variant == 1) {
            return _doubleDownFrame(rareMode);
        } else {
            return _badgeOfShameFrame(rareMode);
        }
    }

    // -------------------------------------------------------------------------
    //  Fixed UI elements
    // -------------------------------------------------------------------------

    /// @notice ENS domain label displayed at the top-centre of the SVG.
    function topEnsDomain() internal pure returns (string memory) {
        return '<text x="500" y="34" text-anchor="middle" class="footer-text">gigglesandgags.eth</text>';
    }

    /**
     * @notice GaG branding element: two circles and "GaG" text, positioned top-left inside the frame.
     * @param rareMode Whether to use the rare colour palette.
     */
    function logoTemplate(bool rareMode) internal pure returns (string memory) {
        string memory accent = rareMode ? "#F2B632" : "#FFC94A";
        string memory fill = rareMode ? "#F7F1E3" : "#F4F1EA";

        return string.concat(
            '<g transform="translate(108 108)">',
                '<circle cx="0" cy="0" r="18" fill="none" stroke="', accent, '" stroke-width="4"/>',
                '<circle cx="42" cy="0" r="18" fill="none" stroke="', accent, '" stroke-width="4"/>',
                '<text x="84" y="8" fill="', fill, '" font-family="monospace" font-size="30" font-weight="900">GaG</text>',
            "</g>"
        );
    }

    /**
     * @notice Top-right badge pill with a label (e.g. "POSTING", "UNHINGED").
     * @param label    The badge text.
     * @param rareMode Whether to use the rare colour palette.
     */
    function badgeTemplate(string memory label, bool rareMode) internal pure returns (string memory) {
        string memory fill = rareMode ? "#F2B632" : "#FFC94A";
        return string.concat(
            '<g transform="translate(740 90)">',
                '<rect x="0" y="0" width="170" height="44" rx="22" fill="', fill, '"/>',
                '<text x="85" y="28" text-anchor="middle" fill="#111111" font-family="monospace" font-size="18" font-weight="900">',
                    label,
                "</text>",
            "</g>"
        );
    }

    // -------------------------------------------------------------------------
    //  Text nodes
    // -------------------------------------------------------------------------

    /**
     * @notice Build an SVG `<text>` element for a single-line message layout.
     * @param escapedText XML-escaped message text.
     * @param fontSize    Font size in pixels.
     * @param variant     Text variant (variant 2 uses a slightly higher y-position).
     */
    function buildSingleLineTextNode(
        string memory escapedText,
        uint256 fontSize,
        uint8 variant
    ) internal pure returns (string memory) {
        // Variant 2 ("Meltdown") shifts the text up slightly for visual balance.
        string memory y = variant == 2 ? "484" : "492";

        return string.concat(
            '<text x="500" y="', y, '" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="',
            _toString(fontSize),
            '">',
            escapedText,
            "</text>"
        );
    }

    /**
     * @notice Build two `<text>` elements for a two-line message layout.
     * @dev Line 1 is centred at y=448, line 2 at y=560, giving a 112px vertical gap.
     * @param escapedLine1 XML-escaped first line.
     * @param escapedLine2 XML-escaped second line.
     * @param fontSize     Font size in pixels (applied to both lines).
     */
    function buildTwoLineTextNode(
        string memory escapedLine1,
        string memory escapedLine2,
        uint256 fontSize
    ) internal pure returns (string memory) {
        return string.concat(
            '<text x="500" y="448" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="',
            _toString(fontSize),
            '">',
            escapedLine1,
            "</text>",
            '<text x="500" y="560" text-anchor="middle" dominant-baseline="middle" class="main-text outline-text" font-size="',
            _toString(fontSize),
            '">',
            escapedLine2,
            "</text>"
        );
    }

    /**
     * @notice Caption text line rendered below the main message area (y=875).
     * @param caption The caption string (always "randomly assigned chaos").
     */
    function captionLine(string memory caption) internal pure returns (string memory) {
        return string.concat(
            '<text x="500" y="875" text-anchor="middle" class="caption-text">',
            caption,
            "</text>"
        );
    }

    /// @notice Fixed "GIGGLES AND GAGS" footer text at the bottom-centre (y=982).
    function footerLabel() internal pure returns (string memory) {
        return '<text x="500" y="982" text-anchor="middle" class="footer-text">GIGGLES AND GAGS</text>';
    }

    /**
     * @notice Token ID label displayed at the bottom-left (x=76, y=982).
     * @param tokenId The numeric token ID to display.
     */
    function tokenIdLabel(uint256 tokenId) internal pure returns (string memory) {
        return string.concat(
            '<text x="76" y="982" text-anchor="start" class="footer-text">#',
            _toString(tokenId),
            "</text>"
        );
    }

    // -------------------------------------------------------------------------
    //  Private background helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Terminal Grid background: a dark inner rectangle with a grid of vertical and
     *      horizontal lines at low opacity, giving a retro terminal aesthetic.
     */
    function _terminalGrid(bool rareMode) private pure returns (string memory) {
        string memory secondaryFill = rareMode ? "#120F08" : "#111111";
        string memory accent = rareMode ? "#F2B632" : "#8BE9FD";

        return string.concat(
            '<rect width="1000" height="1000" class="bg-main"/>',
            '<rect x="40" y="40" width="920" height="920" fill="', secondaryFill, '"/>',
            '<g opacity="0.16" stroke="', accent, '" stroke-width="4" fill="none">',
                '<path d="M200 70V900"/>',
                '<path d="M400 70V900"/>',
                '<path d="M600 70V900"/>',
                '<path d="M800 70V900"/>',
                '<path d="M70 220H930"/>',
                '<path d="M70 420H930"/>',
                '<path d="M70 620H930"/>',
                '<path d="M70 820H930"/>',
            "</g>"
        );
    }

    /**
     * @dev Doomwave background: three sinusoidal-ish SVG curves with pseudo-random
     *      y-offsets derived from different byte ranges of `seed`.
     */
    function _doomwave(bytes32 seed, bool rareMode) private pure returns (string memory) {
        string memory accent = rareMode ? "#F2B632" : "#7A5A20";

        // Derive pseudo-random y-offsets for the three wave paths.
        uint256 a = 180 + (uint256(seed) % 40);
        uint256 b = 510 + (uint256(seed >> 8) % 30);
        uint256 c = 770 - (uint256(seed >> 16) % 40);

        // Build each wave path separately to avoid stack-too-deep.
        string memory wave1 = _wavePath(a, a + 70, a - 60, a, a + 75, a);
        string memory wave2 = _wavePath(b, b - 50, b + 45, b, b - 60, b);
        string memory wave3 = _wavePath(c, c + 50, c - 35, c, c + 65, c);

        return string.concat(
            '<rect width="1000" height="1000" class="bg-main"/>',
            '<g opacity="0.45" stroke="', accent, '" stroke-width="6" fill="none">',
            wave1, wave2, wave3,
            "</g>"
        );
    }

    /**
     * @dev Build a single SVG cubic-bezier wave `<path>` element.
     *      Extracted from `_doomwave` to reduce stack depth per function.
     */
    function _wavePath(
        uint256 y0, uint256 c1y, uint256 c2y,
        uint256 midY, uint256 s1y, uint256 endY
    ) private pure returns (string memory) {
        return string.concat(
            '<path d="M80 ', _toString(y0),
            ' C240 ', _toString(c1y), ', 360 ', _toString(c2y),
            ', 520 ', _toString(midY),
            ' S760 ', _toString(s1y), ', 920 ', _toString(endY),
            '"/>'
        );
    }

    /**
     * @dev Forum Static background: 16 randomly-positioned dots (circles) with sizes
     *      and positions derived from the seed via per-dot keccak hashes.
     */
    function _forumStatic(bytes32 seed, bool rareMode) private pure returns (string memory) {
        string memory accent = rareMode ? "#FF7A59" : "#A78BFA";

        // Build dot batches separately to avoid stack-too-deep.
        string memory dots1 = string.concat(
            _dot(seed, 0), _dot(seed, 1), _dot(seed, 2), _dot(seed, 3),
            _dot(seed, 4), _dot(seed, 5), _dot(seed, 6), _dot(seed, 7)
        );
        string memory dots2 = string.concat(
            _dot(seed, 8), _dot(seed, 9), _dot(seed, 10), _dot(seed, 11),
            _dot(seed, 12), _dot(seed, 13), _dot(seed, 14), _dot(seed, 15)
        );

        return string.concat(
            '<rect width="1000" height="1000" class="bg-main"/>',
            '<g opacity="0.38" fill="', accent, '">',
            dots1, dots2,
            "</g>"
        );
    }

    // -------------------------------------------------------------------------
    //  Private frame helpers
    // -------------------------------------------------------------------------

    /// @dev Soft Coping frame: rounded outer stroke rect with a thin accent inner rect.
    function _softCopingFrame(bool rareMode) private pure returns (string memory) {
        string memory accent = rareMode ? "#F2B632" : "#FFC94A";

        return string.concat(
            '<rect x="52" y="52" width="896" height="896" rx="36" class="stroke-main"/>',
            '<rect x="74" y="74" width="852" height="836" rx="28" stroke="', accent, '" stroke-width="2" fill="none" opacity="0.55"/>'
        );
    }

    /// @dev Double Down frame: two nested rounded rects with tighter radii.
    function _doubleDownFrame(bool rareMode) private pure returns (string memory) {
        string memory accent = rareMode ? "#FF7A59" : "#A78BFA";

        return string.concat(
            '<rect x="48" y="48" width="904" height="904" rx="18" class="stroke-main"/>',
            '<rect x="82" y="82" width="836" height="828" rx="12" stroke="', accent, '" stroke-width="4" fill="none" opacity="0.72"/>'
        );
    }

    /// @dev Badge of Shame frame: outer stroke rect with top and bottom horizontal accent bars.
    function _badgeOfShameFrame(bool rareMode) private pure returns (string memory) {
        string memory accent = rareMode ? "#F2B632" : "#FFC94A";

        return string.concat(
            '<rect x="56" y="56" width="888" height="888" rx="12" class="stroke-main"/>',
            '<path d="M180 74H820" stroke="', accent, '" stroke-width="8" opacity="0.8"/>',
            '<path d="M180 908H820" stroke="', accent, '" stroke-width="8" opacity="0.8"/>'
        );
    }

    // -------------------------------------------------------------------------
    //  Private utility helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Generate a single `<circle>` SVG element with pseudo-random position and radius.
     *      Position is derived from `keccak256(seed, "x"/"y"/"r", i)` to keep each dot
     *      deterministic but unique per seed and index.
     * @param seed The render seed (keccak256 of the message).
     * @param i    The dot index (0–15).
     */
    function _dot(bytes32 seed, uint256 i) private pure returns (string memory) {
        uint256 x = 90 + (uint256(keccak256(abi.encodePacked(seed, "x", i))) % 820);
        uint256 y = 120 + (uint256(keccak256(abi.encodePacked(seed, "y", i))) % 720);
        uint256 r = 3 + (uint256(keccak256(abi.encodePacked(seed, "r", i))) % 6);

        return string.concat(
            '<circle cx="', _toString(x), '" cy="', _toString(y), '" r="', _toString(r), '"/>'
        );
    }

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
