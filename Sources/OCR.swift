import Foundation
import CoreGraphics
import Vision

struct OCRResult {
    var text: String
    var lines: [String]
    var averageConfidence: Float
}

enum OCRError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return "文字识别失败：\(message)"
        }
    }
}

enum OCR {
    /// 识别一张小截图里的文字，按阅读顺序拼成一行。
    static func recognize(_ image: CGImage,
                          languages: [String] = ["en-US"],
                          level: VNRequestTextRecognitionLevel = .accurate) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.minimumTextHeight = 0.0

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.failed(error.localizedDescription)
        }

        struct Item {
            let string: String
            let confidence: Float
            let box: CGRect
        }

        let items: [Item] = (request.results ?? []).compactMap { observation in
            guard let top = observation.topCandidates(1).first, top.confidence > 0.25 else { return nil }
            return Item(string: top.string, confidence: top.confidence, box: observation.boundingBox)
        }

        // Vision 的坐标原点在左下角，按「从上到下、从左到右」排序
        let sorted = items.sorted(by: { (lhs: Item, rhs: Item) -> Bool in
            if abs(lhs.box.midY - rhs.box.midY) > 0.02 { return lhs.box.midY > rhs.box.midY }
            return lhs.box.minX < rhs.box.minX
        })

        let lines = sorted
            .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let confidence = sorted.isEmpty ? 0 : sorted.reduce(Float(0)) { $0 + $1.confidence } / Float(sorted.count)
        return OCRResult(text: lines.joined(separator: " "), lines: lines, averageConfidence: confidence)
    }
}
