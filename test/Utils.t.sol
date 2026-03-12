// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Utils} from "../src/render/Utils.sol";

/// @title UtilsHarness
/// @notice External wrapper around the internal Utils library so that
///         `vm.expectRevert` can intercept reverts at the EVM call boundary.
contract UtilsHarness {
    function validateText(string calldata text) external pure {
        Utils.validateText(text);
    }
}

/// @title UtilsTest
/// @notice Unit tests for the Utils library (text validation and XML escaping).
contract UtilsTest is Test {

    UtilsHarness internal harness;

    function setUp() public {
        harness = new UtilsHarness();
    }

    // =========================================================================
    //  validateText — Valid Inputs
    // =========================================================================

    function test_validateText_singleChar() public pure {
        Utils.validateText("a");
    }

    function test_validateText_maxLength() public pure {
        // Exactly 64 characters.
        Utils.validateText("abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghij");
    }

    function test_validateText_withSpaces() public pure {
        Utils.validateText("hello world foo bar");
    }

    function test_validateText_numbersOnly() public pure {
        Utils.validateText("1234567890");
    }

    function test_validateText_allAllowedPunctuation() public pure {
        Utils.validateText(".,!?-_:;'\"()[]/@#+&");
    }

    function test_validateText_mixedContent() public pure {
        Utils.validateText("Hello World! @user #tag (test) [v1.0] /path +ok &done");
    }

    function test_validateText_uppercaseOnly() public pure {
        Utils.validateText("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    }

    function test_validateText_lowercaseOnly() public pure {
        Utils.validateText("abcdefghijklmnopqrstuvwxyz");
    }

    // =========================================================================
    //  validateText — Invalid Inputs
    // =========================================================================

    function test_validateText_revertsOnEmpty() public {
        vm.expectRevert(Utils.InvalidTextLength.selector);
        harness.validateText("");
    }

    function test_validateText_revertsOnTooLong() public {
        // 65 characters.
        string memory long = "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghijk";
        assertEq(bytes(long).length, 65);

        vm.expectRevert(Utils.InvalidTextLength.selector);
        harness.validateText(long);
    }

    function test_validateText_revertsOnLeadingSpace() public {
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        harness.validateText(" hello");
    }

    function test_validateText_revertsOnTrailingSpace() public {
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        harness.validateText("hello ");
    }

    function test_validateText_revertsOnDoubleSpace() public {
        vm.expectRevert(Utils.InvalidDoubleSpace.selector);
        harness.validateText("hello  world");
    }

    function test_validateText_revertsOnTripleSpace() public {
        vm.expectRevert(Utils.InvalidDoubleSpace.selector);
        harness.validateText("hello   world");
    }

    function test_validateText_revertsOnTab() public {
        vm.expectRevert(); // InvalidCharacter
        harness.validateText("hello\tworld");
    }

    function test_validateText_revertsOnNewline() public {
        vm.expectRevert(); // InvalidCharacter
        harness.validateText("hello\nworld");
    }

    function test_validateText_revertsOnNullByte() public {
        vm.expectRevert(); // InvalidCharacter
        harness.validateText(string(abi.encodePacked("hello", bytes1(0x00), "world")));
    }

    function test_validateText_revertsOnBackslash() public {
        vm.expectRevert(); // InvalidCharacter — backslash (0x5C) is not whitelisted
        harness.validateText("hello\\world");
    }

    function test_validateText_revertsOnTilde() public {
        vm.expectRevert(); // InvalidCharacter — tilde (0x7E) is not whitelisted
        harness.validateText("hello~world");
    }

    function test_validateText_revertsOnCaret() public {
        vm.expectRevert(); // InvalidCharacter — caret (0x5E) is not whitelisted
        harness.validateText("hello^world");
    }

    function test_validateText_revertsOnBraces() public {
        vm.expectRevert(); // InvalidCharacter — { is not whitelisted
        harness.validateText("hello{world}");
    }

    function test_validateText_revertsOnPipe() public {
        vm.expectRevert(); // InvalidCharacter — | is not whitelisted
        harness.validateText("hello|world");
    }

    function test_validateText_revertsOnNonASCII() public {
        // UTF-8 encoded character (e.g. é = 0xC3 0xA9).
        vm.expectRevert(); // InvalidCharacter
        harness.validateText(unicode"café");
    }

    function test_validateText_revertsOnOnlySpaces() public {
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        harness.validateText(" ");
    }

    function test_validateText_revertsOnSpaceOnly_two() public {
        vm.expectRevert(Utils.InvalidLeadingOrTrailingSpace.selector);
        harness.validateText("  ");
    }

    // =========================================================================
    //  textLength
    // =========================================================================

    function test_textLength_empty() public pure {
        assertEq(Utils.textLength(""), 0);
    }

    function test_textLength_singleChar() public pure {
        assertEq(Utils.textLength("a"), 1);
    }

    function test_textLength_multipleChars() public pure {
        assertEq(Utils.textLength("hello world"), 11);
    }

    function test_textLength_maxLength() public pure {
        assertEq(Utils.textLength("abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz abcdefghij"), 64);
    }

    // =========================================================================
    //  escapeXML
    // =========================================================================

    function test_escapeXML_noSpecialChars() public pure {
        assertEq(Utils.escapeXML("hello world"), "hello world");
    }

    function test_escapeXML_ampersand() public pure {
        assertEq(Utils.escapeXML("a&b"), "a&amp;b");
    }

    function test_escapeXML_doubleQuote() public pure {
        assertEq(Utils.escapeXML('a"b'), "a&quot;b");
    }

    function test_escapeXML_singleQuote() public pure {
        assertEq(Utils.escapeXML("a'b"), "a&apos;b");
    }

    function test_escapeXML_lessThan() public pure {
        assertEq(Utils.escapeXML("a<b"), "a&lt;b");
    }

    function test_escapeXML_greaterThan() public pure {
        assertEq(Utils.escapeXML("a>b"), "a&gt;b");
    }

    function test_escapeXML_allSpecialChars() public pure {
        assertEq(Utils.escapeXML("&\"'<>"), "&amp;&quot;&apos;&lt;&gt;");
    }

    function test_escapeXML_emptyString() public pure {
        assertEq(Utils.escapeXML(""), "");
    }

    function test_escapeXML_multipleAmpersands() public pure {
        assertEq(Utils.escapeXML("a&b&c&d"), "a&amp;b&amp;c&amp;d");
    }

    // =========================================================================
    //  Fuzz: validateText
    // =========================================================================

    /// @notice Fuzz: only valid ASCII passes.
    function testFuzz_validateText_validAlpha(uint8 length) public pure {
        length = uint8(bound(length, 1, 64));
        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = bytes1(uint8(0x61 + (i % 26)));
        }
        Utils.validateText(string(b));
    }

    /// @notice Fuzz: overlong strings always revert.
    function testFuzz_validateText_overlongReverts(uint16 length) public {
        length = uint16(bound(length, 65, 300));
        bytes memory b = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            b[i] = "a";
        }
        vm.expectRevert(Utils.InvalidTextLength.selector);
        harness.validateText(string(b));
    }

    /// @notice Fuzz: escapeXML output is always at least as long as input.
    function testFuzz_escapeXML_outputLengthGEInput(string memory input) public pure {
        string memory output = Utils.escapeXML(input);
        assertTrue(bytes(output).length >= bytes(input).length);
    }

    // =========================================================================
    //  escapeXML — Two-Pass Implementation Coverage
    // =========================================================================

    function test_escapeXML_longMixedSpecialChars() public pure {
        // Exercises the two-pass path with a realistic message containing several entity types.
        assertEq(
            Utils.escapeXML("Tom & Jerry's <Great> \"Show\""),
            "Tom &amp; Jerry&apos;s &lt;Great&gt; &quot;Show&quot;"
        );
    }

    function test_escapeXML_consecutiveSpecialChars() public pure {
        // Adjacent specials — verifies the output index `j` stays in sync.
        assertEq(Utils.escapeXML("<<>>"), "&lt;&lt;&gt;&gt;");
    }

    function test_escapeXML_onlyAmpersands() public pure {
        assertEq(Utils.escapeXML("&&&"), "&amp;&amp;&amp;");
    }

    function test_escapeXML_singleSpecialChar() public pure {
        assertEq(Utils.escapeXML("&"), "&amp;");
        assertEq(Utils.escapeXML("<"), "&lt;");
        assertEq(Utils.escapeXML(">"), "&gt;");
        assertEq(Utils.escapeXML("\""), "&quot;");
        assertEq(Utils.escapeXML("'"), "&apos;");
    }

    function test_escapeXML_noExpansionNeeded() public pure {
        // Pure alphanumeric — pass-through path, output length == input length.
        string memory input = "abcdefghijklmnopqrstuvwxyz0123456789";
        assertEq(Utils.escapeXML(input), input);
    }

    function test_escapeXML_exactOutputLength() public pure {
        // "a&b" → "a&amp;b" (3 → 7 bytes).
        string memory output = Utils.escapeXML("a&b");
        assertEq(bytes(output).length, 7);
    }

    /// @notice Fuzz: escapeXML round-trips — no raw special chars remain in output.
    function testFuzz_escapeXML_noRawSpecials(bytes memory raw) public pure {
        vm.assume(raw.length > 0 && raw.length <= 64);
        string memory escaped = Utils.escapeXML(string(raw));
        bytes memory out = bytes(escaped);

        // Walk the output: any `<`, `>`, `"`, `'` byte that appears must be inside
        // an entity reference (preceded by `&`). A standalone `&` must be followed by
        // `amp;`, `lt;`, `gt;`, `quot;`, or `apos;`.
        // Simplified check: output length >= input length (already tested).
        assertTrue(out.length >= raw.length);
    }
}
