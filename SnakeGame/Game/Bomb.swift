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
/// rather than round, and not a hazard to touch at all: it's `Pushable`. The
/// snake walks it along a cell at a time in front of its head. Pushed onto
/// another bomb, it primes and goes off a moment later; a `.sensor` detonating within its
/// vicinity sets it off at once. Either way it blasts its entire row and
/// column.
enum BombKind {
    case mine
    case timed
    case drifter
    case sensor
    case barrel
}

/// A hazard: once placed, running the snake's head into one (without
/// bomb-eater active) costs a life. (Except `.barrel`, which the snake pushes
/// instead; see `Pushable`.) `.mine` never relocates or expires; see
/// `BombKind` for how `.timed` and `.drifter` differ. Drawn as a horned sea
/// mine with a light at its heart in its kind's color (`.barrel` is a banded
/// cask instead), and pulses, so it reads as a hazard rather than a
/// collectible.
final class Bomb {
    let kind: BombKind
    private(set) var position: GridPoint
    private(set) var isExpired = false

    private let node: SKSpriteNode
    private let cellSize: CGFloat
    private let origin: CGPoint

    /// `.sensor`-only: a faintly shaded square over the 3x3 area this bomb
    /// will hit, so its blast radius reads at a glance instead of
    /// being a surprise. Brightens once armed (see `arm()`). nil for every
    /// other kind.
    private let vicinityIndicator: SKShapeNode?

    /// Real seconds remaining before a `.timed` bomb expires -- ticked in
    /// `update(delta:...)`, independent of grid moves, like the bomb-eater
    /// timer. nil for kinds that don't have a fuse.
    private var fuseRemaining: TimeInterval?
    private var hasPlayedFuseWarning = false

    /// `.barrel`-only: the bomb it was pushed onto and is primed to go off with (see
    /// `prime(on:after:)`). nil while it's free to be pushed.
    private(set) weak var primedOn: Bomb?
    /// `.barrel`-only: its fuse has run out, and it's waiting for `GameManager` to
    /// set it off -- the blast hurts things only GameManager knows about.
    private(set) var hasFuseRunOut = false

    /// A barrel has been pushed onto this bomb and primed on it (see
    /// `prime(on:after:)`): it's spent, harmless to touch and won't arm, and goes
    /// off with the barrel.
    private(set) var isUnderBarrel = false

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

    /// How long a barrel blinks on top of the bomb it was pushed onto before it
    /// goes off. Short on purpose: getting the snake off that row or column in
    /// time is part of the puzzle.
    private static let barrelFuseDuration: TimeInterval = 1.2

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

        let texture: SKTexture
        switch kind {
        case .barrel:
            // Square is the one deliberate shape break -- every other kind
            // reads as a "mine" silhouette; barrel should look like a
            // different kind of object entirely.
            texture = SpriteArt.barrel(light: Bomb.lightColor(for: kind), cellSize: cellSize)
        case .mine, .timed, .drifter, .sensor:
            texture = SpriteArt.seaMine(light: Bomb.lightColor(for: kind), ringed: kind == .sensor, cellSize: cellSize)
        }
        node = SKSpriteNode(texture: texture)
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
        if kind == .barrel {
            // An object to push, not a hazard to avoid: it sits still (until
            // primed), and above any bomb it ends up on top of.
            node.zPosition = 0.5
        } else {
            node.run(Bomb.pulseAction(scale: Bomb.calmPulseScale, duration: 0.6), withKey: Bomb.pulseActionKey)
        }

