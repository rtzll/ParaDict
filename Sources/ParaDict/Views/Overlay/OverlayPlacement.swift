import AppKit

enum OverlayPlacement {
  struct SpringStep {
    let origin: NSPoint
    let velocity: CGVector
  }

  static func criticallyDampedSpringStep(
    current: NSPoint,
    target: NSPoint,
    velocity: CGVector,
    response: TimeInterval,
    elapsed: TimeInterval
  ) -> SpringStep {
    let angularFrequency = 2 * Double.pi / max(response, 0.001)
    let deltaTime = max(elapsed, 0)
    let decay = exp(-angularFrequency * deltaTime)

    func updatedAxis(position: CGFloat, target: CGFloat, velocity: CGFloat) -> (
      position: CGFloat,
      velocity: CGFloat
    ) {
      let displacement = Double(position - target)
      let initialVelocity = Double(velocity)
      let coefficient = initialVelocity + angularFrequency * displacement
      let nextDisplacement =
        (displacement + coefficient * deltaTime) * decay
      let nextVelocity =
        (initialVelocity - angularFrequency * coefficient * deltaTime) * decay
      return (
        position: target + CGFloat(nextDisplacement),
        velocity: CGFloat(nextVelocity)
      )
    }

    let x = updatedAxis(position: current.x, target: target.x, velocity: velocity.dx)
    let y = updatedAxis(position: current.y, target: target.y, velocity: velocity.dy)
    return SpringStep(
      origin: NSPoint(x: x.position, y: y.position),
      velocity: CGVector(dx: x.velocity, dy: y.velocity)
    )
  }

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
