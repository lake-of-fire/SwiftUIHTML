import Foundation
import WebKit
#if canImport(AppKit)
import AppKit
#endif

final class Renderer: NSObject, WKNavigationDelegate {
    private let htmlPath: String
    private let outputPath: String
    private let width: CGFloat
    private let height: CGFloat
    private let webView: WKWebView
    private var finished = false

    init(htmlPath: String, outputPath: String, width: CGFloat, height: CGFloat) {
        self.htmlPath = htmlPath
        self.outputPath = outputPath
        self.width = width
        self.height = height
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        let url = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !finished else { return }
        finished = true
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        webView.takeSnapshot(with: config) { image, _ in
            guard let image else {
                exit(3)
            }
#if canImport(AppKit)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                exit(4)
            }
            do {
                try png.write(to: URL(fileURLWithPath: self.outputPath))
            } catch {
                exit(5)
            }
#endif
            exit(0)
        }
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: render_html.swift <html-file> <output-png> [width] [height]\n", stderr)
    exit(1)
}

let htmlPath = args[1]
let outputPath = args[2]
let width = CGFloat(Double(args.count > 3 ? args[3] : "600") ?? 600)
let height = CGFloat(Double(args.count > 4 ? args[4] : "220") ?? 220)

let renderer = Renderer(htmlPath: htmlPath, outputPath: outputPath, width: width, height: height)
renderer.start()
RunLoop.main.run()
