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
    var cssStyle: CSSStyle {
        attributes["style"]?.cssStyle ?? .empty
    }

    var baseText: String {
        attributes["ruby-base"]?.string ?? ""
    }

    var rubyText: String {
        attributes["ruby-text"]?.string ?? ""
    }

    var rubyPosition: CTRubyPosition {
        let raw = attributes["ruby-position"]?.string ?? cssStyle["ruby-position"]?.string
        switch raw {
        case "over": return .before
        case "under": return .after
        case "inter-character": return .interCharacter
        case "after": return .after
        case "before": return .before
        case "interCharacter": return .interCharacter
        case "inline": return .inline
        default: return .before
        }
    }

    var rubyScale: CGFloat {
        if let explicit = attributes["ruby-scale"]?.cgFloat {
            return explicit
        }
        if attributes["ruby-annotation-font-size"] != nil || attributes["ruby-annotation-font-name"] != nil {
            return 1.0
        }
        return 0.58
    }

    var foregroundColor: Color? {
        if let color = cssStyle["color"]?.toColor() {
            return color
        }
        if let color = attributes["ruby-color"]?.toColor() {
            return color
        }
        return nil
    }

    var baseFont: PlatformFont? {
        if let size = attributes["ruby-font-size"]?.cgFloat {
            if let fontName = attributes["ruby-font-name"]?.string,
               let font = PlatformFont(name: fontName, size: size) {
                return font
            }
            return PlatformFont.systemFont(ofSize: size)
        }

        let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: nil)
        if let font {
            return font
        }

        if let size = cssStyle["font-size"]?.string {
            let resolvedSize = CSSFontUtility.parseSize(fromFontSize: size, baseSize: PlatformFont.systemFontSize)
            return PlatformFont.systemFont(ofSize: resolvedSize)
        }

        return PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
    }

    var rubyFont: PlatformFont? {
        if let size = attributes["ruby-annotation-font-size"]?.cgFloat {
            if let fontName = attributes["ruby-annotation-font-name"]?.string,
               let font = PlatformFont(name: fontName, size: size) {
                return font
            }
            if let baseFont {
                return baseFont.withSize(size)
            }
            return PlatformFont.systemFont(ofSize: size)
        }
        return baseFont ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize * rubyScale)
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
            .fixedSize()
#else
        RubyTextRepresentable(attributedText: attributedText)
            .fixedSize()
#endif
    }

    private var attributedText: NSAttributedString {
        let base = baseText.isEmpty ? rubyText : baseText
        guard !base.isEmpty else { return NSAttributedString(string: "") }
        guard !rubyText.isEmpty else {
            logRubyDiagnostics(base: base, ruby: rubyText)
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
        logRubyDiagnostics(base: base, ruby: rubyText)
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

    private func logRubyDiagnostics(base: String, ruby: String) {
        let baseFontName = font?.fontName ?? "nil"
        let baseFontSize = font.map { "\($0.pointSize)" } ?? "nil"
        let rubyFontName = rubyFont?.fontName ?? "nil"
        let rubyFontSize = rubyFont.map { "\($0.pointSize)" } ?? "nil"
        let color = resolvedForegroundColor() ?? "nil"
        let key = "ruby-\(base)-\(ruby)-\(rubyPosition.rawValue)-\(rubyScale)-\(baseFontName)-\(rubyFontName)"
        AttachmentDebugLogger.recordOnce(
            key,
            message: "[Ruby] base='\(base)' ruby='\(ruby)' position=\(rubyPosition) scale=\(rubyScale) baseFont=\(baseFontName)@\(baseFontSize) rubyFont=\(rubyFontName)@\(rubyFontSize) color=\(color)"
        )
    }

    private func resolvedForegroundColor() -> String? {
        guard let foregroundColor else { return nil }
#if os(macOS)
        let nsColor = NSColor(foregroundColor)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        return String(format: "rgba(%.3f,%.3f,%.3f,%.3f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
#else
        let uiColor = UIColor(foregroundColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "rgba(%.3f,%.3f,%.3f,%.3f)", r, g, b, a)
#endif
    }
}

#if os(macOS)
private struct RubyTextRepresentable: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> RubyTextView {
        let view = RubyTextView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
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
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureForTransparentRendering()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForTransparentRendering()
    }

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
    private func configureForTransparentRendering() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
#else
    private func configureForTransparentRendering() {
        backgroundColor = .clear
        isOpaque = false
    }
#endif

#if os(macOS)
    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawText(in: context, rect: bounds)
    }
#else
    override func draw(_ rect: CGRect) {
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
        let height = (ascent + descent + leading).rounded(.up)
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
            || NSClassFromString("XCTestCase") != nil {
            let bounds = CTLineGetBoundsWithOptions(
                line,
                [.useGlyphPathBounds, .useOpticalBounds]
            )
            AttachmentDebugLogger.recordOnce(
                "ruby-view-metrics-\(attributedText.string.hashValue)",
                message: "[RubyView] text='\(attributedText.string)' ascent=\(ascent) descent=\(descent) leading=\(leading) bounds=\(bounds) intrinsic=\(CGSize(width: idealWidth, height: height))"
            )
        }
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
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(truncated, &ascent, &descent, &leading)
        let baselineX = rect.minX - glyphBounds.origin.x
        let baselineY = rect.minY + descent
        context.textPosition = CGPoint(x: baselineX, y: baselineY)

        CTLineDraw(truncated, context)
        context.restoreGState()
    }
}
