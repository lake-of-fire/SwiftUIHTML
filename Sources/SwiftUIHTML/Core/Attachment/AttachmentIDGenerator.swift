//  Copyright © 2026 PRND. All rights reserved.
import Foundation

@MainActor
enum AttachmentIDGenerator {
    private static var counter: Int = 0

    static func next() -> Int {
        counter += 1
        return counter
    }

    static func reset() {
        counter = 0
    }
}
