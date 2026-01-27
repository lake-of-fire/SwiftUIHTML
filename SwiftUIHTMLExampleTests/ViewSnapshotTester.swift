//  Copyright © 2025 PRND. All rights reserved.
#if os(iOS)
import CryptoKit
import SwiftUI
import UIKit
import XCTest
import Vision

@testable import SwiftUIHTML
@_spi(Internals) import SnapshotTesting

/// Utility class for rendering SwiftUI views in UIKit environment and generating snapshots
class ViewSnapshotTester {
    private static var diagnosticLogDirectory: URL {
        artifactsRootURL().appendingPathComponent("diag", isDirectory: true)
    }

    @MainActor
    static func snapshot<V: View>(
        of view: V,
        named name: String? = nil,
        html: String? = nil,
        record recording: Bool? = nil,
        sleep sleepDuration: Duration = .seconds(2),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) async throws {
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_ATTACHMENT_LOGS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_MARGIN_LOGS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_INLINE_LOGS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_PARSER_LOGS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_BLOCK_LOGS")
        setenv("SWIFTUIHTML_ATTACHMENT_LOGS", "1", 1)
        setenv("SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS", "1", 1)
        setenv("SWIFTUIHTML_MARGIN_LOGS", "1", 1)
        setenv("SWIFTUIHTML_INLINE_LOGS", "1", 1)
        setenv("SWIFTUIHTML_PARSER_LOGS", "1", 1)
        setenv("SWIFTUIHTML_BLOCK_LOGS", "1", 1)
        let artifactsURL = ensureSnapshotArtifactsDirectory(filePath: filePath)
        AttachmentDebugLogger.record("[Snapshot] artifactsRoot=\(artifactsURL.path)")
        rawLog("[Raw] artifactsRoot=\(artifactsURL.path)")
        setenv(
            "SWIFTUIHTML_ATTACHMENT_LOG_PATH",
            artifactsURL.appendingPathComponent("swiftuihtml-attachment.log").path,
            1
        )
        setenv("SWIFTUIHTML_ATTACHMENT_LOG_PRESERVE", "1", 1)
        AttachmentDebugLogger.clear()
        rawLog("[Raw] snapshot start: \(testName)")
        rawLog("[Raw] SNAPSHOT_ARTIFACTS=\(ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] ?? "nil")")
        writeProbeFile(testName: testName, name: name)
        writeLocationProbe(testName: testName, name: name)
        AttachmentDebugLogger.record("[TestHarness] snapshot start: \(testName)")
        let rootView = view.background(Color.white).compositingGroup().ignoresSafeArea()
        let hostingController = UIHostingController(rootView: rootView)
        let hostingView = hostingController.view!

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        try await Task.sleep(for: sleepDuration)

        await MainActor.run {
            hostingController.view.layoutIfNeeded()
            hostingController.view.setNeedsLayout()
            hostingView.invalidateIntrinsicContentSize()
        }

        let resolvedSize = resolvedSize(for: hostingController, fallbackView: hostingView)
        AttachmentDebugLogger.record("[Snapshot] resolvedSize=\(resolvedSize)")
        rawLog("[Raw] resolvedSize=\(resolvedSize)")
        hostingView.frame = CGRect(origin: .zero, size: resolvedSize)
        hostingView.bounds = CGRect(origin: .zero, size: resolvedSize)
        hostingController.view.layoutIfNeeded()
        AttachmentDebugLogger.record(
            "[Snapshot] hostingView bounds=\(hostingView.bounds) frame=\(hostingView.frame)"
        )
        rawLog("[Raw] hostingView bounds=\(hostingView.bounds) frame=\(hostingView.frame)")

        guard let renderedView = findActualRenderedView(in: hostingView) else {
            throw SnapshotError.viewNotFound
        }
        renderedView.layoutIfNeeded()
        AttachmentDebugLogger.record(
            "[Snapshot] renderedView type=\(String(describing: type(of: renderedView))) bounds=\(renderedView.bounds) frame=\(renderedView.frame)"
        )
        rawLog("[Raw] renderedView type=\(String(describing: type(of: renderedView))) bounds=\(renderedView.bounds) frame=\(renderedView.frame)")
        let bounds = contentBounds(in: hostingView)
        rawLog("[Raw] contentBounds=\(bounds)")
        writeMetricsArtifact(
            testName: testName,
            name: name,
            metrics: "resolvedSize=\(resolvedSize)\nhostingViewBounds=\(hostingView.bounds)\ncontentBounds=\(bounds)\n"
        )

        let waitImages = await ImageLoadTracker.shared.waitUntilIdle(timeoutSeconds: 5)
        AttachmentDebugLogger.record("[Snapshot] imageLoadIdle=\(waitImages)")
        let waitLayout = await AttachmentLayoutTracker.shared.waitUntilIdle(timeoutSeconds: 3)
        AttachmentDebugLogger.record("[Snapshot] layoutIdle=\(waitLayout)")
        logImageViewDiagnostics(in: hostingView)

        let snapshotting = Snapshotting<UIView, UIImage>.image()
        let image = await snapshotImage(
            of: renderedView,
            snapshotting: snapshotting
        )
        rawLog("[Raw] captured image size=\(image.size) cg=\(image.cgImage != nil)")
        logPixelMetrics(image: image, testName: testName, name: name)
        logListItemSquareMetrics(image: image, testName: testName, name: name)
        writeSnapshotArtifact(
            image: image,
            testName: testName,
            name: name,
            html: html,
            filePath: filePath
        )
        performOCRDebug(
            image: image,
            testName: testName,
            name: name,
            filePath: filePath
        )
        let shouldRecord = recording ?? (ProcessInfo.processInfo.environment["SWIFTUIHTML_SNAPSHOT_RECORD"] == "1")
        let failure = await MainActor.run {
            verifySnapshot(
                of: renderedView,
                as: snapshotting,
                named: name,
                record: shouldRecord,
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column
            )
        }
        if let message = failure {
            recordIssue(
                message,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }
        AttachmentDebugLogger.record("[TestHarness] snapshot end: \(testName)")
        rawLog("[Raw] snapshot end: \(testName)")
        attachDebugLogs(testName: testName, name: name)
    }

    /// Snapshot error type
    enum SnapshotError: Error {
        case viewNotFound
    }
    
    /// Find actual rendered view 
    private static func findActualRenderedView(in hostingView: UIView) -> UIView? {
        if let contentView = hostingView.subviews.first {
            return contentView
        }
        return hostingView
    }

    private static func makeSnapshotImage(of view: UIView, scale: CGFloat) -> UIImage {
        let size = view.bounds.size
        if size.width <= 1 || size.height <= 1 {
            return UIImage()
        }
        let format = UIGraphicsImageRendererFormat(for: UITraitCollection(displayScale: scale))
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        if image.cgImage == nil {
            image = renderer.image { ctx in
                view.layer.render(in: ctx.cgContext)
            }
        }
        if image.cgImage != nil {
            return image
        }
        if let ciImage = image.ciImage {
            let context = CIContext(options: nil)
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
            }
        }
        print("Snapshot image missing CGImage. size=\(size) scale=\(scale)")
        return image
    }

