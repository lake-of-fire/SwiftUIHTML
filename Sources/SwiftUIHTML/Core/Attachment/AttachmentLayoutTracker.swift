//  Copyright © 2026 PRND. All rights reserved.
import Foundation

actor AttachmentLayoutTracker {
    static let shared = AttachmentLayoutTracker()

    private var lastUpdate: Date = .distantPast

    func markUpdated() {
        lastUpdate = Date()
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
