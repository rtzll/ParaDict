import AppKit

enum OverlayPlacement {
  static func initialOrigin(
    cursor: NSPoint,
    size: NSSize,
    visibleFrame: NSRect,
    offset: NSPoint,
    edgePadding: CGFloat
  ) -> NSPoint {
    clampedOrigin(
      NSPoint(x: cursor.x + offset.x, y: cursor.y + offset.y),
      size: size,
      visibleFrame: visibleFrame,
      edgePadding: edgePadding
    )
  }

  static func clampedOrigin(
    _ origin: NSPoint,
    size: NSSize,
    visibleFrame: NSRect,
    edgePadding: CGFloat
  ) -> NSPoint {
    let availableFrame = visibleFrame.insetBy(dx: edgePadding, dy: edgePadding)
    let maximumX = max(availableFrame.minX, availableFrame.maxX - size.width)
    let maximumY = max(availableFrame.minY, availableFrame.maxY - size.height)

    return NSPoint(
      x: min(max(origin.x, availableFrame.minX), maximumX),
      y: min(max(origin.y, availableFrame.minY), maximumY)
    )
  }
}
