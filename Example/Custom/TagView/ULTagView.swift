//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI

import SwiftUIHTML


struct ULTagView: BlockTag {
    let element: BlockElement

    @HTMLEnvironment(\.listIndentCount) var indentCount

    init(element: BlockElement) {
        self.element = element
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lilist(element: element), id: \.0) { _, element in
                liTag(liElement: element)
            }
        }
        .padding(.leading, indent(indentCount))
        .htmlEnvironment(\.listIndentCount, indentCount + 1)
    }

    func liTag(liElement: BlockElement) -> some View {
        let isImageOnly = liIsImageOnly(liElement)
        let alignment: VerticalAlignment = isImageOnly ? .center : .firstTextBaseline
        return HStack(alignment: alignment, spacing: .zero) {
            markerView(isImageOnly: isImageOnly)
            VStack(alignment: .leading, spacing: 4) {
                HTMLBlock(element: liElement)
            }
        }
    }

    @ViewBuilder
    func markerView(isImageOnly: Bool) -> some View {
        let marker = HTMLText(" • ", applyVerticalPadding: false)
        if isImageOnly {
            // Nudge list marker upward to visually center with image-only items.
            marker.offset(y: -0.7)
        } else {
            marker
        }
    }

    func indent(_ index: Int) -> CGFloat {
        if index == .zero { return .zero }
        return 16
    }

    func lilist(element: BlockElement) -> [(Int, BlockElement)] {
        let result: [BlockElement] = element.contents
            .compactMap {
                guard case .block(let element) = $0 else { return nil }
                return element
            }
        return Array(zip(result.indices, result))
    }

    func liIsImageOnly(_ element: BlockElement) -> Bool {
        var hasAttachment = false
        for content in element.contents {
            switch content {
            case .block:
                return false
            case .inline(let inline):
                if isInlineAttachment(inline) {
                    hasAttachment = true
                    continue
                }
                let text = inline.debugDescription
                if !ASCIIWhitespace.trim(text).isEmpty {
                    return false
                }
            }
        }
        return hasAttachment
    }

    func isInlineAttachment(_ inline: InlineElement) -> Bool {
        let tag = inline.tag.lowercased()
        if tag == "img" || inline.attributes["src"] != nil {
            return true
        }
        return false
    }
}


private struct ListIndentCountKey: HTMLEnvironmentKey {
    static let defaultValue: Int = 0
}

extension HTMLEnvironmentValues {
    var listIndentCount: Int {
        get { self[ListIndentCountKey.self] }
        set { self[ListIndentCountKey.self] = newValue }
    }
}
