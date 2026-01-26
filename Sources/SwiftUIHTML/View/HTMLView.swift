//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
#if canImport(os)
import os
#endif


public struct HTMLView: View {
    let html: String

    @HTMLEnvironment(\._configuration) var configuration
    @HTMLEnvironment(\.styleContainer) var styleContainer

    let parser: () -> HTMLParserable
    @State private var parsedNode: HTMLNode?
#if DEBUG
    @State private var didParse = false
    @State private var debugChildCount = 0
    private var shouldShowDebugOverlay: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_DEBUG_OVERLAY"] == "1"
    }
#endif
#if canImport(os)
    private static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "SwiftUIHTML", category: "HTMLView")
    )
#endif

    public init(html: String, parser: @autoclosure @escaping () -> HTMLParserable) {
        self.html = html
        self.parser = parser
    }

    public var body: some View {
        Group {
            if let parsedNode {
                HTMLNodeView(node: parsedNode)
            } else {
#if DEBUG
                Text("HTMLView empty")
#endif
            }
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            if shouldShowDebugOverlay {
                Text("\(didParse ? "HTMLView parsed" : "HTMLView pending") children=\(debugChildCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
#endif
        .task(id: html) {
            guard !html.isEmpty else {
                parsedNode = nil
#if DEBUG
                didParse = false
#endif
                return
            }
#if canImport(os)
            let shouldSignpost = ProcessInfo.processInfo.environment["SWIFTUIHTML_SIGNPOSTS"] == "1"
            let signpostID = shouldSignpost ? Self.signposter.makeSignpostID() : OSSignpostID.invalid
            var intervalState: OSSignpostIntervalState?
            if shouldSignpost {
                intervalState = Self.signposter.beginInterval("HTML parse", id: signpostID, "\(html.count) chars")
            }
#endif
            AttachmentIDGenerator.reset()
            parsedNode = parser().parse(html: html)
#if DEBUG
            didParse = true
            debugChildCount = parsedNode?.children.count ?? 0
#endif
#if DEBUG
            if let parsedNode {
                print("# RESULT parsed tag=\(parsedNode.tag) children=\(parsedNode.children.count)")
            } else {
                print("# RESULT parsed nil")
            }
#endif
#if canImport(os)
            if let intervalState {
                Self.signposter.endInterval("HTML parse", intervalState)
            }
#endif
        }
    }
}
