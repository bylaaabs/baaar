import Foundation

/// Appends to ~/Library/Logs/baaar/baaar.log; os_log redacts the details that matter here.
///
/// Callers on any thread go through one serial queue, so lines never interleave. Past 1 MB the
/// file moves to `baaar.log.1`, replacing the one before, so the log stays small.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/baaar/baaar.log")
    private static let previousURL = url.appendingPathExtension("1")
    private static let rotationSize = 1_000_000
    private static let queue = DispatchQueue(label: "com.laaabs.baaar.log", qos: .utility)

    static func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        // Synchronous, so nothing is lost when baaar exits right after logging.
        queue.sync { append(line) }
    }

    private static func append(_ line: String) {
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? files.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= rotationSize {
            try? files.removeItem(at: previousURL)
            try? files.moveItem(at: url, to: previousURL)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
