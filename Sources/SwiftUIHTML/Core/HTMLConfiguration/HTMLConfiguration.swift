//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI


public struct HTMLConfiguration: @unchecked Sendable {
    enum TagType {
        case block
        case inline
        case attachment
    }

    public var collapseBlockMargins: Bool = false
    var dictionary: [String: HTMLTagElementable.Type] = [:]
    var dictionaryType: [String: TagType] = [:]
    var attributeStyle: any AttributeStyleable = EmptyAttributeStyle()

    public init() {
        // 최소한 정의
        self = register(
            tag: "html", "head", "div", "body", "p", "header", "main", "section", "footer", "h1", "h2",
            renderer: DefaultBlockTag.self
        )
        .register(
            tag: "span",
            renderer: DefaultInlineTag.self
        )
        .register(
            tag: "a",
            renderer: LinkTag.self
        )
        .register(
            tag: "b", "strong",
            renderer: BoldTag.self
        )
        .register(
            tag: "i", "em",
            renderer: ItalicTag.self
        )
        .register(
            tag: "u",
            renderer: UnderlineTag.self
        )
        .register(
            tag: "rb", "rt", "rp", "rtc", "rbc",
            renderer: DefaultInlineTag.self
        )
        .register(tag: "ruby", renderer: RubyTag.self)
        .register(tag: "img", renderer: ImageTag.self)
    }
}

extension HTMLConfiguration {
    public func attributeStyler(_ style: any AttributeStyleable) -> Self {
        var copy = self
        copy.attributeStyle = style
        return copy
    }

    public func collapsingBlockMargins(_ enabled: Bool) -> Self {
        var copy = self
        copy.collapseBlockMargins = enabled
        return copy
    }
}

extension HTMLConfiguration {
    @inline(__always)
    func cacheKey() -> Int {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(type(of: attributeStyle)))

        if !dictionaryType.isEmpty {
            for key in dictionaryType.keys.sorted() {
                hasher.combine(key)
                if let type = dictionaryType[key] {
                    switch type {
                    case .block: hasher.combine(1)
                    case .inline: hasher.combine(2)
                    case .attachment: hasher.combine(3)
                    }
                } else {
                    hasher.combine(0)
                }
            }
        }

        if !dictionary.isEmpty {
            for key in dictionary.keys.sorted() {
                hasher.combine(key)
                if let renderer = dictionary[key] {
                    hasher.combine(ObjectIdentifier(renderer))
                } else {
                    hasher.combine(0)
                }
            }
        }
        return hasher.finalize()
    }
}


// MARK: - Internal Helper
@MainActor
extension HTMLConfiguration {
    @inline(__always)
    func tagType(of tag: String) -> TagType? {
        dictionaryType[tag]
    }

    @inline(__always)
    func applyStyles(tag: String, attributes: [String: AttributeValue], to styleContainer: inout HTMLStyleContainer) {
        attributeStyle.applyStyles(attributes: attributes, to: &styleContainer)
        dictionary[tag]?.applyStyles(with: attributes, to: &styleContainer)
    }

    @ViewBuilder
    func createBlock(element: BlockElement) -> some View {
        if let view = dictionary[element.tag] as? any BlockTag.Type  {
            AnyView(view.init(element: element))
        } else {
            AnyView(HTMLBlock(element: element))
        }
    }


    @MainActor
    func createAttachment(for tag: String, with attributes: [String: AttributeValue]) -> AnyView? {
        guard let view = dictionary[tag] as? any InlineAttachmentTag.Type else {
            return nil
        }
        return AnyView(view.init(attributes: attributes))
    }
}
