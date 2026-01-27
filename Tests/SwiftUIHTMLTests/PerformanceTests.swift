//  Copyright © 2026 PRND. All rights reserved.

import Foundation
import Testing
import SwiftUI
@testable import SwiftUIHTML
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PerformanceTests {
    @Test
    func parseSyntheticHTMLPerformanceSmoke() throws {
        let html = syntheticHTML(sectionCount: 12, includeMedia: false)
        let parser = SimpleHTMLParser()

        let median = measureMedian {
            _ = parser.parse(html: html)
        }
        print("SwiftUIHTML parse median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func parseSyntheticHTMLWithSwiftSoupPerformanceSmoke() throws {
        let html = syntheticHTML(sectionCount: 8, includeMedia: false)
        let parser = HTMLSwiftSoupParser()

        let median = measureMedian {
            _ = parser.parse(html: html)
        }
        print("SwiftSoup parse median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func textLayoutPerformanceSmoke() throws {
        let font = PlatformFont.systemFont(ofSize: 14)
        let text = String(repeating: "SwiftUIHTML layout performance ", count: 80)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        let calculator = TextRangeFrameCalculator()
        let prepared = calculator.prepareCoreTextString(attributed)
        let ranges = [
            NSRange(location: 0, length: min(40, attributed.length)),
            NSRange(location: max(0, attributed.length / 3), length: min(60, attributed.length / 2)),
            NSRange(location: max(0, attributed.length - 80), length: min(80, attributed.length))
        ]
        let containerSize = CGSize(width: 320, height: 800)

        let median = measureMedian {
            _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
        }
        print("Text layout median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func rangeScanBenchmark() throws {
        let font = PlatformFont.systemFont(ofSize: 13)
        let line = "SwiftUIHTML range scan text for layout.\n"
        let text = String(repeating: line, count: 400)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])

        let strideSize = 12
        let ranges: [NSRange] = stride(from: 0, to: attributed.length, by: strideSize).map { location in
            NSRange(location: location, length: min(6, attributed.length - location))
        }
        let containerSize = CGSize(width: 320, height: 1800)
        let calculator = TextRangeFrameCalculator()
        let prepared = calculator.prepareCoreTextString(attributed)
        let median = measureMedian {
            _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
        }

        print("Range scan median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func inlineTextCoalescingPerformanceSmoke() throws {
        let style = HTMLStyleContainer()
        let elements = (0..<2000).map { _ in
            InlineElement(tag: "_text", attributes: [:], text: "SwiftUIHTML ", styleContainer: style)
        }

        let median = measureMedian {
            let inline = HTMLInline(elements: elements)
            _ = inline.texts.count
        }
        print("Inline merge baseline (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s, count \(elements.count)")

        #expect(median > 0)
    }

    @Test
    func cssStyleParsingPerformanceSmoke() throws {
        let styles = (0..<2000).map { index in
            "font-size: \(12 + index % 6)px; color: #333; margin: 4px 8px; padding: 2px; line-height: 1.4; border: 1px solid #eee;"
        }

        let median = measureMedian {
            for style in styles {
                _ = CSSStyle.cached(style: style)
            }
        }
        print("CSSStyle parse median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func cssStyleParsingBenchmark() throws {
        let styles = (0..<6000).map { index in
            "font-size: \(12 + index % 6)px; color: #333; margin: 4px 8px; padding: 2px; line-height: 1.4; border: 1px solid #eee;"
        }

        let baseline = measureMedian(minSeconds: 2.0) {
            var total = 0
            for style in styles {
                total += parseCSSStyleBaseline(style)
            }
            _ = total
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            var total = 0
            for style in styles {
                if let parsed = CSSStyle(style: style) {
                    parsed.forEach { _ in
                        total += 1
                    }
                }
            }
            _ = total
        }

        print("CSS parse baseline: \(String(format: "%.4f", baseline))s")
        print("CSS parse optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }


    @Test
    func attributeCSSStyleBenchmark() throws {
        let values = (0..<8000).map { index -> String in
            if index.isMultiple(of: 3) {
                return "color: #333; font-size: \(12 + index % 6)px;"
            }
            return index.isMultiple(of: 2) ? "bold" : "inherit"
        }

        let baseline = measureMedian(minSeconds: 2.0) {
            var total = 0
            for value in values {
                if let parsed = CSSStyle.cached(style: value) {
                    parsed.forEach { _ in total += 1 }
                }
            }
            _ = total
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            var total = 0
            for value in values {
                let attr = AttributeValue(rawValue: value)
                if let parsed = attr.cssStyle {
                    parsed.forEach { _ in total += 1 }
                }
            }
            _ = total
        }

        print("Attribute cssStyle baseline: \(String(format: "%.4f", baseline))s")
        print("Attribute cssStyle optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }



    @Test
    @MainActor
    func heavyTextLayoutBenchmark() throws {
        let font = PlatformFont.systemFont(ofSize: 13)
        let paragraph = "SwiftUIHTML heavy layout benchmark line with mixed width words and glyphs.\n"
        let text = String(repeating: paragraph, count: 1800)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])

        let ranges: [NSRange] = stride(from: 0, to: attributed.length, by: 7).map { location in
            NSRange(location: location, length: min(5, attributed.length - location))
        }
        let containerSize = CGSize(width: 420, height: 8000)

        let calculator = TextRangeFrameCalculator()
        let prepared = calculator.prepareCoreTextString(attributed)
        let median = measureMedian {
            _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
        }

        print("Heavy layout median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func heavyCSSParsingBenchmark() throws {
        let styles = (0..<12000).map { index in
            "font-size: \(12 + index % 6)px; color: #333; margin: 4px 8px; padding: 2px; line-height: 1.4; border: 1px solid #eee; letter-spacing: 0.\(index % 7)em; background-color: #fafafa;"
        }

        let median = measureMedian {
            for style in styles {
                _ = CSSStyle.cached(style: style)
            }
        }
        print("Heavy CSSStyle parse median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func listParsingBenchmark() throws {
        guard let parser = makeSwiftSoupParserIfAvailable() else {
            print("SwiftSoup parser not available; skipping listParsingBenchmark")
            #expect(true)
            return
        }

        let html = listHeavyHTML(itemCount: 2000, depth: 3)
        let median = measureMedian {
            _ = parser.parse(html: html)
        }
        print("List HTML parse median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func htmlViewLifecycleBenchmark() throws {
        guard let parser = makeSwiftSoupParserIfAvailable() else {
            print("SwiftSoup parser not available; skipping htmlViewLifecycleBenchmark")
            #expect(true)
            return
        }

        let html = listHeavyHTML(itemCount: 2000, depth: 3)
        let configuration = HTMLConfiguration()
        let styleContainer = HTMLStyleContainer()

        let median = measureMedian {
            AttachmentIDGenerator.reset()
            let node = parser.parse(html: html)
            _ = node.toElement(configuration: configuration, with: styleContainer)
        }

        print("HTML view lifecycle median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func listElementBuildBenchmark() throws {
        guard let parser = makeSwiftSoupParserIfAvailable() else {
            print("SwiftSoup parser not available; skipping listElementBuildBenchmark")
            #expect(true)
            return
        }

        let html = listHeavyHTML(itemCount: 900, depth: 2)
        let node = parser.parse(html: html)
        let configuration = HTMLConfiguration().attributeStyler(DefaultAttributeStyler())
        let baseStyle = HTMLStyleContainer()

        let median = measureMedian {
            let element = node.toElement(configuration: configuration, with: baseStyle)
            _ = element.contents.count
        }
        print("List element build median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func elementBuildBenchmarkAB() throws {
        let node = makeListNodeTree(itemCount: 220, depth: 2)
        let configuration = HTMLConfiguration().attributeStyler(DefaultAttributeStyler())
        let baseStyle = HTMLStyleContainer()

        let baseline = measureMedian(minSeconds: 2.0) {
            _ = toElementBaseline(node: node, configuration: configuration, styleContainer: baseStyle)
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            _ = node.toElement(configuration: configuration, with: baseStyle)
        }

        print("Element build baseline: \(String(format: "%.4f", baseline))s")
        print("Element build optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

    @Test
    @MainActor
    func rubyPipelineBenchmark() throws {
        guard let parser = makeSwiftSoupParserIfAvailable() else {
            print("SwiftSoup parser not available; skipping rubyPipelineBenchmark")
            #expect(true)
            return
        }

        let html = rubyHeavyHTML(count: 600)
        let node = parser.parse(html: html)
        let configuration = HTMLConfiguration().attributeStyler(DefaultAttributeStyler())
        let baseStyle = HTMLStyleContainer()

        let median = measureMedian {
            let element = node.toElement(configuration: configuration, with: baseStyle)
            _ = element.contents.count
        }
        print("Ruby pipeline median (>=\(benchmarkMinimumSeconds())s): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func rubyExtractionBenchmarkAB() throws {
        let children = makeRubyChildren(count: 800)
        let baseFont = PlatformFont.systemFont(ofSize: 14)

        let baseline = measureMedian(minSeconds: 2.0) {
            _ = rubyExtractionBaseline(children: children, baseFont: baseFont)
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            _ = rubyExtractionOptimized(children: children, baseFont: baseFont)
        }

        print("Ruby extract baseline: \(String(format: "%.4f", baseline))s")
        print("Ruby extract optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

    @Test
    func rgbParsingBenchmark() throws {
        let inputs = (0..<5000).map { index in
            let r = index % 255
            let g = (index * 2) % 255
            let b = (index * 3) % 255
            let a = Double((index % 10)) / 10.0
            return index.isMultiple(of: 2)
                ? "rgb(\(r), \(g), \(b))"
                : "rgba(\(r), \(g), \(b), \(a))"
        }

        let baseline = measureMedian(minSeconds: 2.0) {
            for value in inputs {
                _ = parseRGBRegex(value)
            }
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            for value in inputs {
                _ = Color(cssString: value)
            }
        }

        print("RGB parse baseline: \(String(format: "%.4f", baseline))s")
        print("RGB parse optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

    @Test
    func htmlChildTrimmingBenchmarkAB() throws {
        let values = (0..<12000).map { index -> String in
            if index.isMultiple(of: 3) {
                return "  Trim me \(index)  "
            }
            return "NoTrim\(index)"
        }

        let baseline = measureMedian(minSeconds: 2.0) {
            for value in values {
                _ = trimmingTextBaseline(value)
            }
        }

        let optimized = measureMedian(minSeconds: 2.0) {
            for value in values {
                _ = HTMLChild.trimmingText(value)
            }
        }

        print("HTMLChild trim baseline: \(String(format: "%.4f", baseline))s")
        print("HTMLChild trim optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

}

private struct SimpleHTMLParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        let stripped = html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty {
            return HTMLNode(tag: "div", attributes: [:], children: [])
        }
        return HTMLNode(tag: "div", attributes: [:], children: [.text(stripped)])
    }
}

// Inline coalescing removed after stress benchmarking showed it was slower at scale.

#if canImport(SwiftSoup)
import SwiftSoup

private struct HTMLSwiftSoupParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                return try buildHTMLNode(from: body)
            } else if let wrapper = try document.select("*").first() {
                return try buildHTMLNode(from: wrapper)
            }
        } catch {
            return HTMLNode(tag: "div", attributes: [:], children: [.text("Parse error: \(error.localizedDescription)")])
        }
        return HTMLNode(tag: "div", attributes: [:], children: [])
    }
}

private struct HTMLSwiftSoupParserBench: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                return try buildHTMLNode(from: body)
            } else if let wrapper = try document.select("*").first() {
                return try buildHTMLNode(from: wrapper)
            }
        } catch {
            return HTMLNode(tag: "div", attributes: [:], children: [.text("Parse error: \(error.localizedDescription)")])
        }
        return HTMLNode(tag: "div", attributes: [:], children: [])
    }
}

private func buildHTMLNode(from root: Element) throws -> HTMLNode {
    try buildHTMLNodeIterative(from: root)
}

private final class SwiftSoupNodeBuilder {
    private static let emptyAttributes: [String: String] = [:]

    let tag: String
    let attributes: [String: String]
    let childNodes: [Node]
    let capacityHint: Int
    var childIndex: Int
    var children: [HTMLChild]?

    init(element: Element) {
        let tag = element.tagName()
        self.tag = tag
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

private func buildHTMLNodeIterative(from root: Element) throws -> HTMLNode {
    var stack: [SwiftSoupNodeBuilder] = []
    stack.reserveCapacity(64)
    stack.append(SwiftSoupNodeBuilder(element: root))

    while let current = stack.last {
        if current.childIndex < current.capacityHint {
            let child = current.childNodes[current.childIndex]
            current.childIndex += 1

            if let textNode = child as? TextNode {
                let text = textNode.text()
                if !text.isEmpty {
                    current.appendChild(.text(text))
                }
                continue
            }
            if let elementNode = child as? Element {
                if isBRTag(elementNode.tagName()) {
                    current.appendChild(.newLine)
                    continue
                }
                stack.append(SwiftSoupNodeBuilder(element: elementNode))
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

    return HTMLNode(tag: "div", attributes: [:], children: [])
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
#endif
private func syntheticHTML(sectionCount: Int, includeMedia: Bool) -> String {
    var chunks: [String] = []
    chunks.reserveCapacity(sectionCount * 6)

    chunks.append("""
        <body style=\"margin: 0; padding: 0;\">
            <header style=\"background-color: #f0f0f0; padding: 16px; border-radius: 8px; margin-bottom: 12px;\">
                <h1 style=\"color: #333;\">SwiftUIHTML Stress Test</h1>
                <p style=\"color: #666;\">Synthetic HTML payload exercising tags, CSS, and attachments.</p>
            </header>
            <main>
        """)

    for index in 1...sectionCount {
        let mediaHTML: String
        if includeMedia {
            mediaHTML = """
                <p>
                    <img src=\"https://picsum.photos/seed/\(index)/80/60\" width=\"80\" height=\"60\" />
                    <video src=\"https://example.com/video\(index).mp4\" />
                </p>
                """
        } else {
            mediaHTML = ""
        }

        chunks.append("""
            <section style=\"margin: 12px 0; padding: 12px; border: 1px solid #ddd; border-radius: 6px;\">
                <h2 style=\"color: #1a4; font-size: 18px;\">Section \(index)</h2>
                <p style=\"line-height: 20px;\">
                    Inline styles: <span style=\"color: #c33;\">red</span>,
                    <span style=\"background-color: #ff0;\">yellow</span>,
                    <strong>bold</strong>, <em>italic</em>, <u>underline</u>.
                </p>
                <p>
                    Ruby: <ruby ruby-position=\"after\" ruby-scale=\"0.5\">漢字<rt>かんじ</rt></ruby>.
                </p>
                <ul>
                    <li>Item \(index).1</li>
                    <li>Item \(index).2 with <span style=\"color: #05a;\">color</span></li>
                    <li>Item \(index).3</li>
                </ul>
                \(mediaHTML)
            </section>
            """)
    }

    chunks.append("""
            </main>
            <footer style=\"margin-top: 16px; padding: 12px; background-color: #333; color: white;\">
                <p>Footer content for synthetic payload.</p>
            </footer>
        </body>
        """)

    return chunks.joined(separator: "\n")
}

private func parseRGBRegex(_ rgbString: String) -> Color? {
    let rgbPattern = "rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([0-9.]+))?\\)"
    guard let regex = try? NSRegularExpression(pattern: rgbPattern, options: []),
          let match = regex.firstMatch(in: rgbString, options: [], range: NSRange(rgbString.startIndex..<rgbString.endIndex, in: rgbString)) else {
        return nil
    }

    var components: [Double] = []
    for i in 1..<match.numberOfRanges {
        if let range = Range(match.range(at: i), in: rgbString),
           !rgbString[range].isEmpty {
            if let value = Double(rgbString[range]) {
                components.append(value)
            } else if i == 4 {
                components.append(1.0)
            } else {
                return nil
            }
        } else if i == 4 {
            components.append(1.0)
        } else {
            return nil
        }
    }

    guard components.count >= 3 else { return nil }
    let r = min(max(components[0] / 255.0, 0), 1)
    let g = min(max(components[1] / 255.0, 0), 1)
    let b = min(max(components[2] / 255.0, 0), 1)
    let a = min(max(components.count >= 4 ? components[3] : 1.0, 0), 1)
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

private func parseCSSStyleBaseline(_ style: String) -> Int {
    var count = 0
    for component in style.split(separator: ";", omittingEmptySubsequences: true) {
        let keyValue = component.split(separator: ":", maxSplits: 1)
        guard keyValue.count == 2 else { continue }
        let key = keyValue[0].trimmingCharacters(in: .whitespaces)
        let value = keyValue[1].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { continue }
        count += 1
    }
    return count
}

private func trimmingTextBaseline(_ string: String) -> HTMLChild {
    let trimmed = ASCIIWhitespace.trim(string)
    if trimmed.startIndex == string.startIndex && trimmed.endIndex == string.endIndex {
        return .text(string)
    }
    return .text(String(trimmed))
}

@MainActor
private func toElementBaseline(node: HTMLNode, configuration: HTMLConfiguration, styleContainer: HTMLStyleContainer) -> BlockElement {
    var contents: [TagElement] = []
    contents.reserveCapacity(node.children.count)
    for child in node.children {
        contents.append(contentsOf: childElementsBaseline(child, configuration: configuration, styleContainer: styleContainer))
    }
    return BlockElement(
        tag: node.tagName,
        attributes: node.attributes,
        contents: contents,
        styleContainer: styleContainer
    )
}

@MainActor
private func childElementsBaseline(_ child: HTMLChild, configuration: HTMLConfiguration, styleContainer: HTMLStyleContainer) -> [TagElement] {
    switch child {
    case let .text(text) where text.isEmpty:
        return []
    case let .text(text):
        return [
            .inline(InlineElement(
                tag: "_text",
                attributes: [:],
                text: text,
                styleContainer: styleContainer
            ))
        ]
    case let .node(childNode):
        return makeElementBaseline(node: childNode, configuration: configuration, styleContainer: styleContainer)
    }
}

@MainActor
private func makeElementBaseline(node: HTMLNode, configuration: HTMLConfiguration, styleContainer: HTMLStyleContainer) -> [TagElement] {
    var _styleContainer = styleContainer
    configuration.applyStyles(tag: node.tagName, attributes: node.attributes, to: &_styleContainer)

    switch configuration.tagType(of: node.tagName) {
    case .inline:
        var contents: [TagElement] = []
        contents.reserveCapacity(node.children.count)
        for child in node.children {
            contents.append(contentsOf: childElementsBaseline(child, configuration: configuration, styleContainer: _styleContainer))
        }
        return contents

    case .attachment:
        return [
            .inline(InlineElement(
                tag: node.tagName,
                attributes: node.attributes,
                type: .attachment,
                styleContainer: _styleContainer
            ))
        ]

    case .block, .none:
        return [
            .block(toElementBaseline(node: node, configuration: configuration, styleContainer: _styleContainer))
        ]
    }
}

private func rubyPlainText(_ node: HTMLNode) -> String {
    var result = ""
    for child in node.children {
        switch child {
        case let .text(text):
            result.append(text)
        case let .node(node):
            result.append(rubyPlainText(node))
        }
    }
    return result
}

private func makeListNodeTree(itemCount: Int, depth: Int) -> HTMLNode {
    func buildList(level: Int) -> HTMLNode {
        var items: [HTMLChild] = []
        items.reserveCapacity(itemCount)
        let nestedStride = max(1, itemCount / 5)

        for index in 1...itemCount {
            var liChildren: [HTMLChild] = [
                .text("Item \(index) with "),
                .node(HTMLNode(
                    tag: "span",
                    attributes: ["style": "font-weight: 600; color: #05a;"],
                    children: [.text("bold")]
                )),
                .text(" text.")
            ]
            if level > 0, index.isMultiple(of: nestedStride) {
                liChildren.append(.node(buildList(level: level - 1)))
            }
            let li = HTMLNode(
                tag: "li",
                attributes: ["style": "margin: 2px 0; padding-left: 8px;"],
                children: liChildren
            )
            items.append(.node(li))
        }

        return HTMLNode(tag: "ul", children: items)
    }

    return HTMLNode(
        tag: "div",
        attributes: ["style": "padding: 12px; border: 1px solid #ddd;"],
        children: [.node(buildList(level: depth))]
    )
}

private func makeRubyChildren(count: Int) -> [HTMLChild] {
    var children: [HTMLChild] = []
    children.reserveCapacity(count * 2)
    for index in 1...count {
        let base = HTMLChild.text("漢字\(index)")
        let rt = HTMLChild.node(
            HTMLNode(
                tag: "rt",
                attributes: ["style": "font-size: \(10 + index % 4)px; font-family: Helvetica;"],
                children: [.text("かんじ\(index)")]
            )
        )
        children.append(base)
        children.append(rt)
    }
    return children
}

private func rubyExtractionBaseline(children: [HTMLChild], baseFont: PlatformFont?) -> (base: String?, ruby: String?, annotationSize: CGFloat?, annotationName: String?) {
    var baseText = ""
    var rubyText = ""
    var hasBase = false
    var hasRuby = false

    for child in children {
        switch child {
        case let .text(text):
            if !text.isEmpty {
                baseText.append(text)
                hasBase = true
            }
        case let .node(node):
            switch node.tag {
            case "rt":
                let trimmedText = rubyPlainText(node).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    if hasRuby {
                        rubyText.append(" ")
                    }
                    rubyText.append(trimmedText)
                    hasRuby = true
                }
            case "rp", "rtc":
                continue
            case "rb":
                let text = rubyPlainText(node)
                if !text.isEmpty {
                    baseText.append(text)
                    hasBase = true
                }
            default:
                let text = rubyPlainText(node)
                if !text.isEmpty {
                    baseText.append(text)
                    hasBase = true
                }
            }
        }
    }

    var size: CGFloat?
    var name: String?
    for child in children {
        guard case let .node(node) = child, node.tag == "rt" else { continue }
        guard let cssStyle = node.attributes["style"]?.cssStyle else { continue }
        if size == nil, let fontSize = cssStyle["font-size"]?.string {
            let baseSize = baseFont?.pointSize ?? PlatformFont.systemFontSize
            size = CSSFontUtility.parseSize(fromFontSize: fontSize, baseSize: baseSize)
        }
        if name == nil, let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: baseFont) {
            name = font.fontName
        }
        if size != nil && name != nil {
            break
        }
    }

    return (
        base: hasBase ? baseText : nil,
        ruby: hasRuby ? rubyText : nil,
        annotationSize: size,
        annotationName: name
    )
}

private func rubyExtractionOptimized(children: [HTMLChild], baseFont: PlatformFont?) -> (base: String?, ruby: String?, annotationSize: CGFloat?, annotationName: String?) {
    var baseText = ""
    var rubyText = ""
    var hasBase = false
    var hasRuby = false
    var annotationSize: CGFloat?
    var annotationName: String?

    for child in children {
        switch child {
        case let .text(text):
            if !text.isEmpty {
                baseText.append(text)
                hasBase = true
            }
        case let .node(node):
            switch node.tag {
            case "rt":
                let trimmedText = ASCIIWhitespace.trim(rubyPlainText(node)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    if hasRuby {
                        rubyText.append(" ")
                    }
                    rubyText.append(contentsOf: trimmedText)
                    hasRuby = true
                }
                if annotationSize == nil || annotationName == nil {
                    if let cssStyle = node.attributes["style"]?.cssStyle {
                        if annotationSize == nil, let fontSize = cssStyle["font-size"]?.string {
                            let baseSize = baseFont?.pointSize ?? PlatformFont.systemFontSize
                            annotationSize = CSSFontUtility.parseSize(fromFontSize: fontSize, baseSize: baseSize)
                        }
                        if annotationName == nil, let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: baseFont) {
                            annotationName = font.fontName
                        }
                    }
                }
            case "rp", "rtc":
                continue
            case "rb":
                let text = rubyPlainText(node)
                if !text.isEmpty {
                    baseText.append(text)
                    hasBase = true
                }
            default:
                let text = rubyPlainText(node)
                if !text.isEmpty {
                    baseText.append(text)
                    hasBase = true
                }
            }
        }
    }

    return (
        base: hasBase ? baseText : nil,
        ruby: hasRuby ? rubyText : nil,
        annotationSize: annotationSize,
        annotationName: annotationName
    )
}





private func listHeavyHTML(itemCount: Int, depth: Int) -> String {
    var items: [String] = []
    items.reserveCapacity(itemCount)
    for index in 1...itemCount {
        let style = "style=\"margin: 2px 0; padding-left: 8px; color: #\(String(format: "%03x", index % 0xfff))\""
        items.append("<li \(style)>Item \(index) with <span style=\"font-weight: 600;\">bold</span> text.</li>")
    }

    func nestedList(level: Int) -> String {
        if level <= 0 {
            return "<ul>\(items.joined())</ul>"
        }
        return "<ul>\(items.prefix(max(20, itemCount / (level + 1))).joined())<li>Nested\(nestedList(level: level - 1))</li></ul>"
    }

    return """
    <body>
        <section style="padding: 12px; border: 1px solid #ddd;">
            <h2>List Benchmark</h2>
            \(nestedList(level: depth))
        </section>
    </body>
    """
}

private func rubyHeavyHTML(count: Int) -> String {
    var chunks: [String] = []
    chunks.reserveCapacity(count)
    for index in 1...count {
        let base = "漢字\(index)"
        let rt = "かんじ\(index)"
        let style = "style=\"ruby-position: after; ruby-scale: 0.55; color: #333;\""
        let rtStyle = "style=\"font-size: \(10 + index % 4)px; font-family: Helvetica;\""
        chunks.append("<ruby \(style)>\(base)<rt \(rtStyle)>\(rt)</rt></ruby>")
    }
    return "<body><p>\(chunks.joined(separator: " "))</p></body>"
}

@MainActor
private func makeSwiftSoupParserIfAvailable() -> HTMLParserable? {
#if canImport(SwiftSoup)
    return HTMLSwiftSoupParserBench()
#else
    return nil
#endif
}

@inline(__always)
private func benchmarkMinimumSeconds() -> TimeInterval {
    4.0
}

@inline(__always)
private func measureMedian(minSeconds: TimeInterval? = nil, _ block: () -> Void) -> TimeInterval {
    let minSeconds = minSeconds ?? benchmarkMinimumSeconds()
    var durations: [TimeInterval] = []
    durations.reserveCapacity(64)

    let warmupCount = 8
    for _ in 0..<warmupCount {
        block()
    }

    let deadline = CFAbsoluteTimeGetCurrent() + minSeconds
    repeat {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        durations.append(CFAbsoluteTimeGetCurrent() - start)
    } while CFAbsoluteTimeGetCurrent() < deadline

    let sorted = durations.sorted()
    return sorted[sorted.count / 2]
}
