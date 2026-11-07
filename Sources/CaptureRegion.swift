import Foundation
import AppKit

/// 一块被框选的识别区域。
/// - `displayID` / `localRect`: 给 ScreenCaptureKit 用，坐标原点在显示器左上角（单位：点）
/// - `globalRect`: 给悬浮窗定位用，AppKit 全局坐标（原点在主屏左下角，y 向上）
struct CaptureRegion: Codable, Equatable {
    var displayID: UInt32
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var globalX: Double
    var globalY: Double
    var globalWidth: Double
    var globalHeight: Double
    var scale: Double

    var localRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var globalRect: CGRect { CGRect(x: globalX, y: globalY, width: globalWidth, height: globalHeight) }

    static func make(screen: NSScreen, globalRect g: CGRect) -> CaptureRegion {
        let frame = screen.frame
        let localX = g.minX - frame.minX
        let localY = frame.maxY - g.maxY
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CaptureRegion(displayID: displayID,
                             x: Double(localX),
                             y: Double(localY),
                             width: Double(g.width),
                             height: Double(g.height),
                             globalX: Double(g.minX),
                             globalY: Double(g.minY),
                             globalWidth: Double(g.width),
                             globalHeight: Double(g.height),
                             scale: Double(screen.backingScaleFactor))
    }

    static func load() -> CaptureRegion? {
        guard let data = UserDefaults.standard.data(forKey: "captureRegion") else { return nil }
        return try? JSONDecoder().decode(CaptureRegion.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "captureRegion")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: "captureRegion")
    }

    var description: String {
        "\(Int(width))×\(Int(height)) @ 屏 \(displayID)"
    }
}
