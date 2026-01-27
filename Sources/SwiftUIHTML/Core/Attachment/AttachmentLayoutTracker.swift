//  Copyright © 2026 PRND. All rights reserved.
import Foundation

actor AttachmentLayoutTracker {
    static let shared = AttachmentLayoutTracker()

    private var lastUpdate: Date = .distantPast
    private var lastCounts: AttachmentCounts?

    struct AttachmentCounts: Sendable {
        let expected: Int
        let expectedImages: Int
        let prepared: Int
        let uniqueKeys: Int
    }

    func markUpdated() {
        lastUpdate = Date()
    }

    func recordCounts(_ counts: AttachmentCounts) {
        lastCounts = counts
    }

    func snapshotCounts() -> AttachmentCounts? {
        lastCounts
    }

    func waitUntilIdle(timeoutSeconds: TimeInterval, quietSeconds: TimeInterval = 0.35) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            let last = lastUpdate
            if Date().timeIntervalSince(last) >= quietSeconds {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
