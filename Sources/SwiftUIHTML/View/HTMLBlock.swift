//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI


public struct HTMLBlock: View {
    enum GroupContent: Equatable {
        case block(BlockElement)
        case inline([InlineElement])
    }

    let element: BlockElement

    @HTMLEnvironment(\._configuration) var configuration
    private var shouldLogMargins: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_MARGIN_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_MARGIN_LOGS")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
    private var shouldLogBlocks: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_BLOCK_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_BLOCK_LOGS")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    public init(element: BlockElement) {
        self.element = element
    }

    public var body: some View {
        let groups = groupContents(contents: element.contents)
        let margins = groups.map { group in
            switch group {
            case .block(let child):
                return Self.blockMargins(for: child.attributes)
            case .inline:
                return (top: CGFloat.zero, bottom: CGFloat.zero)
            }
        }
        let canCollapseParentEdges = !Self.hasPaddingOrBorder(attributes: element.attributes)
        if shouldLogMargins {
            for (index, group) in groups.enumerated() {
                guard case let .block(child) = group else { continue }
                let prevIndex = Self.previousBlockIndex(before: index, in: groups)
                let nextIndex = Self.nextBlockIndex(after: index, in: groups)
                let isFirstBlock = Self.isFirstContentBlock(at: index, in: groups)
                let isLastBlock = Self.isLastContentBlock(at: index, in: groups)
                let prevBottom = prevIndex.map { margins[$0].bottom } ?? 0
                let collapseTop = isFirstBlock && canCollapseParentEdges
                    ? margins[index].top
                    : (prevIndex != nil ? Self.collapseAmount(prevBottom: prevBottom, currentTop: margins[index].top) : 0)
                let dropBottom = isLastBlock && canCollapseParentEdges ? margins[index].bottom : 0
                AttachmentDebugLogger.record(
                    "[Margin] tag=\(child.tag) index=\(index) top=\(margins[index].top) bottom=\(margins[index].bottom) collapseTop=\(collapseTop) dropBottom=\(dropBottom) prevBottom=\(prevBottom) collapseEdges=\(canCollapseParentEdges)"
                )
            }
        }
        return VStack(alignment: .leading, spacing: .zero) {
            ForEach(Array(groups.indices), id: \.self) { index in
                let group = groups[index]
                let prevIndex = Self.previousBlockIndex(before: index, in: groups)
                let nextIndex = Self.nextBlockIndex(after: index, in: groups)
                let isFirstBlock = Self.isFirstContentBlock(at: index, in: groups)
                let isLastBlock = Self.isLastContentBlock(at: index, in: groups)
                let prevBottom = prevIndex.map { margins[$0].bottom } ?? 0
                let collapseTop = isFirstBlock && canCollapseParentEdges
                    ? margins[index].top
                    : (prevIndex != nil ? Self.collapseAmount(prevBottom: prevBottom, currentTop: margins[index].top) : 0)
                let dropBottom = isLastBlock && canCollapseParentEdges ? margins[index].bottom : 0
                renderContent(
                    group,
                    applyTopPadding: true,
                    collapseTop: collapseTop,
                    dropBottom: dropBottom,
                    logBlock: shouldLogBlocks,
                    blockIndex: index
                )
            }
        }
    }
}

// MARK: - private
private extension HTMLBlock {
    @ViewBuilder
    func renderContent(
        _ groupContent: GroupContent,
        applyTopPadding: Bool,
        collapseTop: CGFloat,
        dropBottom: CGFloat,
        logBlock: Bool,
        blockIndex: Int
    ) -> some View {
        switch groupContent {
        case .block(let childElement):
            VStack(alignment: .leading, spacing: .zero) {
                configuration
                    .createBlock(element: childElement)
            }
            .modifier(
                configuration.attributeStyle
                    .eraseToAnyLayoutModifier(attributes: childElement.attributes)
            )
            .padding(.top, -collapseTop)
            .padding(.bottom, -dropBottom)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .hidden()
                        .onAppear {
                            AttachmentDebugLogger.record(
                                "[BlockFrame] tag=\(childElement.tag) index=\(blockIndex) global=\(frame)"
                            )
                        }
                        .onChange(of: frame) { newValue in
                            AttachmentDebugLogger.record(
                                "[BlockFrame] tag=\(childElement.tag) index=\(blockIndex) global=\(newValue)"
                            )
                        }
                }
            )
        case .inline(let elements):
            renderInline(
                elements: elements,
                applyTopPadding: applyTopPadding
            )
        }
    }

    @ViewBuilder
    func renderInline(
        elements: [InlineElement],
        applyTopPadding: Bool
    ) -> some View {
        // attachment 만 독립적으로 있는경우는 Inline 말고 View로 render
        if elements.count == 1, let element = elements.first, case .attachment = element.type {
            configuration.createAttachment(for: element.tag, with: element.attributes)
                .modifier(LinkModifier(link: element.styleContainer.link))
        } else {
            HTMLInline(
                elements: elements,
                applyTopPadding: applyTopPadding,
                applyBottomPadding: true
            )
        }
    }

    func groupContents(contents: [TagElement]) -> [GroupContent] {
        var result: [GroupContent] = []
        result.reserveCapacity(contents.count)
        var currentInlineGroup: [InlineElement] = []

        for content in contents {
            switch content {
            case let .block(blockElement):
                if !currentInlineGroup.isEmpty {
                    if !Self.isTrimmableWhitespaceInlineGroup(currentInlineGroup) {
                        result.append(.inline(currentInlineGroup))
                    }
                    currentInlineGroup.removeAll(keepingCapacity: true)
                }
                result.append(.block(blockElement))

            case let .inline(inlineElement):
                currentInlineGroup.append(inlineElement)
            }
        }

        if !currentInlineGroup.isEmpty,
           !Self.isTrimmableWhitespaceInlineGroup(currentInlineGroup) {
            result.append(.inline(currentInlineGroup))
        }
        return result
    }
}

