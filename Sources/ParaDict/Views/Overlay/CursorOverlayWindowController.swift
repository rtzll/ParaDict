import AppKit
import SwiftUI

@MainActor
private enum OverlayCanvas {
  static let margin: CGFloat = 120
  static let overlaySize = RecordingOverlayView.expandedSize
  static let canvasSize = CGSize(
    width: overlaySize.width + margin * 2,
    height: overlaySize.height + margin * 2
  )
  static let overlayFrame = CGRect(
    x: margin,
    y: margin,
    width: overlaySize.width,
    height: overlaySize.height
  )
}

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
  var isPresented = false
  var tetherAnchor = CGPoint.zero
  var tetherEndpoint = CGPoint.zero
  var tetherStrength: CGFloat = 0
}

private struct CursorTetherView: View {
  let anchor: CGPoint
  let endpoint: CGPoint
  let strength: CGFloat

  var body: some View {
    Canvas { context, _ in
      guard strength > 0.001 else { return }

      let delta = CGVector(dx: endpoint.x - anchor.x, dy: endpoint.y - anchor.y)
      let rawLength = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
      guard rawLength > 1 else { return }

      let unit = CGVector(dx: delta.dx / rawLength, dy: delta.dy / rawLength)
      let nominalLength: CGFloat = 33
      let overshoot = max(0, rawLength - nominalLength)
      let resistedOvershoot = (overshoot * 72 * 0.55) / (72 + 0.55 * overshoot)
      let visibleLength = min(rawLength, nominalLength + resistedOvershoot)
      let visibleEndpoint = CGPoint(
        x: anchor.x + unit.dx * visibleLength,
        y: anchor.y + unit.dy * visibleLength
      )
      let midpoint = CGPoint(
        x: (anchor.x + visibleEndpoint.x) / 2,
        y: (anchor.y + visibleEndpoint.y) / 2
      )
      let bend = min(4, visibleLength * 0.05) * strength
      let control = CGPoint(
        x: midpoint.x - unit.dy * bend,
        y: midpoint.y + unit.dx * bend
      )

      var path = Path()
      path.move(to: anchor)
      path.addQuadCurve(to: visibleEndpoint, control: control)

      let opacity = Double(strength) * 0.26
      context.stroke(
        path,
        with: .linearGradient(
          Gradient(colors: [
            Color.white.opacity(opacity),
            Color.white.opacity(opacity * 0.12),
          ]),
          startPoint: anchor,
          endPoint: visibleEndpoint
        ),
        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
      )
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct OverlayHost: View {
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  let model: RecordingOverlayModel

  var body: some View {
    ZStack(alignment: .topLeading) {
      CursorTetherView(
        anchor: model.tetherAnchor,
        endpoint: model.tetherEndpoint,
        strength: accessibilityReduceMotion ? 0 : model.tetherStrength
      )
      .frame(width: OverlayCanvas.canvasSize.width, height: OverlayCanvas.canvasSize.height)

      RecordingOverlayView(
        state: model.state,
        duration: model.duration,
        meterLevel: model.meterLevel,
        partialTranscript: model.partialTranscript,
        overlayStatus: model.overlayStatus,
        overlayHint: model.overlayHint,
        isCursorMovingQuickly: model.isCursorMovingQuickly
      )
      .scaleEffect(
        accessibilityReduceMotion || model.isPresented ? 1 : 0.86,
        anchor: .bottomLeading
      )
      .blur(radius: accessibilityReduceMotion || model.isPresented ? 0 : 7)
      .opacity(model.isPresented ? 1 : 0)
      .offset(
        x: accessibilityReduceMotion || model.isPresented ? 0 : -12,
        y: accessibilityReduceMotion || model.isPresented ? 0 : 14
      )
      .frame(
        width: OverlayCanvas.overlaySize.width,
        height: OverlayCanvas.overlaySize.height,
        alignment: .bottomLeading
      )
      .offset(x: OverlayCanvas.margin, y: OverlayCanvas.margin)
    }
    .frame(width: OverlayCanvas.canvasSize.width, height: OverlayCanvas.canvasSize.height)
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
  private let dismissalDelay: Duration = .milliseconds(180)

  private let model = RecordingOverlayModel()
  private var panel: OverlayPanel?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var animationTimer: Timer?
  private var cursorSettleTask: Task<Void, Never>?
  private var visibilityTask: Task<Void, Never>?
  private var lastCursorSample: CursorSample?
  private var lastAnimationTimestamp: TimeInterval?
  private var currentVelocity = CGVector.zero
  private var currentOrigin: NSPoint?
  private let canvasSize = NSSize(
    width: OverlayCanvas.canvasSize.width,
    height: OverlayCanvas.canvasSize.height
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
    visibilityTask?.cancel()
    visibilityTask = nil

    guard let panel, panel.isVisible else {
      model.isPresented = false
      currentOrigin = nil
      return
    }
    guard model.isPresented else {
      finishHiding()
      return
    }

    withAnimation(dismissalAnimation) {
      model.isPresented = false
    }
    visibilityTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: self?.dismissalDelay ?? .milliseconds(180))
      guard !Task.isCancelled else { return }
      self?.finishHiding()
    }
  }

  private func show() {
    if panel == nil {
      createPanel()
    }

    guard let panel else { return }
    visibilityTask?.cancel()
    visibilityTask = nil
    positionAtCursorIfNeeded()
    if !panel.isVisible {
      model.isPresented = false
      panel.alphaValue = 1
      panel.orderFrontRegardless()
      visibilityTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard let self, !Task.isCancelled, panel.isVisible else { return }
        withAnimation(self.presentationAnimation) {
          self.model.isPresented = true
        }
        self.visibilityTask = nil
      }
    } else if !model.isPresented {
      withAnimation(presentationAnimation) {
        model.isPresented = true
      }
    }

    startFollowingCursor()
  }

  private var presentationAnimation: Animation {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      return .easeOut(duration: 0.12)
    }
    return .timingCurve(0.16, 1, 0.3, 1, duration: 0.24)
  }

