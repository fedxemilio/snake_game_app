import SpriteKit

/// Adventure's first boss: a kraken in the middle of the Kraken's Lair stage
/// (`AdventureStage.krakensLair`),
/// flailing its arms and lashing out with tentacle strikes (`TentacleStrike`) around
/// the snake.
///
/// Like the board's other entities it owns its own state and nodes, and
/// `GameManager` decides what touching it means:
/// - **The lair** (`footprint`, a disc about 9 cells across) is solid: the snake stops
///   against it like a wall (and it costs a life), nothing spawns inside it, and
///   it's what a barrel blast has to cross to do damage.
/// - **Strikes** start every `strikeGap` seconds (real time, like bomb fuses) in a
///   9x9 patch around where the snake is headed (`GameManager` supplies the aim),
///   with at most `maxConcurrentStrikes` at once.
/// - **Lives**: `maxLives`. A barrel blast whose row or column crosses the lair
///   costs one (`takeHit()`); it flinches, spits ink and thrashes, and can't be hurt
///   again for `hitInvulnerability` seconds, so one chain reaction can't take every
///   life at once. On its last life it sinks away, the lair opens up and the
///   strikes stop.
///
/// Gameplay (`update(delta:head:)`) and drawing (`animate(time:focus:)`) are
/// separate: the scene keeps animating it after a game over, so the arms flail on
/// behind the overlay while any strike in progress stays frozen mid-swing.
final class Kraken {
    static let maxLives = 3

    private(set) var lives = Kraken.maxLives
    var isDefeated: Bool { lives <= 0 }
    /// Cells the kraken and its resting arms cover. Empty once it's defeated.
    private(set) var footprint: Set<GridPoint>

    private static let lairRadius = 4.5
    private static let firstStrikeDelay: TimeInterval = 3
    private static let strikeGap: ClosedRange<TimeInterval> = 1.4...3.6
    private static let maxConcurrentStrikes = 2
    /// How far from the aim point, in cells, a strike patch's middle may land: well
    /// within a screen of the snake, so the player sees every one coming.
    private static let strikeReachX = 6
    private static let strikeReachY = 10
    private static let hitInvulnerability: TimeInterval = 1.5
    private static let thrashDuration: TimeInterval = 1.6

    /// Where the arms join the head, relative to the center cell, in cells. The
    /// body texture is drawn around this (see `SpriteArt.krakenBody`).
    private static let headCenter = CGPoint(x: 0, y: -0.65)
    private static let armLength: CGFloat = 2.8
    private static let armLinks = 22
    /// Eight arms fanning out around the head, leaving a gap at the top where the
    /// mantle is, in degrees counterclockwise from pointing right.
    private static let armAngles: [CGFloat] = [150, 185, 215, 250, 290, 325, 355, 30]

    private struct Arm {
        let baseAngle: CGFloat
        let phase: Double
        let speed: Double
        /// Which way the tip curls: 1 counterclockwise, -1 clockwise.
        let curl: Double
        let chain: TentacleChain
    }

    private let columns: Int
    private let rows: Int
    private let cellSize: CGFloat
    private let origin: CGPoint

    /// Body and arms, positioned at the center cell.
    private let container = SKNode()
    /// Strike patches and their tentacles, in scene coordinates.
    private let strikeLayer = SKNode()
    private let body: SKSpriteNode
    private let pupils: [SKSpriteNode]
    private var arms: [Arm] = []
    private var strikes: [TentacleStrike] = []

    private var timeUntilNextStrike = Kraken.firstStrikeDelay
    private var invulnerability: TimeInterval = 0
    /// Seconds of extra-violent flailing left after a hit.
    private var thrashRemaining: TimeInterval = 0

