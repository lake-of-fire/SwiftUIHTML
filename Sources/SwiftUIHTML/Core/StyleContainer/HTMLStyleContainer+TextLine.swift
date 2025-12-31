//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif


extension HTMLStyleContainer {
    public enum TextLineAttribute: Equatable, Sendable, Hashable {
        case lineSpacing(spacing: CGFloat)
        case lineHeight(fontLineHeight: CGFloat, lineHeight: CGFloat)
    }
}

public extension HTMLStyleContainer.TextLineAttribute {
#if os(macOS)
    static func lineHeight(font: NSFont, lineHeight: CGFloat) -> Self {
        .lineHeight(fontLineHeight: font.manabiLineHeight, lineHeight: lineHeight)
    }
#else
    static func lineHeight(font: UIFont, lineHeight: CGFloat) -> Self {
        .lineHeight(fontLineHeight: font.manabiLineHeight, lineHeight: lineHeight)
    }
#endif
}

extension HTMLStyleContainer.TextLineAttribute {
    var lineSpacing: CGFloat {
        switch self {
        case let .lineHeight(fontLineHeight, lineHeight):
            let value = lineHeight - fontLineHeight
            return CGFloat(round(10 * value) / 10)
        case let .lineSpacing(spacing):
            return spacing
        }
    }

    var verticalPadding: CGFloat? {
        switch self {
        case let .lineHeight(fontLineHeight, lineHeight):
            let value = (lineHeight - fontLineHeight) / 2
            return CGFloat(round(10 * value) / 10)
        case .lineSpacing:
            return nil
        }
    }

    var lineHeight: CGFloat? {
        switch self {
        case let .lineHeight(_, lineHeight):
            return lineHeight
        case .lineSpacing:
            return nil
        }
    }
}