  private var dismissalAnimation: Animation {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      return .easeIn(duration: 0.1)
    }
    return .timingCurve(0.7, 0, 0.84, 0, duration: 0.16)
  }

  private func finishHiding() {
    panel?.orderOut(nil)
    currentOrigin = nil
    visibilityTask = nil
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
    setTetherHidden()
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
    updateTether(
      panelOrigin: step.origin,
      cursor: NSEvent.mouseLocation,
      lag: remainingDistance
    )
    let speed = sqrt(
      step.velocity.dx * step.velocity.dx + step.velocity.dy * step.velocity.dy
    )
    if remainingDistance < snapThreshold, speed < snapVelocityThreshold {
      currentOrigin = target
      currentVelocity = .zero
      panel.setFrameOrigin(target)
      setTetherHidden()
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
    setTetherHidden()
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

  private func updateTether(
    panelOrigin: NSPoint,
    cursor: NSPoint,
    lag: CGFloat
  ) {
    guard supportsTether else {
      setTetherHidden()
      return
    }

    let strength = min(max((lag - 5) / 48, 0), 1)
    guard strength > 0 else {
      setTetherHidden()
      return
    }

    let rawEndpoint = CGPoint(
      x: cursor.x - panelOrigin.x,
      y: canvasSize.height - (cursor.y - panelOrigin.y)
    )
    guard !OverlayCanvas.overlayFrame.contains(rawEndpoint) else {
      setTetherHidden()
      return
    }

    let endpoint = CGPoint(
      x: min(max(rawEndpoint.x, 2), canvasSize.width - 2),
      y: min(max(rawEndpoint.y, 2), canvasSize.height - 2)
    )
    let anchor = CGPoint(
      x: min(max(rawEndpoint.x, OverlayCanvas.overlayFrame.minX), OverlayCanvas.overlayFrame.maxX),
      y: min(max(rawEndpoint.y, OverlayCanvas.overlayFrame.minY), OverlayCanvas.overlayFrame.maxY)
    )

    model.tetherAnchor = anchor
    model.tetherEndpoint = endpoint
    model.tetherStrength = strength
  }

  private func setTetherHidden() {
    guard model.tetherStrength != 0 else { return }
    model.tetherStrength = 0
  }

  private var supportsTether: Bool {
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

  private func targetOriginForCursor() -> NSPoint {
    let mouseLocation = NSEvent.mouseLocation
    let screen = screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens[0]
    let overlayOrigin = OverlayPlacement.initialOrigin(
      cursor: mouseLocation,
      size: NSSize(
        width: OverlayCanvas.overlaySize.width,
        height: OverlayCanvas.overlaySize.height
      ),
      visibleFrame: screen.visibleFrame,
      offset: panelOffset,
      edgePadding: edgePadding
    )
    return NSPoint(
      x: overlayOrigin.x - OverlayCanvas.margin,
      y: overlayOrigin.y - OverlayCanvas.margin
    )
  }

  private func screen(containing point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
  }
}
