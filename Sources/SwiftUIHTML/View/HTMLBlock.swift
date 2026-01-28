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
    private var shouldLogLayout: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_LAYOUT_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_LAYOUT_LOGS")
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
        let collapseEnabled = configuration.collapseBlockMargins
        let isBodyRoot = element.tag.lowercased() == "body"
        let canCollapseParentEdges = collapseEnabled && !isBodyRoot && !Self.hasPaddingOrBorder(attributes: element.attributes)
        if shouldLogMargins {
            for (index, group) in groups.enumerated() {
                guard case let .block(child) = group else { continue }
                let prevIndex = Self.previousBlockIndex(before: index, in: groups)
                let nextIndex = Self.nextBlockIndex(after: index, in: groups)
                let isFirstBlock = Self.isFirstContentBlock(at: index, in: groups)
                let isLastBlock = Self.isLastContentBlock(at: index, in: groups)
                let prevBottom = prevIndex.map { margins[$0].bottom } ?? 0
                let collapseTop = canCollapseParentEdges
                    ? (isFirstBlock ? margins[index].top : (prevIndex != nil ? Self.collapseAmount(prevBottom: prevBottom, currentTop: margins[index].top) : 0))
                    : 0
                let dropBottom = canCollapseParentEdges && isLastBlock ? margins[index].bottom : 0
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
                let collapseTop = canCollapseParentEdges
                    ? (isFirstBlock ? margins[index].top : (prevIndex != nil ? Self.collapseAmount(prevBottom: prevBottom, currentTop: margins[index].top) : 0))
                    : 0
                let dropBottom = canCollapseParentEdges && isLastBlock ? margins[index].bottom : 0
                renderContent(
                    group,
                    applyTopPadding: true,
                    applyBottomPadding: true,
                    collapseTop: collapseTop,
                    dropBottom: dropBottom,
                    logBlock: shouldLogBlocks,
                    blockIndex: index
                )
            }
        }
        .background(
            GeometryReader { proxy in
                let size = proxy.size
                Color.clear
                    .hidden()
                    .onAppear {
                        if shouldLogLayout {
                            AttachmentDebugLogger.record("[Layout][BlockRoot] tag=\(element.tag) size=\(size)")
                        }
                    }
                    .onChange(of: size) { newValue in
                        if shouldLogLayout {
                            AttachmentDebugLogger.record("[Layout][BlockRoot] tag=\(element.tag) size=\(newValue)")
                        }
                    }
            }
        )
    }
}

// MARK: - private
private extension HTMLBlock {
    @ViewBuilder
    func renderContent(
        _ groupContent: GroupContent,
        applyTopPadding: Bool,
        applyBottomPadding: Bool,
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
                    let size = proxy.size
                    Color.clear
                        .hidden()
                        .onAppear {
                            AttachmentDebugLogger.record(
                                "[BlockFrame] tag=\(childElement.tag) index=\(blockIndex) global=\(frame)"
                            )
                            if logBlock {
                                AttachmentDebugLogger.record(
                                    "[Layout][Block] tag=\(childElement.tag) index=\(blockIndex) size=\(size)"
                                )
                            }
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
                applyTopPadding: true,
                applyBottomPadding: true
            )
        }
    }

    @ViewBuilder
    func renderInline(
        elements: [InlineElement],
        applyTopPadding: Bool,
        applyBottomPadding: Bool
    ) -> some View {
        // attachment 만 독립적으로 있는경우는 Inline 말고 View로 render
        if let attachmentElement = Self.singleAttachment(in: elements) {
            let size = ElementSize(attributes: attachmentElement.attributes)
            let _ = shouldLogLayout ? AttachmentDebugLogger.record(
                "[Layout][InlineSingleAttachment] tag=\(attachmentElement.tag) size=\(String(describing: size.width))x\(String(describing: size.height))"
            ) : ()
            if let attachment = configuration.createAttachment(
                for: attachmentElement.tag,
                with: attachmentElement.attributes
            ) {
                let attachmentView = attachment
                    .modifier(LinkModifier(link: attachmentElement.styleContainer.link))
                if let width = size.width, let height = size.height {
                    attachmentView.frame(width: width, height: height, alignment: .topLeading)
                } else if let width = size.width {
                    attachmentView.aspectRatio(contentMode: .fit).frame(width: width)
                } else if let height = size.height {
                    attachmentView.aspectRatio(contentMode: .fit).frame(height: height)
                } else {
                    attachmentView
                }
            } else {
                EmptyView()
            }
        } else {
            HTMLInline(
                elements: elements,
                applyTopPadding: applyTopPadding,
                applyBottomPadding: applyBottomPadding
            )
            .background(
                GeometryReader { proxy in
                    let size = proxy.size
                    Color.clear
                        .hidden()
                        .onAppear {
                            if shouldLogLayout {
                                AttachmentDebugLogger.record("[Layout][Inline] size=\(size)")
                            }
                        }
                        .onChange(of: size) { newValue in
                            if shouldLogLayout {
                                AttachmentDebugLogger.record("[Layout][Inline] size=\(newValue)")
                            }
                        }
                }
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
            return max(prevBottom, currentTop)
        }
        if prevBottom <= 0, currentTop <= 0 {
            return min(prevBottom, currentTop)
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

    static func singleAttachment(in elements: [InlineElement]) -> InlineElement? {
        var attachment: InlineElement?
        for element in elements {
            switch element.type {
            case .attachment:
                if attachment != nil {
                    return nil
                }
                attachment = element
            case let .text(string):
                if !ASCIIWhitespace.trim(string).isEmpty {
                    return nil
                }
            }
        }
        return attachment
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

    static func isFirstInlineGroup(at index: Int, in groups: [GroupContent]) -> Bool {
        guard index >= 0, index < groups.count else { return false }
        guard case let .inline(elements) = groups[index],
              !isWhitespaceOnlyInlineGroup(elements) else { return false }
        var cursor = index - 1
        while cursor >= 0 {
            switch groups[cursor] {
            case .block:
                return false
            case .inline(let prevElements):
                if !isWhitespaceOnlyInlineGroup(prevElements) {
                    return false
                }
            }
            cursor -= 1
        }
        return true
    }

    static func isLastInlineGroup(at index: Int, in groups: [GroupContent]) -> Bool {
        guard index >= 0, index < groups.count else { return false }
        guard case let .inline(elements) = groups[index],
              !isWhitespaceOnlyInlineGroup(elements) else { return false }
        var cursor = index + 1
        while cursor < groups.count {
            switch groups[cursor] {
            case .block:
                return false
            case .inline(let nextElements):
                if !isWhitespaceOnlyInlineGroup(nextElements) {
                    return false
                }
            }
            cursor += 1
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
