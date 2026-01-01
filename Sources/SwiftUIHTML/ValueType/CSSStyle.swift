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
        if style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styles = ["": AttributeValue(rawValue: "")]
            return
        }

        var parsed: [String: AttributeValue] = [:]
        parsed.reserveCapacity(8)

        for component in style.split(separator: ";", omittingEmptySubsequences: true) {
            let keyValue = component.split(separator: ":", maxSplits: 1)
            guard keyValue.count == 2 else { continue }
            let key = keyValue[0].trimmingCharacters(in: .whitespaces)
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            parsed[String(key)] = AttributeValue(rawValue: String(value))
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
