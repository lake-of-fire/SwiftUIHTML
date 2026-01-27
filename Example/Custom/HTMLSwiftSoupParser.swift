//  Copyright © 2024 PRND. All rights reserved.
import Foundation
import SwiftSoup
import SwiftUIHTML

struct HTMLSwiftSoupParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                return try buildHTMLNode(from: body)
            }
            if let root = try document.select("*").first() {
                return try buildHTMLNode(from: root)
            }
        } catch {
            return HTMLNode(tag: "div", children: [.text("failed parsing HTML: \(error.localizedDescription)")])
        }
        return HTMLNode(tag: "div", children: [])
    }

    @inline(__always)
    private func normalizeText(_ node: TextNode) -> String {
        node.text()
    }

    private func buildHTMLNode(from root: Element) throws -> HTMLNode {
        try buildHTMLNodeIterative(from: root)
    }

    fileprivate static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "canvas", "dd", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "hr", "li", "main", "nav", "noscript", "ol", "p", "pre",
        "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    fileprivate static func shouldDropWhitespaceText(_ text: String, in parentTag: String) -> Bool {
        let trimmed = ASCIIWhitespace.trim(text)
        if !trimmed.isEmpty {
            return false
        }
        return blockTags.contains(parentTag)
    }
}

extension HTMLSwiftSoupParser {
    private final class Builder {
        private static let emptyAttributes: [String: String] = [:]

        let tag: String
        let isBlockParent: Bool
        let attributes: [String: String]
        let childNodes: [Node]
        let capacityHint: Int
        var childIndex: Int
        var children: [HTMLChild]?

        init(element: Element) {
            let tag = element.tagName()
            self.tag = tag
            self.isBlockParent = HTMLSwiftSoupParser.blockTags.contains(tag)
            if let rawAttributes = element.getAttributes(), rawAttributes.size() > 0 {
                var attributes: [String: String] = [:]
                attributes.reserveCapacity(rawAttributes.size())
                for attribute in rawAttributes {
                    attributes[attribute.getKey()] = attribute.getValue()
                }
                self.attributes = attributes
            } else {
                self.attributes = Self.emptyAttributes
            }
            let count = element.childNodeSize()
            self.capacityHint = count
            if count > 0 {
                self.childNodes = element.getChildNodes()
            } else {
                self.childNodes = []
            }
            self.childIndex = 0
            self.children = nil
        }

        func appendChild(_ child: HTMLChild) {
            if children == nil {
                var storage: [HTMLChild] = []
                if capacityHint > 0 {
                    storage.reserveCapacity(capacityHint)
                }
                children = storage
            }
            children?.append(child)
        }
    }

    func buildHTMLNodeIterative(from root: Element) throws -> HTMLNode {
        var stack: [Builder] = []
        stack.reserveCapacity(64)
        stack.append(Builder(element: root))

        while let current = stack.last {
            if current.childIndex < current.capacityHint {
                let child = current.childNodes[current.childIndex]
                current.childIndex += 1

                if let textNode = child as? TextNode {
                    let text = normalizeText(textNode)
                    if !text.isEmpty {
                        if current.isBlockParent && HTMLSwiftSoupParser.shouldDropWhitespaceText(text, in: current.tag) {
                            if ProcessInfo.processInfo.environment["SWIFTUIHTML_PARSER_LOGS"] == "1" {
                                print("[SwiftSoupParser] drop whitespace text in <\(current.tag)> len=\(text.count)")
                            }
                            continue
                        }
                        current.appendChild(.text(text))
                    }
                    continue
                }
                if let elementNode = child as? Element {
                    if isBRTag(elementNode.tagName()) {
                        current.appendChild(.newLine)
                        continue
                    }
                    stack.append(Builder(element: elementNode))
                }
            } else {
                _ = stack.popLast()
                let built = HTMLNode(
                    tag: current.tag,
                    attributes: current.attributes,
                    children: current.children ?? []
                )
                if stack.isEmpty {
                    return built
                }
                stack[stack.count - 1].appendChild(.node(built))
            }
        }

        return HTMLNode(tag: "div", children: [])
    }
}

@inline(__always)
private func isBRTag(_ raw: String) -> Bool {
    var iterator = raw.utf8.makeIterator()
    guard let first = iterator.next(), let second = iterator.next() else { return false }
    if iterator.next() != nil { return false }
    let isB = first == 0x62 || first == 0x42
    let isR = second == 0x72 || second == 0x52
    return isB && isR
}