    init(center: GridPoint, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        self.origin = origin
        footprint = Kraken.lair(around: center)

        container.position = GridGeometry.position(for: center, cellSize: cellSize, origin: origin)
        container.zPosition = 3

        body = SKSpriteNode(texture: SpriteArt.krakenBody(cellSize: cellSize))
        body.zPosition = 1
        container.addChild(body)

        var pupils: [SKSpriteNode] = []
        for side: CGFloat in [-1, 1] {
            let eye = SKSpriteNode(texture: SpriteArt.krakenEye(cellSize: cellSize))
            eye.position = CGPoint(x: side * 1.0 * cellSize, y: -0.55 * cellSize)
            eye.zPosition = 0.1
            let pupil = SKSpriteNode(texture: SpriteArt.krakenPupil(cellSize: cellSize))
            pupil.zPosition = 0.1
            eye.addChild(pupil)
            body.addChild(eye)
            pupils.append(pupil)
        }
        self.pupils = pupils

        for (index, degrees) in Kraken.armAngles.enumerated() {
            let chain = TentacleChain(links: Kraken.armLinks, cellSize: cellSize)
            container.addChild(chain.node)
            arms.append(Arm(
                baseAngle: degrees * .pi / 180,
                phase: Double(index) * 1.9,
                speed: 1.6 + 0.3 * Double(index % 3),
                curl: index.isMultiple(of: 2) ? 1 : -1,
                chain: chain
            ))
        }
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
        scene.addChild(strikeLayer)
    }

    func removeFromScene() {
        container.removeFromParent()
        strikeLayer.removeFromParent()
    }

    // MARK: Gameplay

    /// Advances the strikes by `delta` real seconds, and schedules new ones around
    /// `aim` (where the snake's head is expected to be when a new one lands).
    func update(delta: TimeInterval, aim: GridPoint) {
        invulnerability = max(0, invulnerability - delta)
        thrashRemaining = max(0, thrashRemaining - delta)

        for strike in strikes {
            strike.update(delta: delta)
        }
        strikes.removeAll { strike in
            guard strike.isFinished else { return false }
            strike.node.removeFromParent()
            return true
        }

        guard !isDefeated else { return }
        timeUntilNextStrike -= delta
        guard timeUntilNextStrike <= 0, strikes.count < Kraken.maxConcurrentStrikes else { return }
        timeUntilNextStrike = .random(in: Kraken.strikeGap)

        guard let corner = strikeCorner(near: aim) else { return }
        let strike = TentacleStrike(corner: corner, cellSize: cellSize, origin: origin)
        strikeLayer.addChild(strike.node)
        strikes.append(strike)
    }

    /// Whether a tentacle is up over `point` right now.
    func isStriking(_ point: GridPoint) -> Bool {
        strikes.contains { $0.isLethal && $0.covers(point) }
    }

    /// Whether a barrel blast down `point`'s row and column passes through the lair.
    func isCrossed(byBlastFrom point: GridPoint) -> Bool {
        footprint.contains { $0.x == point.x || $0.y == point.y }
    }

    /// Takes a life, unless it's still recovering from the last hit (or already
    /// beaten). Returns whether the hit counted.
    @discardableResult
    func takeHit() -> Bool {
        guard !isDefeated, invulnerability <= 0 else { return false }
        lives -= 1
        invulnerability = Kraken.hitInvulnerability
        thrashRemaining = Kraken.thrashDuration
        flinch()
        if isDefeated {
            sink()
        }
        return true
    }

    /// A random 9x9 patch whose middle is near `aim`, kept inside the map and a
    /// cell clear of the lair. Nil if none turns up in a few tries (the snake is
    /// hugging the lair), in which case this strike is skipped.
    private func strikeCorner(near aim: GridPoint) -> GridPoint? {
        let size = TentacleStrike.zoneSize
        for _ in 0..<12 {
            let middleX = aim.x + Int.random(in: -Kraken.strikeReachX...Kraken.strikeReachX)
            let middleY = aim.y + Int.random(in: -Kraken.strikeReachY...Kraken.strikeReachY)
            let x = min(max(middleX - size / 2, 0), columns - size)
            let y = min(max(middleY - size / 2, 0), rows - size)
            let touchesLair = footprint.contains { cell in
                cell.x >= x - 1 && cell.x <= x + size && cell.y >= y - 1 && cell.y <= y + size
            }
            if !touchesLair {
                return GridPoint(x: x, y: y)
            }
        }
        return nil
    }

    private static func lair(around center: GridPoint) -> Set<GridPoint> {
        let reach = Int(lairRadius)
        var cells: Set<GridPoint> = []
        for dx in -reach...reach {
            for dy in -reach...reach where Double(dx * dx + dy * dy) <= lairRadius * lairRadius {
                cells.insert(GridPoint(x: center.x + dx, y: center.y + dy))
            }
        }
        return cells
    }

