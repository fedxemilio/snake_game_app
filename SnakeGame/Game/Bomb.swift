import SpriteKit

/// The different kinds of bomb that can spawn, each with its own color and
/// twist on "touch it and lose": `.mine` is the original hazard -- permanent
/// and stationary. `.timed` counts down (with a faster warning pulse near
/// the end) and fades away harmlessly once its fuse runs out, so it rewards
/// waiting it out rather than permanent avoidance. `.drifter` never expires
/// but slowly roams the grid on its own clock instead of sitting still, so
/// its danger zone moves under the player. `.sensor` starts dormant (calm,
/// steady pulse, harmless at range) and only starts its countdown once the
/// snake's head enters one of its 8 surrounding cells -- see `Bomb.arm()`
/// and `GameManager.resolveSensorDetonation(at:)` for the proximity trigger
/// and the vicinity-wide consequences when it goes off. `.barrel` is square
/// rather than round and otherwise inert -- it never arms or counts down on
/// its own, and the only thing that sets it off (for now; pushing it safely
/// is planned but not implemented) is a `.sensor` detonating within its
/// vicinity, at which point it blasts its entire row and column.
enum BombKind {
    case mine
    case timed
    case drifter
    case sensor
    case barrel
}

/// A hazard: once placed, running the snake's head into one (without
/// bomb-eater active) is a loss. `.mine` never relocates or expires; see
/// `BombKind` for how `.timed` and `.drifter` differ. Visually pulses/glows
/// so it reads as distinct from Food and PowerUp even though the base
/// palette is similar -- a "mine" rather than a collectible.
final class Bomb {
    let kind: BombKind
    private(set) var position: GridPoint
    private(set) var isExpired = false

    private let node: SKShapeNode
    private let cellSize: CGFloat
    private let origin: CGPoint

    /// `.sensor`-only: a faint square outline over the 3x3 area this bomb
    /// will hit, so its blast radius reads at a glance instead of being a
    /// surprise. Brightens once armed (see `arm()`). nil for every other
    /// kind.
    private let vicinityIndicator: SKShapeNode?

    /// Real seconds remaining before a `.timed` bomb expires -- ticked in
    /// `update(delta:...)`, independent of grid moves, like the bomb-eater
    /// timer. nil for kinds that don't have a fuse.
    private var fuseRemaining: TimeInterval?
    private var hasPlayedFuseWarning = false

    /// Real seconds until a `.drifter` takes its next step. nil for kinds
    /// that don't move on their own.
    private var timeUntilNextDrift: TimeInterval?

    private static let pulseActionKey = "pulse"
    private static let fuseDuration: TimeInterval = 8.0
    private static let fuseWarningThreshold: TimeInterval = 2.5
    private static let driftInterval: TimeInterval = 0.9

    /// `.sensor`'s fuse once armed -- short and unconditionally blinking
    /// (see `arm()`), since arming already means the player is close; there's
    /// no separate calm-then-warn runway like `.timed` gets.
    private static let sensorFuseDuration: TimeInterval = 3.0

    init(kind: BombKind, position: GridPoint, cellSize: CGFloat, origin: CGPoint) {
        self.kind = kind
        self.position = position
        self.cellSize = cellSize
        self.origin = origin

        switch kind {
        case .mine, .sensor, .barrel:
            // .sensor starts dormant, exactly like .mine, until arm() is
            // called from proximity or a neighboring sensor's detonation.
            // .barrel never arms or counts down at all -- see BombKind.
            fuseRemaining = nil
            timeUntilNextDrift = nil
        case .timed:
            fuseRemaining = Bomb.fuseDuration
            timeUntilNextDrift = nil
        case .drifter:
            fuseRemaining = nil
            timeUntilNextDrift = Bomb.driftInterval
        }

        let diameter = cellSize - 4
        switch kind {
        case .barrel:
            // Square is the one deliberate shape break -- every other kind
            // reads as a "mine" silhouette; barrel should look like a
            // different kind of object entirely.
            node = SKShapeNode(rectOf: CGSize(width: diameter, height: diameter), cornerRadius: 3)
        case .mine, .timed, .drifter, .sensor:
            node = SKShapeNode(circleOfRadius: diameter / 2)
        }
        node.fillColor = SKColor(white: 0.15, alpha: 1)
        node.strokeColor = Bomb.strokeColor(for: kind)
        node.lineWidth = 2
        node.glowWidth = 6
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
        node.run(Bomb.pulseAction(scale: 1.2, duration: 0.6), withKey: Bomb.pulseActionKey)

        if kind == .sensor {
            let indicator = SKShapeNode(rectOf: CGSize(width: cellSize * 3 - 2, height: cellSize * 3 - 2))
            indicator.fillColor = .clear
            indicator.strokeColor = Bomb.strokeColor(for: .sensor).withAlphaComponent(0.35)
            indicator.lineWidth = 1.5
            indicator.position = node.position
            indicator.zPosition = -1
            vicinityIndicator = indicator
        } else {
            vicinityIndicator = nil
        }
    }

    private static func strokeColor(for kind: BombKind) -> SKColor {
        switch kind {
        case .mine: return .systemRed
        case .timed: return .systemOrange
        case .drifter: return .systemPink
        case .sensor: return .systemIndigo
        case .barrel: return .systemBrown
        }
    }

