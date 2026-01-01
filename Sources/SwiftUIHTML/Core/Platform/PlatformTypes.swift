//  Copyright © 2025 PRND. All rights reserved.
import CoreText
import Foundation

#if os(macOS)
import AppKit
internal typealias PlatformFont = NSFont
internal typealias PlatformColor = NSColor
internal typealias PlatformImage = NSImage
internal typealias PlatformView = NSView
internal typealias PlatformFontDescriptor = NSFontDescriptor
#else
import UIKit
internal typealias PlatformFont = UIFont
internal typealias PlatformColor = UIColor
internal typealias PlatformImage = UIImage
internal typealias PlatformView = UIView
internal typealias PlatformFontDescriptor = UIFontDescriptor
#endif

internal extension PlatformFont {
    var manabiCTFont: CTFont {
        CTFontCreateWithName(fontName as CFString, pointSize, nil)
    }

    var manabiLineHeight: CGFloat {
        let ctFont = manabiCTFont
        return CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)
    }

    var manabiFontHeight: CGFloat {
        let ctFont = manabiCTFont
        return CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont)
    }

    var manabiBoundingBoxMaxY: CGFloat {
        CTFontGetBoundingBox(manabiCTFont).maxY
    }
}

internal extension PlatformImage {
    static func manabiEmpty(size: CGSize) -> PlatformImage {
#if os(macOS)
        if size == .zero {
            return PlatformImage(size: .zero)
        }
        let image = PlatformImage(size: size)
        image.lockFocus()
        PlatformColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
#else
        if size == .zero {
            return PlatformImage()
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in }
#endif
    }
}
