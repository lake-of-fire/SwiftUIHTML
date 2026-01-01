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
            contents.append(contentsOf: child.toElement(
                configuration: configuration,
                with: styleContainer
            ))
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
    @MainActor
    func toElement(configuration: HTMLConfiguration, with styleContainer: HTMLStyleContainer) -> [TagElement] {
        switch self {
        case let .text(text) where text.isEmpty:
            return []

        case let .text(text):
            return [
                .inline(InlineElement(
                    tag: "_text",
                    attributes: [:],
                    text: text,
                    styleContainer: styleContainer
                ))
            ]

        case let .node(childNode):
            return childNode
                .makeElement(
                    configuration: configuration,
                    with: styleContainer
                )
        }
    }
}


fileprivate extension HTMLNode {
    @MainActor
    func makeElement(configuration: HTMLConfiguration, with styleContainer: HTMLStyleContainer) -> [TagElement] {
        var _styleContainer = styleContainer
        configuration.applyStyles(tag: tag, attributes: attributes, to: &_styleContainer)

        if tag == "ruby",
           let rubyData = rubyAttachmentData(from: children, styleContainer: _styleContainer) {
            return [
                .inline(InlineElement(
                    tag: tag,
                    attributes: rubyData,
                    type: .attachment,
                    styleContainer: _styleContainer
                ))
            ]
        }

        switch configuration.tagType(of: tag) {
        case .inline:
            var contents: [TagElement] = []
            contents.reserveCapacity(children.count)
            for child in children {
                contents.append(contentsOf: child.toElement(
                    configuration: configuration,
                    with: _styleContainer
                ))
            }
            return contents

        case .attachment:
            return [
                .inline(InlineElement(
                    tag: tag,
                    attributes: attributes,
                    type: .attachment,
                    styleContainer: _styleContainer
                ))
            ]

        case .block, .none:
            return [
                .block(toElement(
                    configuration: configuration,
                    with: _styleContainer
                ))
            ]
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

        return result
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
                    let trimmedText = node.plainText().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
                        if hasRuby {
                            rubyText.append(" ")
                        }
                        rubyText.append(trimmedText)
                        hasRuby = true
                    }
                case "rp", "rtc":
                    continue
                case "rb":
                    let text = node.plainText()
                    if !text.isEmpty {
                        baseText.append(text)
                        hasBase = true
                    }
                default:
                    let text = node.plainText()
                    if !text.isEmpty {
                        baseText.append(text)
                        hasBase = true
                    }
                }
            }
        }

        return (base: hasBase ? baseText : nil, ruby: hasRuby ? rubyText : nil)
    }

    func plainText() -> String {
        var result = ""
        for child in children {
            switch child {
            case let .text(text):
                result.append(text)
            case let .node(node):
                result.append(node.plainText())
            }
        }
        return result
    }
}
