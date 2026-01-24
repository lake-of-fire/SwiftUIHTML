//  Copyright © 2026 PRND. All rights reserved.
#if os(macOS)
import AppKit
import SwiftUI
@_spi(Internals) import SnapshotTesting

/// Utility class for rendering SwiftUI views in AppKit and generating snapshots.
class MacViewSnapshotTester {
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
        guard
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static func makeSnapshotImage(
        of view: NSView,
        size: CGSize,
        scale: CGFloat
    ) -> NSImage {
        let pixelsWide = max(1, Int(size.width * scale))
        let pixelsHigh = max(1, Int(size.height * scale))
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
        if let rep {
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                context.cgContext.scaleBy(x: scale, y: scale)
                view.draw(view.bounds)
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return image
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
        let shouldRecord = recording ?? (ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1")
        let recordOverride: SnapshotTestingConfiguration.Record? = snapshotDirectory == nil ? nil : .never
        let recordFlag: Bool? = snapshotDirectory == nil ? shouldRecord : nil
        let referenceSize = referencePixelSize(
            snapshotDirectory: snapshotDirectory,
            testName: testName,
            name: name
        )

        let rootView = view
            .environment(\.colorScheme, .light)
            .background(Color.white)
            .ignoresSafeArea()
        let hostingView = NSHostingView(rootView: rootView)

        let initialHeight: CGFloat = height ?? 1000
        var containerSize = NSSize(width: width, height: initialHeight)
        let container = NSView(frame: NSRect(origin: .zero, size: containerSize))
        container.addSubview(hostingView)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]

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

        if let referenceSize {
            let finalSize = NSSize(
                width: referenceSize.width / scale,
                height: referenceSize.height / scale
            )
            container.setFrameSize(finalSize)
            hostingView.frame = container.bounds
            container.layoutSubtreeIfNeeded()
        } else if height == nil {
            let fittingSize = hostingView.fittingSize
            let finalHeight = max(1, fittingSize.height)
            let finalSize = NSSize(width: width, height: finalHeight)
            container.setFrameSize(finalSize)
            hostingView.frame = container.bounds
            container.layoutSubtreeIfNeeded()
        }

        let image = makeSnapshotImage(
            of: container,
            size: container.frame.size,
            scale: scale
        )
        let failure = withSnapshotTesting(record: recordOverride) {
            verifySnapshot(
                of: image,
                as: .image(
                    precision: precision,
                    perceptualPrecision: perceptualPrecision
                ),
                named: name,
                record: recordFlag,
                snapshotDirectory: snapshotDirectory,
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
    }
}
#endif
