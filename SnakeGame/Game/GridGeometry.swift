import CoreGraphics

/// Shared math for converting a grid cell into an on-screen point, so `Snake`
/// and `Food` don't each duplicate it.
enum GridGeometry {
    static func position(for point: GridPoint, cellSize: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(point.x) * cellSize + cellSize / 2,
            y: origin.y + CGFloat(point.y) * cellSize + cellSize / 2
        )
    }
}
