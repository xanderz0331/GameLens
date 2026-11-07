import Foundation
import AppKit

enum HistoryStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GameLens", isDirectory: true)
    }

    static var logFile: URL {
        directory.appendingPathComponent("对话记录.md")
    }

    static func append(source: String, translation: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: logFile.path) {
                let header = "# GameLens 对话记录\n\n> 只记录识别到的台词，方便事后复习。\n\n"
                try header.write(to: logFile, atomically: true, encoding: .utf8)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let stamp = formatter.string(from: Date())
            let entry = "- `\(stamp)` **\(source)**\n  - \(translation.replacingOccurrences(of: "\n", with: "\n    "))\n"

            let handle = try FileHandle(forWritingTo: logFile)
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            try handle.close()
        } catch {
            NSLog("[GameLens] 写日志失败：\(error.localizedDescription)")
        }
    }

    static func revealInFinder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([logFile])
    }
}
