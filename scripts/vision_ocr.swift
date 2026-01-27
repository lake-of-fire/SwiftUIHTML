import Foundation
import Vision
#if canImport(AppKit)
import AppKit
#endif

struct OCRResult: Codable {
    let text: String
    let lines: [String]
}

func loadCGImage(path: String) -> CGImage? {
#if canImport(AppKit)
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let rep = NSBitmapImageRep(data: data) else {
        return nil
    }
    return rep.cgImage
#else
    return nil
#endif
}

func recognizeText(from imagePath: String) -> OCRResult? {
    guard let cgImage = loadCGImage(path: imagePath) else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return nil
    }
    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
    let lines = observations.compactMap { observation in
        observation.topCandidates(1).first?.string
    }
    return OCRResult(text: lines.joined(separator: "\n"), lines: lines)
}

let args = CommandLine.arguments
if args.count < 2 {
    fputs("usage: vision_ocr.swift <image-path>\n", stderr)
    exit(1)
}

let path = args[1]
guard let result = recognizeText(from: path) else {
    print("error: failed to OCR image")
    exit(0)
}

if result.text.isEmpty {
    print("(no text found)")
} else {
    print(result.text)
}
