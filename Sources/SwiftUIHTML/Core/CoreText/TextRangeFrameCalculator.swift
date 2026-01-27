//  Copyright © 2025 PRND. All rights reserved.
import Foundation
import CoreText
#if os(macOS)
import AppKit
#endif

/// Calculates frame rectangles for text ranges using Core Text
final class TextRangeFrameCalculator {

    // MARK: - Properties

    /// Additional spacing between lines
    var lineSpacing: CGFloat = 0

    // MARK: - Public Methods

    /// Finds attributes and their ranges in an attributed string
    /// - Parameters:
    ///   - attributedString: The string to search in
    ///   - key: The attribute key to search for
    ///   - type: The expected type of the attribute
    /// - Returns: Array of tuples containing the attribute value and its range
    func findAttribute<T>(
        in attributedString: NSAttributedString,
        for key: NSAttributedString.Key,
        type: T.Type
    ) -> [(value: T, range: NSRange)] {
        var targets: [(T, NSRange)] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(key, in: fullRange) { value, range, _ in
            guard let target = value as? T else { return }
            targets.append((target, range))
        }
        return targets
    }

    /// Finds ranges where a specific attribute is present
    /// - Parameters:
    ///   - attributedString: The string to search in
    ///   - key: The attribute key to search for
    /// - Returns: Array of ranges where the attribute exists
    func findRanges(
        in attributedString: NSAttributedString,
        for key: NSAttributedString.Key
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(key, in: fullRange) { value, range, _ in
            if value != nil {
                ranges.append(range)
            }
        }
        return ranges
    }

    /// Prepares an attributed string for Core Text by converting attachments to run delegates
    /// - Parameter attributedString: The attributed string to prepare
    /// - Returns: A mutable attributed string prepared for Core Text
    func prepareCoreTextString(_ attributedString: NSAttributedString) -> NSMutableAttributedString {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var mutableAttrString: NSMutableAttributedString?

        attributedString.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? TextAttachment else { return }
            if mutableAttrString == nil {
                mutableAttrString = attributedString.mutableCopy() as? NSMutableAttributedString
                    ?? NSMutableAttributedString(attributedString: attributedString)
            }
            guard let mutableAttrString else { return }
            if let delegate = CoreTextRunDelegateManager.shared.createDelegate(for: attachment) {
                mutableAttrString.removeAttribute(.attachment, range: range)
                mutableAttrString.addAttribute(.runDelegate, value: delegate, range: range)
            }
        }

        if let mutableAttrString {
            return mutableAttrString
        }
        if let mutable = attributedString as? NSMutableAttributedString {
            return mutable
        }
        return NSMutableAttributedString(attributedString: attributedString)
    }

    /// Main interface: Measures layout for specified text ranges
    /// - Parameters:
    ///   - preparedString: The prepared attributed string
    ///   - containerSize: The size of the container
    ///   - ranges: Text ranges to measure
    /// - Returns: Array of rectangles for each range
    func measureLayout(
        for preparedString: NSMutableAttributedString,
        in containerSize: CGSize,
        by ranges: [NSRange]
    ) -> [CGRect] {
        return calculateTextFrames(
            attributedString: preparedString,
            containerSize: containerSize,
            targetRanges: ranges
        )
    }

#if os(macOS)
    func measureLayoutWithTextKit(
        attributedString: NSAttributedString,
        in containerSize: CGSize,
        by ranges: [NSRange]
    ) -> [CGRect] {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var rects: [CGRect] = []
        rects.reserveCapacity(ranges.count)
        for range in ranges {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if ProcessInfo.processInfo.environment["SWIFTUIHTML_TEXTKIT_FLIP_Y"] == "1" {
                let flipped = CGRect(
                    x: rect.origin.x,
                    y: max(0, containerSize.height - rect.origin.y - rect.height),
                    width: rect.width,
                    height: rect.height
                )
                rects.append(flipped)
            } else {
                rects.append(rect)
            }
        }
        return rects
    }
#endif
}

// MARK: - Private Methods

private extension TextRangeFrameCalculator {

    /// Calculates layout frames for target ranges
    /// - Parameters:
    ///   - attributedString: The prepared attributed string
    ///   - containerSize: The container size
    ///   - targetRanges: Text ranges to measure
    /// - Returns: Array of rectangles for each range
    func calculateTextFrames(
        attributedString: NSAttributedString,
        containerSize: CGSize,
        targetRanges: [NSRange]
    ) -> [CGRect] {
        let frame = createTextFrame(for: attributedString, containerSize: containerSize)
        return calculateRangeRects(in: frame, containerSize: containerSize, targetRanges: targetRanges)
    }

    /// Creates a Core Text frame for the attributed string
    /// - Parameters:
    ///   - attrString: The attributed string
    ///   - containerSize: Size of the container
    /// - Returns: A Core Text frame
    func createTextFrame(for attrString: NSAttributedString, containerSize: CGSize) -> CTFrame {
        let framesetter = framesetter(for: attrString)

        // Calculate optimal text size with constraints
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(),
            nil,
            CGSize(width: containerSize.width, height: .greatestFiniteMagnitude),
            nil
        )