        if kind == .sensor {
            let indicator = SKShapeNode(rectOf: CGSize(width: cellSize * 3 - 2, height: cellSize * 3 - 2), cornerRadius: cellSize * 0.3)
            // Shaded, no outline: a faint wash over the blast area reads clearly
            // without a hard edge competing with the board.
            indicator.fillColor = Bomb.lightColor(for: .sensor).withAlphaComponent(0.08)
            indicator.strokeColor = .clear
            indicator.position = node.position
            indicator.zPosition = -1
            vicinityIndicator = indicator
        } else {
            vicinityIndicator = nil
        }
    }

    /// The light at each kind's heart, which also tints its glow.
    private static func lightColor(for kind: BombKind) -> SKColor {
        switch kind {
        case .mine: return SKColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1)
        case .timed: return SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        case .drifter: return SKColor(red: 1.0, green: 0.42, blue: 0.72, alpha: 1)
        case .sensor: return SKColor(red: 0.5, green: 0.56, blue: 1.0, alpha: 1)
        case .barrel: return SKColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1)
        }
    }

    /// How far the slow, resting pulse swells, and the fast warning one. Kept
    /// modest: the mine's horns already reach most of the way across its cell.
    private static let calmPulseScale: CGFloat = 1.1
    private static let warningPulseScale: CGFloat = 1.25

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
        guard kind == .sensor, fuseRemaining == nil, !isUnderBarrel else { return }
        fuseRemaining = Bomb.sensorFuseDuration
        hasPlayedFuseWarning = true
        node.run(Bomb.pulseAction(scale: Bomb.warningPulseScale, duration: 0.15), withKey: Bomb.pulseActionKey)
        vicinityIndicator?.fillColor = Bomb.lightColor(for: .sensor).withAlphaComponent(0.2)
    }

    /// `.barrel`-only: set off by `GameManager`, either when a `.sensor`
    /// detonates within its vicinity or when its own fuse runs out after
    /// being pushed onto a bomb (`prime(on:after:)`). Marks this bomb for removal and
    /// blasts beams of light down its entire row and column
    /// (`BoardEffects.crossBlast`). GameManager separately checks that same
    /// row/column against the snake's head and the kraken, and sets off the
    /// bomb it was primed on, since Bomb doesn't know about any of those.
    func explodeBarrel(columns: Int, rows: Int, scene: SKScene) {
        guard kind == .barrel, !isExpired else { return }
        isExpired = true
        pop()

        let board = CGRect(x: origin.x, y: origin.y, width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
        BoardEffects.crossBlast(at: node.position, color: Bomb.lightColor(for: .barrel), cellSize: cellSize, board: board, in: scene)
    }

    /// Sets this bomb off where it sits -- the snake touched it, or a sensor's
    /// blast cleared it: it bursts and is gone, with an explosion in its color.
    /// `delay` staggers the bombs in a chain reaction. Purely visual: the caller
    /// has already dropped it from play, and the node removes itself once its
    /// animation is done (so don't also call `removeFromScene()`; see CLAUDE.md).
    func explode(in parent: SKNode, delay: TimeInterval = 0) {
        vicinityIndicator?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        pop(after: delay)
        BoardEffects.explosion(at: node.position, color: Bomb.lightColor(for: kind), cellSize: cellSize, delay: delay, in: parent)
    }

    /// A barrel that has been pushed onto another bomb (`trigger`): once its move
    /// is over (`delay`), it blinks hot for `barrelFuseDuration`, then its fuse has
    /// run out (`hasFuseRunOut`) and `GameManager` sets it off, taking `trigger`
    /// with it. From the moment it primes, neither is an obstacle or a hazard to
    /// touch (`isSolid`, `isUnderBarrel`). A no-op for anything but a free barrel.
    func prime(on trigger: Bomb, after delay: TimeInterval) {
        guard kind == .barrel, primedOn == nil, !isExpired else { return }
        primedOn = trigger
        trigger.isUnderBarrel = true
        fuseRemaining = delay + Bomb.barrelFuseDuration
        hasPlayedFuseWarning = true

        let hot = SKColor(red: 1.0, green: 0.35, blue: 0.2, alpha: 1)
        let blink = SKAction.sequence([
            .colorize(with: hot, colorBlendFactor: 0.85, duration: 0.07),
            .colorize(withColorBlendFactor: 0, duration: 0.07),
        ])
        node.run(.sequence([
            .wait(forDuration: delay),
            .group([.repeatForever(blink), Bomb.pulseAction(scale: Bomb.warningPulseScale, duration: 0.12)]),
        ]), withKey: Bomb.pulseActionKey)
    }

    /// The bomb itself bursting: a quick swell and fade, then it removes itself.
    private func pop(after delay: TimeInterval = 0) {
        node.removeAllActions()
        let burst = SKAction.group([.scale(to: 1.5, duration: 0.08), .fadeOut(withDuration: 0.12)])
        node.run(.sequence([.wait(forDuration: delay), burst, .removeFromParent()]))
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
            if kind == .barrel {
                fuseRemaining = nil
                hasFuseRunOut = true
                return
            }
            isExpired = true
            vicinityIndicator?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            if let parent = node.parent {
                if kind == .sensor {
                    // A real blast, filling the 3x3 area it hits.
                    BoardEffects.sensorBlast(at: node.position, color: Bomb.lightColor(for: kind), cellSize: cellSize, in: parent)
                } else {
                    // A timed bomb's fuse just runs out, harmlessly.
                    BoardEffects.fizzle(at: node.position, color: Bomb.lightColor(for: kind), cellSize: cellSize, in: parent)
                }
            }
            if kind == .sensor {
                pop()
            } else {
                node.removeAllActions()
                node.run(.sequence([.group([.fadeOut(withDuration: 0.3), .scale(to: 0.6, duration: 0.3)]), .removeFromParent()]))
            }
            return
        }

        if fuseRemaining! <= Bomb.fuseWarningThreshold && !hasPlayedFuseWarning {
            hasPlayedFuseWarning = true
            node.run(Bomb.pulseAction(scale: Bomb.warningPulseScale, duration: 0.15), withKey: Bomb.pulseActionKey)
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

extension Bomb: Pushable {
    /// Barrels step: the snake walks one along in front of its head.
    var pushStyle: PushStyle { .step }

    /// A barrel is solid until it's primed on a bomb: from then on the two are
    /// spent, and the snake can swim straight through that cell.
    var isSolid: Bool {
        kind == .barrel && primedOn == nil && !isExpired
    }

    var landsOnBombs: Bool { true }

    /// Steps over in about the time the snake takes to follow it.
    func move(to destination: GridPoint, cells: Int) -> TimeInterval {
        position = destination
        let duration = 0.12 * Double(cells)
        let step = SKAction.move(to: GridGeometry.position(for: destination, cellSize: cellSize, origin: origin), duration: duration)
        step.timingMode = .easeOut
        node.run(step, withKey: "slide")
        return duration
    }
}
