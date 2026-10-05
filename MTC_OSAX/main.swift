import AppKit

// macOS 26's AppKit update cycle holds each incoming Apple event until the next display frame, about 16.5 ms per
// command (Finder and System Events pay it too). The app has no windows to pace, so it turns the cycle off, which
// makes a round trip about 0.2 ms. The key is undocumented: if a later macOS ignores it, commands are just slower.
UserDefaults.standard.register(defaults: ["NSApplicationUpdateCycleEnabled": false])

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