    private static func contentBounds(in rootView: UIView) -> CGRect {
        var unionRect: CGRect = .null
        for view in allDescendants(of: rootView) {
            let size = view.bounds.size
            guard size.width > 1, size.height > 1 else { continue }
            let rect = view.convert(view.bounds, to: rootView)
            unionRect = unionRect.union(rect)
        }
        if unionRect.isNull {
            return .zero
        }
        return unionRect.integral
    }

    private static func allDescendants(of rootView: UIView) -> [UIView] {
        var result: [UIView] = []
        var stack: [UIView] = [rootView]
        while let view = stack.popLast() {
            if view !== rootView {
                result.append(view)
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    private static func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let scale = image.scale
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    private static func logPixelMetrics(image: UIImage, testName: String, name: String?) {
        guard let cgImage = image.cgImage else { return }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1 && height > 1 else { return }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        var buffer = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var nonWhiteCount = 0
        let threshold: UInt8 = 250
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let offset = rowOffset + x * bytesPerPixel
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                let a = buffer[offset + 3]
                if a <= 10 { continue }
                if r < threshold || g < threshold || b < threshold {
                    nonWhiteCount += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        let label = sanitizePathComponent(testName)
        let ident = sanitizePathComponent(name ?? "1")
        if maxX >= minX && maxY >= minY {
            let top = minY
            let left = minX
            let bottom = (height - 1) - maxY
            let right = (width - 1) - maxX
            let inkRatio = Double(nonWhiteCount) / Double(width * height)
            let inkString = String(format: "%.4f", inkRatio)
            let line = "[PixelMetrics] \(label).\(ident) size=\(width)x\(height) top=\(top) left=\(left) bottom=\(bottom) right=\(right) ink=\(inkString)"
            print(line)
            AttachmentDebugLogger.record(line)
        } else {
            let line = "[PixelMetrics] \(label).\(ident) size=\(width)x\(height) no-nonwhite"
            print(line)
            AttachmentDebugLogger.record(line)
        }
    }

    private static func logListItemSquareMetrics(image: UIImage, testName: String, name: String?) {
        let label = sanitizePathComponent(testName)
        let ident = sanitizePathComponent(name ?? "1")
        let shouldMeasure = testName.contains("testListItemSquareSnapshot") || ident == "listItemSquare"
        guard shouldMeasure, let cgImage = image.cgImage else { return }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1 && height > 1 else { return }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        var buffer = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        let darkThreshold: UInt8 = 40
        let alphaThreshold: UInt8 = 10
        var visited = [Bool](repeating: false, count: width * height)
        var components: [(minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int)] = []

        func isDark(_ x: Int, _ y: Int) -> Bool {
            let idx = y * bytesPerRow + x * bytesPerPixel
            let r = buffer[idx]
            let g = buffer[idx + 1]
            let b = buffer[idx + 2]
            let a = buffer[idx + 3]
            guard a > alphaThreshold else { return false }
            return r < darkThreshold && g < darkThreshold && b < darkThreshold
        }

        for y in 0..<height {
            for x in 0..<width {
                let flat = y * width + x
                if visited[flat] || !isDark(x, y) { continue }
                var stack = [(x, y)]
                visited[flat] = true
                var cminX = x
                var cmaxX = x
                var cminY = y
                var cmaxY = y
                var count = 0
                while let (cx, cy) = stack.popLast() {
                    count += 1
                    if cx < cminX { cminX = cx }
                    if cx > cmaxX { cmaxX = cx }
                    if cy < cminY { cminY = cy }
                    if cy > cmaxY { cmaxY = cy }
                    let neighbors = [
                        (cx - 1, cy), (cx + 1, cy),
                        (cx, cy - 1), (cx, cy + 1)
                    ]
                    for (nx, ny) in neighbors where nx >= 0 && ny >= 0 && nx < width && ny < height {
                        let nflat = ny * width + nx
                        if visited[nflat] { continue }
                        if isDark(nx, ny) {
                            visited[nflat] = true
                            stack.append((nx, ny))
                        }
                    }
                }
                components.append((cminX, cminY, cmaxX, cmaxY, count))
            }
        }

        for comp in components {
            if comp.minX < minX { minX = comp.minX }
            if comp.minY < minY { minY = comp.minY }
            if comp.maxX > maxX { maxX = comp.maxX }
            if comp.maxY > maxY { maxY = comp.maxY }
        }

        let squareCandidate = components
            .filter {
                let w = $0.maxX - $0.minX + 1
                let h = $0.maxY - $0.minY + 1
                return w >= 8 && w <= 14 && h >= 8 && h <= 14
            }
            .max { $0.count < $1.count }

        guard maxX >= minX, maxY >= minY else {
            let line = "[ListSquareMetrics] \(label).\(ident) no-dark-components"
            print(line)
            AttachmentDebugLogger.record(line)
            return
        }

        if let square = squareCandidate {
            let overallCenterY = Double(minY + maxY) / 2.0
            let squareCenterY = Double(square.minY + square.maxY) / 2.0
            let delta = squareCenterY - overallCenterY
            let squareW = square.maxX - square.minX + 1
            let squareH = square.maxY - square.minY + 1
            let line = "[ListSquareMetrics] \(label).\(ident) overall=(\(minX),\(minY),\(maxX),\(maxY)) square=(\(square.minX),\(square.minY),\(square.maxX),\(square.maxY)) squareSize=\(squareW)x\(squareH) deltaCenterY=\(String(format: "%.2f", delta))"
            print(line)
            AttachmentDebugLogger.record(line)
        } else {
            let line = "[ListSquareMetrics] \(label).\(ident) squareNotFound overall=(\(minX),\(minY),\(maxX),\(maxY)) components=\(components.count)"
            print(line)
            AttachmentDebugLogger.record(line)
        }
    }

    private static func recordIssue(
        _ message: String,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        XCTFail(message, file: filePath, line: line)
    }

    @MainActor
    private static func snapshotImage<Value>(
        of value: Value,
        snapshotting: Snapshotting<Value, UIImage>
    ) async -> UIImage {
        let expectation = XCTestExpectation(description: "snapshot image")
        var result = UIImage()
        snapshotting.snapshot(value).run { image in
            result = image
            expectation.fulfill()
        }
        _ = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        return result
    }

    private static func logImageViewDiagnostics(in rootView: UIView) {
        let imageViews = allDescendants(of: rootView).compactMap { $0 as? UIImageView }
        let visibleImages = imageViews.filter { view in
            guard let image = view.image else { return false }
            let size = view.bounds.size
            return image.size.width > 0 && image.size.height > 0 && size.width > 1 && size.height > 1
        }
        let layeredViews = allDescendants(of: rootView).filter { $0.layer.contents != nil }
        AttachmentDebugLogger.record("[Snapshot] imageViews total=\(imageViews.count) visible=\(visibleImages.count) layerContents=\(layeredViews.count)")
        guard !visibleImages.isEmpty else { return }
        let frames = visibleImages.prefix(32).map { view in
            view.convert(view.bounds, to: rootView)
        }
        let summary = frames.map { "\($0.integral)" }.joined(separator: " | ")
        AttachmentDebugLogger.record("[Snapshot] imageViewFrames \(summary)")
        if !frames.isEmpty {
            let frameKeys = frames.map { "\($0.integral)" }
            let frameCounts = frameKeys.reduce(into: [String: Int]()) { counts, key in
                counts[key, default: 0] += 1
            }
            let uniqueFrames = frameCounts.count
            if let maxFrameDup = frameCounts.max(by: { $0.value < $1.value }) {
                AttachmentDebugLogger.record("[Snapshot] imageFrameDuplicates total=\(frames.count) unique=\(uniqueFrames) maxDup=\(maxFrameDup.value) sample=\(maxFrameDup.key)")
                if maxFrameDup.value > 1 && uniqueFrames <= max(1, frames.count / 2) {
                    AttachmentDebugLogger.record("[Snapshot][Heuristic] many images share the same frame (possible stacking or offset bug)")
                }
            }
        }

        let hashes: [String] = visibleImages.compactMap { view in
            guard let image = view.image else { return nil }
            return imageHash(for: image)
        }
        guard !hashes.isEmpty else { return }
        let counts = hashes.reduce(into: [String: Int]()) { counts, hash in
            counts[hash, default: 0] += 1
        }
        let uniqueCount = counts.count
        let maxDup = counts.max(by: { $0.value < $1.value })
        if let maxDup {
            AttachmentDebugLogger.record("[Snapshot] imageHashes total=\(hashes.count) unique=\(uniqueCount) maxDup=\(maxDup.value) sample=\(maxDup.key)")
            if maxDup.value > 1 && uniqueCount == 1 {
                AttachmentDebugLogger.record("[Snapshot][Heuristic] all images identical (possible stacking or reuse bug)")
            }
            if uniqueCount > 1 && uniqueCount <= max(1, hashes.count / 2) {
                AttachmentDebugLogger.record("[Snapshot][Heuristic] many images are duplicates (possible missing or repeated image bug)")
            }
        }
    }

    private static func imageHash(for image: UIImage) -> String? {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 1) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resolvedSize<V: View>(
        for hostingController: UIHostingController<V>,
        fallbackView: UIView
    ) -> CGSize {
        var proposedWidth = UIScreen.main.bounds.width
        if #available(iOS 16.0, *) {
            let unconstrained = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            let proposedSize = hostingController.sizeThatFits(in: unconstrained)
            AttachmentDebugLogger.record("[Snapshot] sizeThatFits unconstrained=\(proposedSize)")
            if proposedSize.width > 1 {
                proposedWidth = proposedSize.width
            }
        }

        let measuringSize = CGSize(width: proposedWidth, height: 10000)
        let measuringBounds = CGRect(origin: .zero, size: measuringSize)
        fallbackView.bounds = measuringBounds
        fallbackView.frame = measuringBounds
        fallbackView.layoutIfNeeded()

        var measured = CGSize.zero
        if #available(iOS 16.0, *) {
            let proposed = CGSize(width: proposedWidth, height: CGFloat.greatestFiniteMagnitude)
            measured = hostingController.sizeThatFits(in: proposed)
            AttachmentDebugLogger.record("[Snapshot] sizeThatFits proposed=\(proposed) measured=\(measured)")
        }

        let layoutSize = fallbackView.systemLayoutSizeFitting(
            CGSize(width: proposedWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if layoutSize.width > 1 && layoutSize.height > 1 {
            AttachmentDebugLogger.record("[Snapshot] systemLayoutSizeFitting=\(layoutSize)")
        }

        let candidates = [measured, layoutSize].filter { $0.width > 1 && $0.height > 1 }
        if let best = candidates.max(by: { $0.height < $1.height }) {
            return best
        }
        let intrinsicSize = fallbackView.intrinsicContentSize
        if intrinsicSize.width > 1 && intrinsicSize.height > 1 {
            AttachmentDebugLogger.record("[Snapshot] intrinsicContentSize=\(intrinsicSize)")
            return intrinsicSize
        }
        let screen = UIScreen.main.bounds.size
        AttachmentDebugLogger.record("[Snapshot] fallback screenSize=\(screen)")
        return screen
    }


    private static func ensureSnapshotArtifactsDirectory(filePath: StaticString) -> URL {
        if let existing = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"],
           !existing.isEmpty {
            return URL(fileURLWithPath: existing, isDirectory: true)
        }
        let artifactsUrl = artifactsRootURL()
        do {
            try FileManager.default.createDirectory(at: artifactsUrl, withIntermediateDirectories: true)
            setenv("SNAPSHOT_ARTIFACTS", artifactsUrl.path, 1)
        } catch {
            // If we cannot create the folder, continue without overriding SNAPSHOT_ARTIFACTS.
            AttachmentDebugLogger.record("[Snapshot] artifactsRoot create failed \(error.localizedDescription) path=\(artifactsUrl.path)")
            rawLog("[Raw] artifactsRoot create failed \(error.localizedDescription) path=\(artifactsUrl.path)")
        }
        return artifactsUrl
    }

    private static func artifactsRootURL() -> URL {
        if let existing = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"],
           !existing.isEmpty {
            return URL(fileURLWithPath: existing, isDirectory: true)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.appendingPathComponent("swiftuihtml-ios-artifacts", isDirectory: true)
        }
        let tempRoot = FileManager.default.temporaryDirectory
        if !tempRoot.path.isEmpty {
            return tempRoot.appendingPathComponent("swiftuihtml-ios-artifacts", isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/swiftuihtml-ios-artifacts", isDirectory: true)
    }

    private static func attachDebugLogs(testName: String, name: String?) {
        let bufferLogs = AttachmentDebugLogger.dump()
        let fileLogs = AttachmentDebugLogger.readLogFile()
        let logs = bufferLogs.isEmpty ? (fileLogs ?? "") : bufferLogs
        guard !logs.isEmpty else { return }
        print("SWIFTUIHTML_ATTACHMENT_LOGS_BEGIN")
        print(logs)
        print("SWIFTUIHTML_ATTACHMENT_LOGS_END")
        let logURL = snapshotLogURL(testName: testName, name: name)
        appendDiagnosticLog(logs, to: logURL)
        if let artifactsPath = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] {
            let artifactsURL = URL(fileURLWithPath: artifactsPath, isDirectory: true)
            let safeTestName = sanitizePathComponent(testName)
            let identifier = sanitizePathComponent(name ?? "1")
            let filename = "\(safeTestName).\(identifier).attachment.log"
            let artifactURL = artifactsURL.appendingPathComponent(filename)
            appendDiagnosticLog(logs, to: artifactURL)
            writeAttachmentFrameLog(
                logs: logs,
                testName: safeTestName,
                identifier: identifier,
                artifactsURL: artifactsURL
            )
        }
        let attachment = XCTAttachment(string: logs)
        attachment.name = "SwiftUIHTML Attachment Layout Logs"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "SwiftUIHTML Attachment Layout Logs") { activity in
            activity.add(attachment)
        }
        AttachmentDebugLogger.clear()
    }

    private static func snapshotLogURL(testName: String, name: String?) -> URL {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let filename = "\(safeTestName).\(identifier).log"
        return diagnosticLogDirectory.appendingPathComponent(filename)
    }

    private static func appendDiagnosticLog(_ logs: String, to url: URL) {
        let payload = logs + "\n"
        do {
            if !FileManager.default.fileExists(atPath: diagnosticLogDirectory.path) {
                try FileManager.default.createDirectory(
                    at: diagnosticLogDirectory,
                    withIntermediateDirectories: true
                )
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            if let data = payload.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            print("SWIFTUIHTML_DIAG_WRITE_FAILED: \(error.localizedDescription)")
        }
    }

    private static func writeAttachmentFrameLog(
        logs: String,
        testName: String,
        identifier: String,
        artifactsURL: URL
    ) {
        let filtered = logs
            .split(separator: "\n")
            .filter {
                $0.contains("attachmentFrame id=")
                    || $0.contains("attachmentLineRelative id=")
                    || $0.contains("attachmentSize id=")
            }
        guard !filtered.isEmpty else { return }
        let filename = "\(testName).\(identifier).attachment.frames.log"
        let url = artifactsURL.appendingPathComponent(filename)
        let payload = filtered.joined(separator: "\n") + "\n"
        do {
            try payload.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AttachmentDebugLogger.record("[Snapshot] attachment frame log write failed \(error.localizedDescription)")
        }
    }

    private static func rawLog(_ message: String) {
        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
            let url = artifactsRootURL().appendingPathComponent("swiftuihtml-raw.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
            if let artifactsPath = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"], !artifactsPath.isEmpty {
                let artifactsURL = URL(fileURLWithPath: artifactsPath, isDirectory: true)
                try? FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
                let rawURL = artifactsURL.appendingPathComponent("swiftuihtml-raw.log")
                if let handle = try? FileHandle(forWritingTo: rawURL) {
                    handle.seekToEndOfFile()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try? data.write(to: rawURL)
                }
            }
        }
    }

    private static func writeProbeFile(testName: String, name: String?) {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let timestamp = Int(Date().timeIntervalSince1970)
        let dir = artifactsRootURL()
            .appendingPathComponent("HTMLBasicTests")
        let url = dir.appendingPathComponent("_probe_\(safeTestName).\(identifier).\(timestamp).txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "probe \(timestamp)".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            rawLog("[Raw] probe write failed \(error.localizedDescription)")
        }
    }

    private static func writeLocationProbe(testName: String, name: String?) {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "_location_probe_\(safeTestName).\(identifier).\(timestamp).txt"
        var locations: [URL] = []
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        locations.append(tempURL)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            locations.append(documents.appendingPathComponent(filename))
        }
        for url in locations {
            do {
                try "probe \(timestamp)".write(to: url, atomically: true, encoding: .utf8)
                AttachmentDebugLogger.record("[Snapshot] locationProbe wrote \(url.path)")
                rawLog("[Raw] locationProbe wrote \(url.path)")
                print("SWIFTUIHTML_LOCATION_PROBE_WROTE \(url.path)")
            } catch {
                AttachmentDebugLogger.record("[Snapshot] locationProbe failed \(error.localizedDescription) path=\(url.path)")
                rawLog("[Raw] locationProbe failed \(error.localizedDescription) path=\(url.path)")
                print("SWIFTUIHTML_LOCATION_PROBE_FAILED \(error.localizedDescription) path=\(url.path)")
            }
        }
    }

    private static func writeMetricsArtifact(testName: String, name: String?, metrics: String) {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let root = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"]
            ?? "/tmp/swiftuihtml-ios-artifacts"
        let dir = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("HTMLBasicTests")
        let url = dir.appendingPathComponent("\(safeTestName).\(identifier).metrics.txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try metrics.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            rawLog("[Raw] metrics write failed \(error.localizedDescription)")
        }
        guard NSClassFromString("XCTestCase") != nil else { return }
        let attachment = XCTAttachment(string: metrics)
        attachment.name = "\(safeTestName).\(identifier).metrics"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Snapshot Metrics") { activity in
            activity.add(attachment)
        }
    }

    private static func performOCRDebug(
        image: UIImage,
        testName: String,
        name: String?,
        filePath: StaticString
    ) {
        guard NSClassFromString("XCTestCase") != nil else { return }
        let shouldOCR = ProcessInfo.processInfo.environment["SWIFTUIHTML_OCR_DEBUG"] != "0"
        guard shouldOCR else { return }
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let ocrRoot: String = {
            let root = artifactsRootURL()
            return root.appendingPathComponent("ocr", isDirectory: true).path
        }()

        guard let newStats = ocrStats(for: image, label: "new") else { return }
        AttachmentDebugLogger.record(
            "[OCR] new textRectCount=\(newStats.count) topPadding=\(newStats.topPadding) bottomPadding=\(newStats.bottomPadding) leftPadding=\(newStats.leftPadding) rightPadding=\(newStats.rightPadding) imageSize=\(newStats.imageSize)"
        )
        writeOCRDump(stats: newStats, testName: safeTestName, identifier: identifier, label: "new", outputDir: ocrRoot)
        saveOCROverlay(
            image: image,
            rects: newStats.rects,
            outputDir: ocrRoot,
            filename: "\(safeTestName).\(identifier).ocr.png"
        )
        if let newRectStats = textRectStats(for: image, label: "new-rects") {
            AttachmentDebugLogger.record(
                "[OCR] new-rects count=\(newRectStats.count) topPadding=\(newRectStats.topPadding) bottomPadding=\(newRectStats.bottomPadding) leftPadding=\(newRectStats.leftPadding) rightPadding=\(newRectStats.rightPadding) imageSize=\(newRectStats.imageSize)"
            )
            writeOCRDump(stats: newRectStats, testName: safeTestName, identifier: identifier, label: "new-rects", outputDir: ocrRoot)
        }

        if let baselineImage = loadBaselineImage(
            filePath: filePath,
            testName: safeTestName,
            identifier: identifier
        ), let baselineStats = ocrStats(for: baselineImage, label: "baseline") {
            let deltaTop = newStats.topPadding - baselineStats.topPadding
            let deltaBottom = newStats.bottomPadding - baselineStats.bottomPadding
            let deltaLeft = newStats.leftPadding - baselineStats.leftPadding
            let deltaRight = newStats.rightPadding - baselineStats.rightPadding
            AttachmentDebugLogger.record(
                "[OCR] baseline textRectCount=\(baselineStats.count) topPadding=\(baselineStats.topPadding) bottomPadding=\(baselineStats.bottomPadding) leftPadding=\(baselineStats.leftPadding) rightPadding=\(baselineStats.rightPadding) imageSize=\(baselineStats.imageSize) deltaTop=\(deltaTop) deltaBottom=\(deltaBottom) deltaLeft=\(deltaLeft) deltaRight=\(deltaRight)"
            )
            writeOCRDump(stats: baselineStats, testName: safeTestName, identifier: identifier, label: "baseline", outputDir: ocrRoot)
            logOCRLineDeltas(newStats: newStats, baselineStats: baselineStats)
            writeOCRLineDeltaReport(
                newStats: newStats,
                baselineStats: baselineStats,
                testName: safeTestName,
                identifier: identifier,
                outputDir: ocrRoot
            )
            saveOCROverlay(
                image: baselineImage,
                rects: baselineStats.rects,
                outputDir: ocrRoot + "-baseline",
                filename: "\(safeTestName).\(identifier).baseline.ocr.png"
            )
            if let baseRectStats = textRectStats(for: baselineImage, label: "baseline-rects") {
                AttachmentDebugLogger.record(
                    "[OCR] baseline-rects count=\(baseRectStats.count) topPadding=\(baseRectStats.topPadding) bottomPadding=\(baseRectStats.bottomPadding) leftPadding=\(baseRectStats.leftPadding) rightPadding=\(baseRectStats.rightPadding) imageSize=\(baseRectStats.imageSize)"
                )
                writeOCRDump(stats: baseRectStats, testName: safeTestName, identifier: identifier, label: "baseline-rects", outputDir: ocrRoot)
            }
        } else {
            AttachmentDebugLogger.record("[OCR] baseline image missing for \(safeTestName).\(identifier)")
        }
    }

    private static func ocrStats(for image: UIImage, label: String) -> OCRStats? {
        guard let cgImage = image.cgImage else {
            AttachmentDebugLogger.record("[OCR] missing CGImage (\(label))")
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "ja-JP", "ko-KR", "zh-Hans", "zh-Hant"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AttachmentDebugLogger.record("[OCR] request failed \(error.localizedDescription)")
            return nil
        }

        let observations = request.results ?? []
        if observations.isEmpty {
            return OCRStats(
                rects: [],
                texts: [],
                topPadding: 0,
                bottomPadding: 0,
                leftPadding: 0,
                rightPadding: 0,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height)
            )
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var rects: [CGRect] = []
        var texts: [String] = []
        rects.reserveCapacity(observations.count)
        texts.reserveCapacity(observations.count)
        for observation in observations {
            let bbox = observation.boundingBox
            let rect = CGRect(
                x: bbox.minX * imageWidth,
                y: (1 - bbox.maxY) * imageHeight,
                width: bbox.width * imageWidth,
                height: bbox.height * imageHeight
            )
            rects.append(rect)
            if let candidate = observation.topCandidates(1).first {
                texts.append(candidate.string)
            } else {
                texts.append("")
            }
        }

        let minY = rects.map(\.minY).min() ?? 0
        let maxY = rects.map(\.maxY).max() ?? 0
        let minX = rects.map(\.minX).min() ?? 0
        let maxX = rects.map(\.maxX).max() ?? 0
        let topPadding = minY
        let bottomPadding = max(0, imageHeight - maxY)
        let leftPadding = minX
        let rightPadding = max(0, imageWidth - maxX)
        return OCRStats(
            rects: rects,
            texts: texts,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            leftPadding: leftPadding,
            rightPadding: rightPadding,
            imageSize: CGSize(width: imageWidth, height: imageHeight)
        )
    }

    private static func textRectStats(for image: UIImage, label: String) -> OCRStats? {
        guard let cgImage = image.cgImage else {
            AttachmentDebugLogger.record("[OCR] missing CGImage (\(label))")
            return nil
        }

        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AttachmentDebugLogger.record("[OCR] rect request failed \(error.localizedDescription)")
            return nil
        }

        let observations = request.results as? [VNTextObservation] ?? []
        if observations.isEmpty {
            return OCRStats(
                rects: [],
                texts: [],
                topPadding: 0,
                bottomPadding: 0,
                leftPadding: 0,
                rightPadding: 0,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height)
            )
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var rects: [CGRect] = []
        rects.reserveCapacity(observations.count)
        for observation in observations {
            let bbox = observation.boundingBox
            let rect = CGRect(
                x: bbox.minX * imageWidth,
                y: (1 - bbox.maxY) * imageHeight,
                width: bbox.width * imageWidth,
                height: bbox.height * imageHeight
            )
            rects.append(rect)
        }

        let minX = rects.map(\.minX).min() ?? 0
        let minY = rects.map(\.minY).min() ?? 0
        let maxX = rects.map(\.maxX).max() ?? 0
        let maxY = rects.map(\.maxY).max() ?? 0
        let topPadding = minY
        let bottomPadding = max(0, imageHeight - maxY)
        let leftPadding = minX
        let rightPadding = max(0, imageWidth - maxX)

        return OCRStats(
            rects: rects,
            texts: Array(repeating: "", count: rects.count),
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            leftPadding: leftPadding,
            rightPadding: rightPadding,
            imageSize: CGSize(width: imageWidth, height: imageHeight)
        )
    }

    private static func saveOCROverlay(
        image: UIImage,
        rects: [CGRect],
        outputDir: String,
        filename: String
    ) {
        let overlay = drawOCR(image: image, rects: rects)
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            AttachmentDebugLogger.record("[OCR] create dir failed \(error.localizedDescription)")
        }
        let fileURL = outputURL.appendingPathComponent(filename)
        if let data = overlay.pngData() {
            do {
                try data.write(to: fileURL)
                AttachmentDebugLogger.record("[OCR] overlay saved \(fileURL.path)")
            } catch {
                AttachmentDebugLogger.record("[OCR] write failed \(error.localizedDescription)")
            }
        }
    }

