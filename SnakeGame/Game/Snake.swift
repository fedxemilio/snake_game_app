import SpriteKit

enum SnakeAdvanceResult {
    case moved
    case ateFood
    case collided
}

/// Owns the snake's own state (segments, direction) and its own on-screen
/// nodes. Doesn't know anything about score or the game-over flow — the
/// caller (GameManager) reacts to the result of `advance`.
final class Snake {
    private(set) var segments: [GridPoint]
    private(set) var direction: Direction
    private var pendingDirection: Direction

    private let container = SKNode()
    private var segmentNodes: [SKShapeNode] = []
    private let cellSize: CGFloat
    private let origin: CGPoint
    private let minimumLength: Int

    private static let defaultBodyColor: SKColor = .systemGreen
    private var bodyColor: SKColor = defaultBodyColor

    var head: GridPoint { segments[0] }

    init(startingAt head: GridPoint, length: Int, direction: Direction, cellSize: CGFloat, origin: CGPoint) {
        self.direction = direction
        self.pendingDirection = direction
        self.cellSize = cellSize
        self.origin = origin
        self.minimumLength = length
        self.segments = Snake.horizontalSegments(head: head, length: length)
    }

    private static func horizontalSegments(head: GridPoint, length: Int) -> [GridPoint] {
        (0..<length).map { GridPoint(x: head.x - $0, y: head.y) }
    }

    /// Repositions the snake to a fresh horizontal line at `head`, keeping
    /// its current length -- used between levels so a run's progress (and
    /// score) carries over, but a stale position can't land inside a
    /// freshly-loaded level's walls.
    func recenter(at head: GridPoint, direction: Direction) {
        self.direction = direction
        self.pendingDirection = direction
        segments = Snake.horizontalSegments(head: head, length: segments.count)
        syncNodes()
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
        syncNodes()
    }

    func removeFromScene() {
        container.removeFromParent()
    }

    func turn(to newDirection: Direction) {
        guard newDirection != direction.opposite else { return }
        pendingDirection = newDirection
    }

    /// Shrinks the tail by up to `amount`, never going below the snake's
    /// own starting length. A no-op once already at that floor.
    func cutTail(by amount: Int) {
        let targetCount = max(minimumLength, segments.count - amount)
        guard targetCount < segments.count else { return }
        segments.removeLast(segments.count - targetCount)
        syncNodes()
    }

    /// Tints the whole snake (e.g. while a timed power-up is active).
    /// `resetBodyColor()` returns it to normal.
    func setBodyColor(_ color: SKColor) {
        bodyColor = color
        syncNodes()
    }

    func resetBodyColor() {
        bodyColor = Snake.defaultBodyColor
        syncNodes()
    }

    func advance(columns: Int, rows: Int, foodPosition: GridPoint) -> SnakeAdvanceResult {
        direction = pendingDirection

        let vector = direction.vector
        var newHead = GridPoint(x: head.x + vector.dx, y: head.y + vector.dy)
        newHead.x = (newHead.x + columns) % columns
        newHead.y = (newHead.y + rows) % rows

        if segments.contains(newHead) {
            return .collided
        }

        segments.insert(newHead, at: 0)

        let result: SnakeAdvanceResult
        if newHead == foodPosition {
            result = .ateFood
        } else {
            segments.removeLast()
            result = .moved
        }

        syncNodes()
        return result
    }

    /// Reuses existing nodes and only repositions them; nodes are created or
    /// removed solely when the segment count itself changes.
    private func syncNodes() {
        while segmentNodes.count < segments.count {
            let node = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: cellSize - 2), cornerRadius: 4)
            node.strokeColor = .clear
            container.addChild(node)
            segmentNodes.append(node)
        }
        while segmentNodes.count > segments.count {
            segmentNodes.removeLast().removeFromParent()
        }

        for (index, point) in segments.enumerated() {
            let node = segmentNodes[index]
            node.position = GridGeometry.position(for: point, cellSize: cellSize, origin: origin)
            node.fillColor = index == 0 ? bodyColor : bodyColor.withAlphaComponent(0.7)
        }
    }
}
