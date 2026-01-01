//  Copyright © 2026 PRND. All rights reserved.

#if canImport(SwiftSoup)
import SwiftUI
import SwiftSoup
import SwiftUIHTML

struct SwiftSoupParserSample: View {
    private let html = """
    <div class="parser-sample">
        <h2>SwiftSoup Parser</h2>
        <p id="description">Parsed with <em>SwiftSoup</em> and converted to HTMLNode.</p>
        <p>Ruby: <ruby ruby-position="after">漢字<rt>かんじ</rt></ruby></p>
        <p>Line break<br>after br tag.</p>
    </div>
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SwiftSoup Parser")
                .font(.title2)
                .fontWeight(.semibold)

            HTMLView(html: html, parser: HTMLSwiftSoupParser())
                .htmlEnvironment(\.configuration, .sample)
        }
        .padding()
        .navigationTitle("SwiftSoup Parser")
        .applyInlineNavigationTitleDisplayMode()
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
            }
        } catch {
            return HTMLNode(tag: "div", attributes: [:], children: [.text("Parse error: \(error.localizedDescription)")])
        }
        return HTMLNode(tag: "div", attributes: [:], children: [])
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
#endif
