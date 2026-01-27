//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI


struct HTMLInline: View {
    struct TextLine {
        let lineSpacing: CGFloat
        let verticalPadding: CGFloat
    }

    let texts: [TextType]
    let hasAttachment: Bool
    let textLine: TextLine
    let applyTopPadding: Bool
    let applyBottomPadding: Bool
    @StateObject var attachmentManager = AttachmentManager()
    @HTMLEnvironment(\.styleContainer) private var styleContainer

    init(
        elements: [InlineElement],
        applyTopPadding: Bool = true,
        applyBottomPadding: Bool = true
    ) {
        self.init(
            texts: elements.toHTMLTextType(),
            applyTopPadding: applyTopPadding,
            applyBottomPadding: applyBottomPadding
        )
    }

    init(
        texts: [TextType],
        applyTopPadding: Bool = true,
        applyBottomPadding: Bool = true
    ) {
        if Self.shouldLogInline() {
            Self.logLeadingWhitespace(texts: texts)
        }
        let trimmed = texts
            .trimmingNewLines()
            .trimmingLeadingWhitespace()
            .coalescingTextRuns()
        if trimmed.isEmpty, Self.shouldLogInline() {
            AttachmentDebugLogger.record("[Inline] empty after trimming")
        }
        self.texts = trimmed
        self.hasAttachment = trimmed.contains(where: \.hasAttachment)
        self.textLine = Self.resolveTextLine(texts: trimmed)
        self.applyTopPadding = applyTopPadding
        self.applyBottomPadding = applyBottomPadding
    }

    var body: some View {
        if texts.isEmpty {
            EmptyView()
        } else {
            content
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .topLeading) { htmlTextLayout }
                .modifier(TextLineModifier(
                    textLine: textLine,
                    applyTopPadding: applyTopPadding,
                    applyBottomPadding: applyBottomPadding
                ))
                .onAppear {
                    let styleLineSpacing = styleContainer.textLine?.lineSpacing ?? 0
                    let styleVerticalPadding = styleContainer.textLine?.verticalPadding ?? 0
                    let effectiveLineSpacing = max(textLine.lineSpacing, styleLineSpacing)
                    let effectiveVerticalPadding = max(textLine.verticalPadding, styleVerticalPadding)
                    AttachmentDebugLogger.record(
                        "[Inline] textLine spacing=\(textLine.lineSpacing) verticalPadding=\(textLine.verticalPadding) styleLineSpacing=\(styleLineSpacing) styleVerticalPadding=\(styleVerticalPadding) effectiveLineSpacing=\(effectiveLineSpacing) effectiveVerticalPadding=\(effectiveVerticalPadding)"
                    )
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .hidden()
                            .modifier(OnChangeViewModifier(of: proxy.size, initial: true) { _, newValue in
                                AttachmentDebugLogger.record("[Inline] contentSize=\(newValue)")
                            })
                    }
                )
        }
    }

    @ViewBuilder
    var htmlTextLayout: some View {
        if hasAttachment {
            HTMLTextLayout(
                attachmentManager: attachmentManager,
                texts: texts
            )
        }
    }

    var content: some View {
        texts
            .reduce(Text("")) { result, type in
                switch type {
                case let .text(string, container):
                    return result + Text(AttributedString(
                        string,
                        attributes: container.toAttributeContainer()
                    ))
                case let .newLine(container):
                    return result + Text(AttributedString(
                        "\n",
                        attributes: container.toAttributeContainer()
                    ))
                    
                case let .attachment(_, _, _, styleContainer):
                    let imageText = Text(
                        attachmentImage(for: type, styleContainer: styleContainer)
                    )
                    return result + imageText.font(.system(size: 1))
                }
            }
    }

}

private extension HTMLInline {
    static func shouldLogInline() -> Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_INLINE_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_INLINE_LOGS")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    static func resolveTextLine(texts: [TextType]) -> TextLine {
        var maxLineSpacing: CGFloat = 0
        var maxVerticalPadding: CGFloat = 0

        for text in texts {
            guard case .text(_, let attributes) = text,
                  let textLine = attributes.textLine else { continue }
            maxLineSpacing = max(maxLineSpacing, textLine.lineSpacing)
            if let verticalPadding = textLine.verticalPadding {
                maxVerticalPadding = max(maxVerticalPadding, verticalPadding)
            }
        }

        return TextLine(
            lineSpacing: maxLineSpacing,
            verticalPadding: maxVerticalPadding
        )
    }

    func attachmentImage(for type: TextType, styleContainer: HTMLStyleContainer) -> Image {
#if os(macOS)
        return Image(nsImage: attachmentManager.sizeImage(
            key: type,
            styleContainer: styleContainer
        ))
#else
        let image = attachmentManager.sizeImage(
            key: type,
            styleContainer: styleContainer
        )
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
#endif
    }

    static func logLeadingWhitespace(texts: [TextType]) {
        guard let first = texts.first else { return }
        switch first {
        case .newLine:
            AttachmentDebugLogger.record("[Inline] leading newLine")
        case let .text(string, _):
            let leading = ASCIIWhitespace.trimLeading(string)
            let trimmedCount = string.count - leading.count
            if trimmedCount > 0 {
                AttachmentDebugLogger.record("[Inline] leadingWhitespace count=\(trimmedCount) sample=\(String(string.prefix(min(24, string.count))))")
            }
        case .attachment:
            break
        }
    }
}

extension HTMLInline {
}

extension HTMLInline: @preconcurrency Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.texts == rhs.texts
    }
}

private extension Array where Element == TextType {
    // TextType의 마지막 newLine 제거
    // HTMLInline 에서 마지막이 newLine이 있다면 줄바꿈이 필요없음
    func trimmingNewLines() -> [Element] {

        // 뒤쪽의 .newLine 제거
        if let last, case .newLine = last {
            return dropLast()
        }
        return self
    }

    func trimmingLeadingWhitespace() -> [Element] {
        var result = self
        var index = 0
        while index < result.count {
            switch result[index] {
            case let .text(string, styleContainer):
                let trimmed = ASCIIWhitespace.trimLeading(string)
                if trimmed.isEmpty {
                    result.remove(at: index)
                    continue
                }
                if trimmed.count != string.count {
                    result[index] = .text(String(trimmed), styleContainer: styleContainer)
                }
                return result
            case .newLine:
                result.remove(at: index)
                continue
            case .attachment:
                return result
            }
        }
        return result
    }

    func coalescingTextRuns() -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)

        for element in self {
            switch element {
            case let .text(string, styleContainer):
                guard !string.isEmpty else { continue }
                if let last = result.last, case let .text(existing, existingStyle) = last, existingStyle == styleContainer {
                    result[result.count - 1] = .text(existing + string, styleContainer: existingStyle)
                } else {
                    result.append(.text(string, styleContainer: styleContainer))
                }
            default:
                result.append(element)
            }
        }
        return result
    }
}
