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

    func rubyAnnotationStyle(from children: [HTMLChild], baseFont: PlatformFont?) -> (size: CGFloat?, name: String?)? {
        var size: CGFloat?
        var name: String?
        for child in children {
            guard case let .node(node) = child, node.tag == "rt" else { continue }
            guard let cssStyle = node.attributes["style"]?.cssStyle else { continue }
            if size == nil, let fontSize = cssStyle["font-size"]?.string {
                let baseSize = baseFont?.pointSize ?? PlatformFont.systemFontSize
                size = CSSFontUtility.parseSize(fromFontSize: fontSize, baseSize: baseSize)
            }
            if name == nil, let font = CSSFontUtility.createFont(fromCSSStyle: cssStyle, currentFont: baseFont) {
                name = font.fontName
            }
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
        var rubyText = ""
        var hasBase = false
        var hasRuby = false

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
                    var rubyBuffer = ""
                    rubyBuffer.reserveCapacity(16)
                    node.appendPlainText(into: &rubyBuffer)
                    let trimmedText = ASCIIWhitespace.trim(rubyBuffer)
                    if !trimmedText.isEmpty {
                        if hasRuby {
                            rubyText.append(" ")
                        }
                        rubyText.append(contentsOf: trimmedText)
                        hasRuby = true
                    }
                case "rp", "rtc":
                    continue
                case "rb":
                    let before = baseText.count
                    node.appendPlainText(into: &baseText)
                    if baseText.count > before {
                        hasBase = true
                    }
                default:
                    let before = baseText.count
                    node.appendPlainText(into: &baseText)
                    if baseText.count > before {
                        hasBase = true
                    }
                }
            }
        }

        return (base: hasBase ? baseText : nil, ruby: hasRuby ? rubyText : nil)
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
