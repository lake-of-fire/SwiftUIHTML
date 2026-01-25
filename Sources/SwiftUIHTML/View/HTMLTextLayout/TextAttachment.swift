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
        if bounds.size.width <= 1 || bounds.size.height <= 1 {
            return bounds.size
        }
#if os(macOS)
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

        let final = CGSize(
            width: bounds.size.width,
            height: max(targetHeight, adjustedHeight)
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
        let adjustedSize = getAdjustedSize()
#if os(macOS)
        let fontHeight = font.manabiFontHeight
        let boundHeight = adjustedSize.height
#else
        let fontHeight = font.manabiFontHeight
        let boundHeight = adjustedSize.height
#endif
        let lineHeight = lineHeightOverride ?? textLine?.lineHeight ?? fontHeight

        var verticalOffset = (boundHeight - fontHeight) / 2

        if lineHeight < boundHeight {
            verticalOffset -= (boundHeight - lineHeight) / 2
        }
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
