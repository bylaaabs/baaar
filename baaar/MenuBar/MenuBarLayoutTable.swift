import AppKit

/// macOS 27's record of where every menu bar item sits.
///
/// MenuBarAgent keeps `TrailingItemPreferredPositions` (item id → weight, larger weights further
/// left) in a protected group container. Ids look like `status:<bundle id>::<autosave name>` for
/// apps and `module:<Name>` for Apple's modules. Writing a weight through cfprefsd re-sorts the
/// bar live, so items move without touching the cursor. Access needs the user to pick the file
/// once; baaar keeps a security-scoped bookmark to it.
@MainActor
enum MenuBarLayoutTable {
    static let key = "TrailingItemPreferredPositions"
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")

    private static let bookmarkKey = "menuBarLayoutBookmark"
    private static var accessedURL: URL?

    /// Whether baaar can read the table right now.
    static var hasAccess: Bool {
        (try? Data(contentsOf: url)) != nil
    }

    /// Resolves the saved bookmark, if any, so reads and writes work this session.
    static func restoreAccess() {
        guard accessedURL == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &isStale) else {
            Log.write("layout table bookmark failed to resolve")
            return
        }
        if resolved.startAccessingSecurityScopedResource() {
            accessedURL = resolved
        }
        if isStale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope]) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    /// Asks the user to pick the table in an open panel, the only way to reach the protected container.
    static func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "select com.apple.MenuBar.plist and press grant access, so baaar can rearrange your menu bar"
        panel.prompt = "grant access"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        NSApp.activate()
        guard panel.runModal() == .OK, let picked = panel.url else { return false }
        guard picked.standardizedFileURL.path == url.standardizedFileURL.path else {
            Log.write("layout table: picked \(picked.path) instead of the table")
            return false
        }
        if let data = try? picked.bookmarkData(options: [.withSecurityScope]) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        if picked.startAccessingSecurityScopedResource() {
            accessedURL = picked
        }
        return hasAccess
    }

    /// Every item's weight, straight from the file.
    static func positions() -> [String: Double]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return (plist[key] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    /// Writes weights through cfprefsd, which notifies MenuBarAgent; a direct file write would be ignored and overwritten.
    @discardableResult
    static func setPositions(_ updates: [String: Double]) -> Bool {
        guard var current = positions() else { return false }
        for (id, weight) in updates {
            current[id] = weight
        }
        let domain = url.path as CFString
        CFPreferencesSetValue(key as CFString, current as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synced = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        Log.write("layout table write of \(updates.count) weights synced=\(synced)")
        return synced
    }
}
