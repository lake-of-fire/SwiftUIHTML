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
#endif

    var lineSpacing: CGFloat {
        get { textRangeFrameCalculator.lineSpacing }
        set { textRangeFrameCalculator.lineSpacing = newValue }
    }

    let layoutUpdatePublisher = PassthroughSubject<Void, Never>()

    init() {
        setup()
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
        layoutUpdatePublisher.send(())
    }

    func getSize(key: AnyHashable) -> CGSize {
        guard let textAttachment = keyAttachment[key] else { return .zero }
        return textAttachment.value?.getAdjustedSize() ?? .zero
    }

    func getOffset(key: AnyHashable) -> CGPoint {
        let point = frameStore[key]?.origin ?? .zero
        guard let textAttachment = keyAttachment[key] else { return point }
        return textAttachment.value?.getAdjustedOffset(point: point) ?? point

    }

    func setContainerSize(_ size: CGSize) {
        if containerSize == size {
            return
        }
        containerSize = size
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
            target.value
                .publisher(for: \.bounds)
                .removeDuplicates()
                .filter { $0.size > .invisible }
                .eraseToAnyPublisher()
        }
    }


}

private extension AttachmentLayoutEngine {
    func set(key: AnyHashable, attachment: TextAttachment) {
        guard let _attachment = keyAttachment[key] else {
            keyAttachment[key] = Weak(value: attachment)
            return
        }
        _attachment.value = attachment
    }

    @MainActor
    func makeAttributedString(texts: [TextType]) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString()

        for element in texts {
            switch element {
            case let .text(string, styleContainer):
                let text = makeAttributedString(
                    string: string,
                    styleContainer: styleContainer
                )
                attributedString.append(text)

            case let .newLine(styleContainer):
                let text = makeAttributedString(
                    string: "\n",
                    styleContainer: styleContainer
                )
                attributedString.append(text)

            case let .attachment(_, _, _, styleContainer):
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
        layoutUpdatePublisher.send(())
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
            layoutUpdatePublisher.send(())
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
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineBreakStrategy = .standard

        paragraphStyle.lineSpacing = styleContainer.textLine?.lineSpacing ?? 0
        attributes[.paragraphStyle] = paragraphStyle

        addAttributes(attributes, range: NSRange(location: 0, length: length))
    }
}
