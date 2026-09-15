import AppKit

/// Writes what baaar sees to ~/Library/Logs/baaar, to debug menu bar changes across macOS releases.
@MainActor
enum Diagnostics {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/baaar", directoryHint: .isDirectory)
    }

    static func run(controls: ControlItems) async -> URL {
        var lines: [String] = []
        let bundle = Bundle.main.infoDictionary
        lines.append("baaar \(bundle?["CFBundleShortVersionString"] as? String ?? "?") diagnostics \(Date())")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("accessibility=\(Permissions.hasAccessibility) screenRecording=\(Permissions.hasScreenRecording)")
        for screen in NSScreen.screens {
            lines.append("screen \(screen.localizedName) frame=\(screen.frame) visible=\(screen.visibleFrame) topRight=\(String(describing: screen.auxiliaryTopRightArea)) scale=\(screen.backingScaleFactor)")
        }
        lines.append("hideLength=\(HideLength.value(for: controls.toggleScreen)) visibility=\(controls.visibility)")
        lines.append("toggle window=\(String(describing: controls.toggle.button?.window?.frame)) divider window=\(String(describing: controls.divider.button?.window?.frame))")

        let snapshot = await ItemScanner.scan()
        lines.append("overflowButton=\(String(describing: snapshot.overflowButtonFrame))")
        for item in snapshot.items {
            let element = item.element.raw
            let fields = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXRoleAttribute, kAXSubroleAttribute]
                .map { "\($0.dropFirst(2))=\((AX.value(element, $0) as String?) ?? "")" }
                .joined(separator: " ")
            lines.append("\(item.id) pid=\(item.pid) own=\(item.isOwn) pressable=\(item.isPressable) frame=\(String(describing: item.frame)) \(fields) actions=\(AX.actions(element))")
        }

        let url = directory.appending(path: "diagnostics.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
