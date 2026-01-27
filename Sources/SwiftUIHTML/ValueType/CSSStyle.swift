//  Copyright © 2025 PRND. All rights reserved.
import Foundation


public struct CSSStyle: Sendable {
    private let styles: [String: AttributeValue]
    private nonisolated(unsafe) static let cache: NSCache<NSString, CSSStyleBox> = {
        let cache = NSCache<NSString, CSSStyleBox>()
        cache.countLimit = 256
        return cache
    }()

    init(styles: [String: AttributeValue]) {
        self.styles = styles
    }

    public init?(style: String) {
        if style.isEmpty {
            return nil
        }
        if ASCIIWhitespace.trim(style).isEmpty {
            styles = ["": AttributeValue(rawValue: "")]
            return
        }
        if !style.utf8.contains(0x3A) {
            return nil
        }
        var parsed: [String: AttributeValue] = [:]
        parsed.reserveCapacity(8)

        let utf8 = style.utf8
        var segmentStart = utf8.startIndex
        var index = segmentStart

        func processSegment(start: String.UTF8View.Index, end: String.UTF8View.Index) {
            guard start < end else { return }
            let startIndex = String.Index(start, within: style) ?? style.startIndex
            let endIndex = String.Index(end, within: style) ?? style.endIndex
            let component = style[startIndex..<endIndex]
            let componentUTF8 = component.utf8
            guard let colonIndex = componentUTF8.firstIndex(of: 0x3A) else { return } // ":"

            let keyStart = component.startIndex
            let keyEnd = String.Index(colonIndex, within: component) ?? component.endIndex
            let valueStartUTF8 = componentUTF8.index(after: colonIndex)
            let valueStart = String.Index(valueStartUTF8, within: component) ?? component.endIndex

            let keySlice = ASCIIWhitespace.trim(component[keyStart..<keyEnd])
            let valueSlice = ASCIIWhitespace.trim(component[valueStart..<component.endIndex])
            guard !keySlice.isEmpty, !valueSlice.isEmpty else { return }
            parsed[String(keySlice)] = AttributeValue(rawValue: String(valueSlice))
        }

        while index < utf8.endIndex {
            if utf8[index] == 0x3B { // ";"
                processSegment(start: segmentStart, end: index)
                segmentStart = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }
        if segmentStart < utf8.endIndex {
            processSegment(start: segmentStart, end: utf8.endIndex)
        }

        styles = parsed
        
        if styles.isEmpty {
            return nil
        }
    }
    
    public subscript(_ key: String) -> AttributeValue? {
        styles[key]
    }

    var isEmpty: Bool {
        styles.isEmpty
    }
    
    public func forEach(_ body: ((key: String, value: AttributeValue)) -> Void) {
        styles.forEach(body)
    }
}



extension CSSStyle {
    static let empty = CSSStyle(styles: [:])

    static func cached(style: String) -> CSSStyle? {
        let hasColon = style.utf8.contains(0x3A)
        return cached(style: style, hasColon: hasColon)
    }

    @inline(__always)
    static func cached(style: String, hasColon: Bool) -> CSSStyle? {
        guard hasColon else { return nil }
        let key = style as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        guard let parsed = CSSStyle(style: style) else { return nil }
        cache.setObject(CSSStyleBox(parsed), forKey: key)
        return parsed
    }
}

private final class CSSStyleBox {
    let value: CSSStyle

    init(_ value: CSSStyle) {
        self.value = value
    }
}
