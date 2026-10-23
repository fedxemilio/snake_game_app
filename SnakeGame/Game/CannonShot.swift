import SpriteKit

/// One of the galleon's cannon shots, start to finish:
///
/// 1. **Fired**: a flash and a puff of smoke at one of the galleon's gun ports, and
///    the 3x3 patch of water around where it'll land starts glowing red, in the same
///    transparent, outline-free style as the kraken's strikes, flashing faster as it
///    nears.
/// 2. The ball arcs out over the water (`flightDuration`), plunges in with a splash
///    and sinks straight down its column to the middle of the patch.
/// 3. **Lands**, `warningDuration` after it was fired: the patch flares. That moment
///    is the only one it hurts, anywhere in the patch, and only the head counts.
///    `GameManager` resolves it, and says whether the ball comes to rest there as a
///    `Cannonball` the snake can push (`settle(keepingBall:)`) or breaks up.
///
/// Everything follows the shot's own age, which only advances while the game runs,
/// so a shot in flight when the run ends hangs there behind the overlay. `Galleon`
/// decides where and when shots are fired.
final class CannonShot {
    /// From firing to landing. `GameManager` leads its aim by this much, so shots
    /// land where the snake is headed.
    static let warningDuration: TimeInterval = 1.8
    private static let flightDuration: TimeInterval = 0.55
    private static let fadeDuration: TimeInterval = 0.45
    private static let end = warningDuration + fadeDuration

