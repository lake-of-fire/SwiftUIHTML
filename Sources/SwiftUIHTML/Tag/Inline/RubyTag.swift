//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct RubyTag: InlineAttachmentTag {
    public let attributes: [String: AttributeValue]

    public init(attributes: [String : AttributeValue]) {
        self.attributes = attributes
    }

    public var body: some View {
        RubyInlineLabel(
            baseText: baseText,
            rubyText: rubyText,
            font: baseFont,
            rubyFont: rubyFont,
            rubyPosition: rubyPosition,
            rubyScale: rubyScale,
            foregroundColor: foregroundColor
        )
    }
}

private extension RubyTag {
    var baseText: String {
        attributes["ruby-base"]?.string ?? ""
    }

    var rubyText: String {
        attributes["ruby-text"]?.string ?? ""
    }

    var rubyPosition: CTRubyPosition {
        switch attributes["ruby-position"]?.string {
        case "after": return .after
        case "before": return .before
        case "interCharacter": return .interCharacter
        case "inline": return .inline
        default: return .before
        }
    }

    var rubyScale: CGFloat {
        attributes["ruby-scale"]?.cgFloat ?? 0.58
    }

    var foregroundColor: Color? {
        if let cssStyle = attributes["style"]?.cssStyle,
           let color = cssStyle["color"]?.toColor() {
            return color
        }
        if let color = attributes["ruby-color"]?.toColor() {
            return color
        }
        return nil
    }

    var baseFont: PlatformFont? {
        if let fontName = attributes["ruby-font-name"]?.string,
           let size = attributes["ruby-font-size"]?.cgFloat,
           let font = PlatformFont(name: fontName, size: size) {
            return font
        }

        let cssStyle = attributes["style"]?.cssStyle ?? .empty
        let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: nil)
        if let font {
            return font
        }

        if let size = cssStyle["font-size"]?.string {
            let resolvedSize = CSSFontUtility.parseSize(fromFontSize: size, baseSize: PlatformFont.systemFontSize)
            return PlatformFont.systemFont(ofSize: resolvedSize)
        }

        return nil
    }

    var rubyFont: PlatformFont? {
        if let fontName = attributes["ruby-annotation-font-name"]?.string,
           let size = attributes["ruby-annotation-font-size"]?.cgFloat,
           let font = PlatformFont(name: fontName, size: size) {
            return font
        }
        return baseFont
    }
}

private struct RubyInlineLabel: View {
    let baseText: String
    let rubyText: String
    let font: PlatformFont?
    let rubyFont: PlatformFont?
    let rubyPosition: CTRubyPosition
    let rubyScale: CGFloat
    let foregroundColor: Color?

    var body: some View {
#if os(macOS)
        RubyTextRepresentable(attributedText: attributedText)
#else
        RubyTextRepresentable(attributedText: attributedText)
#endif
    }

    private var attributedText: NSAttributedString {
        let base = baseText.isEmpty ? rubyText : baseText
        guard !base.isEmpty else { return NSAttributedString(string: "") }
        guard !rubyText.isEmpty else {
            return NSAttributedString(string: base, attributes: baseAttributes)
        }

        var rubyAttributes: [CFString: Any] = [
            kCTRubyAnnotationSizeFactorAttributeName: rubyScale,
            kCTRubyAnnotationScaleToFitAttributeName: false,
        ]
        if let rubyFont {
            rubyAttributes[kCTFontAttributeName] = rubyFont
        }

        let annotation = CTRubyAnnotationCreateWithAttributes(
            .auto,
            .auto,
            rubyPosition,
            rubyText as CFString,
            rubyAttributes as CFDictionary
        )

        var attributes = baseAttributes
        attributes[kCTRubyAnnotationAttributeName as NSAttributedString.Key] = annotation
        return NSAttributedString(string: base, attributes: attributes)
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font {
            attributes[.font] = font
        }
        if let foregroundColor {
#if os(macOS)
            attributes[.foregroundColor] = NSColor(foregroundColor)
#else
            attributes[.foregroundColor] = UIColor(foregroundColor)
#endif
        }
        return attributes
    }
}

#if os(macOS)
private struct RubyTextRepresentable: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> RubyTextView {
        let view = RubyTextView()
        view.attributedText = attributedText
        return view
    }

    func updateNSView(_ nsView: RubyTextView, context: Context) {
        nsView.attributedText = attributedText
    }
}
#else
private struct RubyTextRepresentable: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> RubyTextView {
        let view = RubyTextView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.attributedText = attributedText
        return view
    }

    func updateUIView(_ uiView: RubyTextView, context: Context) {
        uiView.attributedText = attributedText
    }
}
#endif

private final class RubyTextView: PlatformView {
    var attributedText: NSAttributedString? {
        didSet {
            guard oldValue != attributedText else { return }
#if os(macOS)
            needsDisplay = true
            invalidateIntrinsicContentSize()
#else
            setNeedsDisplay()
            invalidateIntrinsicContentSize()
#endif
        }
    }

#if os(macOS)
    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawText(in: context, rect: bounds)
    }
#else
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawText(in: context, rect: rect)
    }
#endif

    override var intrinsicContentSize: CGSize {
        guard let attributedText, attributedText.length > 0 else {
            return .zero
        }
        let line = CTLineCreateWithAttributedString(attributedText as CFAttributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let idealWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)).rounded(.up)
        let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let glyphHeight = glyphBounds.height
        let height = (glyphHeight.isNormal && glyphHeight > 0 ? glyphHeight : (ascent + descent + leading)).rounded(.up)
        return CGSize(width: idealWidth, height: height)
    }

    private func drawText(in context: CGContext, rect: CGRect) {
        guard let attributedText, attributedText.length > 0 else { return }

        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let line = CTLineCreateWithAttributedString(attributedText as CFAttributedString)

        let endAttributes = attributedText.attributes(at: max(0, attributedText.length - 1), effectiveRange: nil)
        let token = NSAttributedString(string: "\u{2026}", attributes: endAttributes)
        let tokenLine = CTLineCreateWithAttributedString(token as CFAttributedString)

        let truncated = CTLineCreateTruncatedLine(line, Double(rect.width), .end, tokenLine) ?? line

        let glyphBounds = CTLineGetBoundsWithOptions(truncated, [.useGlyphPathBounds])
        let baselineX = rect.minX - glyphBounds.origin.x
        let baselineY = rect.minY - glyphBounds.origin.y
        context.textPosition = CGPoint(x: baselineX, y: baselineY)

        CTLineDraw(truncated, context)
        context.restoreGState()
    }
}
