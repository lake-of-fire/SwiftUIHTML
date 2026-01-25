//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
#if canImport(os)
import os
#endif


public struct HTMLView: View, Equatable {
    let html: String

    @HTMLEnvironment(\._configuration) var configuration

    let parser: () -> HTMLParserable
    @State private var parsedNode: HTMLNode?
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
            }
        }
        .task(id: html) {
            guard !html.isEmpty else {
                parsedNode = nil
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
#if canImport(os)
            if let intervalState {
                Self.signposter.endInterval("HTML parse", intervalState)
            }
#endif
        }
    }
}

extension HTMLView {
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.html == rhs.html
    }
}
