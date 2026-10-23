import SpriteKit

/// What `GameManager` needs from whichever boss a stage has, so damage, the HUD and
/// the stage-clear don't care which it is.
protocol Boss: AnyObject {
    static var maxLives: Int { get }
    var lives: Int { get }
    var isDefeated: Bool { get }
    /// Cells the snake can't swim into (it stops against them, and it hurts).
    var cells: Set<GridPoint> { get }
    /// Whether a barrel's blast down `point`'s row and column hits it.
    func isCrossed(byBlastFrom point: GridPoint) -> Bool
    /// Takes a life unless it's still recovering from the last; returns whether
    /// the hit counted.
    @discardableResult func takeHit() -> Bool
}

extension Kraken: Boss {
    var cells: Set<GridPoint> { footprint }
}

/// Adventure's second boss, in Moray Hollows: a giant moray eel that hunts the
/// snake. It moves on the same grid, one cell per `moveInterval`, always along the
/// shortest way to the snake's head (`nextStep(toward:isOpen:)`), and bites
/// whatever part of the snake it reaches.
///
/// It's **blind**: mines don't exist to it, so it swims straight into them. Drop
/// mines in its path (it follows you, so behind you works) and each one costs it a
/// life; so does a cannonball rolled into it anywhere along its body (it breaks:
/// see `GameManager.push`), and a barrel's blast across its head. It gets faster with
/// each life lost.
///
/// Like the board's other entities it owns its own state and nodes, and
/// `GameManager` decides what its moves mean (`update` only says where it wants
/// to go).
final class Moray: Boss {
    static let maxLives = 3

    private(set) var lives = Moray.maxLives
    var isDefeated: Bool { lives <= 0 }
    /// Its cells, head first. Solid to the snake. Empty once it's defeated.
    private(set) var segments: [GridPoint]
    var cells: Set<GridPoint> { Set(segments) }

    /// Seconds before it first stirs from its cave.
    private static let wakeDelay: TimeInterval = 2.5
    /// Seconds per cell on its first, second and last life: it speeds up as it's
    /// hurt, but starts slower than the snake so it can be outswum.
    private static let moveIntervals: [TimeInterval] = [0.26, 0.21, 0.17]
    /// After a bite, it holds off this long before coming again.
    private static let biteRecoil: TimeInterval = 1.0
    /// After taking a hit, it's stunned this long, and can't be hurt again for a
    /// little longer than that.
    private static let hitStun: TimeInterval = 1.2
    private static let hitInvulnerability: TimeInterval = 1.5

    private let columns: Int
    private let rows: Int
    private let cellSize: CGFloat
    private let origin: CGPoint

    private let container = SKNode()
    /// One sprite per segment, head first, tail last.
    private var nodes: [SKSpriteNode] = []

    private var timeUntilMove = Moray.wakeDelay
    private var invulnerability: TimeInterval = 0

    private var moveInterval: TimeInterval {
        Moray.moveIntervals[min(Moray.maxLives - lives, Moray.moveIntervals.count - 1)]
    }

    init(body: [GridPoint], columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        segments = body
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        self.origin = origin
        container.zPosition = 1.5

        for index in body.indices {
            let texture: SKTexture
            if index == 0 {
                texture = SpriteArt.morayHead(cellSize: cellSize)
            } else if index == body.count - 1 {
                texture = SpriteArt.morayTail(cellSize: cellSize)
            } else {
                texture = SpriteArt.morayBody(cellSize: cellSize, variant: index % 2)
            }
            let node = SKSpriteNode(texture: texture)
            // Head over body over tail, so it overlaps itself like the snake does.
            node.zPosition = CGFloat(body.count - index) * 0.001
            container.addChild(node)
            nodes.append(node)
        }
        layOut(over: 0)
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
    }

    func removeFromScene() {
        container.removeFromParent()
    }

    // MARK: Gameplay

    /// Counts down to its next move, by `delta` real seconds. When one's due,
    /// returns the cell it wants to move into, which may be part of the snake (a
    /// bite) or a mine (it can't tell). Nil when it isn't moving this frame:
    /// still waking, recoiling, stunned, between moves, defeated or boxed in.
    ///
    /// `isOpen` says which cells the world lets it into: not walls or solid
    /// pushables, but yes to the snake (it's what it's after) and to mines.
    func update(delta: TimeInterval, target: GridPoint, isOpen: (GridPoint) -> Bool) -> GridPoint? {
        invulnerability = max(0, invulnerability - delta)
        guard !isDefeated else { return nil }
        timeUntilMove -= delta
        guard timeUntilMove <= 0 else { return nil }
        timeUntilMove = moveInterval
        return nextStep(toward: target, isOpen: isOpen)
    }

    /// Moves its head into `cell` (one step from it), the body following.
    func advance(to cell: GridPoint) {
        guard !segments.isEmpty else { return }
        segments.insert(cell, at: 0)
        segments.removeLast()
        layOut(over: moveInterval)
    }

