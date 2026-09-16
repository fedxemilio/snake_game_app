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

    /// Picks a random cell that isn't in `occupied` — shared by anything
    /// that spawns onto the grid (Food, PowerUp).
    static func randomPosition(columns: Int, rows: Int, avoiding occupied: [GridPoint]) -> GridPoint {
        var candidate: GridPoint
        repeat {
            candidate = GridPoint(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
        } while occupied.contains(candidate)
        return candidate
    }
}
