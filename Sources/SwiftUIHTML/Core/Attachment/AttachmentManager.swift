// Copyright © 2025 PRND. All rights reserved.
import Combine
import CoreGraphics
import Foundation
#if canImport(os)
import os
#endif


final class AttachmentManager: ObservableObject {
    lazy var layoutEngine = AttachmentLayoutEngine()
    private var cancellables = Set<AnyCancellable>()
    private var shouldLog: Bool {
        ProcessInfo.processInfo.environment["SWIFTUIHTML_ATTACHMENT_LOGS"] == "1"
            || UserDefaults.standard.bool(forKey: "SWIFTUIHTML_ATTACHMENT_LOGS")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
#if canImport(os)
    private static let logger = Logger(subsystem: "SwiftUIHTML", category: "AttachmentManager")
#endif

    private class ImageCache: NSCache<AttachmentImageCacheKey, PlatformImage> {}
    private let textImages = ImageCache()

    init() {
        textImages.countLimit = 512
        textImages.totalCostLimit = 8 * 1024 * 1024
        layoutEngine.layoutUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func setTexts(_ texts: [TextType]) {
        layoutEngine.setTexts(texts)
    }

    @MainActor
    func setContainer(size: CGSize)  {
        layoutEngine.setContainerSize(size)
    }

    func setAttachmentSize(key: AnyHashable, size: CGSize, styleContainer: HTMLStyleContainer) {
        layoutEngine.setSize(key: key, size: size)
        log("setAttachmentSize key=\(key) size=\(size)")
    }

    func offset(key: AnyHashable) -> CGSize {
        let point = layoutEngine.getOffset(key: key)
        log("offset key=\(key) point=\(point)")
        return CGSize(width: point.x, height: point.y)
    }

    // SwiftUI Text(image:) 주입 이미지
    func sizeImage(key: AnyHashable, styleContainer: HTMLStyleContainer) -> PlatformImage {
        var size = layoutEngine.getSize(key: key)
        if size == .zero, let fallbackSize = fallbackAttachmentSize(for: key) {
            size = fallbackSize
            log("fallback size key=\(key) size=\(size)")
        }
        if size == .zero {
            return PlatformImage.manabiEmpty(size: .zero)
        }
        var fontName: String? = nil
        var fontSize: CGFloat? = nil
        if let uiFont = styleContainer.uiFont {
            fontName = uiFont.fontName
            fontSize = uiFont.pointSize
        }
        let cacheKey = AttachmentImageCacheKey(
            key: key,
            size: size,
            fontName: fontName,
            fontSize: fontSize
        )
        if let image = textImages.object(forKey: cacheKey) {
            return image
        }
        let image = EmptyImage(size: size).image
        let cost = max(1, Int(size.width * size.height * 4))
        textImages.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private func fallbackAttachmentSize(for key: AnyHashable) -> CGSize? {
        guard let textType = key.base as? TextType else { return nil }
        guard case let .attachment(_, _, attributes, _) = textType else { return nil }
        let elementSize = ElementSize(attributes: attributes)
        guard let width = elementSize.width ?? elementSize.height,
              let height = elementSize.height ?? elementSize.width else {
            return nil
        }
        return CGSize(width: max(1, width), height: max(1, height))
    }

    func clearImageCache() {
        textImages.removeAllObjects()
    }
}

private extension AttachmentManager {
    func log(_ message: @autoclosure () -> String) {
        guard shouldLog else { return }
        let rendered = message()
        AttachmentDebugLogger.record("[AttachmentManager] \(rendered)")
#if canImport(os)
        if #available(iOS 14.0, macOS 11.0, *) {
            AttachmentManager.logger.debug("\(rendered, privacy: .public)")
        }
#endif
        NSLog("[SwiftUIHTML][AttachmentManager] %@", rendered)
        print("[SwiftUIHTML][AttachmentManager] \(rendered)")
    }
}

private struct EmptyImage {
    let size: CGSize

    var image: PlatformImage {
        PlatformImage.manabiEmpty(size: size)
    }
}

// 복합 캐시 키 정의
private final class AttachmentImageCacheKey: NSObject {
    let key: AnyHashable
    let size: CGSize
    let fontName: String?
    let fontSize: CGFloat?

    init(key: AnyHashable, size: CGSize, fontName: String?, fontSize: CGFloat?) {
        self.key = key
        self.size = size
        self.fontName = fontName
        self.fontSize = fontSize
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AttachmentImageCacheKey else { return false }
        return key == other.key && size == other.size && fontName == other.fontName && fontSize == other.fontSize
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(fontName)
        hasher.combine(fontSize)
        return hasher.finalize()
    }
}