private extension HTMLBlock.GroupContent {
    var isBlock: Bool {
        if case .block = self {
            return true
        }
        return false
    }
}

private extension HTMLBlock {
    static func blockMargins(for attributes: [String: AttributeValue]) -> (top: CGFloat, bottom: CGFloat) {
        let cssStyle = attributes["style"]?.cssStyle ?? .empty
        if let insets = cssStyle["margin"]?.toEdgeInsets() {
            return (insets.top, insets.bottom)
        } else if let value = cssStyle["margin"]?.cgFloat {
            return (value, value)
        }
        let top = cssStyle["margin-top"]?.cgFloat ?? 0
        let bottom = cssStyle["margin-bottom"]?.cgFloat ?? 0
        return (top, bottom)
    }

    static func collapseAmount(prevBottom: CGFloat, currentTop: CGFloat) -> CGFloat {
        if prevBottom >= 0, currentTop >= 0 {
            return min(prevBottom, currentTop)
        }
        if prevBottom <= 0, currentTop <= 0 {
            return max(prevBottom, currentTop)
        }
        return 0
    }

    static func hasPaddingOrBorder(attributes: [String: AttributeValue]) -> Bool {
        let cssStyle = attributes["style"]?.cssStyle ?? .empty
        return hasPadding(cssStyle) || hasBorder(cssStyle)
    }

    static func hasPadding(_ cssStyle: CSSStyle) -> Bool {
        if let insets = cssStyle["padding"]?.toEdgeInsets() {
            return insets.top != 0 || insets.leading != 0 || insets.bottom != 0 || insets.trailing != 0
        }
        if let value = cssStyle["padding"]?.cgFloat, value != 0 {
            return true
        }
        if let top = cssStyle["padding-top"]?.cgFloat, top != 0 { return true }
        if let right = cssStyle["padding-right"]?.cgFloat, right != 0 { return true }
        if let bottom = cssStyle["padding-bottom"]?.cgFloat, bottom != 0 { return true }
        if let left = cssStyle["padding-left"]?.cgFloat, left != 0 { return true }
        return false
    }

    static func hasBorder(_ cssStyle: CSSStyle) -> Bool {
        if let value = cssStyle["border-width"]?.cgFloat, value != 0 {
            return true
        }
        if let top = cssStyle["border-top-width"]?.cgFloat, top != 0 { return true }
        if let right = cssStyle["border-right-width"]?.cgFloat, right != 0 { return true }
        if let bottom = cssStyle["border-bottom-width"]?.cgFloat, bottom != 0 { return true }
        if let left = cssStyle["border-left-width"]?.cgFloat, left != 0 { return true }
        if let shorthand = cssStyle["border"]?.string,
           let numeric = shorthand.split(separator: " ").first,
           let width = Double(numeric.replacingOccurrences(of: "px", with: "")),
           width != 0 {
            return true
        }
        return false
    }

    static func isWhitespaceOnlyInlineGroup(_ elements: [InlineElement]) -> Bool {
        for element in elements {
            switch element.type {
            case .attachment:
                return false
            case let .text(string):
                if !ASCIIWhitespace.trim(string).isEmpty {
                    return false
                }
            }
        }
        return true
    }

    static func isTrimmableWhitespaceInlineGroup(_ elements: [InlineElement]) -> Bool {
        for element in elements {
            switch element.type {
            case .attachment:
                return false
            case let .text(string):
                if !ASCIIWhitespace.trim(string).isEmpty {
                    return false
                }
            }
        }
        return true
    }

    static func previousBlockIndex(before index: Int, in groups: [GroupContent]) -> Int? {
        guard index > 0 else { return nil }
        var cursor = index - 1
        while cursor >= 0 {
            switch groups[cursor] {
            case .block:
                return cursor
            case .inline(let elements):
                if isWhitespaceOnlyInlineGroup(elements) {
                    cursor -= 1
                    continue
                }
                return nil
            }
        }
        return nil
    }

    static func nextBlockIndex(after index: Int, in groups: [GroupContent]) -> Int? {
        guard index + 1 < groups.count else { return nil }
        var cursor = index + 1
        while cursor < groups.count {
            switch groups[cursor] {
            case .block:
                return cursor
            case .inline(let elements):
                if isWhitespaceOnlyInlineGroup(elements) {
                    cursor += 1
                    continue
                }
                return nil
            }
        }
        return nil
    }

    static func isFirstContentBlock(at index: Int, in groups: [GroupContent]) -> Bool {
        guard case .block = groups[index] else { return false }
        guard index > 0 else { return true }
        var cursor = index - 1
        while cursor >= 0 {
            switch groups[cursor] {
            case .block:
                return false
            case .inline(let elements):
                if !isWhitespaceOnlyInlineGroup(elements) {
                    return false
                }
            }
            cursor -= 1
        }
        return true
    }

    static func isLastContentBlock(at index: Int, in groups: [GroupContent]) -> Bool {
        guard case .block = groups[index] else { return false }
        guard index + 1 < groups.count else { return true }
        var cursor = index + 1
        while cursor < groups.count {
            switch groups[cursor] {
            case .block:
                return false
            case .inline(let elements):
                if !isWhitespaceOnlyInlineGroup(elements) {
                    return false
                }
            }
            cursor += 1
        }
        return true
    }
}

private extension HTMLBlock {}

extension HTMLBlock: @preconcurrency Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.element == rhs.element
    }
}
