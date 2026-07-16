import AppKit
import SwiftUI

@MainActor
@Observable
final class RecordingOverlayModel {
  var state: RecordingState = .idle
  var duration: TimeInterval = 0
  var meterLevel: Double = 0
  var partialTranscript: String = ""
  var overlayStatus: OverlayStatus? = nil
  var overlayHint: OverlayHint? = nil
}

private struct OverlayHost: View {
  let model: RecordingOverlayModel

  var body: some View {
    RecordingOverlayView(
      state: model.state,
      duration: model.duration,
      meterLevel: model.meterLevel,
      partialTranscript: model.partialTranscript,
      overlayStatus: model.overlayStatus,
      overlayHint: model.overlayHint
    )
  }
}

@MainActor
final class CursorOverlayWindowController: Sendable {
  private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  private let panelOffset = NSPoint(x: 20, y: 26)
  private let edgePadding: CGFloat = 10

  private let model = RecordingOverlayModel()
  private var panel: OverlayPanel?
  private var hostingView: NSHostingView<OverlayHost>?
  private var currentOrigin: NSPoint?
  private var currentSize = NSSize(
    width: RecordingOverlayView.compactSize.width,
    height: RecordingOverlayView.compactSize.height
  )

  func update(_ snapshot: OverlaySnapshot) {
    switch snapshot.state {
    case .recording, .processing:
      applyContent(snapshot)
      show()
    case .error:
      applyContent(snapshot)
      show()
    case .idle:
      if snapshot.status != nil {
        applyContent(snapshot)
        show()
      } else {
        hide()
      }
    }
  }

  func hide() {
    currentOrigin = nil
    panel?.orderOut(nil)
  }

  private func show() {
    if panel == nil {
      createPanel()
    }

    guard let panel else { return }
    positionAtCursorIfNeeded()
    if !panel.isVisible {
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
      } else {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.12
          panel.animator().alphaValue = 1
        }
      }
    }
  }

  private func createPanel() {
    let panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: currentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let hostingView = NSHostingView(rootView: OverlayHost(model: model))
    hostingView.frame = NSRect(origin: .zero, size: currentSize)
    hostingView.appearance = NSAppearance(named: .darkAqua)
    panel.contentView = hostingView

    self.panel = panel
    self.hostingView = hostingView
  }

  private func applyContent(_ snapshot: OverlaySnapshot) {
    model.state = snapshot.state
    model.duration = snapshot.duration
    model.meterLevel = snapshot.meterLevel
    model.partialTranscript = snapshot.partialTranscript
    model.overlayStatus = snapshot.status
    model.overlayHint = snapshot.hint

    let nextSize = size(
      for: snapshot.state,
      partialTranscript: snapshot.partialTranscript,
      overlayStatus: snapshot.status
    )
    if nextSize != currentSize {
      currentSize = nextSize
      panel?.setContentSize(nextSize)
      hostingView?.frame = NSRect(origin: .zero, size: nextSize)
      reclampCurrentOrigin()
    }
  }

  private func positionAtCursorIfNeeded() {
    guard currentOrigin == nil else { return }
    let mouseLocation = NSEvent.mouseLocation
    let screen = screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    let origin = OverlayPlacement.initialOrigin(
      cursor: mouseLocation,
      size: currentSize,
      visibleFrame: screen.visibleFrame,
      offset: panelOffset,
      edgePadding: edgePadding
    )
    currentOrigin = origin
    panel?.setFrameOrigin(origin)
  }

  private func reclampCurrentOrigin() {
    guard let currentOrigin else { return }
    let screen = screen(containing: currentOrigin) ?? NSScreen.main ?? NSScreen.screens[0]
    let origin = OverlayPlacement.clampedOrigin(
      currentOrigin,
      size: currentSize,
      visibleFrame: screen.visibleFrame,
      edgePadding: edgePadding
    )
    self.currentOrigin = origin
    panel?.setFrameOrigin(origin)
  }

  private func screen(containing point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
  }

  private func size(
    for state: RecordingState,
    partialTranscript: String,
    overlayStatus: OverlayStatus?
  ) -> NSSize {
    if overlayStatus != nil {
      return NSSize(
        width: RecordingOverlayView.statusSize.width,
        height: RecordingOverlayView.statusSize.height
      )
    }

    let trimmedTranscript = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    let usesExpandedLayout: Bool
    switch state {
    case .recording, .processing:
      usesExpandedLayout = true
    case .idle, .error:
      usesExpandedLayout = !trimmedTranscript.isEmpty
    }

    let size =
      usesExpandedLayout ? RecordingOverlayView.expandedSize : RecordingOverlayView.compactSize
    return NSSize(width: size.width, height: size.height)
  }
}
