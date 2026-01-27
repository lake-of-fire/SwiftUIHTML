//  Copyright © 2024 PRND. All rights reserved.
import Foundation


public struct HTMLNode: Equatable, Sendable {
    let tag: String
    let attributes: [String: AttributeValue]
    let children: [HTMLChild]

    public init(tag: String, attributes: [String: String] = [:], children: [HTMLChild] = []) {
        self.tag = tag
        self.attributes = attributes.mapValues { AttributeValue(rawValue: $0) }
        self.children = children
    }

    init(tag: String, attributes: [String: AttributeValue], children: [HTMLChild]) {
        self.tag = tag
        self.attributes = attributes
        self.children = children
    }

    public var tagName: String {
        tag
    }

    public var childrenCount: Int {
        children.count
    }
}


extension HTMLNode {
    @MainActor
    func toElement(
        configuration: HTMLConfiguration,
        with styleContainer: HTMLStyleContainer
    ) -> BlockElement {
        var contents: [TagElement] = []
        contents.reserveCapacity(children.count)
        for child in children {
            child.appendElements(
                into: &contents,
                configuration: configuration,
                with: styleContainer
            )
        }
        return BlockElement(
            tag: tag,
            attributes: attributes,
            contents: contents,
            styleContainer: styleContainer
        )
    }


}


fileprivate extension HTMLChild {
    private static let emptyAttributes: [String: AttributeValue] = [:]

    @MainActor
    @inline(__always)
    func appendElements(into contents: inout [TagElement], configuration: HTMLConfiguration, with styleContainer: HTMLStyleContainer) {
        switch self {
        case let .text(text) where text.isEmpty:
            return

        case let .text(text):
            contents.append(
                .inline(InlineElement(
                    tag: "_text",
                    attributes: Self.emptyAttributes,
                    text: text,
                    styleContainer: styleContainer
                ))
            )
            return

        case let .node(childNode):
            childNode.appendElements(
                into: &contents,
                configuration: configuration,
                with: styleContainer
            )
            return
        }
    }
}


fileprivate extension HTMLNode {
    @MainActor
    @inline(__always)
    func appendElements(into contents: inout [TagElement], configuration: HTMLConfiguration, with styleContainer: HTMLStyleContainer) {
        if tag == "rp" {
            return
        }
        var _styleContainer = styleContainer
        configuration.applyStyles(tag: tag, attributes: attributes, to: &_styleContainer)

        if tag == "ruby",
           let rubyData = rubyAttachmentData(from: children, styleContainer: _styleContainer) {
            contents.append(
                .inline(InlineElement(
                    tag: tag,
                    attributes: rubyData,
                    type: .attachment,
                    styleContainer: _styleContainer
                ))
            )
            return
        }

        switch configuration.tagType(of: tag) {
        case .inline:
            for child in children {
                child.appendElements(
                    into: &contents,
                    configuration: configuration,
                    with: _styleContainer
                )
            }
            return

        case .attachment:
            contents.append(
                .inline(InlineElement(
                    tag: tag,
                    attributes: attributes,
                    type: .attachment,
                    styleContainer: _styleContainer
                ))
            )
            return

        case .block, .none:
            contents.append(
                .block(toElement(
                    configuration: configuration,
                    with: _styleContainer
                ))
            )
            return
        }
    }
}

private extension HTMLNode {
    func rubyAttachmentData(from children: [HTMLChild], styleContainer: HTMLStyleContainer) -> [String: AttributeValue]? {
        let rubyPieces = rubyComponents(from: children)
        guard let baseText = rubyPieces.base, !baseText.isEmpty else { return nil }

        var result = attributes
        result["ruby-base"] = AttributeValue(rawValue: baseText)
        if let rubyText = rubyPieces.ruby, !rubyText.isEmpty {
            result["ruby-text"] = AttributeValue(rawValue: rubyText)
        }
        if result["ruby-position"] == nil,
           let annotationPosition = rubyAnnotationPosition(from: children) {
            result["ruby-position"] = AttributeValue(rawValue: annotationPosition)
        }

        if let font = styleContainer.uiFont {
            result["ruby-font-name"] = AttributeValue(rawValue: font.fontName)
            result["ruby-font-size"] = AttributeValue(rawValue: "\(font.pointSize)")
        }

        if let annotationStyle = rubyAnnotationStyle(from: children, baseFont: styleContainer.uiFont) {
            if let size = annotationStyle.size {
                result["ruby-annotation-font-size"] = AttributeValue(rawValue: "\(size)")
            }
            if let name = annotationStyle.name {
                result["ruby-annotation-font-name"] = AttributeValue(rawValue: name)
            }
        }

        return result
    }