    private static let warningColor = SKColor(red: 1.0, green: 0.22, blue: 0.22, alpha: 1)
    private static let blastColor = SKColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1)

    /// The cell it lands in, the middle of its patch.
    let target: GridPoint
    /// Holds everything this shot draws, in scene coordinates.
    let node = SKNode()

    private let cellSize: CGFloat
    private let muzzle: CGPoint
    /// Where it hits the water, straight above `landing`.
    private let entry: CGPoint
    private let landing: CGPoint
    /// The arc's control point, above the water between the gun and `entry`.
    private let peak: CGPoint
    private let zone: SKShapeNode
    private let ball: SKSpriteNode

    /// Negative while it waits its turn in a volley.
    private var age: TimeInterval
    private var hasFired = false
    private var hasSplashed = false
    private var timeSinceBubble: TimeInterval = 0
    /// Set once it's landed, or been called off: either way, it has nothing left to
    /// report.
    private var isSpent = false

    var isFinished: Bool { age >= Self.end }

    /// - Parameters:
    ///   - muzzle: the gun port it's fired from, in scene coordinates.
    ///   - waterlineY: the surface, in scene coordinates.
    ///   - delay: how long it waits to fire, so a volley goes off gun by gun.
    init(target: GridPoint, from muzzle: CGPoint, waterlineY: CGFloat, delay: TimeInterval, cellSize: CGFloat, origin: CGPoint) {
        self.target = target
        self.muzzle = muzzle
        self.cellSize = cellSize
        age = -delay

        landing = GridGeometry.position(for: target, cellSize: cellSize, origin: origin)
        entry = CGPoint(x: landing.x, y: waterlineY)
        let rise = cellSize * (1.5 + 0.08 * abs(entry.x - muzzle.x) / cellSize)
        peak = CGPoint(x: (muzzle.x + entry.x) / 2, y: max(muzzle.y, entry.y) + rise)

        zone = SKShapeNode(rectOf: CGSize(width: cellSize * 3 - 2, height: cellSize * 3 - 2), cornerRadius: cellSize * 0.3)
        zone.fillColor = Self.warningColor.withAlphaComponent(0)
        zone.strokeColor = .clear
        zone.position = landing
        zone.zPosition = -1
        node.addChild(zone)

        ball = SKSpriteNode(texture: SpriteArt.cannonball(cellSize: cellSize))
        ball.zPosition = 4
        ball.isHidden = true
        node.addChild(ball)
    }

    /// Whether `point` is in its 3x3 patch.
    func covers(_ point: GridPoint) -> Bool {
        abs(point.x - target.x) <= 1 && abs(point.y - target.y) <= 1
    }

    /// Advances the shot by `delta` real seconds. Returns true the moment it lands,
    /// once.
    func update(delta: TimeInterval) -> Bool {
        age += delta
        zone.fillColor = Self.warningColor.withAlphaComponent(zoneAlpha())
        guard age >= 0, !isSpent else { return false }

        if !hasFired {
            hasFired = true
            fire()
        }

        if age < Self.flightDuration {
            ball.position = arc(at: CGFloat(age / Self.flightDuration))
            ball.zRotation -= CGFloat(delta) * 9
            return false
        }
        if !hasSplashed {
            hasSplashed = true
            BoardEffects.splash(at: entry, size: 0.6, cellSize: cellSize, in: effects)
        }

        if age < Self.warningDuration {
            // Gathering speed as it sinks, trailing bubbles.
            let progress = (age - Self.flightDuration) / (Self.warningDuration - Self.flightDuration)
            let eased = CGFloat(0.25 * progress + 0.75 * progress * progress)
            ball.position = CGPoint(x: entry.x, y: entry.y + (landing.y - entry.y) * eased)
            timeSinceBubble += delta
            if timeSinceBubble > 0.08 {
                timeSinceBubble = 0
                BoardEffects.bubbleBurst(at: ball.position, count: 1, cellSize: cellSize, in: effects)
            }
            return false
        }

        isSpent = true
        ball.position = landing
        BoardEffects.sensorBlast(at: landing, color: Self.blastColor, cellSize: cellSize, in: effects)
        return true
    }

    /// After it's landed: the ball either stays (`GameManager` has put a cannonball
    /// in its place, so this one just goes) or breaks up into bubbles.
    func settle(keepingBall: Bool) {
        if keepingBall {
            ball.removeFromParent()
        } else {
            BoardEffects.bubbleBurst(at: landing, count: 6, cellSize: cellSize, in: effects)
            ball.run(.group([.fadeOut(withDuration: 0.3), .scale(to: 0.5, duration: 0.3)]))
        }
    }

    /// Calls the shot off (the galleon's sunk): the warning fades, and a ball on
    /// its way fades out where it is.
    func cancel() {
        guard !isSpent else { return }
        isSpent = true
        age = max(age, Self.warningDuration)
        ball.run(.fadeOut(withDuration: 0.3))
    }

    // MARK: Drawing

    /// Effects outlive the shot, so they go beside it rather than in it.
    private var effects: SKNode { node.parent ?? node }

    private func fire() {
        ball.isHidden = false
        ball.position = muzzle

        let flash = SKSpriteNode(texture: SpriteArt.flare(cellSize: cellSize))
        flash.color = Self.blastColor
        flash.colorBlendFactor = 1
        flash.blendMode = .add
        flash.position = muzzle
        flash.zPosition = 5
        flash.setScale(0.3)
        flash.run(.sequence([.group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
        effects.addChild(flash)

        let smoke = SKSpriteNode(texture: SpriteArt.inkCloud(cellSize: cellSize))
        smoke.color = SKColor(red: 0.55, green: 0.6, blue: 0.64, alpha: 1)
        smoke.colorBlendFactor = 1
        smoke.alpha = 0.55
        smoke.position = muzzle
        smoke.zPosition = 4.5
        smoke.setScale(0.12)
        let billow = SKAction.group([
            .scale(to: 0.45, duration: 1.4),
            .moveBy(x: 0, y: cellSize * 0.8, duration: 1.4),
            .fadeOut(withDuration: 1.4),
        ])
        billow.timingMode = .easeOut
        smoke.run(.sequence([billow, .removeFromParent()]))
        effects.addChild(smoke)
    }

    /// The point `t` (0...1) of the way along its arc from the gun to the water.
    private func arc(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * muzzle.x + 2 * u * t * peak.x + t * t * entry.x,
            y: u * u * muzzle.y + 2 * u * t * peak.y + t * t * entry.y
        )
    }

    private func zoneAlpha() -> CGFloat {
        guard age >= 0 else { return 0 }
        if age < Self.warningDuration {
            // Flashing faster and faster as it comes, never so faint that red over
            // the teal water turns grey.
            let flash = 0.5 + 0.5 * sin(2 * .pi * (1.8 * age + 1.6 * age * age))
            let fadeIn = min(1, age / 0.2)
            return CGFloat(fadeIn * (0.2 + 0.2 * flash))
        }
        let progress = (age - Self.warningDuration) / Self.fadeDuration
        return CGFloat(0.4 * max(0, 1 - progress))
    }
}
