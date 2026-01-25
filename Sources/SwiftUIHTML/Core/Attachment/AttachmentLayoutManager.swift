//  Copyright © 2024 PRND. All rights reserved.
import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if canImport(os)
import os
#endif

final class AttachmentLayoutEngine {
    
    @Published var attributedString: NSMutableAttributedString?
    @Published private var containerSize: CGSize?

    private var keyAttachment: [AnyHashable: Weak<TextAttachment>] = [:]
    private var frameStore: [AnyHashable: CGRect] = [:]
    private var texts: [TextType] = []
    private var preparedString: NSMutableAttributedString?
    private var targetCache: [(value: TextAttachment, range: NSRange)] = []
    private var attachmentKeys: [AnyHashable] = []
    private var attachmentRanges: [NSRange] = []
    private var attachmentSizePublishers: [AnyPublisher<CGRect, Never>] = []
    private var textRangeFrameCalculator = TextRangeFrameCalculator()
    private var cancelBag = Set<AnyCancellable>()
#if canImport(os)
    private static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "SwiftUIHTML", category: "AttachmentLayout")
    )
    private static let logger = Logger(subsystem: "SwiftUIHTML", category: "AttachmentLayout")
#endif

    var lineSpacing: CGFloat {
        get { textRangeFrameCalculator.lineSpacing }
        set { textRangeFrameCalculator.lineSpacing = newValue }
    }

    let layoutUpdatePublisher = PassthroughSubject<Void, Never>()

    init() {
        setup()
    }

    private var shouldLog: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_LOGS")
            || NSClassFromString("XCTestCase") != nil
    }

    private func log(_ message: @autoclosure () -> String) {
        guard shouldLog else { return }
        let rendered = message()
        AttachmentDebugLogger.record("[AttachmentLayout] \(rendered)")
#if canImport(os)
        if #available(iOS 14.0, macOS 11.0, *) {
            AttachmentLayoutEngine.logger.debug("\(rendered, privacy: .public)")
        }
#endif
        NSLog("[SwiftUIHTML][AttachmentLayout] %@", rendered)
        print("[SwiftUIHTML][AttachmentLayout] \(rendered)")
    }

    func setup() {
        let attributedStringPublisher = _attributedString.projectedValue
            .compactMap { $0 }
            .removeDuplicates()
        
        let containerSizePublisher = _containerSize.projectedValue
            .compactMap { $0 }
            .removeDuplicates()
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)

        Publishers
            .CombineLatest(attributedStringPublisher, containerSizePublisher)
            .map { [unowned self] in
                measureLayoutPublisher(attributedString: $0, containerSize: $1)
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.storeRangeBounds(result)
            }
            .store(in: &cancelBag)
    }

    func setSize(key: AnyHashable, size: CGSize) {
        guard let textAttachment = keyAttachment[key] else { return }
        let oldSize = textAttachment.value?.bounds.size ?? .zero
        guard oldSize != size else { return }
        textAttachment.value?.updateSize(size)
        log("setSize key=\(key) size=\(size)")
        recalculateLayoutIfPossible()
        notifyLayoutUpdate()
    }

    func getSize(key: AnyHashable) -> CGSize {
        guard let textAttachment = keyAttachment[key] else { return .zero }
        return textAttachment.value?.getAdjustedSize() ?? .zero
    }

    func getOffset(key: AnyHashable) -> CGPoint {
        let rect = frameStore[key]
        let point = rect?.origin ?? .zero
        guard let textAttachment = keyAttachment[key] else { return point }
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_USE_TEXTKIT_LAYOUT"] == "1" {
            log("getOffset key=\(key) frame=\(String(describing: frameStore[key])) adjusted=\(point) textKit=on")
            return point
        }
        let lineHeightOverride = rect?.height ?? 0
        let adjusted = textAttachment.value?.getAdjustedOffset(
            point: point,
            lineHeightOverride: lineHeightOverride > 0 ? lineHeightOverride : nil
        ) ?? point
        log("getOffset key=\(key) frame=\(String(describing: frameStore[key])) adjusted=\(adjusted)")
        return adjusted

    }

    func setContainerSize(_ size: CGSize) {
        if containerSize == size {
            return
        }
        containerSize = size
        log("setContainerSize \(size)")
        recalculateLayoutIfPossible()
    }

    @MainActor
    func setTexts(_ texts: [TextType]) {
        let hasAttachment = texts.contains(where: \.hasAttachment)
        guard hasAttachment else {
            self.texts = []
            self.attributedString = nil
            self.preparedString = nil
            self.targetCache = []
            self.attachmentKeys = []
            self.attachmentRanges = []
            self.attachmentSizePublishers = []
            return
        }

        guard self.texts != texts else { return }
        self.texts = texts
        lineSpacing = resolveLineSpacing(texts: texts)
        log("resolved lineSpacing=\(lineSpacing)")
        let newAttributedString = makeAttributedString(texts: texts)
        attributedString = newAttributedString
        preparedString = textRangeFrameCalculator.prepareCoreTextString(newAttributedString)
        targetCache = textRangeFrameCalculator.findAttribute(
            in: newAttributedString,
            for: .attachment,
            type: TextAttachment.self
        )
        attachmentKeys = targetCache.map(\.value.key)
        attachmentRanges = targetCache.map(\.range)
        attachmentSizePublishers = targetCache.map { target in
            let initialBounds = target.value.bounds
            let seedBounds = initialBounds.size > .invisible
                ? initialBounds
                : CGRect(origin: .zero, size: CGSize(width: 1, height: 1))
            return target.value
                .publisher(for: \.bounds)
                .prepend(seedBounds)
                .removeDuplicates()
                .filter { $0.size > .invisible }
                .eraseToAnyPublisher()
        }
        logAttachmentCounts(expected: texts.filter(\.hasAttachment).count)
    }


}

