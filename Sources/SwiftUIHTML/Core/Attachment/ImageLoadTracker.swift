//  Copyright © 2026 PRND. All rights reserved.
import Foundation

@MainActor
final class ImageLoadTracker {
    static let shared = ImageLoadTracker()

    private var inFlight: Set<String> = []

    func begin(url: URL?) {
        guard let url else { return }
        let key = url.absoluteString
        let (inserted, _) = inFlight.insert(key)
        if inserted {
            AttachmentDebugLogger.record("[ImageLoadTracker] begin \(key) inflight=\(inFlight.count)")
        }
    }

    func end(url: URL?) {
        guard let url else { return }
        let key = url.absoluteString
        if inFlight.remove(key) != nil {
            AttachmentDebugLogger.record("[ImageLoadTracker] end \(key) inflight=\(inFlight.count)")
        }
    }

    func waitUntilIdle(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !inFlight.isEmpty {
            if Date() >= deadline {
                let urls = inFlight.sorted()
                let suffix = urls.isEmpty ? "" : " urls=\(urls)"
                AttachmentDebugLogger.record("[ImageLoadTracker] timeout inflight=\(inFlight.count)\(suffix)")
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }
}