    private static func pulseAction(scale: CGFloat, duration: TimeInterval) -> SKAction {
        let pulseOut = SKAction.scale(to: scale, duration: duration)
        pulseOut.timingMode = .easeInEaseOut
        let pulseIn = SKAction.scale(to: 1.0, duration: duration)
        pulseIn.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([pulseOut, pulseIn]))
    }

    func addToScene(_ scene: SKScene) {
        if let vicinityIndicator {
            scene.addChild(vicinityIndicator)
        }
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
        vicinityIndicator?.removeFromParent()
    }

    /// Transitions a dormant `.sensor` bomb into its countdown: switches
    /// straight to the fast/blinking pulse -- arming *is* the warning, there's
    /// no calm runway first -- and starts `sensorFuseDuration` ticking via the
    /// same `fuseRemaining` machinery `.timed` uses, so `updateFuse(delta:)`
    /// (unchanged) counts it down and fades it out exactly the same way.
    /// Marking `hasPlayedFuseWarning` up front stops that shared code from
    /// trying to switch pulses again partway through.
    ///
    /// A no-op for anything not a dormant sensor -- any kind, or a sensor
    /// that's already armed -- so GameManager can call this unconditionally
    /// from both the player-proximity check and a neighboring sensor's
    /// detonation without first checking whether this bomb needs it.
    func arm() {
        guard kind == .sensor, fuseRemaining == nil else { return }
        fuseRemaining = Bomb.sensorFuseDuration
        hasPlayedFuseWarning = true
        node.run(Bomb.pulseAction(scale: 1.35, duration: 0.15), withKey: Bomb.pulseActionKey)
        vicinityIndicator?.strokeColor = Bomb.strokeColor(for: .sensor).withAlphaComponent(0.75)
        vicinityIndicator?.lineWidth = 2.5
    }

    /// `.barrel`-only: triggered externally by a `.sensor` detonating within
    /// its vicinity -- there's no player-safe way to set one off yet
    /// (pushing it is planned, not implemented, hence it's still lethal to
    /// touch directly like any other bomb). Marks this bomb for removal and
    /// flashes its entire row and column. GameManager separately checks that
    /// same row/column against the snake's head, since Bomb doesn't know
    /// about the snake.
    func explodeBarrel(columns: Int, rows: Int, scene: SKScene) {
        guard kind == .barrel, !isExpired else { return }
        isExpired = true
        node.removeAllActions()
        node.run(.sequence([.scale(to: 1.6, duration: 0.15), .fadeOut(withDuration: 0.15), .removeFromParent()]))

        for x in 0..<columns {
            addBlastFlash(at: GridPoint(x: x, y: position.y), scene: scene)
        }
        for y in 0..<rows {
            addBlastFlash(at: GridPoint(x: position.x, y: y), scene: scene)
        }
    }

    /// One brief cross-blast tile, standalone from this Bomb -- it has no
    /// gameplay effect of its own (GameManager does the actual head-hit
    /// check once, against the row/column, not per tile) and just fades
    /// itself out.
    private func addBlastFlash(at point: GridPoint, scene: SKScene) {
        let flash = SKShapeNode(rectOf: CGSize(width: cellSize - 2, height: cellSize - 2))
        flash.fillColor = Bomb.strokeColor(for: .barrel).withAlphaComponent(0.5)
        flash.strokeColor = .clear
        flash.position = GridGeometry.position(for: point, cellSize: cellSize, origin: origin)
        flash.zPosition = -1
        scene.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    /// Advances this bomb's own fuse/movement by `delta` real seconds --
    /// called unconditionally every frame (like the bomb-eater timer), so
    /// neither is tied to (or sped up by) the snake's own move interval.
    /// A no-op for `.mine`. `columns`/`rows`/`occupied` are only used by
    /// `.drifter` to find a legal next cell.
    func update(delta: TimeInterval, columns: Int, rows: Int, avoiding occupied: [GridPoint]) {
        updateFuse(delta: delta)
        updateDrift(delta: delta, columns: columns, rows: rows, avoiding: occupied)
    }

    private func updateFuse(delta: TimeInterval) {
        guard let remaining = fuseRemaining else { return }
        fuseRemaining = remaining - delta

        if fuseRemaining! <= 0 {
            isExpired = true
            node.removeAllActions()
            node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            vicinityIndicator?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            return
        }

        if fuseRemaining! <= Bomb.fuseWarningThreshold && !hasPlayedFuseWarning {
            hasPlayedFuseWarning = true
            node.run(Bomb.pulseAction(scale: 1.35, duration: 0.15), withKey: Bomb.pulseActionKey)
        }
    }

    private func updateDrift(delta: TimeInterval, columns: Int, rows: Int, avoiding occupied: [GridPoint]) {
        guard let remaining = timeUntilNextDrift else { return }
        guard remaining - delta <= 0 else {
            timeUntilNextDrift = remaining - delta
            return
        }
        timeUntilNextDrift = Bomb.driftInterval
        step(columns: columns, rows: rows, avoiding: occupied)
    }

    /// Steps to one random open neighboring cell, wrapping at the grid's
    /// edges the same way the snake does. Stays put for this cycle if every
    /// neighbor is occupied.
    private func step(columns: Int, rows: Int, avoiding occupied: [GridPoint]) {
        let directions: [Direction] = [.up, .down, .left, .right]
        for direction in directions.shuffled() {
            let vector = direction.vector
            var next = GridPoint(x: position.x + vector.dx, y: position.y + vector.dy)
            next.x = (next.x + columns) % columns
            next.y = (next.y + rows) % rows
            guard !occupied.contains(next) else { continue }

            position = next
            node.run(.move(to: GridGeometry.position(for: next, cellSize: cellSize, origin: origin), duration: Bomb.driftInterval * 0.6))
            return
        }
    }
}
