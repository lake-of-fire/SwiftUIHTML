//  Copyright © 2026 PRND. All rights reserved.
#if os(macOS)
import AppKit
import CryptoKit
import SwiftUI
@_spi(Internals) import SnapshotTesting
import Vision
import XCTest
import QuartzCore

@testable import SwiftUIHTML

/// Utility class for rendering SwiftUI views in AppKit and generating snapshots.
class MacViewSnapshotTester {
    private static let diagnosticLogDirectory: URL = {
        URL(fileURLWithPath: "/tmp/swiftuihtml-macos-diag", isDirectory: true)
    }()
    private static let artifactsDirectory: URL = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        return URL(fileURLWithPath: "/tmp/swiftuihtml-macos-artifacts-\(stamp)", isDirectory: true)
    }()

    static func iosSnapshotDirectory(filePath: StaticString = #filePath) -> String {
        let url = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        return root
            .appendingPathComponent("SwiftUIHTMLExampleTests/__Snapshots__/HTMLBasicTests")
            .path
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

    private static func baselineExists(
        snapshotDirectory: String?,
        testName: String,
        name: String?
    ) -> Bool {
        guard let snapshotDirectory else { return false }
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let url = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
            .appendingPathComponent("\(safeTestName).\(identifier)")
            .appendingPathExtension("png")
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func resolveBaselineTestName(
        snapshotDirectory: String?,
        testName: String,
        name: String?
    ) -> String {
        guard let snapshotDirectory else { return testName }
        if testName.hasSuffix("MacOS") {
            let trimmed = String(testName.dropLast("MacOS".count))
            if baselineExists(snapshotDirectory: snapshotDirectory, testName: trimmed, name: name) {
                return trimmed
            }
        }
        if testName.hasSuffix("macOS") {
            let trimmed = String(testName.dropLast("macOS".count))
            if baselineExists(snapshotDirectory: snapshotDirectory, testName: trimmed, name: name) {
                return trimmed
            }
        }
        if baselineExists(snapshotDirectory: snapshotDirectory, testName: testName, name: name) {
            return testName
        }
        return testName
    }

    private static func referencePixelSize(
        snapshotDirectory: String?,
        testName: String,
        name: String?
    ) -> CGSize? {
        guard let snapshotDirectory else { return nil }
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let url = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
            .appendingPathComponent("\(safeTestName).\(identifier)")
            .appendingPathExtension("png")
        if !FileManager.default.fileExists(atPath: url.path) {
            AttachmentDebugLogger.record("[Snapshot] baseline missing \(url.path)")
            return nil
        }
        guard
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            AttachmentDebugLogger.record("[Snapshot] baseline load failed \(url.path)")
            return nil
        }
        AttachmentDebugLogger.record("[Snapshot] baseline found \(url.lastPathComponent) px=\(cgImage.width)x\(cgImage.height)")
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static func makeSnapshotImage(
        of view: NSView,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage {
        let pixelsWide = max(1, Int(size.width * scale))
        let pixelsHigh = max(1, Int(size.height * scale))
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = size
            view.cacheDisplay(in: CGRect(origin: .zero, size: size), to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            AttachmentDebugLogger.record("[Snapshot] render=cacheDisplay px=\(pixelsWide)x\(pixelsHigh)")
            return image
        }

        if let layer = view.layer {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
            rep?.size = size
            let image = NSImage(size: size)
            if let rep, let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                layer.render(in: context.cgContext)
                NSGraphicsContext.restoreGraphicsState()
                image.addRepresentation(rep)
                AttachmentDebugLogger.record("[Snapshot] render=layerRender px=\(pixelsWide)x\(pixelsHigh)")
            }
            return image
        }

        let fallback = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        fallback?.size = size
        let image = NSImage(size: size)
        if let fallback {
            view.cacheDisplay(in: CGRect(origin: .zero, size: size), to: fallback)
            image.addRepresentation(fallback)
            AttachmentDebugLogger.record("[Snapshot] render=fallbackCache px=\(pixelsWide)x\(pixelsHigh)")
        }
        return image
    }

    @MainActor
    @available(macOS 13.0, *)
    private static func makeSnapshotImageUsingRenderer<V: View>(
        of view: V,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = scale
        renderer.isOpaque = true
        if let image = renderer.nsImage {
            let pixelsWide = max(1, Int(size.width * scale))
            let pixelsHigh = max(1, Int(size.height * scale))
            AttachmentDebugLogger.record("[Snapshot] render=imageRenderer px=\(pixelsWide)x\(pixelsHigh)")
            return image
        }
        return nil
    }

    private static func renderPDFImage(of view: NSView, size: CGSize) -> NSImage? {
        let pdfData = view.dataWithPDF(inside: view.bounds)
        guard let pdfImage = NSPDFImageRep(data: pdfData) else { return nil }
        pdfImage.size = size
        let image = NSImage(size: size)
        image.addRepresentation(pdfImage)
        return image
    }

    private static func logPaddingDiagnostics(
        image: NSImage,
        testName: String,
        name: String?,
        snapshotDirectory: String?,
        baselineTestName: String
    ) {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        let baseImage = loadBaselineImage(
            snapshotDirectory: snapshotDirectory,
            testName: sanitizePathComponent(baselineTestName),
            identifier: identifier
        )
        if let newMetrics = nonWhiteMetrics(for: image) {
            if let baseImage, let baseMetrics = nonWhiteMetrics(for: baseImage) {
                let deltaTop = newMetrics.topPadding - baseMetrics.topPadding
                let deltaBottom = newMetrics.bottomPadding - baseMetrics.bottomPadding
                AttachmentDebugLogger.record(
                    "[Padding] test=\(safeTestName).\(identifier) newTop=\(newMetrics.topPadding) newBottom=\(newMetrics.bottomPadding) baseTop=\(baseMetrics.topPadding) baseBottom=\(baseMetrics.bottomPadding) deltaTop=\(deltaTop) deltaBottom=\(deltaBottom) newNonWhiteRatio=\(newMetrics.nonWhiteRatio) baseNonWhiteRatio=\(baseMetrics.nonWhiteRatio)"
                )
            } else {
                AttachmentDebugLogger.record(
                    "[Padding] test=\(safeTestName).\(identifier) newTop=\(newMetrics.topPadding) newBottom=\(newMetrics.bottomPadding) newNonWhiteRatio=\(newMetrics.nonWhiteRatio) baselineMissing"
                )
            }
        }
    }

    private struct NonWhiteMetrics {
        let topPadding: Int
        let bottomPadding: Int
        let nonWhiteRatio: Double
    }

    private static func nonWhiteMetrics(for image: NSImage) -> NonWhiteMetrics? {
        let size = image.size
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: bytesPerPixel,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bytesPerRow,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.cgContext.setFillColor(NSColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return nil }
        let dataLength = bytesPerRow * height
        let threshold: UInt8 = 245
        var top = height
        var bottom = 0
        var nonWhiteCount = 0
        let total = width * height
        for y in 0..<height {
            var rowHasContent = false
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * bytesPerPixel
                if offset + 3 >= dataLength { break }
                let r = bytes[offset]
                let g = bytes[offset + 1]
                let b = bytes[offset + 2]
                let isNonWhite = (r < threshold || g < threshold || b < threshold)
                if isNonWhite {
                    nonWhiteCount += 1
                    rowHasContent = true
                }
            }
            if rowHasContent {
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        if top == height {
            return NonWhiteMetrics(topPadding: height, bottomPadding: 0, nonWhiteRatio: 0)
        }
        let topPadding = top
        let bottomPadding = max(0, height - 1 - bottom)
        let ratio = total > 0 ? Double(nonWhiteCount) / Double(total) : 0
        return NonWhiteMetrics(topPadding: topPadding, bottomPadding: bottomPadding, nonWhiteRatio: ratio)
    }

    private struct TrimMetrics {
        let width: Int
        let height: Int
        let x: Int
        let y: Int
        let imageWidth: Int
        let imageHeight: Int
        var bottom: Int { max(0, imageHeight - height - y) }
    }

    private static func logTrimDiagnostics(
        image: NSImage,
        testName: String,
        name: String?,
        snapshotDirectory: String?,
        baselineTestName: String
    ) {
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        guard let pngData = pngData(from: image) else { return }
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftuihtml-macos-trim-\(safeTestName)-\(identifier).png")
        do {
            try pngData.write(to: tmpURL)
        } catch {
            AttachmentDebugLogger.record("[Trim] write failed \(error.localizedDescription)")
            return
        }

        let newTrim = runTrimDiagnostics(
            imageURL: tmpURL,
            label: "new",
            testName: safeTestName,
            identifier: identifier
        )
        if let snapshotDirectory {
            let baseURL = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
                .appendingPathComponent("\(sanitizePathComponent(baselineTestName)).\(identifier)")
                .appendingPathExtension("png")
            if FileManager.default.fileExists(atPath: baseURL.path) {
                let baseTrim = runTrimDiagnostics(
                    imageURL: baseURL,
                    label: "base",
                    testName: safeTestName,
                    identifier: identifier
                )
                if let newTrim, let baseTrim {
                    let deltaTop = newTrim.y - baseTrim.y
                    let deltaBottom = newTrim.bottom - baseTrim.bottom
                    AttachmentDebugLogger.record(
                        "[TrimDelta] test=\(safeTestName).\(identifier) deltaTop=\(deltaTop) deltaBottom=\(deltaBottom)"
                    )
                }
            } else {
                AttachmentDebugLogger.record("[Trim] baseline missing for \(safeTestName).\(identifier)")
            }
        }
        try? FileManager.default.removeItem(at: tmpURL)
    }

    private static func runTrimDiagnostics(
        imageURL: URL,
        label: String,
        testName: String,
        identifier: String
    ) -> TrimMetrics? {
        let magickPath = "/opt/homebrew/bin/magick"
        let convertPath = "/opt/homebrew/bin/convert"
        let tool: String
        let usesMagick: Bool
        if FileManager.default.fileExists(atPath: magickPath) {
            tool = magickPath
            usesMagick = true
        } else if FileManager.default.fileExists(atPath: convertPath) {
            tool = convertPath
            usesMagick = false
        } else {
            tool = "magick"
            usesMagick = true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        var arguments: [String] = []
        if usesMagick {
            arguments.append("convert")
        }
        arguments.append(contentsOf: [
            imageURL.path,
            "-alpha", "remove",
            "-background", "white",
            "-flatten",
            "-fuzz", "1%",
            "-trim",
            "-format", "%w %h %X %Y",
            "info:"
        ])
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AttachmentDebugLogger.record("[Trim] \(label) convert failed \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let lastLine = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? ""
        let parts = lastLine.split(separator: " ")
        guard parts.count == 4,
              let trimW = Int(parts[0]),
              let trimH = Int(parts[1]),
              let trimX = Int(parts[2]),
              let trimY = Int(parts[3]) else {
            AttachmentDebugLogger.record("[Trim] \(label) parse failed output='\(output.trimmingCharacters(in: .whitespacesAndNewlines))'")
            return nil
        }
        let imageRep = NSImage(contentsOf: imageURL)
        let size = imageRep?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            .map { (w: $0.width, h: $0.height) }
            ?? (w: 0, h: 0)
        let metrics = TrimMetrics(
            width: trimW,
            height: trimH,
            x: trimX,
            y: trimY,
            imageWidth: size.w,
            imageHeight: size.h
        )
        AttachmentDebugLogger.record(
            "[Trim] \(label) test=\(testName).\(identifier) trimX=\(metrics.x) trimY=\(metrics.y) trimW=\(metrics.width) trimH=\(metrics.height) imgW=\(metrics.imageWidth) imgH=\(metrics.imageHeight) bottom=\(metrics.bottom)"
        )
        return metrics
    }

    @MainActor
    static func snapshot<V: View>(
        of view: V,
        width: CGFloat,
        height: CGFloat? = nil,
        named name: String? = nil,
        record recording: Bool? = nil,
        snapshotDirectory: String? = nil,
        precision: Float = 0.9,
        perceptualPrecision: Float = 0.85,
        scale: CGFloat = 3,
        sleep sleepDuration: Duration = .seconds(2),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) async throws {
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_ATTACHMENT_LOGS")
        UserDefaults.standard.set(true, forKey: "SWIFTUIHTML_ATTACHMENT_DIAGNOSTICS")
        setenv("SWIFTUIHTML_USE_TEXTKIT_LAYOUT", "1", 1)
        let allowHeightOverride = ProcessInfo.processInfo.environment["SWIFTUIHTML_MACOS_USE_FITTING_HEIGHT"] == "1"
        AttachmentDebugLogger.clear()
        let identifier = name ?? "1"
        let shouldRecord = recording ?? (ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1")
        let recordOverride: SnapshotTestingConfiguration.Record? = snapshotDirectory == nil ? nil : .never
        let recordFlag: Bool? = snapshotDirectory == nil ? shouldRecord : nil
        let baselineTestName = resolveBaselineTestName(
            snapshotDirectory: snapshotDirectory,
            testName: testName,
            name: name
        )
        AttachmentDebugLogger.record(
            "[Snapshot] start test=\(testName) name=\(identifier) baseline=\(baselineTestName)"
        )
        defer {
            AttachmentDebugLogger.record("[Snapshot] end test=\(testName) name=\(identifier)")
        }
        let referenceSize = referencePixelSize(
            snapshotDirectory: snapshotDirectory,
            testName: baselineTestName,
            name: name
        )
        var targetScale = scale
        if let referenceSize, width > 0 {
            let candidate = referenceSize.width / width
            if candidate > 0.5 {
                targetScale = candidate
            }
        }
        AttachmentDebugLogger.record("[Snapshot] baselineTestName=\(baselineTestName) scale requested=\(scale) targetScale=\(targetScale)")

        let rootView = view
            .environment(\.colorScheme, .light)
            .background(Color.white)
            .ignoresSafeArea()
        let hostingView = NSHostingView(rootView: rootView)

        let initialHeight: CGFloat = height ?? 1000
        let initialSize = NSSize(width: width, height: initialHeight)
        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))
        container.wantsLayer = true
        container.addSubview(hostingView)
        hostingView.wantsLayer = true
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]

        container.layoutSubtreeIfNeeded()

        if let referenceSize {
            let targetWidth = referenceSize.width / targetScale
            var targetHeight: CGFloat
            if let height {
                targetHeight = height
            } else {
                let fittingSize = hostingView.fittingSize
                targetHeight = max(1, ceil(fittingSize.height))
            }
            let finalSize = NSSize(width: targetWidth, height: targetHeight)
            container.setFrameSize(finalSize)
            hostingView.frame = container.bounds
            container.layoutSubtreeIfNeeded()
            AttachmentDebugLogger.record("[Snapshot] referenceSize=on finalSize=\(finalSize)")
        } else if height == nil {
            let fittingSize = hostingView.fittingSize
            let finalHeight = max(1, ceil(fittingSize.height))
            let finalSize = NSSize(width: width, height: finalHeight)
            if allowHeightOverride {
                container.setFrameSize(finalSize)
                hostingView.frame = container.bounds
                container.layoutSubtreeIfNeeded()
                AttachmentDebugLogger.record("[Snapshot] heightOverride=on finalHeight=\(finalHeight)")
            } else {
                AttachmentDebugLogger.record("[Snapshot] heightOverride=off finalHeight=\(finalHeight)")
            }
        }

        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.appearance = NSAppearance(named: .aqua)
        window.makeKeyAndOrderFront(nil)

        try await Task.sleep(for: sleepDuration)

        container.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        AttachmentDebugLogger.record("[Snapshot] fittingSize=\(fittingSize) containerSize=\(container.frame.size) hostFrame=\(hostingView.frame.size)")
        AttachmentDebugLogger.record("[Snapshot] intrinsicContentSize=\(hostingView.intrinsicContentSize)")

        let waitImages = await ImageLoadTracker.shared.waitUntilIdle(timeoutSeconds: 5)
        AttachmentDebugLogger.record("[Snapshot] imageLoadIdle=\(waitImages)")
        let waitLayout = await AttachmentLayoutTracker.shared.waitUntilIdle(timeoutSeconds: 3)
        AttachmentDebugLogger.record("[Snapshot] layoutIdle=\(waitLayout)")
        try await Task.sleep(for: .milliseconds(800))
        container.layoutSubtreeIfNeeded()
        container.needsLayout = true
        if height == nil {
            let fittingSize = hostingView.fittingSize
            let updatedHeight = max(1, ceil(fittingSize.height))
            if abs(updatedHeight - container.frame.height) > 1 {
                let updatedSize = NSSize(width: container.frame.width, height: updatedHeight)
                container.setFrameSize(updatedSize)
                hostingView.frame = container.bounds
                container.layoutSubtreeIfNeeded()
                window.setContentSize(updatedSize)
                AttachmentDebugLogger.record("[Snapshot] postLoadHeight=\(updatedHeight)")
            }
        }
        window.displayIfNeeded()
        hostingView.displayIfNeeded()
        NSApp.updateWindows()
#if canImport(CoreAnimation)
        CATransaction.flush()
#endif
        logImageViewDiagnostics(in: container)


        let snapshotSize = container.frame.size
        let renderScale = targetScale
        let backingScale = window.backingScaleFactor
        AttachmentDebugLogger.record("[Snapshot] backingScale=\(backingScale) renderScale=\(renderScale)")

        let image: NSImage
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_MACOS_USE_IMAGE_RENDERER"] == "1",
           #available(macOS 13.0, *),
           let rendered = makeSnapshotImageUsingRenderer(
            of: rootView,
            size: snapshotSize,
            scale: renderScale
           ) {
            image = rendered
        } else {
            image = makeSnapshotImage(
                of: hostingView,
                size: snapshotSize,
                scale: renderScale
            )
        }
        let finalImage = image
        performOCRDebug(
            image: finalImage,
            testName: testName,
            name: name,
            scale: targetScale,
            snapshotDirectory: snapshotDirectory,
            baselineTestName: baselineTestName
        )
        logPaddingDiagnostics(
            image: finalImage,
            testName: testName,
            name: name,
            snapshotDirectory: snapshotDirectory,
            baselineTestName: baselineTestName
        )
        logTrimDiagnostics(
            image: finalImage,
            testName: testName,
            name: name,
            snapshotDirectory: snapshotDirectory,
            baselineTestName: baselineTestName
        )
        ensureSnapshotArtifactsDirectory()
        let failure = withSnapshotTesting(record: recordOverride) {
            verifySnapshot(
                of: finalImage,
                as: snapshottingForImages(
                    precision: precision,
                    perceptualPrecision: perceptualPrecision
                ),
                named: name,
                record: recordFlag,
                snapshotDirectory: snapshotDirectory,
                fileID: fileID,
                file: filePath,
                testName: baselineTestName,
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
        attachDebugLogs(testName: baselineTestName, name: name)
    }

    private static func ensureSnapshotArtifactsDirectory() {
        if ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] != nil {
            return
        }
        let artifactsUrl = artifactsDirectory
        do {
            try FileManager.default.createDirectory(at: artifactsUrl, withIntermediateDirectories: true)
            setenv("SNAPSHOT_ARTIFACTS", artifactsUrl.path, 1)
            AttachmentDebugLogger.record("[Snapshot] SNAPSHOT_ARTIFACTS=\(artifactsUrl.path)")
        } catch {
            // Continue without overriding SNAPSHOT_ARTIFACTS.
        }
    }


    private static func logImageViewDiagnostics(in rootView: NSView) {
        let imageViews = allDescendants(of: rootView).compactMap { $0 as? NSImageView }
        let visibleImages = imageViews.filter { view in
            guard let image = view.image else { return false }
            let size = view.bounds.size
            return image.size.width > 0 && image.size.height > 0 && size.width > 1 && size.height > 1
        }
        let layeredViews = allDescendants(of: rootView).filter { $0.layer?.contents != nil }
        let layerContentsCount = layerContentsTotal(in: rootView.layer)
        let layerImageHashes = layerContentsHashes(in: rootView.layer)
        AttachmentDebugLogger.record("[Snapshot] imageViews total=\(imageViews.count) visible=\(visibleImages.count) layerContents=\(layeredViews.count) layerTreeContents=\(layerContentsCount) layerImageHashes=\(layerImageHashes.count)")
        guard !visibleImages.isEmpty else {
            AttachmentDebugLogger.record("[Snapshot][Heuristic] no visible NSImageView instances (attachments may not be rendering)")
            return
        }
        let frames = visibleImages.prefix(32).map { view in
            view.convert(view.bounds, to: rootView)
        }
        let summary = frames.map { "\($0.integral)" }.joined(separator: " | ")
        AttachmentDebugLogger.record("[Snapshot] imageViewFrames \(summary)")

        let hashes: [String] = visibleImages.compactMap { view -> String? in
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

    private static func imageHash(for image: NSImage) -> String? {
        guard let data = image.tiffRepresentation else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resizedImage(image: NSImage, pixelSize: CGSize) -> NSImage? {
        let targetWidth = max(1, Int(pixelSize.width.rounded()))
        let targetHeight = max(1, Int(pixelSize.height.rounded()))
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resizedCG = context.makeImage() else { return nil }
        let resized = NSImage(cgImage: resizedCG, size: NSSize(width: targetWidth, height: targetHeight))
        return resized
    }

    private static func pixelSize(of image: NSImage) -> CGSize? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static func snapshottingForImages(
        precision: Float,
        perceptualPrecision: Float
    ) -> Snapshotting<NSImage, NSImage> {
        let base = Snapshotting<NSImage, NSImage>.image(
            precision: precision,
            perceptualPrecision: perceptualPrecision
        )
        let diffing = Diffing<NSImage>(
            toData: base.diffing.toData,
            fromData: base.diffing.fromData,
            diff: { oldImage, newImage in
                let preparedOld = preparedForComparison(oldImage)
                let preparedNew = preparedForComparison(newImage)
                guard let targetSize = pixelSize(of: preparedOld) else {
                    return base.diffing.diff(preparedOld, preparedNew)
                }
                if let newSize = pixelSize(of: preparedNew), newSize != targetSize,
                   let resized = resizedImage(image: preparedNew, pixelSize: targetSize) {
                    AttachmentDebugLogger.record(
                        "[Snapshot] scaled new image from \(Int(newSize.width))x\(Int(newSize.height)) to \(Int(targetSize.width))x\(Int(targetSize.height))"
                    )
                    return base.diffing.diff(preparedOld, resized)
                }
                return base.diffing.diff(preparedOld, preparedNew)
            }
        )
        return Snapshotting<NSImage, NSImage>(
            pathExtension: base.pathExtension,
            diffing: diffing
        )
    }

    private static func preparedForComparison(_ image: NSImage) -> NSImage {
        guard let cropped = croppedContentImage(image) else {
            return image
        }
        return cropped
    }

    private static func croppedContentImage(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard let rect = contentCropRect(for: cgImage) else {
            return nil
        }
        guard let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        let result = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        AttachmentDebugLogger.record(
            "[Snapshot] contentCrop rect=\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))"
        )
        return result
    }

    private static func contentCropRect(for cgImage: CGImage) -> CGRect? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 1, height > 1 else { return nil }

        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let whiteThreshold: UInt8 = 245
        let alphaThreshold: UInt8 = 5
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let idx = rowStart + (x * 4)
                let r = buffer[idx]
                let g = buffer[idx + 1]
                let b = buffer[idx + 2]
                let a = buffer[idx + 3]
                if a > alphaThreshold && (r < whiteThreshold || g < whiteThreshold || b < whiteThreshold) {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                    found = true
                }
            }
        }

        guard found else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX + 1),
            height: max(1, maxY - minY + 1)
        )
    }

    private static func imageHash(for cgImage: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func layerContentsHashes(in layer: CALayer?) -> [String] {
        guard let layer else { return [] }
        var hashes: [String] = []
        var stack: [CALayer] = [layer]
        while let current = stack.popLast() {
            if let contents = current.contents {
                if let nsImage = contents as? NSImage, let hash = imageHash(for: nsImage) {
                    hashes.append(hash)
                }
            }
            if let sublayers = current.sublayers {
                stack.append(contentsOf: sublayers)
            }
        }
        if !hashes.isEmpty {
            let counts = hashes.reduce(into: [String: Int]()) { counts, hash in
                counts[hash, default: 0] += 1
            }
            let uniqueCount = counts.count
            let maxDup = counts.max(by: { $0.value < $1.value })
            if let maxDup {
                AttachmentDebugLogger.record("[Snapshot] layerImageHashStats total=\(hashes.count) unique=\(uniqueCount) maxDup=\(maxDup.value)")
                if uniqueCount == 1 && maxDup.value > 1 {
                    AttachmentDebugLogger.record("[Snapshot][Heuristic] all layer images identical (possible stacking or reuse bug)")
                }
            }
        }
        return hashes
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

    private static func allDescendants(of rootView: NSView) -> [NSView] {
        var result: [NSView] = []
        var stack: [NSView] = [rootView]
        while let view = stack.popLast() {
            result.append(view)
            stack.append(contentsOf: view.subviews)
        }
        return result
    }

    private static func layerContentsTotal(in layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        var count = layer.contents == nil ? 0 : 1
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                count += layerContentsTotal(in: sublayer)
            }
        }
        return count
    }

    private static func applyContentsScale(_ layer: CALayer?, scale: CGFloat) {
        guard let layer else { return }
        layer.contentsScale = scale
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                applyContentsScale(sublayer, scale: scale)
            }
        }
    }

    private static func performOCRDebug(
        image: NSImage,
        testName: String,
        name: String?,
        scale: CGFloat,
        snapshotDirectory: String?,
        baselineTestName: String
    ) {
        guard NSClassFromString("XCTestCase") != nil else { return }
        let shouldOCR = ProcessInfo.processInfo.environment["SWIFTUIHTML_OCR_DEBUG"] != "0"
        guard shouldOCR else { return }
        let safeTestName = sanitizePathComponent(testName)
        let identifier = sanitizePathComponent(name ?? "1")
        guard let newStats = ocrStats(for: image, label: "new") else { return }
        let newLog = "[OCR] new textRectCount=\(newStats.count) topPadding=\(newStats.topPadding) bottomPadding=\(newStats.bottomPadding) imageSize=\(newStats.imageSize)"
        print("[SwiftUIHTML]\(newLog)")
        AttachmentDebugLogger.record(newLog)

        saveOCROverlay(
            image: image,
            cgImage: newStats.cgImage,
            rects: newStats.drawRects,
            scale: scale,
            outputDir: "/tmp/swiftuihtml-ocr/macos",
            filename: "\(safeTestName).\(identifier).ocr.png"
        )

        if let baselineImage = loadBaselineImage(
            snapshotDirectory: snapshotDirectory,
            testName: sanitizePathComponent(baselineTestName),
            identifier: identifier
        ), let baselineStats = ocrStats(for: baselineImage, label: "baseline") {
            let deltaTop = newStats.topPadding - baselineStats.topPadding
            let deltaBottom = newStats.bottomPadding - baselineStats.bottomPadding
            let baselineLog = "[OCR] baseline textRectCount=\(baselineStats.count) topPadding=\(baselineStats.topPadding) bottomPadding=\(baselineStats.bottomPadding) imageSize=\(baselineStats.imageSize) deltaTop=\(deltaTop) deltaBottom=\(deltaBottom)"
            print("[SwiftUIHTML]\(baselineLog)")
            AttachmentDebugLogger.record(baselineLog)
            saveOCROverlay(
                image: baselineImage,
                cgImage: baselineStats.cgImage,
                rects: baselineStats.drawRects,
                scale: scale,
                outputDir: "/tmp/swiftuihtml-ocr/macos-baseline",
                filename: "\(safeTestName).\(identifier).baseline.ocr.png"
            )
        } else {
            let missingLog = "[OCR] baseline image missing for \(safeTestName).\(identifier)"
            print("[SwiftUIHTML]\(missingLog)")
            AttachmentDebugLogger.record(missingLog)
        }
    }

    private static func ocrStats(for image: NSImage, label: String) -> OCRStats? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("[SwiftUIHTML][OCR] missing CGImage (\(label))")
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
            print("[SwiftUIHTML][OCR] request failed \(error.localizedDescription)")
            return nil
        }

        let observations = request.results ?? []
        if observations.isEmpty {
            return OCRStats(
                drawRects: [],
                topPadding: 0,
                bottomPadding: 0,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height),
                cgImage: cgImage
            )
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var drawRects: [CGRect] = []
        var topLeftRects: [CGRect] = []
        drawRects.reserveCapacity(observations.count)
        topLeftRects.reserveCapacity(observations.count)

        for observation in observations {
            let bbox = observation.boundingBox
            let drawRect = CGRect(
                x: bbox.minX * imageWidth,
                y: bbox.minY * imageHeight,
                width: bbox.width * imageWidth,
                height: bbox.height * imageHeight
            )
            let topLeftRect = CGRect(
                x: bbox.minX * imageWidth,
                y: (1 - bbox.maxY) * imageHeight,
                width: bbox.width * imageWidth,
                height: bbox.height * imageHeight
            )
            drawRects.append(drawRect)
            topLeftRects.append(topLeftRect)
        }

        let minY = topLeftRects.map(\.minY).min() ?? 0
        let maxY = topLeftRects.map(\.maxY).max() ?? 0
        let topPadding = minY
        let bottomPadding = max(0, imageHeight - maxY)
        return OCRStats(
            drawRects: drawRects,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            imageSize: CGSize(width: imageWidth, height: imageHeight),
            cgImage: cgImage
        )
    }

    private static func saveOCROverlay(
        image: NSImage,
        cgImage: CGImage,
        rects: [CGRect],
        scale: CGFloat,
        outputDir: String,
        filename: String
    ) {
        let overlay = drawOCR(image: image, cgImage: cgImage, rects: rects, scale: scale)
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            print("[SwiftUIHTML][OCR] create dir failed \(error.localizedDescription)")
        }
        let fileURL = outputURL.appendingPathComponent(filename)
        if let data = pngData(from: overlay) {
            do {
                try data.write(to: fileURL)
                print("[SwiftUIHTML][OCR] overlay saved \(fileURL.path)")
            } catch {
                print("[SwiftUIHTML][OCR] write failed \(error.localizedDescription)")
            }
        }
    }

    private static func drawOCR(
        image: NSImage,
        cgImage: CGImage,
        rects: [CGRect],
        scale: CGFloat
    ) -> NSImage {
        let pixelsWide = max(1, cgImage.width)
        let pixelsHigh = max(1, cgImage.height)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        rep?.size = NSSize(width: CGFloat(pixelsWide) / scale, height: CGFloat(pixelsHigh) / scale)

        let output = NSImage(size: rep?.size ?? image.size)
        if let rep {
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                context.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(pixelsWide), height: CGFloat(pixelsHigh)))
                context.cgContext.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.7).cgColor)
                context.cgContext.setLineWidth(2.0)
                rects.forEach { rect in
                    context.cgContext.stroke(rect)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            output.addRepresentation(rep)
        }
        return output
    }

    private static func loadBaselineImage(
        snapshotDirectory: String?,
        testName: String,
        identifier: String
    ) -> NSImage? {
        guard let snapshotDirectory else { return nil }
        let fileURL = URL(fileURLWithPath: snapshotDirectory, isDirectory: true)
            .appendingPathComponent("\(testName).\(identifier)")
            .appendingPathExtension("png")
        return NSImage(contentsOf: fileURL)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private struct OCRStats {
        let drawRects: [CGRect]
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let imageSize: CGSize
        let cgImage: CGImage

        var count: Int { drawRects.count }
    }
}
#endif
