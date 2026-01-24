//  Copyright © 2026 PRND. All rights reserved.

import Testing
import SwiftSoup
@testable import SwiftUIHTML

struct SwiftSoupParserTests {
    @Test
    func swiftSoupParserMapsNodesAttributesAndLineBreaks() {
        let html = """
        <body>
            <p data-x=\"1\">Hello<br>World</p>
            <ruby ruby-position=\"after\">漢字<rt>かんじ</rt></ruby>
        </body>
        """
        let parser = HTMLSwiftSoupParser()
        let root = parser.parse(html: html)

        #expect(root.tag == "body")

        let paragraph = firstNode(tag: "p", in: root)
        #expect(paragraph?.attributes["data-x"]?.string == "1")
        let paragraphText = paragraph?.children.compactMap(textValue(from:)) ?? []
        #expect(paragraphText.contains("Hello"))
        #expect(paragraphText.contains("\n"))
        #expect(paragraphText.contains("World"))

        let rubyNode = firstNode(tag: "ruby", in: root)
        #expect(rubyNode?.attributes["ruby-position"]?.string == "after")
        #expect(rubyNode?.children.contains(where: { child in
            if case let .text(text) = child { return text.contains("漢字") }
            return false
        }) == true)
        let rtNode = rubyNode.flatMap { firstNode(tag: "rt", in: $0) }
        #expect(rtNode?.children.compactMap(textValue(from:)).contains("かんじ") == true)
    }

    @Test
    func swiftSoupParserDropsEmptyTextNodes() {
        let html = """
        <body>
            <div>    </div>
            <div>Value</div>
        </body>
        """
        let parser = HTMLSwiftSoupParser()
        let root = parser.parse(html: html)

        let emptyDiv = firstNode(tag: "div", in: root)
        let emptyText = emptyDiv?.children.compactMap(textValue(from:)) ?? []
        let trimmedEmptyText = emptyText.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmedEmptyText.isEmpty)

        let secondDiv = secondNode(tag: "div", in: root)
        let text = secondDiv?.children.compactMap(textValue(from:)) ?? []
        #expect(text == ["Value"])
    }

    @Test
    func swiftSoupParserNormalizesWhitespaceAndNestedEmphasis() {
        let html = """
        <body>
            <p>Alpha <em>beta <strong>gamma</strong></em> delta</p>
            <p>  spaced   text </p>
        </body>
        """
        let parser = HTMLSwiftSoupParser()
        let root = parser.parse(html: html)

        let firstParagraph = firstNode(tag: "p", in: root)
        let firstParagraphText = allText(in: firstParagraph)
        #expect(firstParagraphText.contains("Alpha"))
        #expect(firstParagraphText.contains("beta"))
        #expect(firstParagraphText.contains("gamma"))
        #expect(firstParagraphText.contains("delta"))

        let secondParagraph = secondNode(tag: "p", in: root)
        let secondText = secondParagraph?.children.compactMap(textValue(from:)).joined() ?? ""
        let normalized = secondText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(normalized == "spaced text")
    }

    @Test
    func swiftSoupParserHandlesAttributesAndInlineTags() {
        let html = """
        <body>
            <p data-id="42"><span style="color: #f00;">Red</span> <a href="https://example.com">Link</a></p>
        </body>
        """
        let parser = HTMLSwiftSoupParser()
        let root = parser.parse(html: html)

        let paragraph = firstNode(tag: "p", in: root)
        #expect(paragraph?.attributes["data-id"]?.string == "42")

        let spanNode = firstNode(tag: "span", in: root)
        #expect(spanNode?.attributes["style"]?.string.contains("color") == true)

        let linkNode = firstNode(tag: "a", in: root)
        #expect(linkNode?.attributes["href"]?.string == "https://example.com")
    }

}

private struct HTMLSwiftSoupParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                return try elementToHTMLNode(element: body)
            } else if let wrapper = try document.select("*").first() {
                return try elementToHTMLNode(element: wrapper)
            } else {
                return HTMLNode(tag: "div", attributes: [:], children: [])
            }
        } catch {
            return HTMLNode(tag: "div", attributes: [:], children: [.text("Parse error: \(error.localizedDescription)")])
        }
    }

    private func elementToHTMLNode(element: SwiftSoup.Element) throws -> HTMLNode {
        let tag = element.tagName()
        let attributes = element.getAttributes()?.reduce(into: [String: String]()) { result, attribute in
            result[attribute.getKey()] = attribute.getValue()
        } ?? [:]
        let children: [HTMLChild] = try element.getChildNodes().compactMap { node in
            if let textNode = node as? TextNode {
                let text = textNode.text()
                return text.isEmpty ? nil : .text(text)
            }
            if let elementNode = node as? Element {
                if elementNode.tagName() == "br" {
                    return .text("\n")
                }
                return .node(try elementToHTMLNode(element: elementNode))
            }
            return nil
        }
        return HTMLNode(tag: tag, attributes: attributes, children: children)
    }
}

private func firstNode(tag: String, in node: HTMLNode) -> HTMLNode? {
    for child in node.children {
        if case let .node(childNode) = child {
            if childNode.tag == tag {
                return childNode
            }
            if let found = firstNode(tag: tag, in: childNode) {
                return found
            }
        }
    }
    return nil
}

private func secondNode(tag: String, in node: HTMLNode) -> HTMLNode? {
    var matches: [HTMLNode] = []
    collectNodes(tag: tag, in: node, results: &matches)
    return matches.count > 1 ? matches[1] : nil
}

private func collectNodes(tag: String, in node: HTMLNode, results: inout [HTMLNode]) {
    for child in node.children {
        if case let .node(childNode) = child {
            if childNode.tag == tag {
                results.append(childNode)
            }
            collectNodes(tag: tag, in: childNode, results: &results)
        }
    }
}

private func textValue(from child: HTMLChild) -> String? {
    if case let .text(text) = child {
        return text
    }
    return nil
}

private func allText(in node: HTMLNode?) -> String {
    guard let node else { return "" }
    var result = ""
    for child in node.children {
        switch child {
        case let .text(text):
            result.append(text)
        case let .node(inner):
            result.append(allText(in: inner))
        }
    }
    return result
}
