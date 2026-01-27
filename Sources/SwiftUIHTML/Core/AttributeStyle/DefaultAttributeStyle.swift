//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI


public struct DefaultAttributeStyler: AttributeStyleable {
    public init() {

    }

    public func layoutStyle(attributes: [String: AttributeValue]) -> some ViewModifier {
        let cssStyle = attributes["style"]?.cssStyle ?? .empty
        return LayoutStyleModifier(cssStyle: cssStyle)
    }

    public func applyStyles(
        attributes: [String : AttributeValue],
        to styleContainer: inout HTMLStyleContainer
    ) {
        guard let cssStyle = attributes["style"]?.cssStyle else { return }

        if let color = cssStyle["color"]?.toColor() {
            styleContainer.foregroundColor = color
        }

        if let color = cssStyle["background-color"]?.toColor() {
            styleContainer.backgroundColor = color
        }

        if let newFont = CSSFontUtility.createFont(
            fromCSSStyle: cssStyle,
            currentFont: styleContainer.uiFont
        ) {
            styleContainer.uiFont = newFont
        }

        if let rawLineHeight = cssStyle["line-height"]?.string,
           let font = styleContainer.uiFont,
           let lineHeight = resolveLineHeight(rawLineHeight, font: font) {
            styleContainer.textLine = .lineHeight(font: font, lineHeight: lineHeight)
        } else if let lineSpacing = cssStyle["line-spacing"]?.cgFloat {
            styleContainer.textLine = .lineSpacing(spacing: lineSpacing)
        }

        if let wordBreak = cssStyle["word-break"]?.string {
            switch wordBreak {
            case "break-all":
                styleContainer.lineBreakMode = .byCharWrapping
            case "inherit":
                break // Noting
            default:
                styleContainer.lineBreakMode = .byWordWrapping
            }
        }
    }
}

private func resolveLineHeight(_ rawValue: String, font: PlatformFont) -> CGFloat? {
    let trimmed = ASCIIWhitespace.trim(rawValue)
    guard !trimmed.isEmpty else { return nil }
    let value = String(trimmed)
    let lowered = value.lowercased()

    if lowered == "normal" || lowered == "inherit" || lowered == "initial" || lowered == "unset" {
        return font.manabiLineHeight
    }

    if lowered.hasSuffix("px")
        || lowered.hasSuffix("pt")
        || lowered.hasSuffix("em")
        || lowered.hasSuffix("rem")
        || lowered.hasSuffix("%") {
        return CSSFontUtility.parseSize(fromFontSize: value, baseSize: font.pointSize)
    }

    if let multiplier = Double(lowered) {
        return font.pointSize * CGFloat(multiplier)
    }

    return nil
}
