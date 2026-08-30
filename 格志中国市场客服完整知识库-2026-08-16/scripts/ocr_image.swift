import Foundation
import Vision
import AppKit

if CommandLine.arguments.count < 2 {
    fputs("usage: ocr_image <image_path>\n", stderr)
    exit(2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let nsImage = NSImage(contentsOf: imageURL),
      let tiffData = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    fputs("failed to load image: \(imagePath)\n", stderr)
    exit(1)
}

func paddedForVision(_ image: CGImage) -> CGImage {
    let targetWidth = ((image.width + 15) / 16) * 16
    let targetHeight = ((image.height + 15) / 16) * 16
    if targetWidth == image.width && targetHeight == image.height {
        return image
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    context.draw(image, in: CGRect(x: 0, y: targetHeight - image.height, width: image.width, height: image.height))
    return context.makeImage() ?? image
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US"]
if let supportedLanguages = try? request.supportedRecognitionLanguages() {
    let usableLanguages = preferredLanguages.filter { supportedLanguages.contains($0) }
    if !usableLanguages.isEmpty {
        request.recognitionLanguages = usableLanguages
    }
}

let handler = VNImageRequestHandler(cgImage: paddedForVision(cgImage), options: [:])

do {
    try handler.perform([request])
} catch {
    fputs("ocr failed: \(error)\n", stderr)
    exit(1)
}

let observations = request.results ?? []
let lines = observations.compactMap { observation -> String? in
    observation.topCandidates(1).first?.string
}

print(lines.joined(separator: "\n"))
