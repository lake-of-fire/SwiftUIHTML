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
    @State private var renderedElement: BlockElement?
#if canImport(Foundation)
    private final class HTMLNodeBox: NSObject {
        let node: HTMLNode
        init(_ node: HTMLNode) {
            self.node = node
        }
    }

    private static let parseCache: NSCache<NSString, HTMLNodeBox> = {
        let cache = NSCache<NSString, HTMLNodeBox>()
        cache.countLimit = 64
        return cache
    }()
#endif
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
            if let renderedElement {
                HTMLBlock(element: renderedElement)
            } else if let parsedNode {
                HTMLNodeView(node: parsedNode)
            } else {
                Color.clear
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
                renderedElement = nil
#if DEBUG
                didParse = false
#endif
                return
            }
#if canImport(Foundation)
            let cacheDisabled = ProcessInfo.processInfo.environment["SWIFTUIHTML_DISABLE_PARSE_CACHE"] == "1"
            let parserInstance = parser()
            let parserTypeName = String(describing: type(of: parserInstance))
            let cacheKey = "\(parserTypeName)::\(html)" as NSString
            if !cacheDisabled, let cached = Self.parseCache.object(forKey: cacheKey) {
                parsedNode = cached.node
#if DEBUG
                didParse = true
                debugChildCount = cached.node.children.count
#endif
                return
            }
#else
            let parserInstance = parser()
#endif
#if canImport(os)
            let shouldSignpost = ProcessInfo.processInfo.environment["SWIFTUIHTML_SIGNPOSTS"] == "1"
            let signpostID = shouldSignpost ? Self.signposter.makeSignpostID() : OSSignpostID.invalid
            var intervalState: OSSignpostIntervalState?
            if shouldSignpost {
                intervalState = Self.signposter.beginInterval("HTML parse", id: signpostID, "\(html.count) chars")
            }
#endif
            AttachmentIDGenerator.reset()
            let parsed = parserInstance.parse(html: html)
            parsedNode = parsed
            renderedElement = parsed.toElement(configuration: configuration, with: styleContainer)
#if canImport(Foundation)
            if !cacheDisabled {
                Self.parseCache.setObject(HTMLNodeBox(parsed), forKey: cacheKey, cost: html.count)
            }
#endif
#if DEBUG
            didParse = true
            debugChildCount = parsed.children.count
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
        .onChange(of: styleContainer) { _ in
            guard let parsedNode else { return }
            renderedElement = parsedNode.toElement(configuration: configuration, with: styleContainer)
        }
        .onChange(of: configuration.cacheKey()) { _ in
            guard let parsedNode else { return }
            renderedElement = parsedNode.toElement(configuration: configuration, with: styleContainer)
        }
    }
}
