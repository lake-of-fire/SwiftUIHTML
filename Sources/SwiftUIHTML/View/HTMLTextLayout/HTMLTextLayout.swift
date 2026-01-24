//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
#if canImport(os)
import os
#endif

struct HTMLTextLayout: View {
    let texts: [TextType]
    let attachmentTexts: [TextType]
    
    @ObservedObject var attachmentManager: AttachmentManager
    @HTMLEnvironment(\._configuration) var configuration
    private var shouldLog: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_LOGS")
            || NSClassFromString("XCTestCase") != nil
    }
#if canImport(os)
    private static let logger = Logger(subsystem: "SwiftUIHTML", category: "HTMLTextLayout")
#endif

    init(attachmentManager: AttachmentManager, texts: [TextType]) {
        self.texts = texts
        self.attachmentTexts = texts.filter(\.hasAttachment)
        self.attachmentManager = attachmentManager
        attachmentManager.setTexts(texts)
    }

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .hidden()
                .modifier(OnChangeViewModifier(of: proxy.size, initial: true) { _, newValue in
                    attachmentManager.setContainer(size: proxy.size)
                    log("containerSize=\(newValue)")
                })
            ForEach(attachmentTexts, id: \.self) { text in
                attachmentView(for: text)
            }
        }
        .coordinateSpace(name: "HTMLTextLayoutSpace")
    }

    @ViewBuilder
    private func attachmentView(for text: TextType) -> some View {
        if let info = extractAttachmentInfo(from: text) {
            let offset = attachmentManager.offset(key: text)
            info.view
                .modifier(LinkModifier(link: info.link))
                .offset(offset)
                .background(attachmentFrameReader(for: text, offset: offset))
                .background(attachmentSizeReader(for: text, styleContainer: info.styleContainer))
        }
    }

    private func extractAttachmentInfo(from text: TextType) -> (view: AnyView, link: URL?, styleContainer: HTMLStyleContainer)? {
        if case let .attachment(_, tag, attributes, styleContainer) = text,
           let view = configuration.createAttachment(for: tag, with: attributes) {
            return (view: AnyView(view), link: styleContainer.link, styleContainer: styleContainer)
        }
        return nil
    }

    private func attachmentSizeReader(for text: TextType, styleContainer: HTMLStyleContainer) -> some View {
        GeometryReader { proxy in
            Color.clear
                .hidden()
                .modifier(OnChangeViewModifier(of: proxy.size, initial: true) { _, newValue in
                    attachmentManager.setAttachmentSize(
                        key: text,
                        size: newValue,
                        styleContainer: styleContainer
                    )
                    logAttachmentSize(text: text, size: newValue)
                })
        }
    }

    private func attachmentFrameReader(for text: TextType, offset: CGSize) -> some View {
        GeometryReader { proxy in
            Color.clear
                .hidden()
                .modifier(OnChangeViewModifier(of: proxy.frame(in: .named("HTMLTextLayoutSpace")), initial: true) { _, newValue in
                    logAttachmentFrame(text: text, frame: newValue, offset: offset)
                })
        }
    }

    private func attachmentDebugInfo(for text: TextType) -> (id: AnyHashable, tag: String, attributes: [String: AttributeValue])? {
        switch text {
        case let .attachment(id, tag, attributes, _):
            return (id, tag, attributes)
        default:
            return nil
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        guard shouldLog else { return }
        let rendered = message()
        AttachmentDebugLogger.record("[HTMLTextLayout] \(rendered)")
#if canImport(os)
        if #available(iOS 14.0, macOS 11.0, *) {
            HTMLTextLayout.logger.debug("\(rendered, privacy: .public)")
        }
#endif
        NSLog("[SwiftUIHTML][HTMLTextLayout] %@", rendered)
        print("[SwiftUIHTML][HTMLTextLayout] \(rendered)")
    }

    private func logAttachmentSize(text: TextType, size: CGSize) {
        guard shouldLog else { return }
        if let info = attachmentDebugInfo(for: text) {
            let keys = info.attributes.keys.sorted()
            log("attachmentSize id=\(info.id) tag=\(info.tag) size=\(size) attrs=\(keys)")
        } else {
            log("attachmentSize size=\(size)")
        }
    }

    private func logAttachmentFrame(text: TextType, frame: CGRect, offset: CGSize) {
        guard shouldLog else { return }
        if let info = attachmentDebugInfo(for: text) {
            let keys = info.attributes.keys.sorted()
            log("attachmentFrame id=\(info.id) tag=\(info.tag) frame=\(frame) offset=\(offset) attrs=\(keys)")
        } else {
            log("attachmentFrame frame=\(frame) offset=\(offset)")
        }
    }
}
