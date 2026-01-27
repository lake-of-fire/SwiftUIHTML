//  Copyright © 2026 PRND. All rights reserved.

import Testing
import SwiftUI
@testable import SwiftUIHTML

struct UTF8ParsingTests {
    @Test
    func asciiWhitespaceTrim() throws {
        let input = " \t\nHello\r "
        let trimmed = ASCIIWhitespace.trim(input)
        #expect(trimmed == "Hello")
    }

    @Test
    func asciiWhitespaceTrimPreservesNBSP() throws {
        let nbsp = "\u{00A0}"
        let input = "\(nbsp)Hello\(nbsp)"
        let trimmed = ASCIIWhitespace.trim(input)
        #expect(trimmed == input)
    }

    @Test
    func cssStyleParsingUsesSlices() throws {
        let style = "  color :  #fff ;  "
        let parsed = CSSStyle(style: style)
        #expect(parsed?["color"]?.string == "#fff")
    }

    @Test
    func cssFontSizeParsingAsciiTrim() throws {
        let size = CSSFontUtility.parseSize(fromFontSize: " 12px ", baseSize: 10)
        #expect(size == 12)
    }

    @Test
    func hexColorParsingAsciiTrim() throws {
        let color = Color(cssString: "  #abc ")
        #expect(color != nil)
    }

    @Test
    func htmlChildTrimmingTextAscii() throws {
        let child = HTMLChild.trimmingText("  hello \n")
        #expect(child == .text("hello"))
    }

    @Test
    func attributeValueNumericParsing() throws {
        let intValue = AttributeValue(rawValue: "12px").int
        let floatValue = AttributeValue(rawValue: "12.5px").float
        let negative = AttributeValue(rawValue: "-3").int
        #expect(intValue == 12)
        #expect(floatValue == 12.5)
        #expect(negative == -3)
    }
}
