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

        lines.append("\n== MenuBarAgent tree")
        lines += await menuBarAgentTree()

        let url = directory.appending(path: "diagnostics.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Apple's items live in MenuBarAgent; dump three levels with roles and actions.
    private nonisolated static func menuBarAgentTree() async -> [String] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return ["no MenuBarAgent"] }
        let pid = agent.processIdentifier
        return await Task.detached {
            var lines: [String] = []
            func walk(_ element: AXUIElement, depth: Int) {
                let role: String = AX.value(element, kAXRoleAttribute) ?? "?"
                let subrole: String = AX.value(element, kAXSubroleAttribute) ?? ""
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute, kAXValueAttribute]
                    .compactMap { (AX.value(element, $0) as String?)?.nilIfEmpty.map { "\($0.dropFirst(2))=\($0)" } }
                    .joined(separator: " ")
                lines.append(String(repeating: "  ", count: depth) + "\(role) \(subrole) \(label) frame=\(String(describing: AX.frame(element))) actions=\(AX.actions(element))")
                guard depth < 4 else { return }
                for child in (AX.value(element, kAXChildrenAttribute) as [AXUIElement]?) ?? [] {
                    walk(child, depth: depth + 1)
                }
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            if let extras: AXUIElement = AX.value(app, "AXExtrasMenuBar") {
                walk(extras, depth: 0)
            }
            return lines
        }.value
    }
}