    func rubyAnnotationPosition(from children: [HTMLChild]) -> String? {
        var position: String?
        func scanPosition(in node: HTMLNode) {
            if node.tag == "rt" || node.tag == "rtc" {
                if let raw = node.attributes["ruby-position"]?.string {
                    position = raw
                    return
                }
                if let cssStyle = node.attributes["style"]?.cssStyle,
                   let raw = cssStyle["ruby-position"]?.string {
                    position = raw
                    return
                }
            }
            for child in node.children {
                if case let .node(childNode) = child {
                    scanPosition(in: childNode)
                    if position != nil {
                        return
                    }
                }
            }
        }

        for child in children {
            guard case let .node(node) = child else { continue }
            scanPosition(in: node)
            if position != nil {
                break
            }
        }
        return position
    }

    func rubyAnnotationStyle(from children: [HTMLChild], baseFont: PlatformFont?) -> (size: CGFloat?, name: String?)? {
        var size: CGFloat?
        var name: String?
        func scanRTStyles(in node: HTMLNode) {
            guard node.tag == "rt" else {
                for child in node.children {
                    if case let .node(childNode) = child {
                        scanRTStyles(in: childNode)
                    }
                }
                return
            }
            guard let cssStyle = node.attributes["style"]?.cssStyle else { return }
            if size == nil, let fontSize = cssStyle["font-size"]?.string {
                let baseSize = baseFont?.pointSize ?? PlatformFont.systemFontSize
                size = CSSFontUtility.parseSize(fromFontSize: fontSize, baseSize: baseSize)
            }
            if name == nil {
                let hasExplicitFamily = cssStyle["font-family"]?.string != nil || cssStyle["font"]?.string != nil
                if hasExplicitFamily, let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: baseFont) {
                    name = font.fontName
                }
            }
        }

        for child in children {
            guard case let .node(node) = child else { continue }
            scanRTStyles(in: node)
            if size != nil && name != nil {
                break
            }
        }
        if size == nil && name == nil {
            return nil
        }
        return (size, name)
    }

    func rubyComponents(from children: [HTMLChild]) -> (base: String?, ruby: String?) {
        var baseText = ""
        var rbText = ""
        var rubyText = ""
        var hasBase = false
        var hasRuby = false
        var hasRB = false

        func appendRubyText(_ text: String) {
            let trimmed = ASCIIWhitespace.trim(text)
            if trimmed.isEmpty { return }
            let normalized = normalizedRubyWhitespace(trimmed)
            if hasRuby {
                rubyText.append("\u{00A0}")
            }
            rubyText.append(contentsOf: normalized)
            hasRuby = true
        }

        func scanRubyText(in node: HTMLNode) {
            if node.tag == "rt" {
                var rubyBuffer = ""
                rubyBuffer.reserveCapacity(16)
                node.appendPlainText(into: &rubyBuffer)
                appendRubyText(rubyBuffer)
                return
            }
            for child in node.children {
                if case let .node(childNode) = child {
                    scanRubyText(in: childNode)
                }
            }
        }

        func scanBaseText(in node: HTMLNode) {
            switch node.tag {
            case "rb":
                let before = rbText.count
                node.appendPlainText(into: &rbText)
                if rbText.count > before {
                    hasBase = true
                    hasRB = true
                }
            case "rbc":
                for child in node.children {
                    switch child {
                    case let .text(text):
                        if !text.isEmpty {
                            baseText.append(text)
                            hasBase = true
                        }
                    case let .node(childNode):
                        scanBaseText(in: childNode)
                    }
                }
            default:
                let before = baseText.count
                node.appendPlainText(into: &baseText)
                if baseText.count > before {
                    hasBase = true
                }
            }
        }

        for child in children {
            switch child {
            case let .text(text):
                if !text.isEmpty {
                    baseText.append(text)
                    hasBase = true
                }

            case let .node(node):
                switch node.tag {
                case "rt":
                    scanRubyText(in: node)
                case "rtc":
                    scanRubyText(in: node)
                    continue
                case "rp":
                    continue
                case "rb", "rbc":
                    scanBaseText(in: node)
                default:
                    scanBaseText(in: node)
                }
            }
        }

        let resolvedBase = hasRB ? rbText : baseText
        return (base: hasBase ? resolvedBase : nil, ruby: hasRuby ? rubyText : nil)
    }

    private func normalizedRubyWhitespace(_ text: Substring) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20:
                output.unicodeScalars.append(UnicodeScalar(0x00A0)!)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    func plainText() -> String {
        var result = ""
        appendPlainText(into: &result)
        return result
    }

    @inline(__always)
    func appendPlainText(into result: inout String) {
        for child in children {
            switch child {
            case let .text(text):
                result.append(text)
            case let .node(node):
                node.appendPlainText(into: &result)
            }
        }
    }
}