        // Ensure minimum dimensions
        let width = max(suggestedSize.width, containerSize.width)
        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: suggestedSize.height))
        let path = CGPath(rect: rect, transform: nil)

        return CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
    }

    /// Calculates line metrics for text lines
    /// - Parameter lines: Array of Core Text lines
    /// - Returns: Array of line metrics (ascent, descent, leading)
    func calculateLineMetrics(for lines: [CTLine]) -> [(ascent: CGFloat, descent: CGFloat, leading: CGFloat)] {
        return lines.map { line in
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            return (ascent, descent, leading)
        }
    }

    /// Gets original line origins from Core Text frame
    /// - Parameters:
    ///   - frame: The Core Text frame
    ///   - count: Number of lines
    /// - Returns: Array of line origin points
    func getOriginalLineOrigins(frame: CTFrame, count: Int) -> [CGPoint] {
        var origins = Array(repeating: CGPoint.zero, count: count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        return origins
    }

    /// Adjusts line origins to account for line spacing
    /// - Parameters:
    ///   - frame: The Core Text frame
    ///   - lines: Array of Core Text lines
    ///   - containerSize: Size of the container
    /// - Returns: Array of adjusted line origin points
    func adjustLineOrigins(frame: CTFrame, lines: [CTLine], containerSize: CGSize) -> [CGPoint] {
        guard !lines.isEmpty else { return [] }

        // Get original origins and line metrics
        let origins = getOriginalLineOrigins(frame: frame, count: lines.count)
        let lineMetrics = calculateLineMetrics(for: lines)

        var adjustedOrigins = [CGPoint](repeating: .zero, count: lines.count)

        // Position first line
        let firstAscent = lineMetrics[0].ascent
        adjustedOrigins[0] = CGPoint(x: origins[0].x, y: firstAscent)

        // Position remaining lines
        for i in 1..<lines.count {
            let prevPosition = adjustedOrigins[i-1].y
            let prevMetrics = lineMetrics[i-1]
            let currentAscent = lineMetrics[i].ascent

            // Calculate vertical position with line spacing
            let y = prevPosition + prevMetrics.descent + prevMetrics.leading + currentAscent + lineSpacing
            adjustedOrigins[i] = CGPoint(x: origins[i].x, y: y)
        }

        return adjustedOrigins
    }

    /// Calculates rectangles for target text ranges
    /// - Parameters:
    ///   - frame: The Core Text frame
    ///   - containerSize: Size of the container
    ///   - targetRanges: Text ranges to measure
    /// - Returns: Array of rectangles for each range
    func calculateRangeRects(in frame: CTFrame, containerSize: CGSize, targetRanges: [NSRange]) -> [CGRect] {
        return calculateRangeRectsStreaming(
            in: frame,
            containerSize: containerSize,
            targetRanges: targetRanges
        )
    }

    func calculateRangeRectsLegacy(in frame: CTFrame, containerSize: CGSize, targetRanges: [NSRange]) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let adjustedOrigins = adjustLineOrigins(frame: frame, lines: lines, containerSize: containerSize)

        var rangeRects: [CGRect] = []
        rangeRects.reserveCapacity(targetRanges.count)

        // Process each line
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)

            // Find ranges that intersect with this line
            let intersectingRanges = targetRanges.filter { range in
                NSIntersectionRange(lineNSRange, range).length > 0
            }

            guard !intersectingRanges.isEmpty else { continue }

            let lineOrigin = adjustedOrigins[lineIndex]
            let characterRects = calculateCharacterBounds(
                in: line,
                lineRange: lineNSRange,
                ranges: intersectingRanges
            )

            // Create rect for each character range
            for charFrame in characterRects {
#if os(macOS)
                let yOrigin = lineOrigin.y + charFrame.origin.y
#else
                let yOrigin = lineOrigin.y
#endif
                let lineRect = CGRect(
                    x: charFrame.origin.x + lineOrigin.x,
                    y: yOrigin,
                    width: charFrame.size.width,
                    height: charFrame.size.height
                )
                rangeRects.append(lineRect)
            }
        }

        return rangeRects
    }

    func calculateRangeRectsOptimized(in frame: CTFrame, containerSize: CGSize, targetRanges: [NSRange]) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return [] }

        let adjustedOrigins = adjustLineOrigins(frame: frame, lines: lines, containerSize: containerSize)

        var rangesAreSorted = true
        if targetRanges.count > 1 {
            for index in 1..<targetRanges.count where targetRanges[index].location < targetRanges[index - 1].location {
                rangesAreSorted = false
                break
            }
        }
        let ranges = rangesAreSorted ? targetRanges : targetRanges.sorted { $0.location < $1.location }

        var rangeRects: [CGRect] = []
        rangeRects.reserveCapacity(targetRanges.count)

        var rangeIndex = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
            let lineStart = lineNSRange.location
            let lineEnd = lineNSRange.location + lineNSRange.length

            while rangeIndex < ranges.count,
                  ranges[rangeIndex].location + ranges[rangeIndex].length <= lineStart {
                rangeIndex += 1
            }

            if rangeIndex >= ranges.count {
                break
            }

            var intersectingRanges: [NSRange] = []
            var scanIndex = rangeIndex
            while scanIndex < ranges.count {
                let range = ranges[scanIndex]
                if range.location >= lineEnd {
                    break
                }
                if NSIntersectionRange(lineNSRange, range).length > 0 {
                    intersectingRanges.append(range)
                }
                scanIndex += 1
            }

            guard !intersectingRanges.isEmpty else { continue }

            let lineOrigin = adjustedOrigins[lineIndex]
            let characterRects = calculateCharacterBounds(
                in: line,
                lineRange: lineNSRange,
                ranges: intersectingRanges
            )

            for charFrame in characterRects {
#if os(macOS)
                let yOrigin = lineOrigin.y + charFrame.origin.y
#else
                let yOrigin = lineOrigin.y
#endif
                let lineRect = CGRect(
                    x: charFrame.origin.x + lineOrigin.x,
                    y: yOrigin,
                    width: charFrame.size.width,
                    height: charFrame.size.height
                )
                rangeRects.append(lineRect)
            }
        }

        return rangeRects
    }

    func calculateRangeRectsStreaming(in frame: CTFrame, containerSize: CGSize, targetRanges: [NSRange]) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return [] }

        let adjustedOrigins = adjustLineOrigins(frame: frame, lines: lines, containerSize: containerSize)

        var rangesAreSorted = true
        if targetRanges.count > 1 {
            for index in 1..<targetRanges.count where targetRanges[index].location < targetRanges[index - 1].location {
                rangesAreSorted = false
                break
            }
        }
        let ranges = rangesAreSorted ? targetRanges : targetRanges.sorted { $0.location < $1.location }

        var rangeRects: [CGRect] = []
        rangeRects.reserveCapacity(targetRanges.count)

        var rangeIndex = 0

        for (lineIndex, line) in lines.enumerated() {
            let lineRange = CTLineGetStringRange(line)
            let lineNSRange = NSRange(location: lineRange.location, length: lineRange.length)
            let lineStart = lineNSRange.location
            let lineEnd = lineNSRange.location + lineNSRange.length

            while rangeIndex < ranges.count,
                  ranges[rangeIndex].location + ranges[rangeIndex].length <= lineStart {
                rangeIndex += 1
            }

            if rangeIndex >= ranges.count {
                break
            }

            if ranges[rangeIndex].location >= lineEnd {
                continue
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let lineOrigin = adjustedOrigins[lineIndex]

            var scanIndex = rangeIndex
            while scanIndex < ranges.count {
                let range = ranges[scanIndex]
                if range.location >= lineEnd {
                    break
                }
                let intersection = NSIntersectionRange(lineNSRange, range)
                if intersection.length > 0 {
                    var secondaryOffset: CGFloat = 0
                    let startOffset = CTLineGetOffsetForStringIndex(line, intersection.location, &secondaryOffset)
                    let endOffset = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, &secondaryOffset)
                    let rect = CGRect(
                        x: startOffset,
                        y: -descent,
                        width: endOffset - startOffset,
                        height: ascent + descent
                    )
#if os(macOS)
                    let yOrigin = lineOrigin.y + rect.origin.y
#else
                    let yOrigin = lineOrigin.y
#endif
                    let lineRect = CGRect(
                        x: rect.origin.x + lineOrigin.x,
                        y: yOrigin,
                        width: rect.size.width,
                        height: rect.size.height
                    )
                    rangeRects.append(lineRect)
                }
                scanIndex += 1
            }
        }

        return rangeRects
    }

    /// Calculates bounds for text ranges within a line
    /// - Parameters:
    ///   - line: The Core Text line
    ///   - ranges: Text ranges to measure
    /// - Returns: Array of rectangles for the ranges in this line
    func calculateCharacterBounds(in line: CTLine, lineRange: NSRange, ranges: [NSRange]) -> [CGRect] {
        var characterBounds: [CGRect] = []
        characterBounds.reserveCapacity(ranges.count)

        // Calculate metrics for the line
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)

        // Process each range
        for range in ranges {
            // Check if the range intersects with this line
            let intersection = NSIntersectionRange(lineRange, range)
            guard intersection.length > 0 else { continue }

            // Calculate offsets for the intersection range
            var secondaryOffset: CGFloat = 0
            let startOffset = CTLineGetOffsetForStringIndex(line, intersection.location, &secondaryOffset)
            let endOffset = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, &secondaryOffset)

            // Create rectangle for the range
            let width = endOffset - startOffset
            let rect = CGRect(
                x: startOffset,
                y: -descent,
                width: width,
                height: ascent + descent
            )
            characterBounds.append(rect)
        }

        return characterBounds
    }
}

private extension TextRangeFrameCalculator {
    func framesetter(for attributedString: NSAttributedString) -> CTFramesetter {
        return CTFramesetterCreateWithAttributedString(attributedString)
    }
}

// MARK: - Extensions

extension NSAttributedString.Key {
    static let runDelegate = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
}
