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
  private let followAlpha: CGFloat = 0.35
  private let snapThreshold: CGFloat = 0.5

  private let model = RecordingOverlayModel()
  private var panel: OverlayPanel?
  private var hostingView: NSHostingView<OverlayHost>?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var animationTimer: Timer?
  private var currentOrigin: NSPoint?
  private var currentSize = NSSize(
    width: RecordingOverlayView.compactSize.width,
    height: RecordingOverlayView.compactSize.height
  )

  func update(
    state: RecordingState,
    duration: TimeInterval,
    meterLevel: Double,
    partialTranscript: String,
    overlayStatus: OverlayStatus?,
    overlayHint: OverlayHint?
  ) {
    switch state {
    case .recording, .processing:
      show()
      applyContent(
        state: state, duration: duration, meterLevel: meterLevel,
        partialTranscript: partialTranscript, overlayStatus: overlayStatus, overlayHint: overlayHint
      )
    case .error(let message):
      show()
      applyContent(
        state: .error(message), duration: duration, meterLevel: meterLevel,
        partialTranscript: partialTranscript, overlayStatus: overlayStatus, overlayHint: overlayHint
      )
    case .idle:
      if overlayStatus != nil {
        show()
        applyContent(
          state: state, duration: duration, meterLevel: meterLevel,
          partialTranscript: partialTranscript, overlayStatus: overlayStatus,
          overlayHint: overlayHint)
      } else {
        hide()
      }
    }
  }

  func hide() {
    stopFollowingCursor()
    currentOrigin = nil
    panel?.orderOut(nil)
  }

  private func show() {
    if panel == nil {
      createPanel()
    }

    guard let panel else { return }
    if !panel.isVisible {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        panel.animator().alphaValue = 1
      }
    }

    startFollowingCursor()
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

  private func applyContent(
    state: RecordingState,
    duration: TimeInterval,
    meterLevel: Double,
    partialTranscript: String,
    overlayStatus: OverlayStatus?,
    overlayHint: OverlayHint?
  ) {
    model.state = state
    model.duration = duration
    model.meterLevel = meterLevel
    model.partialTranscript = partialTranscript
    model.overlayStatus = overlayStatus
    model.overlayHint = overlayHint

    let nextSize = size(
      for: state,
      partialTranscript: partialTranscript,
      overlayStatus: overlayStatus
    )
    if nextSize != currentSize {
      currentSize = nextSize
      panel?.setContentSize(nextSize)
      hostingView?.frame = NSRect(origin: .zero, size: nextSize)
      // Resize can push the overlay off the cursor anchor; kick the animation to re-clamp.
      ensureAnimating()
    }
  }

  // MARK: - Cursor following (event-driven)

  private func startFollowingCursor() {
    if currentOrigin == nil {
      let target = targetOriginForCursor()
      currentOrigin = target
      panel?.setFrameOrigin(target)
    }

    if globalMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
        [weak self] _ in
        Task { @MainActor [weak self] in
          self?.ensureAnimating()
        }
      }
    }
    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
        [weak self] event in
        Task { @MainActor [weak self] in
          self?.ensureAnimating()
        }
        return event
      }
    }
  }

  private func stopFollowingCursor() {
    if let monitor = globalMouseMonitor {
      NSEvent.removeMonitor(monitor)
      globalMouseMonitor = nil
    }
    if let monitor = localMouseMonitor {
      NSEvent.removeMonitor(monitor)
      localMouseMonitor = nil
    }
    animationTimer?.invalidate()
    animationTimer = nil
  }

  private func ensureAnimating() {
    guard animationTimer == nil else { return }
    animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.tickAnimation()
      }
    }
  }

  private func tickAnimation() {
    guard let panel else {
      animationTimer?.invalidate()
      animationTimer = nil
      return
    }

    let target = targetOriginForCursor()
    let current = currentOrigin ?? target
    let dx = target.x - current.x
    let dy = target.y - current.y

    if abs(dx) < snapThreshold && abs(dy) < snapThreshold {
      currentOrigin = target
      panel.setFrameOrigin(target)
      animationTimer?.invalidate()
      animationTimer = nil
      return
    }

    let newOrigin = NSPoint(
      x: current.x + dx * followAlpha,
      y: current.y + dy * followAlpha
    )
    currentOrigin = newOrigin
    panel.setFrameOrigin(newOrigin)
  }

  private func targetOriginForCursor() -> NSPoint {
    let mouseLocation = NSEvent.mouseLocation
    let screen = screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    let visibleFrame = screen.visibleFrame.insetBy(dx: edgePadding, dy: edgePadding)

    let rawX = mouseLocation.x + panelOffset.x
    let rawY = mouseLocation.y + panelOffset.y

    let clampedX = min(max(rawX, visibleFrame.minX), visibleFrame.maxX - currentSize.width)
    let clampedY = min(max(rawY, visibleFrame.minY), visibleFrame.maxY - currentSize.height)

    return NSPoint(x: clampedX, y: clampedY)
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
