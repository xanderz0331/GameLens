import Foundation
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "还没有「屏幕录制」权限。请在 系统设置 › 隐私与安全性 › 屏幕录制 里勾选 GameLens，然后重新打开 GameLens。"
        case .displayNotFound:
            return "找不到对应的显示器，请重新框选识别区域。"
        case .failed(let message):
            return "抓屏失败：\(message)"
        }
    }
}

/// 用 ScreenCaptureKit 只抓「框选的那一小块」，开销很低，可以每秒抓 2~3 次。
@available(macOS 14.0, *)
final class ScreenCapturer {
    private var cachedContent: SCShareableContent?
    private var cachedAt = Date.distantPast
    private let cacheLifetime: TimeInterval = 12

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedContent, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            return cachedContent
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cachedContent = content
            cachedAt = Date()
            return content
        } catch {
            cachedContent = nil
            throw CaptureError.permissionDenied
        }
    }

    func capture(_ region: CaptureRegion) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            cachedContent = nil
            throw CaptureError.displayNotFound
        }

        // 把 GameLens 自己的悬浮窗从画面里排除掉，避免"翻译被自己识别"的死循环
        var ownApps: [SCRunningApplication] = []
        if let bundleID = Bundle.main.bundleIdentifier {
            ownApps = content.applications.filter { $0.bundleIdentifier == bundleID }
        }

        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApps,
                                     exceptingWindows: [])

        let local = region.localRect
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: local.minX, y: local.minY,
                                   width: max(4, local.width), height: max(4, local.height))
        config.width = max(4, Int((local.width * region.scale).rounded()))
        config.height = max(4, Int((local.height * region.scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }
}
