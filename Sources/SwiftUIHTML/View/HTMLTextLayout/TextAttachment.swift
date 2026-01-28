//  Copyright © 2025 PRND. All rights reserved.
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class TextAttachment: NSTextAttachment {

    let key: AnyHashable
    let font: PlatformFont?
    let textLine: HTMLStyleContainer.TextLineAttribute?

    init(
        key: AnyHashable,
        styleContainer: HTMLStyleContainer
    ) {
        self.key = key
        self.font = styleContainer.uiFont
        self.textLine = styleContainer.textLine
        super.init(data: nil, ofType: nil)
        self.image = PlatformImage.manabiEmpty(size: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSize(_ size: CGSize) {
        guard size.width > 1 && size.height > 1 else {
            bounds = CGRect(origin: .zero, size: .invisible)
            return
        }
        bounds = CGRect(origin: .zero, size: size)
    }

    func getAdjustedSize() -> CGSize {
        guard let font else { return bounds.size }
#if os(macOS)
        if bounds.size.width <= 1 || bounds.size.height <= 1 {
            return bounds.size
        }
        let targetHeight = round(max(font.manabiBoundingBoxMaxY, font.manabiLineHeight))
#else
        let targetHeight = round(font.manabiBoundingBoxMaxY)
#endif
        var adjustedHeight = bounds.size.height

        switch textLine {
        case let .lineHeight(_, lineHeight):
#if os(macOS)
            if lineHeight > 0, bounds.size.height / lineHeight >= 1.6 {
                adjustedHeight += targetHeight - font.manabiLineHeight
            } else {
                adjustedHeight += targetHeight - lineHeight
            }
#else
            adjustedHeight += targetHeight - lineHeight
#endif
        case .lineSpacing, .none:
            adjustedHeight += targetHeight - font.manabiLineHeight
        }

        let finalHeight: CGFloat
#if os(macOS)
        finalHeight = max(bounds.size.height, targetHeight, adjustedHeight)
#else
        finalHeight = max(targetHeight, adjustedHeight)
#endif
        let final = CGSize(
            width: bounds.size.width,
            height: finalHeight
        )
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
            || NSClassFromString("XCTestCase") != nil {
            AttachmentDebugLogger.record(
                "[Attachment] size key=\(key) bounds=\(bounds.size) targetHeight=\(targetHeight) adjustedHeight=\(adjustedHeight) lineHeight=\(textLine?.lineHeight ?? -1) final=\(final)"
            )
        }
        return final
    }

    func getAdjustedOffset(point: CGPoint, lineHeightOverride: CGFloat? = nil) -> CGPoint {
        guard let font else { return point }
        if bounds.size.width <= 1 || bounds.size.height <= 1 {
            return point
        }
        if isRubyAttachment {
            let metrics = rubyMetrics()
            let fontHeight = font.manabiFontHeight
            let lineHeight = lineHeightOverride ?? textLine?.lineHeight ?? fontHeight
            let ascent = metrics?.ascent ?? fontHeight
            let descent = metrics?.descent ?? max(0, fontHeight - ascent)
            let extraBelow: CGFloat
            if let metrics {
                switch metrics.position {
                case .after: extraBelow = metrics.extra
                case .before: extraBelow = 0
                default: extraBelow = metrics.extra / 2
                }
            } else {
                extraBelow = 0
            }
            let adjusted = CGPoint(x: point.x, y: point.y - extraBelow)
            if ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS"] == "1"
                || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
                || NSClassFromString("XCTestCase") != nil {
                let rubyPosition = metrics.map { Int($0.position.rawValue) } ?? -1
                AttachmentDebugLogger.record(
                    "[Attachment][Ruby] offset key=\(key) point=\(point) boundsH=\(bounds.size.height) fontHeight=\(fontHeight) lineHeight=\(lineHeight) ascent=\(ascent) descent=\(descent) extra=\(metrics?.extra ?? -1) position=\(rubyPosition) extraBelow=\(extraBelow) adjusted=\(adjusted)"
                )
            }
            return adjusted
        }
#if os(macOS)
        let fontHeight = font.manabiFontHeight
        let boundHeight = getAdjustedSize().height
#else
        let fontHeight = font.manabiFontHeight
        let boundHeight = getAdjustedSize().height
#endif
        let lineHeight = lineHeightOverride ?? textLine?.lineHeight ?? fontHeight
        let centerOffset = boundHeight / 2
        let heightDelta = max(0, boundHeight - lineHeight)
        let verticalOffset = centerOffset - heightDelta / 2
        let adjusted = CGPoint(x: point.x, y: point.y - boundHeight + verticalOffset)
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
            || NSClassFromString("XCTestCase") != nil {
            AttachmentDebugLogger.record(
                "[Attachment] offset key=\(key) point=\(point) boundsH=\(bounds.size.height) adjustedH=\(boundHeight) fontHeight=\(fontHeight) lineHeight=\(lineHeight) lineHeightOverride=\(lineHeightOverride ?? -1) verticalOffset=\(verticalOffset) adjusted=\(adjusted)"
            )
        }
        return adjusted
    }

}

extension TextAttachment {
    var isRubyAttachment: Bool {
        guard let textType = key.base as? TextType else { return false }
        guard case let .attachment(_, tag, _, _) = textType else { return false }
        return tag == "ruby"
    }

    struct RubyMetrics {
        let ascent: CGFloat
        let descent: CGFloat
        let extra: CGFloat
        let position: CTRubyPosition
    }

    func rubyMetrics() -> RubyMetrics? {
        guard isRubyAttachment, let font else { return nil }
        let ctFont = font.manabiCTFont
        let baseAscent = CTFontGetAscent(ctFont)
        let baseDescent = CTFontGetDescent(ctFont)
        let baseLeading = CTFontGetLeading(ctFont)
        let baseHeight = baseAscent + baseDescent + baseLeading
        let extra = max(0, bounds.size.height - baseHeight)
        let position = rubyPosition
        let extraAbove: CGFloat
        let extraBelow: CGFloat
        switch position {
        case .before:
            extraAbove = extra
            extraBelow = 0
        case .after:
            extraAbove = 0
            extraBelow = extra
        default:
            extraAbove = extra / 2
            extraBelow = extra / 2
        }
        return RubyMetrics(
            ascent: baseAscent + extraAbove,
            descent: baseDescent + extraBelow,
            extra: extra,
            position: position
        )
    }
}

private extension TextAttachment {
    var rubyPosition: CTRubyPosition {
        guard let textType = key.base as? TextType else { return .before }
        guard case let .attachment(_, _, attributes, _) = textType else { return .before }
        let cssStyle = attributes["style"]?.cssStyle ?? .empty
        let raw = attributes["ruby-position"]?.string ?? cssStyle["ruby-position"]?.string
        switch raw?.lowercased() {
        case "over": return .before
        case "under": return .after
        case "inter-character": return .interCharacter
        case "intercharacter": return .interCharacter
        case "alternate": return .before
        case "alternate over": return .before
        case "alternate under": return .after
        case "after": return .after
        case "before": return .before
        case "inline": return .inline
        default: return .before
        }
    }
}
