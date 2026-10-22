import SpriteKit

enum SnakeAdvanceResult: Equatable {
    case moved
    case ateFood
    /// The next cell (`at`) is a barrier (the snake's own body, or anything the
    /// caller's `isBlocked` says): the snake stays where it is this tick.
    case blocked(at: GridPoint)
}

/// Owns the snake's own state (segments, direction) and its own on-screen
/// nodes. Doesn't know anything about score or the game-over flow — the
/// caller (GameManager) reacts to the result of `advance`.
final class Snake {
    private(set) var segments: [GridPoint]
    private(set) var direction: Direction
    private var pendingDirection: Direction

    private let container = SKNode()
    /// Segment 0's sprite: it has a face and turns to point the way the snake is going.
    private let headNode: SegmentSprite
    /// Sprites for segments 1..., reused tick to tick (see `syncNodes`).
    private var bodyNodes: [SegmentSprite] = []
    private let cellSize: CGFloat
    private let origin: CGPoint
    private let minimumLength: Int

    /// Set while a power-up tints the whole snake; nil for its natural colors.
    private var tint: SKColor?
    private var isGlowing = false
    private var glowColor: SKColor = .clear

    /// Set only when `advance(..., halvedGrowth: true)` is in play. Alternates
    /// false/true each fruit eaten -- true means "this fruit's growth is
    /// deferred to the next one" (see `advance`). Purely a growth-cadence
    /// flag; the segment it corresponds to isn't tracked separately (see
    /// `growthIndicatorNode` for why that's deliberate).
    private var pendingGrowth = false
    /// Segments still to grow: each move that owes one keeps its tail instead of
    /// dropping it.
    private var growthOwed = 0
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

