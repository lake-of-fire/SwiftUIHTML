#!/usr/bin/env swift
import Foundation
import Vision
import ImageIO
import CoreGraphics

struct LineBox: Codable {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct OCRReport: Codable {
    let imagePath: String
    let imageWidth: Int
    let imageHeight: Int
    let lineCount: Int
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let leftPadding: CGFloat
    let rightPadding: CGFloat
    let lines: [LineBox]
}

struct LineDelta: Codable {
    let index: Int
    let textNew: String
    let textBase: String
    let dx: CGFloat
    let dy: CGFloat
    let dWidth: CGFloat
    let dHeight: CGFloat
}

struct DeltaReport: Codable {
    let newPath: String
    let baselinePath: String
    let count: Int
    let deltas: [LineDelta]
}

func usage() -> Never {
    fputs("Usage: ocr_compare.swift <baseline.png> <new.png> [outputDir]\n", stderr)
    exit(2)
}

func loadCGImage(path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Failed to load image at \(path)")
    }
    return image
}

func recognizeText(image: CGImage) -> [(CGRect, String)] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.01
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
        try handler.perform([request])
    } catch {
        fatalError("Vision request failed: \(error)")
    }
    let observations = request.results ?? []
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    return observations.compactMap { obs in
        guard let candidate = obs.topCandidates(1).first else { return nil }
        let rect = VNImageRectForNormalizedRect(obs.boundingBox, Int(width), Int(height))
        // Convert to top-left coordinate space for easier comparison.
        let topLeftY = height - rect.maxY
        let converted = CGRect(x: rect.minX, y: topLeftY, width: rect.width, height: rect.height)
        return (converted, candidate.string)
    }
}

func clusterLines(rects: [CGRect], texts: [String]) -> [(CGRect, String)] {
    guard !rects.isEmpty else { return [] }
    let pairs = zip(rects, texts)
        .map { (rect: $0.0, text: $0.1) }
        .sorted { $0.rect.minY < $1.rect.minY }
    var lines: [(CGRect, String)] = []
    var currentRects: [CGRect] = []
    var currentTexts: [String] = []
    var currentMidY: CGFloat?
    for pair in pairs {
        let midY = pair.rect.midY
        if let current = currentMidY {
            let threshold = max(4, pair.rect.height * 0.6)
            if abs(midY - current) <= threshold {
                currentRects.append(pair.rect)
                currentTexts.append(pair.text)
            } else {
                lines.append(makeLineCluster(rects: currentRects, texts: currentTexts))
                currentRects = [pair.rect]
                currentTexts = [pair.text]
                currentMidY = midY
            }
        } else {
            currentRects = [pair.rect]
            currentTexts = [pair.text]
            currentMidY = midY
        }
    }
    if !currentRects.isEmpty {
        lines.append(makeLineCluster(rects: currentRects, texts: currentTexts))
    }
    return lines
}

func makeLineCluster(rects: [CGRect], texts: [String]) -> (CGRect, String) {
    var union = rects.first ?? .zero
    for rect in rects.dropFirst() {
        union = union.union(rect)
    }
    let joined = texts.filter { !$0.isEmpty }.joined(separator: " | ")
    return (union, joined)
}

func buildReport(imagePath: String) -> OCRReport {
    let image = loadCGImage(path: imagePath)
    let results = recognizeText(image: image)
    let rects = results.map { $0.0 }
    let texts = results.map { $0.1 }
    let lines = clusterLines(rects: rects, texts: texts)
    let union = rects.reduce(CGRect.null) { $0.union($1) }
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let leftPadding = union.isNull ? 0 : union.minX
    let rightPadding = union.isNull ? 0 : max(0, width - union.maxX)
    let topPadding = union.isNull ? 0 : union.minY
    let bottomPadding = union.isNull ? 0 : max(0, height - union.maxY)
    let lineBoxes = lines.map { line in
        LineBox(
            text: line.1,
            x: line.0.minX,
            y: line.0.minY,
            width: line.0.width,
            height: line.0.height
        )
    }
    return OCRReport(
        imagePath: imagePath,
        imageWidth: image.width,
        imageHeight: image.height,
        lineCount: lineBoxes.count,
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        leftPadding: leftPadding,
        rightPadding: rightPadding,
        lines: lineBoxes
    )
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url)
}

let args = CommandLine.arguments
if args.count < 3 { usage() }
let baselinePath = args[1]
let newPath = args[2]
let outputDir = args.count > 3 ? args[3] : "/tmp/swiftuihtml-ocr"

let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let baseReport = buildReport(imagePath: baselinePath)
let newReport = buildReport(imagePath: newPath)

let baseURL = outputURL.appendingPathComponent("baseline.lines.json")
let newURL = outputURL.appendingPathComponent("new.lines.json")
do {
    try writeJSON(baseReport, to: baseURL)
    try writeJSON(newReport, to: newURL)
} catch {
    fatalError("Failed to write reports: \(error)")
}

let count = min(baseReport.lines.count, newReport.lines.count)
let deltas = (0..<count).map { index -> LineDelta in
    let base = baseReport.lines[index]
    let new = newReport.lines[index]
    return LineDelta(
        index: index,
        textNew: new.text,
        textBase: base.text,
        dx: new.x - base.x,
        dy: new.y - base.y,
        dWidth: new.width - base.width,
        dHeight: new.height - base.height
    )
}
let deltaReport = DeltaReport(
    newPath: newPath,
    baselinePath: baselinePath,
    count: count,
    deltas: deltas
)
let deltaURL = outputURL.appendingPathComponent("line-deltas.json")
do {
    try writeJSON(deltaReport, to: deltaURL)
} catch {
    fatalError("Failed to write deltas: \(error)")
}

print("Wrote OCR reports to \(outputURL.path)")
