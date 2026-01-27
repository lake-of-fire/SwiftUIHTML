//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI


public struct HTMLText: View {
    let text: String
    let applyVerticalPadding: Bool

    @HTMLEnvironment(\.styleContainer) var styleContainer

    public init(_ text: String, applyVerticalPadding: Bool = true) {
        self.text = text
        self.applyVerticalPadding = applyVerticalPadding
    }

    public var body: some View {
        Text(AttributedString(
            text,
            attributes: styleContainer.toAttributeContainer()
        ))
        .modifier(TextLineModifier(textLine: HTMLInline.TextLine(
            lineSpacing: styleContainer.textLine?.lineSpacing ?? .zero,
            verticalPadding: styleContainer.textLine?.verticalPadding ?? .zero
        ), applyTopPadding: applyVerticalPadding, applyBottomPadding: applyVerticalPadding))
    }
}