        headNode = SegmentSprite(texture: SpriteArt.snakeHead(cellSize: cellSize), auraTexture: SpriteArt.snakeAura(cellSize: cellSize))
        headNode.zPosition = 2
        let face = SKSpriteNode(texture: SpriteArt.snakeFace(cellSize: cellSize))
        face.zPosition = 0.5
        headNode.addChild(face)
        container.addChild(headNode)
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
        tint = color
        syncNodes()
    }

    func resetBodyColor() {
        tint = nil
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

    /// Cancels whatever power-up visual sequence is currently running, and
    /// clears glow state directly rather than leaving that to the cancelled
    /// sequence's own cleanup step -- that step (bomb-eater's final
    /// `setGlowing(false)`) is exactly what just got cancelled, so relying
    /// on it would leave the snake glowing in a color no longer tied to any
    /// active effect (e.g. collecting speed-cooler during bomb-eater's grace
    /// glow used to leave that glow stuck on permanently).
    private func cancelInFlightEffect() {
        container.removeAction(forKey: Snake.effectActionKey)
        isGlowing = false
        glowColor = .clear
    }

    /// Power-up effects, the hit blink and the hit/death shudder run on
    /// `container` under separate keys, so starting one never cancels another.
    private static let effectActionKey = "powerUpEffect"
    private static let blinkActionKey = "hitBlink"
    private static let shudderActionKey = "shudder"
    private static let hurtColor = SKColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)

    private var allSegmentNodes: [SegmentSprite] { [headNode] + bodyNodes }

    /// The moment of a non-fatal hit: every segment flashes red and the snake
    /// shudders. The grace-period blink (`playHitBlink`) runs alongside.
    func playHitImpact() {
        for node in allSegmentNodes {
            node.flash(color: Snake.hurtColor, alpha: 0.9, duration: 0.4)
        }
        container.run(Snake.shudder(strength: cellSize * 0.14, beats: 4), withKey: Snake.shudderActionKey)
    }

    /// The end of a run: a hard convulsion and a white-hot flash, then the snake
    /// comes apart head to tail, each segment bursting into bubbles. Calls
    /// `completion` once it's gone (about 1.3 s), which is when the Game Over
    /// overlay should appear.
    func playDeath(completion: @escaping () -> Void) {
        cancelInFlightEffect()
        container.removeAction(forKey: Snake.blinkActionKey)
        container.alpha = 1

        let nodes = allSegmentNodes
        for node in nodes {
            node.flash(color: .white, alpha: 1, duration: 0.45)
        }
        container.run(Snake.shudder(strength: cellSize * 0.22, beats: 7), withKey: Snake.shudderActionKey)

        let start: TimeInterval = 0.4
        let stagger = min(0.05, 0.7 / Double(nodes.count))
        let parent = container.parent ?? container
        for (index, node) in nodes.enumerated() {
            node.run(.sequence([
                .wait(forDuration: start + Double(index) * stagger),
                .run { [weak self, weak node] in
                    guard let self, let node else { return }
                    let point = self.container.convert(node.position, to: parent)
                    BoardEffects.bubbleBurst(at: point, count: 4, cellSize: self.cellSize, in: parent)
                },
                .group([.scale(to: 0.15, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            ]))
        }
        growthIndicatorNode?.run(.fadeOut(withDuration: 0.3))

        let total = start + Double(nodes.count) * stagger + 0.6
        container.run(.sequence([.wait(forDuration: total), .run(completion)]))
    }

    /// A side-to-side jolt of `container`, dying away over `beats` steps and
    /// ending back where it started.
    private static func shudder(strength: CGFloat, beats: Int) -> SKAction {
        var steps: [SKAction] = []
        for beat in 0..<beats {
            let falloff = 1 - CGFloat(beat) / CGFloat(beats)
            let side: CGFloat = beat.isMultiple(of: 2) ? 1 : -1
            steps.append(.move(to: CGPoint(x: side * strength * falloff, y: 0), duration: 0.035))
        }
        steps.append(.move(to: .zero, duration: 0.035))
        return .sequence(steps)
    }

    /// Blinks the whole snake for `duration`: the grace period after losing a
    /// life, when it can't be hurt again. Purely cosmetic -- GameManager tracks
    /// the matching invincibility itself, sized to the same duration. Restarts
    /// if it's already blinking.
    func playHitBlink(duration: TimeInterval) {
        let interval: TimeInterval = 0.1
        let blink = SKAction.sequence([
            .fadeAlpha(to: 0.25, duration: 0),
            .wait(forDuration: interval),
            .fadeAlpha(to: 1, duration: 0),
            .wait(forDuration: interval),
        ])
        let count = max(1, Int(duration / (interval * 2)))
        container.run(.sequence([.repeat(blink, count: count), .fadeAlpha(to: 1, duration: 0)]), withKey: Snake.blinkActionKey)
    }

    /// A brief color flash with no other effect -- speed-cooler's whole
    /// effect, and tail-cutter's fallback when there's no tail to spare.
    func flashBodyColor(_ color: SKColor, duration: TimeInterval) {
        cancelInFlightEffect()
        container.run(.sequence([
            .run { [weak self] in self?.setBodyColor(color) },
            .wait(forDuration: duration),
            .run { [weak self] in self?.resetBodyColor() }
        ]), withKey: Snake.effectActionKey)
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

        cancelInFlightEffect()
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
        container.run(.sequence(steps), withKey: Snake.effectActionKey)
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
        cancelInFlightEffect()

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

        container.run(.sequence(steps), withKey: Snake.effectActionKey)
    }

    /// `halvedGrowth`: when true (Levels mode), only every *other* fruit
    /// actually lengthens the snake -- the in-between fruit still removes
    /// the tail (net zero growth) but flips `pendingGrowth` on, which shows
    /// a small non-collidable indicator at the tail (see `syncNodes`) as a
    /// preview of the growth to come. When false (free play), unchanged:
    /// every fruit grows the snake by one segment.
    ///
    /// `isBlocked` is asked about the next cell before moving into it: walls
    /// and the like are barriers the snake stops against rather than enters
    /// (`.blocked`), the same as its own body. Snake still doesn't know what
    /// any of them are -- the caller decides, and what a bump costs.
    func advance(
        columns: Int,
        rows: Int,
        foodPosition: GridPoint,
        halvedGrowth: Bool,
        isBlocked: (GridPoint) -> Bool
    ) -> SnakeAdvanceResult {
        func isBarrier(_ point: GridPoint) -> Bool {
            segments.contains(point) || isBlocked(point)
        }
        func step(toward heading: Direction) -> GridPoint {
            let vector = heading.vector
            return GridPoint(
                x: (head.x + vector.dx + columns) % columns,
                y: (head.y + vector.dy + rows) % rows
            )
        }

        // Worked out on copies and committed only if the snake actually moves: a
        // turn that goes nowhere (blocked) doesn't count toward the same-way
        // streak, and the snake keeps facing the way it last moved, so turning
        // back the way it came is still judged against its real neck. The
        // requested turn stays pending until the player changes it.
        var turnSense = lastTurnSense
        var streak = sameSenseStreak
        var next = Snake.resolveNextDirection(
            current: direction,
            requested: pendingDirection,
            lastTurnSense: &turnSense,
            sameSenseStreak: &streak
        )
        var newHead = step(toward: next)

        // The streak rule dropped the requested turn, but straight ahead is
        // blocked. The rule is there to stop accidental hooks back into the
        // body, not to hold the snake against a wall, so take the turn after all
        // if it's open (it can be, for a snake at its minimum length).
        if next != pendingDirection && isBarrier(newHead) {
            let turned = step(toward: pendingDirection)
            if !isBarrier(turned) {
                next = pendingDirection
                newHead = turned
                streak += 1
            }
        }

        guard !isBarrier(newHead) else { return .blocked(at: newHead) }

        direction = next
        pendingDirection = next
        lastTurnSense = turnSense
        sameSenseStreak = streak

        segments.insert(newHead, at: 0)

        let ate = newHead == foodPosition
        if ate {
            countFruit(halvedGrowth: halvedGrowth)
        }
        // Growing is just not dropping the tail this move.
        if growthOwed > 0 {
            growthOwed -= 1
        } else {
            segments.removeLast()
        }

        syncNodes()
        return ate ? .ateFood : .moved
    }

    /// Fruit the snake got without eating it itself (knocked into by something it
    /// pushed): it grows on its next move exactly as if it had, halved growth and
    /// all.
    func feed(halvedGrowth: Bool) {
        countFruit(halvedGrowth: halvedGrowth)
        syncGrowthIndicator()
    }

    /// One fruit's worth of growth: a segment owed to the next move, or in Levels
    /// (`halvedGrowth`) every other fruit, with the in-between one shown as the
    /// growth indicator.
    private func countFruit(halvedGrowth: Bool) {
        let grows: Bool
        if halvedGrowth {
            grows = pendingGrowth
            pendingGrowth.toggle()
        } else {
            grows = true
        }
        if grows {
            growthOwed += 1
        }
    }

    /// Reuses existing nodes and only repositions them; nodes are created or
    /// removed solely when the segment count itself changes.
    private func syncNodes() {
        let bodyCount = segments.count - 1
        while bodyNodes.count < bodyCount {
            let node = SegmentSprite(texture: SpriteArt.snakeBody(cellSize: cellSize), auraTexture: SpriteArt.snakeAura(cellSize: cellSize))
            node.zPosition = 1
            container.addChild(node)
            bodyNodes.append(node)
        }
        while bodyNodes.count > bodyCount {
            bodyNodes.removeLast().removeFromParent()
        }

        let glow = isGlowing ? glowColor : nil
        headNode.position = GridGeometry.position(for: head, cellSize: cellSize, origin: origin)
        headNode.zRotation = Snake.angle(facing: direction)
        headNode.style(tint: tint, glow: glow)

        let bodyTexture = SpriteArt.snakeBody(cellSize: cellSize)
        let tailTexture = SpriteArt.snakeTail(cellSize: cellSize)
        // Never taper the neck: a three-long snake tapers only its tail.
        let taperCount = min(Snake.tailTaperLength, max(0, bodyCount - 1))

        for (offset, node) in bodyNodes.enumerated() {
            let index = offset + 1
            node.position = GridGeometry.position(for: segments[index], cellSize: cellSize, origin: origin)
            // Fades a little toward the tail, so the snake's length reads at a glance.
            node.alpha = 1 - 0.3 * CGFloat(index) / CGFloat(segments.count)
            node.style(tint: tint, glow: glow)

            // The last few segments narrow toward the tail, and the very last is a
            // point. Only across the body, never along it, so no gaps open up
            // between segments.
            let fromTail = bodyCount - 1 - offset
            let width = fromTail < taperCount ? 0.5 + 0.5 * CGFloat(fromTail + 1) / CGFloat(taperCount + 1) : 1
            let towardHead = Snake.step(from: segments[index], to: segments[index - 1])

            if fromTail == 0 {
                node.texture = tailTexture
                // Points away from the body; scaled across it in its own rotated frame.
                node.zRotation = atan2(CGFloat(-towardHead.dy), CGFloat(-towardHead.dx))
                node.xScale = 1
                node.yScale = width
                // Under the segment before it, which hides the tail's base.
                node.zPosition = 0.9
            } else {
                node.texture = bodyTexture
                node.zRotation = 0
                node.xScale = towardHead.dx == 0 ? width : 1
                node.yScale = towardHead.dx == 0 ? 1 : width
                node.zPosition = 1
            }
        }

        syncGrowthIndicator()
    }

    /// How many segments, counting the tail itself, narrow toward the tail tip.
    private static let tailTaperLength = 4

    /// The one-cell step from `point` to its neighbor `next`, undoing a wrap across
    /// the grid's edge (where the raw difference is the grid's width or height, not 1).
    private static func step(from point: GridPoint, to next: GridPoint) -> (dx: Int, dy: Int) {
        func unwrap(_ delta: Int) -> Int {
            abs(delta) > 1 ? (delta > 0 ? -1 : 1) : delta
        }
        return (unwrap(next.x - point.x), unwrap(next.y - point.y))
    }

    /// The head's texture faces right; this turns it to face `direction`.
    private static func angle(facing direction: Direction) -> CGFloat {
        switch direction {
        case .right: return 0
        case .up: return .pi / 2
        case .left: return .pi
        case .down: return -.pi / 2
        }
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
        node.fillColor = (tint ?? SKColor(named: "SnakeBodyStart") ?? .systemTeal).withAlphaComponent(0.45)
    }
}

/// One segment's sprite, plus a halo behind it for the bomb-eater grace glow. Tinting
/// is SpriteKit's color blend rather than a separate texture, so a power-up color can
/// wash over the gradient without any extra art.
private final class SegmentSprite: SKSpriteNode {
    private let aura: SKSpriteNode

    init(texture: SKTexture, auraTexture: SKTexture) {
        aura = SKSpriteNode(texture: auraTexture)
        super.init(texture: texture, color: .white, size: texture.size())
        aura.zPosition = -1
        aura.blendMode = .add
        aura.colorBlendFactor = 1
        aura.isHidden = true
        addChild(aura)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func style(tint: SKColor?, glow: SKColor?) {
        color = tint ?? .white
        colorBlendFactor = tint == nil ? 0 : 0.7
        aura.isHidden = glow == nil
        if let glow {
            aura.color = glow
        }
    }

    /// A brief wash of `color` over the segment (and its glow) that fades over
    /// `duration`: added light on a copy of its own texture, so it shows over
    /// any power-up tint without disturbing it.
    func flash(color: SKColor, alpha: CGFloat, duration: TimeInterval) {
        guard let texture else { return }
        let overlay = SKSpriteNode(texture: texture)
        overlay.color = color
        overlay.colorBlendFactor = 1
        overlay.blendMode = .add
        overlay.alpha = alpha
        overlay.zPosition = 0.2
        overlay.run(.sequence([.fadeOut(withDuration: duration), .removeFromParent()]))
        addChild(overlay)
    }
}
