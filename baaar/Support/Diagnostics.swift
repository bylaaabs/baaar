import AppKit

/// Writes what baaar sees to ~/Library/Logs/baaar, to debug menu bar changes across macOS releases.
@MainActor
enum Diagnostics {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/baaar", directoryHint: .isDirectory)
    }

    static func run(controller: MenuBarController) async -> URL {
        var lines: [String] = []
        let bundle = Bundle.main.infoDictionary
        lines.append("baaar \(bundle?["CFBundleShortVersionString"] as? String ?? "?") diagnostics \(Date())")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("accessibility=\(Permissions.hasAccessibility) screenRecording=\(Permissions.hasScreenRecording) restriction=\(VisibilityRestriction.isAvailable)")
        for screen in NSScreen.screens {
            lines.append("screen \(screen.localizedName) frame=\(screen.frame) visible=\(screen.visibleFrame) scale=\(screen.backingScaleFactor)")
        }
        lines.append("reveal=\(controller.reveal) mode=\(Settings.displayMode.rawValue) sections=\(Settings.sections.mapValues(\.rawValue))")

        // Collected off the main thread: AX calls into baaar's own items would wait on the main thread.
        let snapshot = await ItemScanner.scan()
        lines.append("overflowButton=\(String(describing: snapshot.overflowButtonFrame))")
        for item in snapshot.items {
            lines.append("\(item.id) pid=\(item.pid) label=\(item.label ?? "-") pressable=\(item.isPressable) frame=\(String(describing: item.frame))")
        }

        let url = directory.appending(path: "diagnostics.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