    /// Hit: a flash of white, a shudder and a puff of ink.
    private func flinch() {
        body.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.8, duration: 0.05),
            .colorize(withColorBlendFactor: 0, duration: 0.35),
        ]))
        let jolt = cellSize * 0.18
        container.run(.sequence([
            .moveBy(x: jolt, y: 0, duration: 0.04),
            .moveBy(x: -jolt * 2, y: 0, duration: 0.08),
            .moveBy(x: jolt * 1.5, y: 0, duration: 0.07),
            .moveBy(x: -jolt * 0.5, y: 0, duration: 0.05),
        ]))
        spitInk(scale: 1)
    }

    /// Defeated: the lair opens, any strikes under way are called off, and it sinks
    /// into a cloud of its own ink.
    private func sink() {
        footprint = []
        strikes.forEach { $0.cancel() }
        spitInk(scale: 1.8)
        container.run(.sequence([
            .wait(forDuration: 0.3),
            .group([
                .fadeOut(withDuration: 2.4),
                .scale(to: 0.7, duration: 2.4),
                .moveBy(x: 0, y: -cellSize, duration: 2.4),
            ]),
        ]))
    }

    private func spitInk(scale: CGFloat) {
        let ink = SKSpriteNode(texture: SpriteArt.inkCloud(cellSize: cellSize))
        ink.position = container.position
        ink.zPosition = container.zPosition + 2
        ink.setScale(0.4 * scale)
        let spread = SKAction.scale(to: 1.5 * scale, duration: 1.6)
        spread.timingMode = .easeOut
        ink.run(.sequence([.group([spread, .fadeOut(withDuration: 1.6)]), .removeFromParent()]))
        strikeLayer.addChild(ink)
    }

    // MARK: Drawing

    /// Poses everything for this frame: breathing, swaying, flailing arms, eyes on
    /// `focus` (the snake's head, in scene coordinates), and any strikes.
    func animate(time: Double, focus: CGPoint) {
        let thrash = min(1, thrashRemaining / 0.8)
        let breath = CGFloat(sin(time * 1.3))
        body.yScale = 1 + 0.035 * breath
        body.xScale = 1 - 0.015 * breath
        body.zRotation = 0.05 * CGFloat(sin(time * 0.6)) + 0.06 * CGFloat(thrash * sin(time * 23))

        for arm in arms {
            pose(arm, time: time, thrash: thrash)
        }

        let toFocus = CGPoint(x: focus.x - container.position.x, y: focus.y - container.position.y)
        let distance = max(1, hypot(toFocus.x, toFocus.y))
        let glance = cellSize * 0.11
        for pupil in pupils {
            pupil.position = CGPoint(x: toFocus.x / distance * glance, y: toFocus.y / distance * glance)
        }

        for strike in strikes {
            strike.animate(time: time)
        }
    }

    /// Lays an arm out link by link from where it joins the head, bending as it
    /// goes: a wave rolling out toward the tip, plus a curl that tightens near it.
    /// Thrashing makes the wave bigger and faster.
    private func pose(_ arm: Arm, time: Double, thrash: Double) {
        let count = Kraken.armLinks
        let step = Kraken.armLength * cellSize / CGFloat(count - 1)
        let energy = 1 + 1.4 * thrash
        let head = CGPoint(x: Kraken.headCenter.x * cellSize, y: Kraken.headCenter.y * cellSize)

        var angle = arm.baseAngle
        var point = CGPoint(x: head.x + cos(angle) * 0.9 * cellSize, y: head.y + sin(angle) * 0.9 * cellSize)
        var points: [CGPoint] = []
        var radii: [CGFloat] = []
        points.reserveCapacity(count)
        radii.reserveCapacity(count)

        for index in 0..<count {
            let along = Double(index) / Double(count - 1)
            points.append(point)
            radii.append(cellSize * (0.34 - 0.255 * CGFloat(along)))

            // Curvature, in radians over the arm's whole length.
            let wave = 2.2 * energy * sin(time * arm.speed * energy + arm.phase - along * 4)
            let curl = arm.curl * 6 * along * along * (0.75 + 0.25 * sin(time * 0.8 + arm.phase))
            angle += CGFloat((wave + curl) / Double(count - 1))
            point.x += cos(angle) * step
            point.y += sin(angle) * step
        }
        arm.chain.layout(points: points, radii: radii)
    }
}
