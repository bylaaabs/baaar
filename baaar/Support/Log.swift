import Foundation

/// Appends to ~/Library/Logs/baaar/baaar.log; os_log redacts the details that matter here.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/baaar/baaar.log")

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
