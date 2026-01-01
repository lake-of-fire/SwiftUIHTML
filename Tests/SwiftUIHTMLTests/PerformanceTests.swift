//  Copyright © 2026 PRND. All rights reserved.

import Foundation
import Testing
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

        let iterations = 5
        let durations = (0..<iterations).map { _ in
            let start = CFAbsoluteTimeGetCurrent()
            _ = parser.parse(html: html)
            return CFAbsoluteTimeGetCurrent() - start
        }

        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("SwiftUIHTML parse median (\(iterations)x): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    func parseSyntheticHTMLWithSwiftSoupPerformanceSmoke() throws {
        let html = syntheticHTML(sectionCount: 8, includeMedia: false)
        let parser = HTMLSwiftSoupParser()

        let iterations = 3
        let durations = (0..<iterations).map { _ in
            let start = CFAbsoluteTimeGetCurrent()
            _ = parser.parse(html: html)
            return CFAbsoluteTimeGetCurrent() - start
        }

        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("SwiftSoup parse median (\(iterations)x): \(String(format: "%.4f", median))s")

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

        let iterations = 5
        let durations = (0..<iterations).map { _ in
            let start = CFAbsoluteTimeGetCurrent()
            _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
            return CFAbsoluteTimeGetCurrent() - start
        }

        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("Text layout median (\(iterations)x): \(String(format: "%.4f", median))s")

        #expect(median > 0)
    }

    @Test
    @MainActor
    func framesetterCacheBenchmark() throws {
        let font = PlatformFont.systemFont(ofSize: 14)
        let text = String(repeating: "SwiftUIHTML framesetter cache ", count: 120)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        let ranges = [
            NSRange(location: 0, length: min(40, attributed.length)),
            NSRange(location: max(0, attributed.length / 3), length: min(60, attributed.length / 2)),
            NSRange(location: max(0, attributed.length - 80), length: min(80, attributed.length))
        ]
        let containerSize = CGSize(width: 320, height: 800)

        let baseline = measureFramesetterCache(attributed: attributed, ranges: ranges, containerSize: containerSize, enabled: false)
        let optimized = measureFramesetterCache(attributed: attributed, ranges: ranges, containerSize: containerSize, enabled: true)

        print("Framesetter cache baseline: \(String(format: "%.4f", baseline))s")
        print("Framesetter cache optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

    @Test
    @MainActor
    func rangeScanOptimizationBenchmark() throws {
        let font = PlatformFont.systemFont(ofSize: 13)
        let line = "SwiftUIHTML range scan text for layout.\n"
        let text = String(repeating: line, count: 400)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])

        let strideSize = 12
        let ranges: [NSRange] = stride(from: 0, to: attributed.length, by: strideSize).map { location in
            NSRange(location: location, length: min(6, attributed.length - location))
        }
        let containerSize = CGSize(width: 320, height: 1800)

        let baseline = measureRangeScanOptimization(attributed: attributed, ranges: ranges, containerSize: containerSize, enabled: false)
        let optimized = measureRangeScanOptimization(attributed: attributed, ranges: ranges, containerSize: containerSize, enabled: true)

        print("Range scan baseline: \(String(format: "%.4f", baseline))s")
        print("Range scan optimized: \(String(format: "%.4f", optimized))s")

        #expect(baseline > 0)
        #expect(optimized > 0)
    }

    @Test
    @MainActor
    func inlineTextCoalescingPerformanceSmoke() throws {
        let style = HTMLStyleContainer()
        let elements = (0..<2000).map { _ in
            InlineElement(tag: "_text", attributes: [:], text: "SwiftUIHTML ", styleContainer: style)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let inline = HTMLInline(elements: elements)
        let duration = CFAbsoluteTimeGetCurrent() - start
        print("Inline merge baseline: \(String(format: "%.4f", duration))s, count \(inline.texts.count)")

        #expect(duration > 0)
    }

    @Test
    func cssStyleParsingPerformanceSmoke() throws {
        let styles = (0..<2000).map { index in
            "font-size: \(12 + index % 6)px; color: #333; margin: 4px 8px; padding: 2px; line-height: 1.4; border: 1px solid #eee;"
        }

        let iterations = 4
        let durations = (0..<iterations).map { _ in
            let start = CFAbsoluteTimeGetCurrent()
            for style in styles {
                _ = CSSStyle.cached(style: style)
            }
            return CFAbsoluteTimeGetCurrent() - start
        }

        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("CSSStyle parse median (\(iterations)x): \(String(format: "%.4f", median))s")

        #expect(median > 0)
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

@MainActor
private func measureFramesetterCache(
    attributed: NSMutableAttributedString,
    ranges: [NSRange],
    containerSize: CGSize,
    enabled: Bool,
    iterations: Int = 8
) -> TimeInterval {
    let key = "SWIFTUIHTML_CACHE_FRAMESETTER"
    let previous = getenv(key)
    setenv(key, enabled ? "1" : "0", 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }

    let calculator = TextRangeFrameCalculator()
    let prepared = calculator.prepareCoreTextString(attributed)
    var durations: [TimeInterval] = []
    durations.reserveCapacity(iterations)

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
        durations.append(CFAbsoluteTimeGetCurrent() - start)
    }

    let sorted = durations.sorted()
    let median = sorted[sorted.count / 2]
    return median
}

@MainActor
private func measureRangeScanOptimization(
    attributed: NSMutableAttributedString,
    ranges: [NSRange],
    containerSize: CGSize,
    enabled: Bool,
    iterations: Int = 8
) -> TimeInterval {
    let key = "SWIFTUIHTML_DISABLE_RANGE_SCAN_OPT"
    let previous = getenv(key)
    if enabled {
        unsetenv(key)
    } else {
        setenv(key, "1", 1)
    }
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }

    let calculator = TextRangeFrameCalculator()
    let prepared = calculator.prepareCoreTextString(attributed)
    var durations: [TimeInterval] = []
    durations.reserveCapacity(iterations)

    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        _ = calculator.measureLayout(for: prepared, in: containerSize, by: ranges)
        durations.append(CFAbsoluteTimeGetCurrent() - start)
    }

    let sorted = durations.sorted()
    return sorted[sorted.count / 2]
}

#if canImport(SwiftSoup)
import SwiftSoup

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
