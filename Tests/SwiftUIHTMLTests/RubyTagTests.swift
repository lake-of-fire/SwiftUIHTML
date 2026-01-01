import SwiftUI
import Testing
@testable import SwiftUIHTML

@MainActor
struct RubyTagTests {
    @Test
    func rubyNodeCreatesInlineAttachment() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .text("base"),
                .node(HTMLNode(tag: "rt", children: [.text("ruby")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.tag == "ruby")
        #expect(inline.attributes["ruby-base"]?.string == "base")
        #expect(inline.attributes["ruby-text"]?.string == "ruby")
    }

    @Test
    func rubyNodeIgnoresRpAndUsesRbAndRt() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .node(HTMLNode(tag: "rb", children: [.text("漢字")])),
                .node(HTMLNode(tag: "rp", children: [.text("(")])),
                .node(HTMLNode(tag: "rt", children: [.text("かんじ")])),
                .node(HTMLNode(tag: "rp", children: [.text(")")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-base"]?.string == "漢字")
        #expect(inline.attributes["ruby-text"]?.string == "かんじ")
    }

    @Test
    func rubyNodePropagatesBaseFontIntoAttributes() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .text("猫"),
                .node(HTMLNode(tag: "rt", children: [.text("ねこ")]))
            ]
        )

        var container = HTMLStyleContainer()
#if os(macOS)
        let font = NSFont.systemFont(ofSize: 17)
#else
        let font = UIFont.systemFont(ofSize: 17)
#endif
        container.uiFont = font

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: container)

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-font-name"]?.string == font.fontName)
        #expect(inline.attributes["ruby-font-size"]?.string == "\(font.pointSize)")
    }

    @Test
    func rubyNodeFlattensNestedInlineText() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .node(HTMLNode(tag: "span", children: [.text("漢")])),
                .text("字"),
                .node(HTMLNode(tag: "rt", children: [.text("かん")])),
                .node(HTMLNode(tag: "rt", children: [.text("じ")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-base"]?.string == "漢字")
        #expect(inline.attributes["ruby-text"]?.string == "かん じ")
    }

    @Test
    func rubyNodeWithoutRtOmitsRubyText() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .text("漢字")
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-base"]?.string == "漢字")
        #expect(inline.attributes["ruby-text"] == nil)
    }

    @Test
    func rubyAttributesPreservePositionAndScale() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            attributes: [
                "ruby-position": "after",
                "ruby-scale": "0.5"
            ],
            children: [
                .text("今日"),
                .node(HTMLNode(tag: "rt", children: [.text("きょう")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-position"]?.string == "after")
        #expect(inline.attributes["ruby-scale"]?.string == "0.5")
    }

    @Test
    func rubyNodeKeepsOriginalAttributes() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            attributes: [
                "style": "color: #f00;",
                "data-test": "ruby"
            ],
            children: [
                .text("漢字"),
                .node(HTMLNode(tag: "rt", children: [.text("かんじ")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["style"]?.string == "color: #f00;")
        #expect(inline.attributes["data-test"]?.string == "ruby")
        #expect(inline.attributes["ruby-base"]?.string == "漢字")
        #expect(inline.attributes["ruby-text"]?.string == "かんじ")
    }

    @Test
    func rubyNodeWithOnlyRtDoesNotCreateRubyBase() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .node(HTMLNode(tag: "rt", children: [.text("かんじ")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-base"] == nil)
        #expect(inline.attributes["ruby-text"] == nil)
    }

    @Test
    func rubyNodePreservesBaseWhitespace() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .text(" 漢字 "),
                .node(HTMLNode(tag: "rt", children: [.text("かんじ")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-base"]?.string == " 漢字 ")
        #expect(inline.attributes["ruby-text"]?.string == "かんじ")
    }

    @Test
    func rubyNodeTrimsRtWhitespace() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            children: [
                .text("漢字"),
                .node(HTMLNode(tag: "rt", children: [.text("  かんじ \n")])),
                .node(HTMLNode(tag: "rt", children: [.text("\tけんじ ")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-text"]?.string == "かんじ けんじ")
    }

    @Test
    func rubyNodePreservesRubyFontAttributes() {
        let rubyNode = HTMLNode(
            tag: "ruby",
            attributes: [
                "ruby-font-name": "HelveticaNeue",
                "ruby-font-size": "22",
                "ruby-annotation-font-name": "HiraginoSans-W3",
                "ruby-annotation-font-size": "12"
            ],
            children: [
                .text("明日"),
                .node(HTMLNode(tag: "rt", children: [.text("あした")]))
            ]
        )

        let root = HTMLNode(tag: "div", children: [.node(rubyNode)])
        let element = root.toElement(configuration: .default, with: HTMLStyleContainer())

        #expect(element.contents.count == 1)
        guard case let .inline(inline) = element.contents[0] else {
            Issue.record("Expected inline element for ruby attachment")
            return
        }

        #expect(inline.attributes["ruby-font-name"]?.string == "HelveticaNeue")
        #expect(inline.attributes["ruby-font-size"]?.string == "22")
        #expect(inline.attributes["ruby-annotation-font-name"]?.string == "HiraginoSans-W3")
        #expect(inline.attributes["ruby-annotation-font-size"]?.string == "12")
    }
}
