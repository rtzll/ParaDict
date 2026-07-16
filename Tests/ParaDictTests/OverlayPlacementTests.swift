import AppKit
import Testing

@testable import ParaDict

struct OverlayPlacementTests {
  private let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
  private let offset = NSPoint(x: 20, y: 26)

  @Test func initialPlacementUsesTheCursorAsAStableAnchor() {
    let origin = OverlayPlacement.initialOrigin(
      cursor: NSPoint(x: 100, y: 100),
      size: NSSize(width: 340, height: 124),
      visibleFrame: visibleFrame,
      offset: offset,
      edgePadding: 10
    )

    #expect(origin == NSPoint(x: 120, y: 126))
  }

  @Test func initialPlacementStaysInsideTheVisibleScreen() {
    let origin = OverlayPlacement.initialOrigin(
      cursor: NSPoint(x: 900, y: 750),
      size: NSSize(width: 340, height: 124),
      visibleFrame: visibleFrame,
      offset: offset,
      edgePadding: 10
    )

    #expect(origin == NSPoint(x: 650, y: 666))
  }

  @Test func resizingKeepsTheExistingAnchorWhenItStillFits() {
    let origin = OverlayPlacement.clampedOrigin(
      NSPoint(x: 120, y: 126),
      size: NSSize(width: 340, height: 124),
      visibleFrame: visibleFrame,
      edgePadding: 10
    )

    #expect(origin == NSPoint(x: 120, y: 126))
  }

  @Test func resizingReclampsOnlyAsMuchAsTheScreenEdgeRequires() {
    let origin = OverlayPlacement.clampedOrigin(
      NSPoint(x: 820, y: 720),
      size: NSSize(width: 340, height: 124),
      visibleFrame: visibleFrame,
      edgePadding: 10
    )

    #expect(origin == NSPoint(x: 650, y: 666))
  }

  @Test func cursorFollowingPreservesVelocityWhileSettlingTowardTheCursor() {
    let step = OverlayPlacement.criticallyDampedSpringStep(
      current: NSPoint(x: 100, y: 200),
      target: NSPoint(x: 200, y: 300),
      velocity: .zero,
      response: 0.28,
      elapsed: 1.0 / 60.0
    )

    #expect(step.origin.x > 100 && step.origin.x < 200)
    #expect(step.origin.y > 200 && step.origin.y < 300)
    #expect(step.velocity.dx > 0)
    #expect(step.velocity.dy > 0)
  }
}