    private static func drawOCR(image: UIImage, rects: [CGRect]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            ctx.cgContext.setStrokeColor(UIColor.red.withAlphaComponent(0.7).cgColor)
            ctx.cgContext.setLineWidth(2.0)
            for rect in rects {
                let scaledRect = CGRect(
                    x: rect.minX / image.scale,
                    y: rect.minY / image.scale,
                    width: rect.width / image.scale,
                    height: rect.height / image.scale
                )
                ctx.cgContext.stroke(scaledRect)
            }
        }
    }

    private static func sanitizePathComponent(_ string: String) -> String {
        let sanitized = string.replacingOccurrences(
            of: "\\W+",
            with: "-",
            options: .regularExpression
        )
        return sanitized.replacingOccurrences(
            of: "^-|-$",
            with: "",
            options: .regularExpression
        )
    }

    private static func writeSnapshotArtifact(
        image: UIImage,
        testName: String,
        name: String?,
        html: String?,
        filePath: StaticString
    ) {
        let artifactRoot = ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"]
            ?? "/tmp/swiftuihtml-ios-artifacts"
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let artifactDir = URL(fileURLWithPath: artifactRoot, isDirectory: true)
            .appendingPathComponent("HTMLBasicTests")
        let artifactURL = artifactDir
            .appendingPathComponent("\(safeTestName).\(identifier)")
            .appendingPathExtension("png")
        let htmlURL = artifactDir
            .appendingPathComponent("\(safeTestName).\(identifier)")
            .appendingPathExtension("html")
        do {
            try FileManager.default.createDirectory(
                at: artifactDir,
                withIntermediateDirectories: true
            )
            if let data = image.pngData() {
                try data.write(to: artifactURL)
            }
            let htmlCount = html?.count ?? 0
            AttachmentDebugLogger.record("[Snapshot] artifact html length=\(htmlCount) path=\(htmlURL.path)")
            if let html, !html.isEmpty {
                try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            }
        } catch {
            AttachmentDebugLogger.record("[Snapshot] artifact write failed \(error.localizedDescription)")
        }
        guard NSClassFromString("XCTestCase") != nil else { return }
        if let data = image.pngData() {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "\(safeTestName).\(identifier).png"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Snapshot Image") { activity in
                activity.add(attachment)
            }
        }
        if let html, !html.isEmpty {
            let attachment = XCTAttachment(string: html)
            attachment.name = "\(safeTestName).\(identifier).html"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Snapshot HTML") { activity in
                activity.add(attachment)
            }
        }
    }

    private static func loadBaselineImage(
        filePath: StaticString,
        testName: String,
        identifier: String
    ) -> UIImage? {
        let url = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
        let testsDir = url.deletingLastPathComponent()
        let snapshotDir = testsDir
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent("HTMLBasicTests")
        let fileURL = snapshotDir
            .appendingPathComponent("\(testName).\(identifier)")
            .appendingPathExtension("png")
        return UIImage(contentsOfFile: fileURL.path)
    }

    private struct OCRStats {
        let rects: [CGRect]
        let texts: [String]
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let leftPadding: CGFloat
        let rightPadding: CGFloat
        let imageSize: CGSize

        var count: Int { rects.count }
    }

    private struct OCRLine: Codable {
        let index: Int
        let rect: RectDTO
        let text: String
    }

    private struct RectDTO: Codable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    private struct OCRDump: Codable {
        let label: String
        let imageWidth: Double
        let imageHeight: Double
        let topPadding: Double
        let bottomPadding: Double
        let leftPadding: Double
        let rightPadding: Double
        let lines: [OCRLine]
    }

    private struct OCRLineDeltaReport: Codable {
        let label: String
        let count: Int
        let deltas: [OCRLineDelta]
    }

    private struct OCRLineDelta: Codable {
        let index: Int
        let newRect: RectDTO
        let baselineRect: RectDTO
        let deltaX: Double
        let deltaY: Double
        let text: String
    }

    private static func writeOCRDump(
        stats: OCRStats,
        testName: String,
        identifier: String,
        label: String,
        outputDir: String
    ) {
        let lines = clusterLines(rects: stats.rects, texts: stats.texts)
        let payload = OCRDump(
            label: label,
            imageWidth: Double(stats.imageSize.width),
            imageHeight: Double(stats.imageSize.height),
            topPadding: Double(stats.topPadding),
            bottomPadding: Double(stats.bottomPadding),
            leftPadding: Double(stats.leftPadding),
            rightPadding: Double(stats.rightPadding),
            lines: lines.enumerated().map { index, line in
                OCRLine(
                    index: index,
                    rect: RectDTO(
                        x: Double(line.rect.origin.x),
                        y: Double(line.rect.origin.y),
                        w: Double(line.rect.size.width),
                        h: Double(line.rect.size.height)
                    ),
                    text: line.text
                )
            }
        )
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let fileURL = outputURL.appendingPathComponent("\(testName).\(identifier).\(label).lines.json")
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
            AttachmentDebugLogger.record("[OCR] lines json saved \(fileURL.path)")
        } catch {
            AttachmentDebugLogger.record("[OCR] lines json write failed \(error.localizedDescription)")
        }
    }

    private static func logOCRLineDeltas(newStats: OCRStats, baselineStats: OCRStats) {
        let newLines = clusterLines(rects: newStats.rects, texts: newStats.texts)
        let baseLines = clusterLines(rects: baselineStats.rects, texts: baselineStats.texts)
        guard !newLines.isEmpty, !baseLines.isEmpty else { return }
        let count = min(newLines.count, baseLines.count)
        var samples: [String] = []
        for index in 0..<min(count, 8) {
            let newRect = newLines[index].rect
            let baseRect = baseLines[index].rect
            let delta = newRect.minY - baseRect.minY
            samples.append("line\(index) dy=\(String(format: "%.2f", delta))")
        }
        AttachmentDebugLogger.record("[OCR] lineDeltaSamples \(samples.joined(separator: ", ")) totalNew=\(newLines.count) totalBase=\(baseLines.count)")
    }

    private static func writeOCRLineDeltaReport(
        newStats: OCRStats,
        baselineStats: OCRStats,
        testName: String,
        identifier: String,
        outputDir: String
    ) {
        let newLines = clusterLines(rects: newStats.rects, texts: newStats.texts)
        let baseLines = clusterLines(rects: baselineStats.rects, texts: baselineStats.texts)
        guard !newLines.isEmpty, !baseLines.isEmpty else { return }
        let count = min(newLines.count, baseLines.count)
        let deltas: [OCRLineDelta] = (0..<count).map { index in
            let newLine = newLines[index]
            let baseLine = baseLines[index]
            return OCRLineDelta(
                index: index,
                newRect: RectDTO(
                    x: Double(newLine.rect.origin.x),
                    y: Double(newLine.rect.origin.y),
                    w: Double(newLine.rect.size.width),
                    h: Double(newLine.rect.size.height)
                ),
                baselineRect: RectDTO(
                    x: Double(baseLine.rect.origin.x),
                    y: Double(baseLine.rect.origin.y),
                    w: Double(baseLine.rect.size.width),
                    h: Double(baseLine.rect.size.height)
                ),
                deltaX: Double(newLine.rect.minX - baseLine.rect.minX),
                deltaY: Double(newLine.rect.minY - baseLine.rect.minY),
                text: newLine.text
            )
        }
        let payload = OCRLineDeltaReport(
            label: "line-deltas",
            count: count,
            deltas: deltas
        )
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let fileURL = outputURL.appendingPathComponent("\(testName).\(identifier).line-deltas.json")
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
            AttachmentDebugLogger.record("[OCR] line-deltas json saved \(fileURL.path)")
        } catch {
            AttachmentDebugLogger.record("[OCR] line-deltas json write failed \(error.localizedDescription)")
        }
    }

    private struct LineCluster {
        let rect: CGRect
        let text: String
    }

    private static func clusterLines(rects: [CGRect], texts: [String]) -> [LineCluster] {
        guard !rects.isEmpty else { return [] }
        let pairs = zip(rects, texts)
            .map { (rect: $0.0, text: $0.1) }
            .sorted { $0.rect.minY < $1.rect.minY }
        var lines: [LineCluster] = []
        var currentRects: [CGRect] = []
        var currentTexts: [String] = []
        var currentMidY: CGFloat?
        for pair in pairs {
            let midY = pair.rect.midY
            if let current = currentMidY {
                let threshold = max(4, pair.rect.height * 0.6)
                if abs(midY - current) <= threshold {
                    currentRects.append(pair.rect)
                    currentTexts.append(pair.text)
                } else {
                    lines.append(makeLineCluster(rects: currentRects, texts: currentTexts))
                    currentRects = [pair.rect]
                    currentTexts = [pair.text]
                    currentMidY = midY
                }
            } else {
                currentRects = [pair.rect]
                currentTexts = [pair.text]
                currentMidY = midY
            }
        }
        if !currentRects.isEmpty {
            lines.append(makeLineCluster(rects: currentRects, texts: currentTexts))
        }
        return lines
    }

    private static func makeLineCluster(rects: [CGRect], texts: [String]) -> LineCluster {
        var union = rects.first ?? .zero
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        let joined = texts
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        return LineCluster(rect: union, text: joined)
    }
}
#endif
