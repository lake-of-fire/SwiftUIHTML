//  Copyright © 2024 PRND. All rights reserved.
import SwiftUI
import NukeUI


struct ImageTag: InlineAttachmentTag {

    var attributes: [String : AttributeValue]
    init(attributes: [String : AttributeValue]) {
        self.attributes = attributes
    }
    var body: some View {
        let size = ElementSize(attributes: attributes)
        let url = attributes["src"]?.url
        LazyImage(url: url, transaction: Transaction(animation: nil)) { state in
            if let image = state.image {
                ImageContainer(image: image, size: size)
                    .onAppear {
                        recordImageEvent("success", size: size)
                    }
            } else if state.error != nil {
                ImagePlaceholder(size: size)
                    .onAppear {
                        recordImageEvent("failure", size: size)
                    }
            } else {
                ImagePlaceholder(size: size)
                    .onAppear {
                        recordImageEvent("empty", size: size)
                    }
            }
        }
        .onStart { _ in
            ImageLoadTracker.shared.begin(url: url)
        }
        .onCompletion { _ in
            ImageLoadTracker.shared.end(url: url)
        }
    }

    private func recordImageEvent(_ state: String, size: ElementSize) {
        let src = attributes["src"]?.string ?? "-"
        let width = attributes["width"]?.string ?? "-"
        let height = attributes["height"]?.string ?? "-"
        AttachmentDebugLogger.recordOnce(
            "ImageTag:\(state):\(src)",
            message: "[ImageTag] \(state) src=\(src) width=\(width) height=\(height) resolvedWidth=\(String(describing: size.width)) resolvedHeight=\(String(describing: size.height))"
        )
    }
}

private struct ImagePlaceholder: View {
    let size: ElementSize
    var body: some View {
        if size.width == nil && size.height == nil {
            Color.clear.frame(width: 1, height: 1)
        } else {
            Color.clear.modifier(SizeModifier(size: size))
        }
    }
}

private struct ImageContainer: View {
    let image: Image
    let size: ElementSize
    init(image: Image, size: ElementSize) {
        let needResizable = size.width != nil || size.height != nil
        self.image = needResizable ? image.resizable() : image
        self.size = size
    }
    var body: some View {
        image
            .modifier(SizeModifier(size: size))
    }
}



struct SizeModifier: ViewModifier, Equatable {
    let size: ElementSize
    func body(content: Content) -> some View {
        if let width = size.width, let height = size.height {
            content
                .frame(width: width, height: height)
        } else if let width = size.width {
            content
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
        } else if let height = size.height {
            content
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            content
        }
    }
}