    /// It reached the snake at `cell` and bit: its head snaps forward and back,
    /// and it holds off for a moment before coming again.
    func bite(at cell: GridPoint) {
        timeUntilMove = Moray.biteRecoil
        guard let head = segments.first, let headNode = nodes.first else { return }
        let reach = cellSize * 0.4
        let dx = CGFloat(cell.x - head.x) * reach
        let dy = CGFloat(cell.y - head.y) * reach
        headNode.run(.sequence([
            .moveBy(x: dx, y: dy, duration: 0.07),
            .moveBy(x: -dx, y: -dy, duration: 0.12),
        ]))
    }

    @discardableResult
    func takeHit() -> Bool {
        guard !isDefeated, invulnerability <= 0 else { return false }
        lives -= 1
        invulnerability = Moray.hitInvulnerability
        timeUntilMove = Moray.hitStun

        for node in nodes {
            node.run(.sequence([
                .colorize(with: .white, colorBlendFactor: 0.8, duration: 0.05),
                .colorize(withColorBlendFactor: 0, duration: 0.4),
            ]))
        }
        let jolt = cellSize * 0.2
        container.run(.sequence([
            .moveBy(x: jolt, y: 0, duration: 0.04),
            .moveBy(x: -jolt * 2, y: 0, duration: 0.08),
            .moveBy(x: jolt * 1.5, y: 0, duration: 0.07),
            .moveBy(x: -jolt * 0.5, y: 0, duration: 0.05),
        ]))

        if isDefeated {
            dissolve()
        }
        return true
    }

    /// Only its head counts, same as the snake.
    func isCrossed(byBlastFrom point: GridPoint) -> Bool {
        guard let head = segments.first else { return false }
        return head.x == point.x || head.y == point.y
    }

    /// The first step along the shortest way from its head to `target`, by
    /// breadth-first search over the grid (no wrapping). Its own body is in the
    /// way, bar the tail, which moves on as it does. If there's no way through, it
    /// at least moves somewhere open rather than freezing in place.
    private func nextStep(toward target: GridPoint, isOpen: (GridPoint) -> Bool) -> GridPoint? {
        guard let head = segments.first else { return nil }
        let body = Set(segments.dropLast())
        func passable(_ cell: GridPoint) -> Bool {
            cell.x >= 0 && cell.x < columns && cell.y >= 0 && cell.y < rows && !body.contains(cell) && isOpen(cell)
        }
        func neighbors(of cell: GridPoint) -> [GridPoint] {
            [GridPoint(x: cell.x + 1, y: cell.y), GridPoint(x: cell.x - 1, y: cell.y),
             GridPoint(x: cell.x, y: cell.y + 1), GridPoint(x: cell.x, y: cell.y - 1)]
        }

        // Each reached cell remembers which first step got there. The first steps
        // are tried in a random order, so ties don't always break the same way.
        var firstStep: [GridPoint: GridPoint] = [:]
        var queue: [GridPoint] = []
        for cell in neighbors(of: head).shuffled() where passable(cell) {
            firstStep[cell] = cell
            queue.append(cell)
        }
        var index = 0
        while index < queue.count {
            let cell = queue[index]
            index += 1
            if cell == target {
                return firstStep[cell]
            }
            for next in neighbors(of: cell) where next != head && firstStep[next] == nil && passable(next) {
                firstStep[next] = firstStep[cell]
                queue.append(next)
            }
        }
        return queue.first
    }

    // MARK: Drawing

    /// Puts every sprite on its segment's cell, sliding there over `duration` so
    /// it glides cell to cell instead of hopping. The head turns to face where it's
    /// going; the tail points away from the body.
    private func layOut(over duration: TimeInterval) {
        for (index, node) in nodes.enumerated() where index < segments.count {
            let point = GridGeometry.position(for: segments[index], cellSize: cellSize, origin: origin)
            if duration > 0 {
                node.run(.move(to: point, duration: duration), withKey: "move")
            } else {
                node.position = point
            }
        }
        if segments.count >= 2 {
            turn(nodes[0], toFace: Moray.angle(from: segments[1], to: segments[0]), over: duration)
            let last = segments.count - 1
            turn(nodes[last], toFace: Moray.angle(from: segments[last - 1], to: segments[last]), over: duration)
        }
    }

    private func turn(_ node: SKSpriteNode, toFace angle: CGFloat, over duration: TimeInterval) {
        if duration > 0 {
            node.run(.rotate(toAngle: angle, duration: min(0.12, duration), shortestUnitArc: true), withKey: "turn")
        } else {
            node.zRotation = angle
        }
    }

    private static func angle(from previous: GridPoint, to next: GridPoint) -> CGFloat {
        atan2(CGFloat(next.y - previous.y), CGFloat(next.x - previous.x))
    }

    /// Defeated: it stops being in the way at once, and comes apart head to tail
    /// into bubbles.
    private func dissolve() {
        let parent = container.parent ?? container
        for (index, node) in nodes.enumerated() {
            node.run(.sequence([
                .wait(forDuration: 0.5 + Double(index) * 0.06),
                .run { [weak self, weak node] in
                    guard let self, let node else { return }
                    BoardEffects.bubbleBurst(at: self.container.convert(node.position, to: parent), count: 5,
                                             cellSize: self.cellSize, in: parent)
                },
                .group([.scale(to: 0.2, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            ]))
        }
        segments = []
    }
}
