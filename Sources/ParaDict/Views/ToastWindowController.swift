import AppKit
import SwiftUI

@MainActor
protocol ToastPresenting: AnyObject {
  func show(_ toast: ToastMessage, anchor: ToastWindowController.Anchor)
  func showError(title: String, message: String?)
}

extension ToastPresenting {
  func show(_ toast: ToastMessage) {
    show(toast, anchor: .topCenter)
  }
}

@MainActor
final class ToastWindowController: Sendable, ToastPresenting {
  enum Anchor {
    case topCenter
    case cursor(offset: NSPoint = NSPoint(x: 20, y: 22))
  }

  static let shared = ToastWindowController()

  private var panel: NSPanel?
  private var hostingView: NSHostingView<AnyView>?
  private var currentToast: ToastMessage?
  private var dismissTask: Task<Void, Never>?
  private var currentAnchor: Anchor = .topCenter

  private let panelWidth: CGFloat = 350
  private let panelHeight: CGFloat = 80

  func show(_ toast: ToastMessage, anchor: Anchor = .topCenter) {
    dismissTask?.cancel()

    currentToast = toast
    currentAnchor = anchor
    if panel != nil {
      updateHostingView(toast: toast)
      if let panel {
        positionPanel(panel, anchor: anchor)
      }
    } else {
      createAndShowPanel(toast: toast, anchor: anchor)
    }
  }

  func showError(title: String, message: String? = nil) {
    show(ToastMessage(type: .error, title: title, message: message))
  }

  func dismiss() {
    dismissTask?.cancel()

    guard panel != nil else { return }

    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.2
        panel?.animator().alphaValue = 0
      },
      completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          self?.panel?.orderOut(nil)
          self?.panel = nil
          self?.hostingView = nil
          self?.currentToast = nil
        }
      })
  }

  private func createAndShowPanel(toast: ToastMessage, anchor: Anchor) {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false

    let hostingView = NSHostingView(
      rootView: AnyView(
        ToastView(toast: toast) { [weak self] in
          self?.dismiss()
        }
        .frame(width: panelWidth)
      ))

    panel.contentView = hostingView

    positionPanel(panel, anchor: anchor)
    panel.alphaValue = 1
    panel.orderFrontRegardless()

    self.panel = panel
    self.hostingView = hostingView
  }

  private func updateHostingView(toast: ToastMessage) {
    hostingView?.rootView = AnyView(
      ToastView(toast: toast) { [weak self] in
        self?.dismiss()
      }
      .frame(width: panelWidth)
    )
  }

  private func positionPanel(_ panel: NSPanel, anchor: Anchor) {
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens[0]

    let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
    let origin: NSPoint

    switch anchor {
    case .topCenter:
      origin = NSPoint(
        x: visibleFrame.midX - panelWidth / 2,
        y: visibleFrame.maxY - panelHeight
      )
    case .cursor(let offset):
      let rawX = mouseLocation.x + offset.x
      let rawY = mouseLocation.y + offset.y
      origin = NSPoint(
        x: min(max(rawX, visibleFrame.minX), visibleFrame.maxX - panelWidth),
        y: min(max(rawY, visibleFrame.minY), visibleFrame.maxY - panelHeight)
      )
    }

    panel.setFrameOrigin(origin)
  }
}
