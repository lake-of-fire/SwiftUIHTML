//  Copyright © 2025 PRND. All rights reserved.
import Foundation

enum AttachmentDebugLogger {
    private static nonisolated(unsafe) let lock = NSLock()
    private static nonisolated(unsafe) var buffer: [String] = []
    private static let logFileURL: URL = {
        let env = ProcessInfo.processInfo.environment
        if let customPath = env["SWIFTUIHTML_ATTACHMENT_LOG_PATH"], !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil {
            return URL(fileURLWithPath: "/tmp/swiftuihtml-attachment.log")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftuihtml-attachment.log")
    }()

    static func record(_ message: String) {
        lock.lock()
        buffer.append(message)
        if let data = (message + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
        lock.unlock()
    }

    static func recordOnce(_ key: String, message: @autoclosure () -> String) {
        lock.lock()
        if buffer.contains(key) {
            lock.unlock()
            return
        }
        buffer.append(key)
        let rendered = message()
        buffer.append(rendered)
        if let data = (rendered + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
        lock.unlock()
    }

    static func dump() -> String {
        lock.lock()
        let output = buffer.joined(separator: "\n")
        lock.unlock()
        return output
    }

    static func clear() {
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        let env = ProcessInfo.processInfo.environment
        let shouldPreserveLog = env["SWIFTUIHTML_ATTACHMENT_LOG_PRESERVE"] == "1"
            || env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
        if !shouldPreserveLog {
            try? FileManager.default.removeItem(at: logFileURL)
        }
        lock.unlock()
    }
}
