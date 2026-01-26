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
    private static let diagnosticLogDirectory: URL = {
        URL(fileURLWithPath: "/tmp/swiftuihtml-ios-diag", isDirectory: true)
    }()

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
        AttachmentDebugLogger.clear()
        AttachmentDebugLogger.record("[TestHarness] snapshot start: \(testName)")
        let rootView = view.background(Color.white).compositingGroup().ignoresSafeArea()
        let hostingView = UIHostingController(rootView: rootView).view!

        let viewController = UIViewController()
        viewController.view.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor)
        ])

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = viewController
        window.makeKeyAndVisible()

        try await Task.sleep(for: sleepDuration)

        await MainActor.run {
            viewController.view.layoutIfNeeded()
            viewController.view.setNeedsLayout()
            hostingView.invalidateIntrinsicContentSize()
        }

        guard let renderedView = findActualRenderedView(in: hostingView) else {
            throw SnapshotError.viewNotFound
        }
        renderedView.layoutIfNeeded()

        let waitImages = await ImageLoadTracker.shared.waitUntilIdle(timeoutSeconds: 5)
        AttachmentDebugLogger.record("[Snapshot] imageLoadIdle=\(waitImages)")
        let waitLayout = await AttachmentLayoutTracker.shared.waitUntilIdle(timeoutSeconds: 3)
        AttachmentDebugLogger.record("[Snapshot] layoutIdle=\(waitLayout)")
        logImageViewDiagnostics(in: hostingView)

        let scale = UIScreen.main.scale
        let image = makeSnapshotImage(of: renderedView, scale: scale)
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
        ensureSnapshotArtifactsDirectory(filePath: filePath)
        let failure = verifySnapshot(
            of: renderedView,
            as: .image,
            named: name,
            record: recording,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
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
        attachDebugLogs(testName: testName, name: name)
    }

    /// Snapshot error type
    enum SnapshotError: Error {
        case viewNotFound
    }
    
    /// Find actual rendered view 
    private static func findActualRenderedView(in hostingView: UIView) -> UIView? {
        // Always render the hosting view, then crop to content bounds.
        hostingView
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
        var image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        if image.cgImage == nil {
            image = renderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
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

    private static func recordIssue(
        _ message: String,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        XCTFail(message, file: filePath, line: line)
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


    private static func ensureSnapshotArtifactsDirectory(filePath: StaticString) {
        if ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] != nil {
            return
        }
        let artifactsUrl = URL(fileURLWithPath: "/tmp/swiftuihtml-ios-artifacts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: artifactsUrl, withIntermediateDirectories: true)
            setenv("SNAPSHOT_ARTIFACTS", artifactsUrl.path, 1)
        } catch {
            // If we cannot create the folder, continue without overriding SNAPSHOT_ARTIFACTS.
        }
    }

    private static func attachDebugLogs(testName: String, name: String?) {
        let logs = AttachmentDebugLogger.dump()
        guard !logs.isEmpty else { return }
        print("SWIFTUIHTML_ATTACHMENT_LOGS_BEGIN")
        print(logs)
        print("SWIFTUIHTML_ATTACHMENT_LOGS_END")
        let logURL = snapshotLogURL(testName: testName, name: name)
        appendDiagnosticLog(logs, to: logURL)
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

        guard let newStats = ocrStats(for: image, label: "new") else { return }
        AttachmentDebugLogger.record(
            "[OCR] new textRectCount=\(newStats.count) topPadding=\(newStats.topPadding) bottomPadding=\(newStats.bottomPadding) imageSize=\(newStats.imageSize)"
        )
        saveOCROverlay(
            image: image,
            rects: newStats.rects,
            outputDir: "/tmp/swiftuihtml-ocr/ios",
            filename: "\(safeTestName).\(identifier).ocr.png"
        )

        if let baselineImage = loadBaselineImage(
            filePath: filePath,
            testName: safeTestName,
            identifier: identifier
        ), let baselineStats = ocrStats(for: baselineImage, label: "baseline") {
            let deltaTop = newStats.topPadding - baselineStats.topPadding
            let deltaBottom = newStats.bottomPadding - baselineStats.bottomPadding
            AttachmentDebugLogger.record(
                "[OCR] baseline textRectCount=\(baselineStats.count) topPadding=\(baselineStats.topPadding) bottomPadding=\(baselineStats.bottomPadding) imageSize=\(baselineStats.imageSize) deltaTop=\(deltaTop) deltaBottom=\(deltaBottom)"
            )
            saveOCROverlay(
                image: baselineImage,
                rects: baselineStats.rects,
                outputDir: "/tmp/swiftuihtml-ocr/ios-baseline",
                filename: "\(safeTestName).\(identifier).baseline.ocr.png"
            )
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
                topPadding: 0,
                bottomPadding: 0,
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

        let minY = rects.map(\.minY).min() ?? 0
        let maxY = rects.map(\.maxY).max() ?? 0
        let topPadding = minY
        let bottomPadding = max(0, imageHeight - maxY)
        return OCRStats(
            rects: rects,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
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
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let imageSize: CGSize

        var count: Int { rects.count }
    }
}
#endif
