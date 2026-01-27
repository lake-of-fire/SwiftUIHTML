//  Copyright © 2024 PRND. All rights reserved.
import Foundation


public enum HTMLChild: Equatable, Sendable {
    case text(String)
    case node(HTMLNode)
}

public extension HTMLChild {
    static var newLine: HTMLChild {
        .text("\n")
    }

    static func trimmingText(_ string: String) -> HTMLChild {
        if string.isEmpty {
            return .text(string)
        }
        let utf8 = string.utf8
        if let first = utf8.first, let last = utf8.last,
           !ASCIIWhitespace.isWhitespace(first),
           !ASCIIWhitespace.isWhitespace(last) {
            return .text(string)
        }
        let trimmed = ASCIIWhitespace.trim(string)
        if trimmed.startIndex == string.startIndex && trimmed.endIndex == string.endIndex {
            return .text(string)
        }
        return .text(String(trimmed))
    }
}
