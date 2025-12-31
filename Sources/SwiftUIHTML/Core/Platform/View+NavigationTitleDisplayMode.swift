//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI

public extension View {
    @ViewBuilder
    func applyInlineNavigationTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
