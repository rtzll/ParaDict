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
  var isCursorMovingQuickly = false
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
      overlayHint: model.overlayHint,
      isCursorMovingQuickly: model.isCursorMovingQuickly
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
}

@MainActor
final class CursorOverlayWindowController: Sendable {
  private struct CursorSample {
    let location: NSPoint
    let timestamp: TimeInterval
  }

  private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  private let panelOffset = NSPoint(x: 20, y: 26)
  private let edgePadding: CGFloat = 10
  private let springResponse: TimeInterval = 0.22
  private let snapThreshold: CGFloat = 0.5
  private let snapVelocityThreshold: CGFloat = 4
  private let quickCursorVelocity: CGFloat = 650
  private let cursorSettleDelay: Duration = .milliseconds(320)

  private let model = RecordingOverlayModel()
  private var panel: OverlayPanel?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var animationTimer: Timer?
  private var cursorSettleTask: Task<Void, Never>?
  private var lastCursorSample: CursorSample?
  private var lastAnimationTimestamp: TimeInterval?
  private var currentVelocity = CGVector.zero
  private var currentOrigin: NSPoint?
  private let canvasSize = NSSize(
    width: RecordingOverlayView.expandedSize.width,
    height: RecordingOverlayView.expandedSize.height
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
    stopFollowingCursor()
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

    startFollowingCursor()
  }

  private func createPanel() {
    let panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: canvasSize),
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
    hostingView.frame = NSRect(origin: .zero, size: canvasSize)
    hostingView.appearance = NSAppearance(named: .darkAqua)
    panel.contentView = hostingView

    self.panel = panel
  }

  private func applyContent(_ snapshot: OverlaySnapshot) {
    let changesStructure =
      model.state != snapshot.state
      || model.overlayStatus != snapshot.status
      || model.overlayHint != snapshot.hint
    let updateModel = {
      self.model.state = snapshot.state
      self.model.duration = snapshot.duration
      self.model.meterLevel = snapshot.meterLevel
      self.model.partialTranscript = snapshot.partialTranscript
      self.model.overlayStatus = snapshot.status
      self.model.overlayHint = snapshot.hint
    }

    if changesStructure,
      panel?.isVisible == true,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    {
      withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.2)) {
        updateModel()
      }
    } else {
      updateModel()
    }

    if !supportsAdaptiveCompactness(snapshot) {
      cursorSettleTask?.cancel()
      cursorSettleTask = nil
      setAdaptiveCompactness(false, animated: false)
    }
  }

  // MARK: - Cursor following

  private func startFollowingCursor() {
    positionAtCursorIfNeeded()
    if lastCursorSample == nil {
      lastCursorSample = CursorSample(
        location: NSEvent.mouseLocation,
        timestamp: ProcessInfo.processInfo.systemUptime
      )
    }

    if globalMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
        [weak self] _ in
        Task { @MainActor [weak self] in
          self?.cursorDidMove()
        }
      }
    }
    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
        [weak self] event in
        Task { @MainActor [weak self] in
          self?.cursorDidMove()
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
    cursorSettleTask?.cancel()
    cursorSettleTask = nil
    lastCursorSample = nil
    lastAnimationTimestamp = nil
    currentVelocity = .zero
    setAdaptiveCompactness(false, animated: false)
  }

  private func cursorDidMove() {
    updateAdaptiveCompactness()

    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      animationTimer?.invalidate()
      animationTimer = nil
      positionAtCursor()
    } else {
      ensureAnimating()
    }
  }

  private func ensureAnimating() {
    guard animationTimer == nil else { return }
    lastAnimationTimestamp = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        self?.tickAnimation()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    animationTimer = timer
  }

  private func tickAnimation() {
    guard let panel else {
      animationTimer?.invalidate()
      animationTimer = nil
      return
    }

    let timestamp = ProcessInfo.processInfo.systemUptime
    let elapsed = min(
      max(timestamp - (lastAnimationTimestamp ?? timestamp), 1.0 / 240.0),
      1.0 / 30.0
    )
    lastAnimationTimestamp = timestamp

    let target = targetOriginForCursor()
    let step = OverlayPlacement.criticallyDampedSpringStep(
      current: currentOrigin ?? target,
      target: target,
      velocity: currentVelocity,
      response: springResponse,
      elapsed: elapsed
    )
    currentOrigin = step.origin
    currentVelocity = step.velocity
    panel.setFrameOrigin(step.origin)

    let remainingDistance = distance(from: step.origin, to: target)
    let speed = sqrt(
      step.velocity.dx * step.velocity.dx + step.velocity.dy * step.velocity.dy
    )
    if remainingDistance < snapThreshold, speed < snapVelocityThreshold {
      currentOrigin = target
      currentVelocity = .zero
      panel.setFrameOrigin(target)
      animationTimer?.invalidate()
      animationTimer = nil
      lastAnimationTimestamp = nil
    }
  }

  private func updateAdaptiveCompactness() {
    let timestamp = ProcessInfo.processInfo.systemUptime
    let location = NSEvent.mouseLocation

    if let lastCursorSample {
      let elapsed = max(timestamp - lastCursorSample.timestamp, 1.0 / 1_000.0)
      let velocity = distance(from: lastCursorSample.location, to: location) / elapsed
      if velocity >= quickCursorVelocity, supportsAdaptiveCompactness {
        setAdaptiveCompactness(true)
      }
    }
    lastCursorSample = CursorSample(location: location, timestamp: timestamp)

    guard model.isCursorMovingQuickly else { return }
    cursorSettleTask?.cancel()
    cursorSettleTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: self?.cursorSettleDelay ?? .milliseconds(320))
      guard !Task.isCancelled else { return }
      self?.setAdaptiveCompactness(false)
      self?.cursorSettleTask = nil
    }
  }

  private func setAdaptiveCompactness(_ isCompact: Bool, animated: Bool = true) {
    guard model.isCursorMovingQuickly != isCompact else { return }
    guard animated else {
      model.isCursorMovingQuickly = isCompact
      return
    }

    let animation: Animation =
      if isCompact {
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
      } else {
        .timingCurve(0.65, 0, 0.35, 1, duration: 0.24)
      }
    withAnimation(animation) {
      model.isCursorMovingQuickly = isCompact
    }
  }

  private func positionAtCursorIfNeeded() {
    guard currentOrigin == nil else { return }
    positionAtCursor()
  }

  private func positionAtCursor() {
    let origin = targetOriginForCursor()
    currentOrigin = origin
    currentVelocity = .zero
    lastAnimationTimestamp = nil
    panel?.setFrameOrigin(origin)
  }

  private var supportsAdaptiveCompactness: Bool {
    guard
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      model.overlayStatus == nil,
      model.overlayHint == nil
    else { return false }
    switch model.state {
    case .recording, .processing:
      return true
    case .idle, .error:
      return false
    }
  }

  private func supportsAdaptiveCompactness(_ snapshot: OverlaySnapshot) -> Bool {
    guard
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      snapshot.status == nil,
      snapshot.hint == nil
    else { return false }
    switch snapshot.state {
    case .recording, .processing:
      return true
    case .idle, .error:
      return false
    }
  }

  private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
  }

  private func targetOriginForCursor() -> NSPoint {
    let mouseLocation = NSEvent.mouseLocation
    let screen = screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    return OverlayPlacement.initialOrigin(
      cursor: mouseLocation,
      size: canvasSize,
      visibleFrame: screen.visibleFrame,
      offset: panelOffset,
      edgePadding: edgePadding
    )
  }

  private func screen(containing point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
  }
}
