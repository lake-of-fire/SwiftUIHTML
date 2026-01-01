// Copyright © 2025 PRND. All rights reserved.
import Combine
import CoreGraphics
import Foundation


final class AttachmentManager: ObservableObject {
    lazy var layoutEngine = AttachmentLayoutEngine()
    private var cancellables = Set<AnyCancellable>()

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
        //NOTE: lineSpacing 각각 다를 수 있음
        layoutEngine.lineSpacing = styleContainer.textLine?.lineSpacing ?? 0
    }

    func offset(key: AnyHashable) -> CGSize {
        let point = layoutEngine.getOffset(key: key)
        return CGSize(width: point.x, height: point.y)
    }

    // SwiftUI Text(image:) 주입 이미지
    func sizeImage(key: AnyHashable, styleContainer: HTMLStyleContainer) -> PlatformImage {
        let size = layoutEngine.getSize(key: key)
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

    func clearImageCache() {
        textImages.removeAllObjects()
    }
}

private extension AttachmentManager {
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
