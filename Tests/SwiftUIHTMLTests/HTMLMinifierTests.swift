//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI
import Testing
@testable import SwiftUIHTML

struct HTMLMinifierTests {
    @Test("Minify removes line breaks after <br>")
    func minify_removesLineBreaksAfterBR() {
        let html = "<p>Hello<br>   \nWorld</p>"
        let result = HTMLMinifier.minify(html)
        #expect(result == "<p>Hello<br>World</p>")
    }

    @Test("Minify removes tag-only newlines")
    func minify_removesNewlinesBetweenTags() {
        let html = "<p>One</p>\n   <p>Two</p>"
        let result = HTMLMinifier.minify(html)
        #expect(result == "<p>One</p><p>Two</p>")
    }

    @Test("Minify replaces pure whitespace between tags with &nbsp;")
    func minify_replacesWhitespaceBetweenTagsWithNbsp() {
        let html = "<div>   </div>"
        let result = HTMLMinifier.minify(html)
        #expect(result == "<div>&nbsp;&nbsp;&nbsp;</div>")
    }

    @Test("Minify replaces inline line breaks with a space")
    func minify_replacesInlineLineBreaks() {
        let html = "<p>Hello\nWorld\tTab</p>"
        let result = HTMLMinifier.minify(html)
        #expect(result == "<p>Hello World Tab</p>")
    }

    @Test("Minify preserves short input", arguments: ["", "a", "ab", "abc"])
    func minify_preservesShortInput(_ html: String) {
        #expect(HTMLMinifier.minify(html) == html)
    }
}

struct CSSFontUtilityTests {
    @Test(
        "parseSize handles keywords and units",
        arguments: [
            ("large", 10.0, 12.0),
            ("16px", 10.0, 16.0),
            ("12pt", 10.0, 12.0),
            ("1.5em", 10.0, 15.0),
            ("2rem", 10.0, 20.0),
            ("150%", 10.0, 15.0),
            ("0.5", 10.0, 0.5)
        ]
    )
    func parseSize_handlesKeywordAndUnits(_ fontSize: String, baseSize: Double, expected: Double) {
        let result = Double(CSSFontUtility.parseSize(fromFontSize: fontSize, baseSize: baseSize))
        #expect(abs(result - expected) < 0.0001)
    }
}

struct AttributeValueTests {
    @Test("AttributeValue parses numeric and boolean helpers")
    func attributeValue_parsingHelpers() {
        #expect(AttributeValue(rawValue: "12px").int == 12)
        #expect(AttributeValue(rawValue: "12px").float == 12)
        #expect(AttributeValue(rawValue: "infinity").cgFloat == .infinity)
        #expect(AttributeValue(rawValue: "true").toBool() == true)
        #expect(AttributeValue(rawValue: "0").toBool() == false)
    }

    @Test("AttributeValue parses URL and CSS style")
    func attributeValue_urlAndCssStyle() {
        #expect(AttributeValue(rawValue: "https://example.com").url?.host == "example.com")
        let style = AttributeValue(rawValue: "color: red; line-height: 20").cssStyle
        #expect(style?["color"]?.string == "red")
        #expect(style?["line-height"]?.cgFloat == 20)
    }
}

struct CSSStyleTests {
    @Test("CSSStyle handles empty and whitespace-only inputs")
    func cssStyle_emptyString() {
        #expect(CSSStyle(style: "") == nil)
        let whitespaceStyle = CSSStyle(style: "   ")
        #expect(whitespaceStyle != nil)
        #expect(whitespaceStyle?[""]?.string == "")
    }
}

struct EdgeInsetsParsingTests {
    @Test("EdgeInsets parses 1-4 value CSS shorthands")
    func edgeInsets_cssShorthand() {
        let one = EdgeInsets(cssString: "10px")
        #expect(one?.top == 10)
        #expect(one?.leading == 10)
        #expect(one?.bottom == 10)
        #expect(one?.trailing == 10)

        let two = EdgeInsets(cssString: "10px 20px")
        #expect(two?.top == 10)
        #expect(two?.leading == 20)
        #expect(two?.bottom == 10)
        #expect(two?.trailing == 20)

        let three = EdgeInsets(cssString: "10px 20px 30px")
        #expect(three?.top == 10)
        #expect(three?.leading == 20)
        #expect(three?.bottom == 30)
        #expect(three?.trailing == 20)

        let four = EdgeInsets(cssString: "10px 20px 30px 40px")
        #expect(four?.top == 10)
        #expect(four?.leading == 40)
        #expect(four?.bottom == 30)
        #expect(four?.trailing == 20)
    }
}

struct ColorParsingTests {
    @Test("Color parses hex, rgb, and named values")
    func color_cssString() {
        #expect(Color(cssString: "#ff0000") != nil)
        #expect(Color(cssString: "rgb(255, 0, 0)") != nil)
        #expect(Color(cssString: "red") != nil)
        #expect(Color(cssString: "not-a-color") == nil)
    }
}

struct LineBreakModeTests {
    @Test("Custom line-break modes compare by id")
    func lineBreakMode_customEquality() {
        let left = LineBreakMode.custom(id: "alpha", transform: { $0 })
        let right = LineBreakMode.custom(id: "alpha", transform: { $0 + "x" })
        let other = LineBreakMode.custom(id: "beta", transform: { $0 })
        #expect(left == right)
        #expect(left != other)
    }

    @Test("LineBreakMode description is stable")
    func lineBreakMode_description() {
        #expect(LineBreakMode.byWordWrapping.description == "byWordWrapping")
        #expect(LineBreakMode.byCharWrapping.description == "byCharWrapping")
        #expect(LineBreakMode.custom(id: "custom-id", transform: { $0 }).description == "custom-id")
    }

    @Test("LineBreakMode callAsFunction applies byCharWrapping")
    func lineBreakMode_callAsFunction() {
        let result = LineBreakMode.byCharWrapping("ab")
        #expect(result == "a\u{200B}b")
    }
}

struct HTMLConfigurationTests {
    private struct TestInlineTag: InlineTag {
        init() {}
        static func applyStyles(with attributes: [String : AttributeValue], to styleContainer: inout HTMLStyleContainer) {
            styleContainer.lineBreakMode = .byCharWrapping
        }
    }

    @MainActor
    @Test("HTMLConfiguration register/remove updates tag type and styles")
    func configuration_registerRemove() {
        let config = HTMLConfiguration()
            .removeAll()
            .register(tag: "test-inline", renderer: TestInlineTag.self)

        #expect(config.tagType(of: "test-inline") == .inline)

        var container = HTMLStyleContainer()
        config.applyStyles(tag: "test-inline", attributes: [:], to: &container)
        #expect(container.lineBreakMode == .byCharWrapping)

        let removed = config.remove(tag: "test-inline")
        #expect(removed.tagType(of: "test-inline") == nil)
    }
}
