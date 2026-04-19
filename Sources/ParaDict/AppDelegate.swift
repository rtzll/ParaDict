import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private var container: AppContainer!
  private var appNapActivity: NSObjectProtocol?
  private let overlayWindowController = CursorOverlayWindowController()
  private var iconBinder: MenuBarIconBinder!
  private var overlayBinder: OverlayWindowBinder!
  private var menuBarViewModel: MenuBarViewModel { container.menuBarViewModel }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    // Disable App Nap for reliable background operation
    appNapActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
      reason: "Audio recording and transcription"
    )

    container = AppContainer()

    setupStatusItem()
    setupPopover()

    iconBinder = MenuBarIconBinder(
      statusItem: statusItem,
      recordingController: container.recordingController
    )
    overlayBinder = OverlayWindowBinder(
      viewModel: container.overlayViewModel,
      windowController: overlayWindowController
    )
    iconBinder.start()
    overlayBinder.start()

    Task {
      await container.bootstrap.start()
    }
  }

  // MARK: - Status Item & Popover

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.image = MenuBarIconRenderer.render(state: .idle, meterLevel: 0)
      button.action = #selector(togglePopover(_:))
      button.target = self
    }
  }

  private func setupPopover() {
    popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = VibrancyHostingController(
      rootView: MenuBarView().environment(menuBarViewModel)
    )
  }

  @objc private func togglePopover(_ sender: Any?) {
    if popover.isShown {
      popover.performClose(sender)
    } else if let button = statusItem.button {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    overlayWindowController.hide()
    if let activity = appNapActivity {
      ProcessInfo.processInfo.endActivity(activity)
      appNapActivity = nil
    }
  }
}

// MARK: - Vibrancy Hosting

/// Hosting view that opts into vibrancy so the popover content participates
/// in the system's glass/translucency effect rather than painting an opaque
/// backing.
private final class VibrancyHostingView<Content: View>: NSHostingView<Content> {
  override var allowsVibrancy: Bool { true }
}

/// View controller wrapper for VibrancyHostingView, since NSPopover requires
/// a contentViewController (not just a view).
private final class VibrancyHostingController<Content: View>: NSViewController {
  private let hostingView: VibrancyHostingView<Content>

  init(rootView: Content) {
    hostingView = VibrancyHostingView(rootView: rootView)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    view = hostingView
  }
}
