import Foundation
import CoreGraphics

/// 把 OCR 出来的文本做归一化，用来判断"这一句台词是否变化"
func normalizeForCompare(_ s: String) -> String {
    let collapsed = s
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?;:'\"`~-—…·。，！？；：、"))
    return stripped.lowercased()
}

/// CGImage 不是 Sendable，用一个盒子把它安全地丢到后台线程。
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}
