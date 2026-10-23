import SpriteKit

/// Adventure's third and last boss, in the Shallows: a ghost galleon on the stormy
/// surface overhead. It sails along the waterline after the snake, one cell per
/// sail interval (racing to catch up if it falls far behind), and fires volleys of
/// cannon shot (`CannonShot`) down into the water where the snake is headed.
///
/// Its shot is how it's beaten: where a ball lands it comes to rest as a cannonball,
/// and a cannonball rolled straight up into the hull holes it (`GameManager` sees
/// that happen in `push`, since the hull's `cells` are what the ball rolls into). A
/// barrel's blast up through the hull counts too. It sails faster and fires more
/// shot with every life it loses, and on its last it founders and sinks.
///
/// Like the other bosses it owns its own state and nodes, and `GameManager`
/// decides what its shots and cells mean.
final class Galleon: Boss {
    static let maxLives = 3
    /// How far the hull reaches either side of its middle, in cells: it's nine
    /// cells long at the waterline.
    static let halfLength = 4

    private(set) var lives = Galleon.maxLives
    var isDefeated: Bool { lives <= 0 }
    /// The column under the middle of the hull.
    private(set) var column: Int
    /// The row of sky the hull sits in, on the water.
    private let waterline: Int
    /// The hull, along the waterline. Already sky (and so a barrier), so these
    /// matter for what's rolled up into them. Empty once it's sunk.
    var cells: Set<GridPoint> {
        guard !isDefeated else { return [] }
        return Set((column - Galleon.halfLength...column + Galleon.halfLength).map { GridPoint(x: $0, y: waterline) })
    }

    private static let wakeDelay: TimeInterval = 2.5
    /// Seconds per cell it sails, seconds between volleys, and shots per volley, on
    /// its first, second and last life.
    private static let sailIntervals: [TimeInterval] = [0.42, 0.34, 0.27]
    /// More than this many columns behind the snake, it crowds on sail and races
    /// to catch up (`raceInterval` per cell), so it never stays off screen for long.
    private static let raceDistance = 6
    private static let raceInterval: TimeInterval = 0.1
    private static let volleyGaps: [TimeInterval] = [3.4, 2.9, 2.4]
    private static let volleySizes = [1, 2, 3]
    /// Between one gun of a volley and the next.
    private static let shotStagger: TimeInterval = 0.3
    /// How far from the aim point, in cells, a shot may land.
    private static let spreadX = 4
    private static let spreadY = 3
    private static let hitInvulnerability: TimeInterval = 1.5
    /// How long it rocks after a hit.
    private static let heaveDuration: TimeInterval = 1.4

    private let columns: Int
    private let cellSize: CGFloat
    private let origin: CGPoint
    private let waterlineY: CGFloat

    /// Sits at the middle of the hull, on the waterline.
    private let container = SKNode()
    private let ship: SKSpriteNode
    /// Shots and their effects, in scene coordinates.
    private let shotLayer = SKNode()
    private var shots: [CannonShot] = []

    private var timeUntilSail = Galleon.wakeDelay
    private var timeUntilVolley = Galleon.wakeDelay + 1
    private var invulnerability: TimeInterval = 0
    private var heaveRemaining: TimeInterval = 0
    /// 1 facing right (as drawn), -1 left.
    private var facing: CGFloat = 1

    /// Index into the per-life tables: 0 unhurt, up to their last entry.
    private var wounds: Int {
        min(Galleon.maxLives - lives, Galleon.sailIntervals.count - 1)
    }

    /// Where the middle of the hull may sail, keeping the whole ship on the map.
    private var sailableColumns: ClosedRange<Int> {
        (Galleon.halfLength + 1)...(columns - Galleon.halfLength - 2)
    }

    init(column: Int, waterline: Int, columns: Int, cellSize: CGFloat, origin: CGPoint) {
        self.waterline = waterline
        self.columns = columns
        self.cellSize = cellSize
        self.origin = origin
        waterlineY = origin.y + CGFloat(waterline) * cellSize
        self.column = column

        ship = SKSpriteNode(texture: SpriteArt.galleon(cellSize: cellSize))
        ship.anchorPoint = SpriteArt.galleonAnchor
        container.addChild(ship)
        container.zPosition = 2.5
        shotLayer.zPosition = 2
        container.position = CGPoint(x: hullX(for: column), y: waterlineY)
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
        scene.addChild(shotLayer)
    }

    func removeFromScene() {
        container.removeFromParent()
        shotLayer.removeFromParent()
    }

    // MARK: Gameplay

    /// Advances its shots by `delta` real seconds, sails toward `targetColumn`, and
    /// fires a new volley around `aim` (where the snake's head is expected to be
    /// when it lands) when one's due, only at cells `canLand` allows. Returns the
    /// shots that landed this frame, for `GameManager` to resolve.
    func update(delta: TimeInterval, chasing targetColumn: Int, aim: GridPoint, canLand: (GridPoint) -> Bool) -> [CannonShot] {
        invulnerability = max(0, invulnerability - delta)
        heaveRemaining = max(0, heaveRemaining - delta)

        var landed: [CannonShot] = []
        for shot in shots where shot.update(delta: delta) {
            landed.append(shot)
        }
        shots.removeAll { shot in
            guard shot.isFinished else { return false }
            shot.node.removeFromParent()
            return true
        }

        guard !isDefeated else { return landed }
        timeUntilSail -= delta
        if timeUntilSail <= 0 {
            let isRacing = abs(targetColumn - column) > Galleon.raceDistance
            timeUntilSail = isRacing ? Galleon.raceInterval : Galleon.sailIntervals[wounds]
            sail(toward: targetColumn, over: timeUntilSail)
        }
        timeUntilVolley -= delta
        if timeUntilVolley <= 0 {
            timeUntilVolley = Galleon.volleyGaps[wounds]
            fireVolley(around: aim, canLand: canLand)
        }
        return landed
    }