private extension AttachmentLayoutEngine {
    func resolveLineSpacing(texts: [TextType]) -> CGFloat {
        var maxLineSpacing: CGFloat = 0
        for text in texts {
            switch text {
            case let .text(_, styleContainer):
                if let lineSpacing = styleContainer.textLine?.lineSpacing {
                    maxLineSpacing = max(maxLineSpacing, lineSpacing)
                }
            case let .attachment(_, _, _, styleContainer):
                if let lineSpacing = styleContainer.textLine?.lineSpacing {
                    maxLineSpacing = max(maxLineSpacing, lineSpacing)
                }
            default:
                continue
            }
        }
        return maxLineSpacing
    }

    func logAttachmentCounts(expected: Int) {
        guard shouldLog else { return }
        let uniqueKeys = Set(attachmentKeys)
        log("attachmentCounts expected=\(expected) prepared=\(attachmentKeys.count) uniqueKeys=\(uniqueKeys.count)")
        guard uniqueKeys.count != expected else { return }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(attachmentKeys.count)
        for key in attachmentKeys {
            let summary = attachmentSummary(for: key)
            counts[summary, default: 0] += 1
        }
        let duplicates = counts
            .filter { $0.value > 1 }
            .sorted { $0.value > $1.value }
            .map { "\($0.key)x\($0.value)" }
        if !duplicates.isEmpty {
            log("attachmentKeyDuplicates \(duplicates.joined(separator: " | "))")
        }
    }

    func attachmentSummary(for key: AnyHashable) -> String {
        guard let textType = key.base as? TextType else {
            return "unknown"
        }
        switch textType {
        case let .attachment(id, tag, attributes, _):
            let src = attributes["src"]?.string ?? "-"
            let width = attributes["width"]?.string ?? "-"
            let height = attributes["height"]?.string ?? "-"
            return "id=\(id) tag=\(tag) src=\(src) w=\(width) h=\(height)"
        default:
            return "non-attachment"
        }
    }

    func set(key: AnyHashable, attachment: TextAttachment) {
        guard let _attachment = keyAttachment[key] else {
            keyAttachment[key] = Weak(value: attachment)
            return
        }
        _attachment.value = attachment
    }

    func recalculateLayoutIfPossible() {
        guard let preparedString, let attributedString, let container = containerSize else { return }
        guard !attachmentRanges.isEmpty else { return }
        let frames: [CGRect]
#if os(macOS)
        if ProcessInfo.processInfo.environment["SWIFTUIHTML_USE_TEXTKIT_LAYOUT"] == "1" {
            frames = textRangeFrameCalculator.measureLayoutWithTextKit(
                attributedString: attributedString,
                in: container,
                by: attachmentRanges
            )
            log("layoutEngine=TextKit")
        } else {
            frames = textRangeFrameCalculator.measureLayout(
                for: preparedString,
                in: container,
                by: attachmentRanges
            )
        }
#else
        frames = textRangeFrameCalculator.measureLayout(
            for: preparedString,
            in: container,
            by: attachmentRanges
        )
#endif
        let values = zip(attachmentKeys, frames).map { (key: $0, bounds: $1) }
        storeRangeBounds(values)
    }

    @MainActor
    func makeAttributedString(texts: [TextType]) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString()

