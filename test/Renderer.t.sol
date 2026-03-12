// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Renderer} from "../src/render/Renderer.sol";
import {Metadata} from "../src/render/Metadata.sol";

/// @title RendererTest
/// @notice Unit and fuzz tests for the Renderer and Metadata libraries.
///         Validates SVG rendering, trait derivation, layout splitting, and metadata generation.
contract RendererTest is Test {

    // =========================================================================
    //  renderSVG — Basic Rendering
    // =========================================================================

    function test_renderSVG_shortText() public pure {
        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(0, "gm");
        assertTrue(bytes(svg).length > 100, "SVG should be non-trivial");
        assertFalse(data.twoLines, "Short text should be single-line");
        assertEq(data.length, 2);
    }

    function test_renderSVG_mediumText() public pure {
        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(1, "hello world this is a test");
        assertTrue(bytes(svg).length > 100);
        // May be two lines depending on width score.
        assertTrue(data.length == 26);
    }

    function test_renderSVG_maxLengthText() public pure {
        string memory maxMsg = "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghij";
        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(42, maxMsg);
        assertTrue(bytes(svg).length > 100);
        assertTrue(data.twoLines, "Max-length text should be two lines");
        assertEq(data.length, 64);
    }

    function test_renderSVG_singleChar() public pure {
        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(99, "X");
        assertTrue(bytes(svg).length > 100);
        assertFalse(data.twoLines);
        assertEq(data.length, 1);
    }

    function test_renderSVG_containsSVGTags() public pure {
        (string memory svg,) = Renderer.renderSVG(0, "hello");
        bytes memory b = bytes(svg);
        // Should start with <svg and end with </svg>
        assertEq(b[0], "<");
        assertEq(b[1], "s");
        assertEq(b[2], "v");
        assertEq(b[3], "g");
    }

    // =========================================================================
    //  deriveRenderData — Trait Derivation
    // =========================================================================

    function test_deriveRenderData_deterministic() public pure {
        Renderer.RenderData memory data1 = Renderer.deriveRenderData("test message");
        Renderer.RenderData memory data2 = Renderer.deriveRenderData("test message");

        assertEq(data1.seed, data2.seed);
        assertEq(data1.bgVariant, data2.bgVariant);
        assertEq(data1.frameVariant, data2.frameVariant);
        assertEq(data1.textVariant, data2.textVariant);
        assertEq(data1.rareMode, data2.rareMode);
        assertEq(data1.fontSize, data2.fontSize);
    }

    function test_deriveRenderData_differentTextDifferentSeeds() public pure {
        Renderer.RenderData memory data1 = Renderer.deriveRenderData("hello");
        Renderer.RenderData memory data2 = Renderer.deriveRenderData("world");

        assertTrue(data1.seed != data2.seed, "Different texts should have different seeds");
    }

    function test_deriveRenderData_bgVariantBounded() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("variant test");
        assertTrue(data.bgVariant < 3);
    }

    function test_deriveRenderData_frameVariantBounded() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("frame test");
        assertTrue(data.frameVariant < 3);
    }

    function test_deriveRenderData_textVariantBounded() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("text test");
        assertTrue(data.textVariant < 3);
    }

    function test_deriveRenderData_captionIsFixed() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("caption test");
        assertEq(data.caption, "randomly assigned chaos");
    }

    function test_deriveRenderData_backgroundNames() public pure {
        // Test all three background names exist in the possible outputs.
        // We'll check a few messages and verify names are valid.
        string[3] memory validBgNames = ["Terminal Grid", "Doomwave", "Forum Static"];

        for (uint256 i = 0; i < 20; i++) {
            bytes memory msg_ = abi.encodePacked("bg", i);
            Renderer.RenderData memory data = Renderer.deriveRenderData(string(msg_));
            bool valid = false;
            for (uint256 j = 0; j < 3; j++) {
                if (keccak256(bytes(data.backgroundName)) == keccak256(bytes(validBgNames[j]))) {
                    valid = true;
                    break;
                }
            }
            assertTrue(valid, "Background name should be one of the three variants");
        }
    }

    function test_deriveRenderData_frameNames() public pure {
        string[3] memory validFrameNames = ["Soft Coping", "Double Down", "Badge of Shame"];

        for (uint256 i = 0; i < 20; i++) {
            Renderer.RenderData memory data = Renderer.deriveRenderData(
                string(abi.encodePacked("frame", i))
            );
            bool valid = false;
            for (uint256 j = 0; j < 3; j++) {
                if (keccak256(bytes(data.frameName)) == keccak256(bytes(validFrameNames[j]))) {
                    valid = true;
                    break;
                }
            }
            assertTrue(valid, "Frame name should be one of the three variants");
        }
    }

    function test_deriveRenderData_toneNames() public pure {
        string[3] memory validToneNames = ["Deadpan", "Posting", "Meltdown"];

        for (uint256 i = 0; i < 20; i++) {
            Renderer.RenderData memory data = Renderer.deriveRenderData(
                string(abi.encodePacked("tone", i))
            );
            bool valid = false;
            for (uint256 j = 0; j < 3; j++) {
                if (keccak256(bytes(data.toneName)) == keccak256(bytes(validToneNames[j]))) {
                    valid = true;
                    break;
                }
            }
            assertTrue(valid, "Tone name should be one of the three variants");
        }
    }

    function test_deriveRenderData_moodNames() public pure {
        string[4] memory validMoodNames = ["Giggly", "Snarky", "Spicy", "Terminal"];

        for (uint256 i = 0; i < 30; i++) {
            Renderer.RenderData memory data = Renderer.deriveRenderData(
                string(abi.encodePacked("mood", i))
            );
            bool valid = false;
            for (uint256 j = 0; j < 4; j++) {
                if (keccak256(bytes(data.moodName)) == keccak256(bytes(validMoodNames[j]))) {
                    valid = true;
                    break;
                }
            }
            assertTrue(valid, "Mood name should be one of the four variants");
        }
    }

    // =========================================================================
    //  Layout — Single-Line vs Two-Line
    // =========================================================================

    function test_layout_veryShortText_singleLine() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("hi");
        assertFalse(data.twoLines);
    }

    function test_layout_longText_twoLines() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData(
            "this is a much longer message that should wrap"
        );
        assertTrue(data.twoLines);
    }

    function test_layout_20charNarrow_singleLine() public pure {
        // 20 narrow chars: all "i" characters (width score = 4 * 20 = 80 <= 110).
        Renderer.RenderData memory data = Renderer.deriveRenderData("iiiiiiiiiiiiiiiiiiii");
        assertFalse(data.twoLines);
    }

    function test_layout_20charWide_twoLines() public pure {
        // 20 wide chars like "W" (width score = 9 * 20 = 180 > 110).
        // But also length > 20 check... "WWWWWWWWWWWWWWWWWWWW" is exactly 20 chars
        // but score = 180 which is > 110, so it wraps.
        Renderer.RenderData memory data = Renderer.deriveRenderData("WWWWWWWWWWWWWWWWWWWW");
        assertTrue(data.twoLines);
    }

    function test_layout_fontSizeDecreases_withLength() public pure {
        Renderer.RenderData memory short_ = Renderer.deriveRenderData("hi");
        Renderer.RenderData memory long_ = Renderer.deriveRenderData(
            "this message is intentionally very long to test font shrinking"
        );
        assertTrue(short_.fontSize > long_.fontSize, "Longer text should have smaller font");
    }

    function test_layout_twoLines_bothLinesPopulated() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("hello beautiful world out there");
        if (data.twoLines) {
            assertTrue(bytes(data.line1).length > 0, "Line 1 should not be empty");
            assertTrue(bytes(data.line2).length > 0, "Line 2 should not be empty");
        }
    }

    function test_layout_noSpaceText_hardSplit() public pure {
        // A long single word with no spaces — should hard-split at midpoint.
        Renderer.RenderData memory data = Renderer.deriveRenderData("abcdefghijklmnopqrstuvwxyz");
        assertTrue(data.twoLines, "26-char single word should wrap");
        assertTrue(bytes(data.line1).length > 0);
        assertTrue(bytes(data.line2).length > 0);
    }

    // =========================================================================
    //  attributesJSON
    // =========================================================================

    function test_attributesJSON_returnsValidJSON() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("attributes test");
        string memory json = Renderer.attributesJSON(data);

        bytes memory b = bytes(json);
        // Should start with [ and end with ]
        assertEq(b[0], "[");
        assertEq(b[b.length - 1], "]");
    }

    function test_attributesJSON_containsAllTraits() public pure {
        Renderer.RenderData memory data = Renderer.deriveRenderData("traits test");
        string memory json = Renderer.attributesJSON(data);

        // Check that all expected trait names are present.
        assertTrue(_contains(json, "Background"));
        assertTrue(_contains(json, "Frame"));
        assertTrue(_contains(json, "Tone"));
        assertTrue(_contains(json, "Mood"));
        assertTrue(_contains(json, "Badge"));
        assertTrue(_contains(json, "Caption"));
        assertTrue(_contains(json, "Layout"));
        assertTrue(_contains(json, "Rare"));
        assertTrue(_contains(json, "Length"));
    }

    // =========================================================================
    //  Metadata.buildTokenURI
    // =========================================================================

    function test_buildTokenURI_returnsDataURI() public pure {
        string memory uri = Metadata.buildTokenURI("Giggles and Gags", 0, "metadata test");
        bytes memory b = bytes(uri);

        // Should start with "data:application/json;base64,"
        assertEq(b[0], "d");
        assertEq(b[1], "a");
        assertEq(b[2], "t");
        assertEq(b[3], "a");
        assertEq(b[4], ":");
        assertTrue(b.length > 200, "URI should be substantial");
    }

    function test_buildTokenURI_differentTokenIdsDifferentNames() public pure {
        string memory uri0 = Metadata.buildTokenURI("GaG", 0, "hello");
        string memory uri1 = Metadata.buildTokenURI("GaG", 1, "hello");

        // Same text but different token IDs → different URIs (name includes token ID).
        assertTrue(
            keccak256(bytes(uri0)) != keccak256(bytes(uri1)),
            "Different token IDs should produce different URIs"
        );
    }

    function test_buildTokenURI_differentTextsDifferentURIs() public pure {
        string memory uri1 = Metadata.buildTokenURI("GaG", 0, "hello");
        string memory uri2 = Metadata.buildTokenURI("GaG", 0, "world");

        assertTrue(
            keccak256(bytes(uri1)) != keccak256(bytes(uri2)),
            "Different texts should produce different URIs"
        );
    }

    // =========================================================================
    //  Fuzz: Renderer
    // =========================================================================

    /// @notice Fuzz: renderSVG should never revert for valid ASCII strings.
    function testFuzz_renderSVG_neverReverts(uint8 length, uint256 tokenId) public pure {
        length = uint8(bound(length, 1, 64));

        // Build a valid ASCII string.
        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = bytes1(uint8(0x61 + (i % 26)));
        }

        (string memory svg, Renderer.RenderData memory data) = Renderer.renderSVG(tokenId, string(b));
        assertTrue(bytes(svg).length > 0);
        assertTrue(data.fontSize > 0, "Font size should be positive");
    }

    /// @notice Fuzz: all derived variants are within bounds.
    function testFuzz_deriveRenderData_variantsBounded(string memory text) public pure {
        // Only test non-empty strings.
        vm.assume(bytes(text).length > 0 && bytes(text).length <= 64);

        Renderer.RenderData memory data = Renderer.deriveRenderData(text);
        assertTrue(data.bgVariant < 3);
        assertTrue(data.frameVariant < 3);
        assertTrue(data.textVariant < 3);
        assertTrue(data.fontSize > 0);
    }

    /// @notice Fuzz: font size is always within the expected range (roughly 38–114 px).
    function testFuzz_fontSize_inRange(uint8 length) public pure {
        length = uint8(bound(length, 1, 64));

        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = bytes1(uint8(0x61 + (i % 26)));
        }

        Renderer.RenderData memory data = Renderer.deriveRenderData(string(b));
        // Font sizes range from 36 (two-line base 52, variant 2 -2px, length>=60 shrink -14px)
        // to 114 (single-line base 112, variant 1 +2px).
        assertTrue(data.fontSize >= 36 && data.fontSize <= 114, "Font size out of expected range");
    }

    /// @notice Fuzz: layout split with spaces produces valid lines (prefix-sum coverage).
    function testFuzz_layout_splitWithSpaces(uint8 wordCount) public pure {
        wordCount = uint8(bound(wordCount, 2, 8));

        // Build a multi-word string like "aaa bbb ccc".
        bytes memory buf = new bytes(0);
        for (uint256 w = 0; w < wordCount; w++) {
            if (w > 0) {
                buf = abi.encodePacked(buf, " ");
            }
            // Each word is 3–5 chars of lowercase letters.
            uint256 wordLen = 3 + (w % 3);
            bytes memory word = new bytes(wordLen);
            for (uint256 c = 0; c < wordLen; c++) {
                word[c] = bytes1(uint8(0x61 + ((w * 5 + c) % 26)));
            }
            buf = abi.encodePacked(buf, word);
        }

        // Truncate to 64 if needed.
        if (buf.length > 64) {
            bytes memory truncated = new bytes(64);
            for (uint256 i = 0; i < 64; i++) {
                truncated[i] = buf[i];
            }
            buf = truncated;
        }

        string memory text = string(buf);
        Renderer.RenderData memory data = Renderer.deriveRenderData(text);

        // Both lines should be non-empty if two-line layout was chosen.
        if (data.twoLines) {
            assertTrue(bytes(data.line1).length > 0, "Line 1 should not be empty");
            assertTrue(bytes(data.line2).length > 0, "Line 2 should not be empty");
        }
        assertTrue(data.fontSize > 0, "Font size should be positive");
    }

    /// @notice Prefix-sum yields same split result as the original approach.
    ///         Since both are internal, we verify determinism: same text → same layout.
    function test_layout_prefixSumDeterminism() public pure {
        string memory text = "hello beautiful wonderful world out there today";
        Renderer.RenderData memory d1 = Renderer.deriveRenderData(text);
        Renderer.RenderData memory d2 = Renderer.deriveRenderData(text);

        assertEq(d1.twoLines, d2.twoLines);
        assertEq(keccak256(bytes(d1.line1)), keccak256(bytes(d2.line1)));
        assertEq(keccak256(bytes(d1.line2)), keccak256(bytes(d2.line2)));
        assertEq(d1.fontSize, d2.fontSize);
    }

    /// @notice Known split: "aaaa bbbb" has one space at index 4.
    ///         Should split there: "aaaa" | "bbbb".
    function test_layout_knownSplit_singleSpace() public pure {
        // "aaaa bbbbbbbbbbbbbbbbbbbb" — 25 chars, score > 110, so two-line.
        string memory text = "aaaa bbbbbbbbbbbbbbbbbbbb";
        Renderer.RenderData memory data = Renderer.deriveRenderData(text);

        assertTrue(data.twoLines, "Should be two-line layout");
        assertEq(keccak256(bytes(data.line1)), keccak256(bytes("aaaa")));
        assertEq(keccak256(bytes(data.line2)), keccak256(bytes("bbbbbbbbbbbbbbbbbbbb")));
    }

    /// @notice Wide characters produce a split even on shorter text.
    function test_layout_wideChars_forceTwoLine() public pure {
        // "WWWWW MMMMM" — 11 chars, score = 5*9 + 4 + 5*9 = 94.
        // Length = 11 which is <= 20, and score = 94 which is <= 110.
        // So this stays single-line.
        Renderer.RenderData memory data = Renderer.deriveRenderData("WWWWW MMMMM");
        assertFalse(data.twoLines, "Short wide text still fits single-line");

        // Longer wide text should force two lines.
        data = Renderer.deriveRenderData("WWWWWWW MMMMMMM OOOOOOO");
        assertTrue(data.twoLines, "Longer wide text should wrap");
    }

    /// @notice Fuzz: buildTokenURI never reverts for valid inputs.
    function testFuzz_buildTokenURI_neverReverts(uint256 tokenId, uint8 length) public pure {
        length = uint8(bound(length, 1, 64));

        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = bytes1(uint8(0x61 + (i % 26)));
        }

        string memory uri = Metadata.buildTokenURI("Test", tokenId, string(b));
        assertTrue(bytes(uri).length > 0);
    }

    // =========================================================================
    //  Helpers
    // =========================================================================

    /// @dev Check if `haystack` contains `needle` as a substring.
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
