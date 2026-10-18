import AppKit

let app = NSApplication.shared
// the kit draws baaar's own mark in the settings
Wordmark.appMark = .baaar
BrandFonts.register()
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
