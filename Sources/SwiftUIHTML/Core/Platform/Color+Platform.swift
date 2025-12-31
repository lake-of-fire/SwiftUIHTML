//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public extension Color {
    static var platformSystemGray4: Color {
#if os(macOS)
        return Color(nsColor: NSColor.systemGray.withAlphaComponent(0.35))
#else
        return Color(.systemGray4)
#endif
    }

    static var platformSystemGray5: Color {
#if os(macOS)
        return Color(nsColor: NSColor.systemGray.withAlphaComponent(0.25))
#else
        return Color(.systemGray5)
#endif
    }

    static var platformSystemGray6: Color {
#if os(macOS)
        return Color(nsColor: NSColor.systemGray.withAlphaComponent(0.18))
#else
        return Color(.systemGray6)
#endif
    }
}