    /// Whether a barrel's blast up `point`'s column goes through the hull. (Its row
    /// never reaches the surface.)
    func isCrossed(byBlastFrom point: GridPoint) -> Bool {
        !isDefeated && abs(point.x - column) <= Galleon.halfLength
    }

    /// Takes a life, unless it's still recovering from the last hit (or already
    /// sunk). Returns whether the hit counted.
    @discardableResult
    func takeHit() -> Bool {
        guard !isDefeated, invulnerability <= 0 else { return false }
        lives -= 1
        invulnerability = Galleon.hitInvulnerability
        heaveRemaining = Galleon.heaveDuration
        ship.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.7, duration: 0.05),
            .colorize(withColorBlendFactor: 0, duration: 0.4),
        ]))
        if isDefeated {
            founder()
        }
        return true
    }

    /// One cell toward `target`, gliding there over `duration`, unless it's already
    /// over it (or as near as the map lets it get). Comes about if that's the other
    /// way.
    private func sail(toward target: Int, over duration: TimeInterval) {
        let goal = min(max(target, sailableColumns.lowerBound), sailableColumns.upperBound)
        guard goal != column else { return }
        let step = goal > column ? 1 : -1
        column += step
        if CGFloat(step) != facing {
            facing = CGFloat(step)
            ship.run(.scaleX(to: facing, duration: 0.5), withKey: "come about")
        }
        let glide = SKAction.moveTo(x: hullX(for: column), duration: duration)
        container.run(glide, withKey: "sail")
    }

    /// A volley: shots around `aim` (kept in the water), in cells `canLand` allows,
    /// far enough apart that their patches don't overlap. If there's nowhere for
    /// one, it isn't fired.
    private func fireVolley(around aim: GridPoint, canLand: (GridPoint) -> Bool) {
        let center = GridPoint(x: min(max(aim.x, 1), columns - 2), y: min(max(aim.y, 1), waterline - 2))
        var targets: [GridPoint] = []
        for _ in 0..<Galleon.volleySizes[wounds] {
            for _ in 0..<12 {
                let candidate = GridPoint(x: center.x + .random(in: -Galleon.spreadX...Galleon.spreadX),
                                          y: center.y + .random(in: -Galleon.spreadY...Galleon.spreadY))
                let isApart = targets.allSatisfy { max(abs($0.x - candidate.x), abs($0.y - candidate.y)) >= 3 }
                if isApart && canLand(candidate) {
                    targets.append(candidate)
                    break
                }
            }
        }
        for (index, target) in targets.enumerated() {
            let shot = CannonShot(target: target, from: muzzle(toward: target), waterlineY: waterlineY,
                                  delay: Double(index) * Galleon.shotStagger, cellSize: cellSize, origin: origin)
            shotLayer.addChild(shot.node)
            shots.append(shot)
        }
    }

    /// The gun port nearest `target`, in scene coordinates.
    private func muzzle(toward target: GridPoint) -> CGPoint {
        let middle = hullX(for: column)
        let targetX = GridGeometry.position(for: target, cellSize: cellSize, origin: origin).x
        let ports = SpriteArt.galleonGunPorts.map { middle + $0 * facing * cellSize }
        let nearest = ports.min { abs($0 - targetX) < abs($1 - targetX) } ?? middle
        return CGPoint(x: nearest, y: waterlineY + SpriteArt.galleonGunPortHeight * cellSize)
    }

    private func hullX(for column: Int) -> CGFloat {
        GridGeometry.position(for: GridPoint(x: column, y: waterline), cellSize: cellSize, origin: origin).x
    }

    /// Sunk: its shots are called off, and it rolls over and goes down, bubbling,
    /// with a great splash where it was.
    private func founder() {
        shots.forEach { $0.cancel() }
        container.removeAction(forKey: "sail")
        BoardEffects.splash(at: container.position, size: 2.4, cellSize: cellSize, in: shotLayer)

        let sinking = SKAction.moveBy(x: 0, y: -cellSize * 5, duration: 3.2)
        sinking.timingMode = .easeIn
        container.run(.group([
            .rotate(toAngle: 0.38 * facing, duration: 2.6),
            sinking,
            .sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 1.8)]),
        ]))

        let bubbling = SKAction.run { [weak self] in
            guard let self else { return }
            let along = CGFloat.random(in: -1...1) * CGFloat(Galleon.halfLength) * self.cellSize
            let point = CGPoint(x: self.container.position.x + along, y: self.container.position.y - self.cellSize * 0.5)
            BoardEffects.bubbleBurst(at: point, count: 4, cellSize: self.cellSize, in: self.shotLayer)
        }
        shotLayer.run(.repeat(.sequence([bubbling, .wait(forDuration: 0.1)]), count: 30))
    }

    // MARK: Drawing

    /// Bobs and rolls on the swell, rocking hard for a moment after a hit. Called
    /// every frame, including after a game over.
    func animate(time: Double) {
        let heave = heaveRemaining / Galleon.heaveDuration
        ship.position = CGPoint(x: 0, y: cellSize * 0.12 * CGFloat(sin(time * 1.5)))
        ship.zRotation = 0.035 * CGFloat(sin(time * 0.9)) + 0.09 * CGFloat(heave * sin(time * 14))
    }
}
