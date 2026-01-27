//  Copyright © 2026 PRND. All rights reserved.
import Foundation

public enum ASCIIWhitespace {
    @inline(__always)
    public static func isWhitespace(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    public static func trim(_ value: String) -> Substring {
        trim(value[...])
    }

    @inline(__always)
    public static func trim(_ value: Substring) -> Substring {
        let utf8 = value.utf8
        var start = utf8.startIndex
        var end = utf8.endIndex

        while start < end, ASCIIWhitespace.isWhitespace(utf8[start]) {
            start = utf8.index(after: start)
        }

        while end > start {
            let before = utf8.index(before: end)
            if ASCIIWhitespace.isWhitespace(utf8[before]) {
                end = before
            } else {
                break
            }
        }

        let startIndex = String.Index(start, within: value) ?? value.startIndex
        let endIndex = String.Index(end, within: value) ?? value.endIndex
        return value[startIndex..<endIndex]
    }

    @inline(__always)
    public static func trimLeading(_ value: String) -> Substring {
        trimLeading(value[...])
    }

    @inline(__always)
    public static func trimLeading(_ value: Substring) -> Substring {
        let utf8 = value.utf8
        var start = utf8.startIndex
        let end = utf8.endIndex

        while start < end, ASCIIWhitespace.isWhitespace(utf8[start]) {
            start = utf8.index(after: start)
        }

        let startIndex = String.Index(start, within: value) ?? value.startIndex
        return value[startIndex..<value.endIndex]
    }

    @inline(__always)
    public static func trimTrailing(_ value: String) -> Substring {
        trimTrailing(value[...])
    }

    @inline(__always)
    public static func trimTrailing(_ value: Substring) -> Substring {
        let utf8 = value.utf8
        var end = utf8.endIndex
        let start = utf8.startIndex

        while end > start {
            let before = utf8.index(before: end)
            if ASCIIWhitespace.isWhitespace(utf8[before]) {
                end = before
            } else {
                break
            }
        }

        let endIndex = String.Index(end, within: value) ?? value.endIndex
        return value[value.startIndex..<endIndex]
    }
}
