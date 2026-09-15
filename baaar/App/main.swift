import AppKit

let app = NSApplication.shared
BrandFonts.register()
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
