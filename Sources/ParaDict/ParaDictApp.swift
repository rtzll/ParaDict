import SwiftUI

@main
struct ParaDictApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // Status item and popover are managed by AppDelegate.
    // A scene is still required to keep the SwiftUI lifecycle alive.
    Settings { EmptyView() }
  }
}