        for element in texts {
            switch element {
            case let .text(string, styleContainer):
                if let uiFont = styleContainer.uiFont {
                    AttachmentDebugLogger.recordOnce(
                        "uiFont:\(uiFont.fontName):\(uiFont.pointSize)",
                        message: "[Font] uiFont name=\(uiFont.fontName) size=\(uiFont.pointSize)"
                    )
                }
                let text = makeAttributedString(
                    string: string,
                    styleContainer: styleContainer
                )
                attributedString.append(text)

            case let .newLine(styleContainer):
                if let uiFont = styleContainer.uiFont {
                    AttachmentDebugLogger.recordOnce(
                        "uiFont:\(uiFont.fontName):\(uiFont.pointSize)",
                        message: "[Font] uiFont name=\(uiFont.fontName) size=\(uiFont.pointSize)"
                    )
                }
                let text = makeAttributedString(
                    string: "\n",
                    styleContainer: styleContainer
                )
                attributedString.append(text)

            case let .attachment(_, _, _, styleContainer):
                if let uiFont = styleContainer.uiFont {
                    AttachmentDebugLogger.recordOnce(
                        "uiFont:\(uiFont.fontName):\(uiFont.pointSize)",
                        message: "[Font] uiFont name=\(uiFont.fontName) size=\(uiFont.pointSize)"
                    )
                }
                let attachment = TextAttachment(
                    key: element,
                    styleContainer: styleContainer
                )
                let attachmentString = NSMutableAttributedString(attachment: attachment)
                attachmentString.addAttributes(by: styleContainer)

                attributedString.append(attachmentString)
                set(key: element, attachment: attachment)
            }
        }

        return attributedString
    }

    func makeAttributedString(string: String, styleContainer: HTMLStyleContainer) -> NSMutableAttributedString {
        let value = AttributedString(string, attributes: styleContainer.toAttributeContainer())
        let text = NSMutableAttributedString(value)
        text.addAttributes(by: styleContainer)
        return text
    }


    func measureLayoutPublisher(attributedString: NSMutableAttributedString, containerSize: CGSize) -> AnyPublisher<[(AnyHashable, CGRect)], Never> {
        let coreTextString = preparedString ?? textRangeFrameCalculator.prepareCoreTextString(attributedString)

        let targets = targetCache
        if targets.isEmpty {
            return Just([]).eraseToAnyPublisher()
        }

        let keys = attachmentKeys
        let ranges = attachmentRanges

        let sizePublishers = attachmentSizePublishers
        return Publishers.MergeMany(sizePublishers)
            .receive(on: DispatchQueue.global(qos: .background))
            .compactMap { [weak textRangeFrameCalculator] _ in
#if canImport(os)
                let shouldSignpost = ProcessInfo.processInfo.environment["SWIFTUIHTML_SIGNPOSTS"] == "1"
                let intervalState = shouldSignpost
                    ? AttachmentLayoutEngine.signposter.beginInterval("Attachment layout", "\(ranges.count) ranges")
                    : nil
                defer {
                    if let intervalState {
                        AttachmentLayoutEngine.signposter.endInterval("Attachment layout", intervalState)
                    }
                }
#endif
                return textRangeFrameCalculator?
                    .measureLayout(for: coreTextString, in: containerSize, by: ranges)
            }
            .map { zip(keys, $0).map { ($0, $1) } }
            .eraseToAnyPublisher()
    }


    func storeRangeBounds(key: AnyHashable, bounds: CGRect) {
        if let existing = frameStore[key], existing == bounds {
            return
        }
        frameStore[key] = bounds
        let container = containerSize ?? .zero
        log("storeRangeBounds key=\(key) bounds=\(bounds) container=\(container)")
        notifyLayoutUpdate()
    }

    func storeRangeBounds(_ values: [(key: AnyHashable, bounds: CGRect)]) {
        var didChange = false
        values.forEach {
            if frameStore[$0.key] != $0.bounds {
                frameStore[$0.key] = $0.bounds
                didChange = true
            }
        }
        if didChange {
            let container = containerSize ?? .zero
            log("storeRangeBounds batch count=\(values.count) container=\(container)")
            notifyLayoutUpdate()
        }
    }

    private func notifyLayoutUpdate() {
        layoutUpdatePublisher.send(())
        Task {
            await AttachmentLayoutTracker.shared.markUpdated()
        }
    }
}


private extension NSMutableAttributedString {
    func addAttributes(by styleContainer: HTMLStyleContainer) {
        var attributes: [NSAttributedString.Key: Any] = [:]

        if let kern = styleContainer.kern {
            attributes[.kern] = kern
        }
        if let tracking = styleContainer.tracking {
            attributes[.tracking] = tracking
        }

        let paragraphStyle = NSMutableParagraphStyle()
        switch styleContainer.lineBreakMode {
        case .byCharWrapping:
            paragraphStyle.lineBreakMode = .byCharWrapping
        default:
            paragraphStyle.lineBreakMode = .byWordWrapping
        }
        paragraphStyle.lineBreakStrategy = .standard

        paragraphStyle.lineSpacing = styleContainer.textLine?.lineSpacing ?? 0
        attributes[.paragraphStyle] = paragraphStyle

        addAttributes(attributes, range: NSRange(location: 0, length: length))
    }
}
