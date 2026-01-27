//  Copyright © 2024 PRND. All rights reserved.
import Foundation
import SwiftSoup
import SwiftUIHTML

struct HTMLSwiftSoupParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                if ProcessInfo.processInfo.environment["SWIFTUIHTML_PARSER_LOGS"] == "1" {
                    logBodyChildren(body)
                }
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

    private func logBodyChildren(_ body: Element) {
        var lines: [String] = []
        lines.reserveCapacity(body.childNodeSize() + 1)
        lines.append("[Parser] body children=\(body.childNodeSize())")
        for child in body.getChildNodes() {
            if let textNode = child as? TextNode {
                let text = normalizeText(
                    textNode,
                    preserveWhitespace: HTMLSwiftSoupParser.shouldPreserveWhitespace(in: body.tagName())
                )
                let preview = text
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\t", with: "\\t")
                lines.append("[Parser] text len=\(text.count) preview=\(preview)")
            } else if let element = child as? Element {
                lines.append("[Parser] element tag=\(element.tagName()) children=\(element.childNodeSize())")
            } else {
                lines.append("[Parser] node type=\(type(of: child))")
            }
        }
        let payload = lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: "/tmp/swiftuihtml-parser.log")
        if let data = payload.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    @inline(__always)
    private func normalizeText(_ node: TextNode, preserveWhitespace: Bool) -> String {
        let text = node.text()
        guard !preserveWhitespace else { return text }
        var result = String()
        result.reserveCapacity(text.count)
        var lastWasWhitespace = false
        for scalar in text.unicodeScalars {
            let isWhitespace: Bool
            if scalar.isASCII {
                isWhitespace = ASCIIWhitespace.isWhitespace(UInt8(scalar.value))
            } else {
                isWhitespace = scalar.properties.isWhitespace
            }
            if isWhitespace {
                if !lastWasWhitespace {
                    result.append(" ")
                    lastWasWhitespace = true
                }
            } else {
                result.append(String(scalar))
                lastWasWhitespace = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildHTMLNode(from root: Element) throws -> HTMLNode {
        try buildHTMLNodeIterative(from: root)
    }

    fileprivate static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "canvas", "dd", "div", "dl",
        "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "header", "hr", "html", "li", "main", "nav", "noscript", "ol",
        "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    fileprivate static func shouldDropWhitespaceText(_ text: String, in parentTag: String) -> Bool {
        let trimmed = ASCIIWhitespace.trim(text)
        if !trimmed.isEmpty {
            return false
        }
        return blockTags.contains(parentTag)
    }

    fileprivate static let whitespacePreservingTags: Set<String> = [
        "pre", "code", "textarea"
    ]

    fileprivate static func shouldPreserveWhitespace(in tag: String) -> Bool {
        whitespacePreservingTags.contains(tag)
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
                    let text = normalizeText(
                        textNode,
                        preserveWhitespace: HTMLSwiftSoupParser.shouldPreserveWhitespace(in: current.tag)
                    )
                    if !text.isEmpty {
                        if ProcessInfo.processInfo.environment["SWIFTUIHTML_PARSER_LOGS"] == "1" {
                            let trimmed = ASCIIWhitespace.trim(text)
                            if trimmed.isEmpty, current.tag == "body" {
                                let preview = text
                                    .replacingOccurrences(of: "\n", with: "\\n")
                                    .replacingOccurrences(of: "\t", with: "\\t")
                                print("[SwiftSoupParser] whitespace in <body> len=\\(text.count) preview=\\(preview)")
                            }
                        }
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
