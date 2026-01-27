//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI


struct TextLineModifier: ViewModifier {
    typealias TextLine = HTMLInline.TextLine
    @HTMLEnvironment(\.styleContainer) var styleContainer
    let textLine: TextLine
    let applyTopPadding: Bool
    let applyBottomPadding: Bool

    init(
        textLine: TextLine,
        applyTopPadding: Bool = true,
        applyBottomPadding: Bool = true
    ) {
        self.textLine = textLine
        self.applyTopPadding = applyTopPadding
        self.applyBottomPadding = applyBottomPadding
    }

    func body(content: Content) -> some View {
        content
            .lineSpacing(lineSpacing)
            .padding(.top, applyTopPadding ? verticalPadding : 0)
            .padding(.bottom, applyBottomPadding ? verticalPadding : 0)
    }

    var lineSpacing: CGFloat {
        max(0, max(textLine.lineSpacing, styleContainer.textLine?.lineSpacing ?? 0))
    }

    var verticalPadding: CGFloat {
        max(0, max(textLine.verticalPadding, styleContainer.textLine?.verticalPadding ?? 0))
    }
}
