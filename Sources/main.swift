import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
