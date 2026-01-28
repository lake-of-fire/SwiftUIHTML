//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI


struct InnerLayoutModifier: ViewModifier {
    let cssStyle: CSSStyle

    func body(content: Content) -> some View {
        let width = cssStyle["width"]?.cgFloat
        let height = cssStyle["height"]?.cgFloat
        let minWidth = cssStyle["min-width"]?.cgFloat ?? width
        let maxWidth = cssStyle["max-width"]?.cgFloat
        let minHeight = cssStyle["min-height"]?.cgFloat ?? height
        let maxHeight = cssStyle["max-height"]?.cgFloat
        content
            .frame(
                minWidth: minWidth,
                idealWidth: width,
                maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: height,
                maxHeight: maxHeight,
                alignment: getAlignment()
            )
    }
}

private extension InnerLayoutModifier {
    func getAlignment() -> Alignment {
       if let alignValue = cssStyle["align"]?.string {
           switch alignValue {
           case "center":
               return .center
           case "left":
               return .topLeading
           case "right":
               return .topTrailing
           default:
               return .topLeading
           }
       }
       return .topLeading
   }
}
