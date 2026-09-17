import AppKit

@main
@MainActor
enum ParaDictApp {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate

    // NSApplication's delegate is weak; retain it for the entire event loop.
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}
