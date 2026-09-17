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
    private var isGlowing = false
    private var glowColor: SKColor = .clear

    /// Set only when `advance(..., halvedGrowth: true)` is in play. Alternates
    /// false/true each fruit eaten -- true means "this fruit's growth is
    /// deferred to the next one" (see `advance`). Purely a growth-cadence
    /// flag; the segment it corresponds to isn't tracked separately (see
    /// `growthIndicatorNode` for why that's deliberate).
    private var pendingGrowth = false
    private var growthIndicatorNode: SKShapeNode?

    /// Tracks consecutive same-direction turns (left/left/left or
    /// right/right/right) across separate grid ticks. Two in a row is a
    /// legitimate fast U-turn onto a perpendicular row/column; a third
    /// traces a tight enough hook to loop back into the snake's own body a
    /// few segments back, well past where the immediate-180 guard in
    /// `turn(to:)` can catch it (that guard only ever compares against the
    /// single most-recently-committed direction). See `advance`.
    private enum TurnSense { case left, right }
    private var lastTurnSense: TurnSense?
    private var sameSenseStreak = 0

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

    private static let clockwiseOrder: [Direction] = [.up, .right, .down, .left]

    /// nil for going straight, or for a direct reversal (which `turn(to:)`
    /// already prevents from ever reaching here as `requested`).
    private static func turnSense(from: Direction, to: Direction) -> TurnSense? {
        guard let fromIndex = clockwiseOrder.firstIndex(of: from), let toIndex = clockwiseOrder.firstIndex(of: to) else {
            return nil
        }
        switch (toIndex - fromIndex + 4) % 4 {
        case 1: return .right
        case 3: return .left
        default: return nil
        }
    }

    /// The actual fix for issue #7: a turn request is only honored if it
    /// isn't the *third* consecutive turn in the same rotational sense.
    /// Two lefts (or two rights) in a row stays fast and unrestricted --
    /// that's a legitimate quick U-turn -- but a third gets dropped and the
    /// snake just continues in its current direction that tick, rather
    /// than tracing a hook tight enough to loop back into its own body.
    private static func resolveNextDirection(
        current: Direction,
        requested: Direction,
        lastTurnSense: inout TurnSense?,
        sameSenseStreak: inout Int
    ) -> Direction {
        guard let sense = turnSense(from: current, to: requested) else {
            lastTurnSense = nil
            sameSenseStreak = 0
            return requested == current ? requested : current
        }

        if sense == lastTurnSense && sameSenseStreak >= 2 {
            return current
        }

        if sense == lastTurnSense {
            sameSenseStreak += 1
        } else {
            lastTurnSense = sense
            sameSenseStreak = 1
        }
        return requested
    }

    /// Repositions the snake to a fresh horizontal line at `head`, keeping
    /// its current length -- used between levels so a run's progress (and
    /// score) carries over, but a stale position can't land inside a
    /// freshly-loaded level's walls.
    func recenter(at head: GridPoint, direction: Direction) {
        self.direction = direction
        self.pendingDirection = direction
        segments = Snake.horizontalSegments(head: head, length: segments.count)
        pendingGrowth = false
        lastTurnSense = nil
        sameSenseStreak = 0
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

    /// Removes exactly one tail segment, never going below the snake's own
    /// starting length. Returns whether it actually happened -- the driver
    /// of a multi-pop sequence can stop once this starts returning false.
    @discardableResult
    private func popTailSegment() -> Bool {
        guard segments.count > minimumLength else { return false }
        segments.removeLast()
        syncNodes()
        return true
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

    private func setGlowing(_ glowing: Bool, color: SKColor = .clear) {
        isGlowing = glowing
        glowColor = glowing ? color : .clear
        syncNodes()
    }

    // MARK: - Power-up visual effects
    //
    // These are purely cosmetic timelines run via SKAction on `container`
    // (a convenient always-in-the-scene node -- nothing about the action
    // sequence actually depends on it visually). Each cancels anything
    // already in flight first, since collecting a second power-up mid
    // effect should restart cleanly rather than layering animations.

    /// A brief color flash with no other effect -- speed-cooler's whole
    /// effect, and tail-cutter's fallback when there's no tail to spare.
    func flashBodyColor(_ color: SKColor, duration: TimeInterval) {
        container.removeAllActions()
        container.run(.sequence([
            .run { [weak self] in self?.setBodyColor(color) },
            .wait(forDuration: duration),
            .run { [weak self] in self?.resetBodyColor() }
        ]))
    }

    /// Flashes to `color` and pops one tail segment per flash, up to
    /// `maxPops` times, stopping early once the snake reaches its minimum
    /// length. If already at minimum, just flashes once with nothing to
    /// pop (see `flashBodyColor`).
    func playTailCutterEffect(color: SKColor, maxPops: Int, flashInterval: TimeInterval, fallbackFlashDuration: TimeInterval) {
        guard segments.count > minimumLength else {
            flashBodyColor(color, duration: fallbackFlashDuration)
            return
        }

        container.removeAllActions()
        var steps: [SKAction] = []
        for _ in 0..<maxPops {
            steps.append(contentsOf: [
                .run { [weak self] in self?.setBodyColor(color) },
                .wait(forDuration: flashInterval),
                .run { [weak self] in
                    self?.popTailSegment()
                    self?.resetBodyColor()
                },
                .wait(forDuration: flashInterval)
            ])
        }
        container.run(.sequence(steps))
    }

    /// Bomb-eater's full visual lifecycle: solid `color`, a couple of
    /// warning flashes near the end, then a steady glow through a final
    /// grace window, then back to normal. Purely cosmetic -- GameManager
    /// tracks the matching gameplay timer (immunity) separately, sized to
    /// the same total duration, so what's shown and what's actually safe
    /// stay in step.
    func playBombEaterEffect(
        color: SKColor,
        mainDuration: TimeInterval,
        warningFlashes: Int,
        warningFlashInterval: TimeInterval,
        graceDuration: TimeInterval
    ) {
        container.removeAllActions()

        let warningWindow = TimeInterval(warningFlashes) * warningFlashInterval * 2
        let solidDuration = max(0, mainDuration - warningWindow)

        var steps: [SKAction] = [
            .run { [weak self] in self?.setBodyColor(color) },
            .wait(forDuration: solidDuration)
        ]
        for _ in 0..<warningFlashes {
            steps.append(contentsOf: [
                .run { [weak self] in self?.resetBodyColor() },
                .wait(forDuration: warningFlashInterval),
                .run { [weak self] in self?.setBodyColor(color) },
                .wait(forDuration: warningFlashInterval)
            ])
        }
        steps.append(contentsOf: [
            .run { [weak self] in self?.setGlowing(true, color: color) },
            .wait(forDuration: graceDuration),
            .run { [weak self] in
                self?.setGlowing(false)
                self?.resetBodyColor()
            }
        ])

        container.run(.sequence(steps))
    }

    /// `halvedGrowth`: when true (Levels mode), only every *other* fruit
    /// actually lengthens the snake -- the in-between fruit still removes
    /// the tail (net zero growth) but flips `pendingGrowth` on, which shows
    /// a small non-collidable indicator at the tail (see `syncNodes`) as a
    /// preview of the growth to come. When false (free play), unchanged:
    /// every fruit grows the snake by one segment.
    func advance(columns: Int, rows: Int, foodPosition: GridPoint, halvedGrowth: Bool) -> SnakeAdvanceResult {
        direction = Snake.resolveNextDirection(
            current: direction,
            requested: pendingDirection,
            lastTurnSense: &lastTurnSense,
            sameSenseStreak: &sameSenseStreak
        )
        pendingDirection = direction

        let vector = direction.vector
        var newHead = GridPoint(x: head.x + vector.dx, y: head.y + vector.dy)
        newHead.x = (newHead.x + columns) % columns
        newHead.y = (newHead.y + rows) % rows

        if segments.contains(newHead) {
            return .collided
        }

        segments.insert(newHead, at: 0)

        guard newHead == foodPosition else {
            segments.removeLast()
            syncNodes()
            return .moved
        }

        let shouldGrow: Bool
        if halvedGrowth {
            shouldGrow = pendingGrowth
            pendingGrowth.toggle()
        } else {
            shouldGrow = true
        }
        if !shouldGrow {
            segments.removeLast()
        }

        syncNodes()
        return .ateFood
    }

    /// Reuses existing nodes and only repositions them; nodes are created or
    /// removed solely when the segment count itself changes.
    private func syncNodes() {
        while segmentNodes.count < segments.count {
            let node = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: cellSize - 2), cornerRadius: 4)
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
            node.strokeColor = isGlowing ? glowColor : .clear
            node.glowWidth = isGlowing ? 5 : 0
        }

        syncGrowthIndicator()
    }

    /// Purely cosmetic preview of a deferred (halved-growth) fruit: a small
    /// circle just past the tail, extrapolated from the last two segments
    /// so it trails naturally as the snake moves. Never part of `segments`,
    /// never checked for collision -- this is deliberately *not* a real
    /// cell, to avoid needing any half-collidable-cell logic in `advance`.
    private func syncGrowthIndicator() {
        guard pendingGrowth, segments.count >= 2 else {
            growthIndicatorNode?.isHidden = true
            return
        }

        let tail = segments[segments.count - 1]
        let beforeTail = segments[segments.count - 2]
        let trailingPoint = GridPoint(x: tail.x + (tail.x - beforeTail.x), y: tail.y + (tail.y - beforeTail.y))

        let node = growthIndicatorNode ?? {
            let node = SKShapeNode(circleOfRadius: (cellSize - 2) / 2 * 0.55)
            node.strokeColor = .clear
            container.addChild(node)
            growthIndicatorNode = node
            return node
        }()
        node.isHidden = false
        node.position = GridGeometry.position(for: trailingPoint, cellSize: cellSize, origin: origin)
        node.fillColor = bodyColor.withAlphaComponent(0.45)
    }
}
