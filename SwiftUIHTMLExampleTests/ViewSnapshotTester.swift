//  Copyright © 2025 PRND. All rights reserved.
#if os(iOS)
import SwiftUI
import UIKit
import XCTest

@testable import SwiftUIHTML
@_spi(Internals) import SnapshotTesting

/// Utility class for rendering SwiftUI views in UIKit environment and generating snapshots
class ViewSnapshotTester {

    @MainActor
    static func snapshot<V: View>(
        of view: V,
        named name: String? = nil,
        record recording: Bool? = nil,
        sleep sleepDuration: Duration = .seconds(2),
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) async throws {
        AttachmentDebugLogger.clear()
        AttachmentDebugLogger.record("[TestHarness] snapshot start: \(testName)")
        // Wrap SwiftUI view as UIKit view
        let rootView = view.background(Color.white).compositingGroup().ignoresSafeArea()
        let hostingController = UIHostingController(rootView: rootView)
        let hostingView = hostingController.view!

        // Create and display window
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingView.frame = window.bounds
        
        // Wait for layout calculation time
        try await Task.sleep(for: sleepDuration)

        // Force layout update
        await MainActor.run {
            hostingView.layoutIfNeeded()
            hostingView.setNeedsLayout()
            hostingView.invalidateIntrinsicContentSize()
        }
        await MainActor.run {
            let bounds = window.bounds
            let windowSafeInsets = window.safeAreaInsets
            let hostingBounds = hostingView.bounds
            let hostingSafeInsets = hostingView.safeAreaInsets
            AttachmentDebugLogger.record("[Snapshot] containerBounds=\(bounds) windowSafeInsets=\(windowSafeInsets) hostingSafeInsets=\(hostingSafeInsets) hostingBounds=\(hostingBounds)")
        }
        
        // Find rendered view
        guard let renderedView = findActualRenderedView(in: hostingView) else {
            throw SnapshotError.viewNotFound
        }

        renderedView.layoutIfNeeded()
        var targetSize = resolvedSize(for: hostingController, fallbackView: hostingView)
        let windowSafeInsets = window.safeAreaInsets
        let hostingSafeInsets = hostingView.safeAreaInsets
        let totalTopInset = max(windowSafeInsets.top, hostingSafeInsets.top)
        let totalBottomInset = max(windowSafeInsets.bottom, hostingSafeInsets.bottom)
        if totalTopInset > 0 || totalBottomInset > 0 {
            let adjustedHeight = max(1, targetSize.height - totalTopInset - totalBottomInset)
            AttachmentDebugLogger.record("[Snapshot] effectiveSafeInsets=UIEdgeInsets(top: \(totalTopInset), left: 0.0, bottom: \(totalBottomInset), right: 0.0) adjustedHeight=\(adjustedHeight)")
            targetSize.height = adjustedHeight
        }
        renderedView.bounds.size = targetSize
        renderedView.frame.size = targetSize
        renderedView.layoutIfNeeded()

        let scale = UIScreen.main.scale
        let layoutMargins = renderedView.layoutMargins
        let renderedInsets = renderedView.safeAreaInsets
        let intrinsicSize = renderedView.intrinsicContentSize
        let fittingSize = renderedView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        AttachmentDebugLogger.record("[Snapshot] rendered layoutMargins=\(layoutMargins) safeInsets=\(renderedInsets) intrinsicSize=\(intrinsicSize) fittingSize=\(fittingSize)")
        AttachmentDebugLogger.record("[Snapshot] targetSize=\(targetSize) scale=\(scale)")
        let image = makeSnapshotImage(of: renderedView, scale: scale)
        ensureSnapshotArtifactsDirectory(filePath: filePath)
        let failure = verifySnapshot(
            of: image,
            as: .image(
                precision: 1,
                perceptualPrecision: 1,
                scale: scale
            ),
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
        attachDebugLogs()
    }

    /// Snapshot error type
    enum SnapshotError: Error {
        case viewNotFound
    }
    
    /// Find actual rendered view 
    private static func findActualRenderedView(in hostingView: UIView) -> UIView? {
        // Use the hosting view itself to avoid zero-sized subviews during layout.
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

    private static func attachDebugLogs() {
        let logs = AttachmentDebugLogger.dump()
        guard !logs.isEmpty else { return }
        print("SWIFTUIHTML_ATTACHMENT_LOGS_BEGIN")
        print(logs)
        print("SWIFTUIHTML_ATTACHMENT_LOGS_END")
        let attachment = XCTAttachment(string: logs)
        attachment.name = "SwiftUIHTML Attachment Layout Logs"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "SwiftUIHTML Attachment Layout Logs") { activity in
            activity.add(attachment)
        }
        AttachmentDebugLogger.clear()
    }
}
#endif
