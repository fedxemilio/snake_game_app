import SpriteKit

/// One of the kraken's tentacle attacks, start to finish:
///
/// 1. **Warning** (`warningDuration`): a 9x9 patch of water glows red, in the same
///    transparent, outline-free style as a sensor bomb's blast area, flashing faster
///    and faster as the strike nears.
/// 2. **Strike**: a tentacle bursts up out of the patch's middle with a splash
///    (`emergeDuration`), sweeps once all the way around it (`sweepDuration`)...
/// 3. **Retract** (`retractDuration`): ...and sinks back under as the glow fades.
///
/// The patch is dangerous only while the tentacle is up (`isLethal`), and the whole
/// patch counts, not just where the tentacle happens to be drawn. `Kraken` decides
/// where and when strikes happen; `GameManager` decides what a hit means.
final class TentacleStrike {
    static let zoneSize = 9

    /// How long the patch glows before the tentacle comes up. `GameManager` leads
    /// its aim by this much, so strikes land where the snake is headed.
    static let warningDuration: TimeInterval = 2.0
    private static let emergeDuration: TimeInterval = 0.25
    private static let sweepDuration: TimeInterval = 0.95
    private static let retractDuration: TimeInterval = 0.4

    private static let strikeStart = warningDuration
    private static let sweepStart = strikeStart + emergeDuration
    private static let retractStart = sweepStart + sweepDuration
    private static let end = retractStart + retractDuration

    private static let warningColor = SKColor(red: 1.0, green: 0.22, blue: 0.22, alpha: 1)
    private static let tentacleLinks = 30
    /// Length of the fully extended tentacle, in cells: most of the way to the edge
    /// of the patch.
    private static let tentacleLength: CGFloat = 4.1

    /// Holds everything this strike draws, in scene coordinates.
    let node = SKNode()

    private let corner: GridPoint
    private let cellSize: CGFloat
    private let center: CGPoint
    private let zone: SKShapeNode
    private let tentacle: TentacleChain
    /// Which way the tentacle points as it comes up, and which way it sweeps.
    private let startAngle = CGFloat.random(in: 0..<(2 * .pi))
    private let spin: CGFloat = Bool.random() ? 1 : -1

    private var age: TimeInterval = 0
    private var hasSplashedUp = false
    private var hasSplashedDown = false

    /// True while the tentacle is up: from the moment it breaks the surface until
    /// it starts to sink.
    var isLethal: Bool { age >= Self.strikeStart && age < Self.retractStart }
    var isFinished: Bool { age >= Self.end }

    /// - Parameter corner: the patch's bottom-left cell.
    init(corner: GridPoint, cellSize: CGFloat, origin: CGPoint) {
        self.corner = corner
        self.cellSize = cellSize

        let side = CGFloat(Self.zoneSize)
        let cornerCenter = GridGeometry.position(for: corner, cellSize: cellSize, origin: origin)
        center = CGPoint(x: cornerCenter.x + (side - 1) * cellSize / 2, y: cornerCenter.y + (side - 1) * cellSize / 2)

        zone = SKShapeNode(rectOf: CGSize(width: side * cellSize - 2, height: side * cellSize - 2), cornerRadius: cellSize * 0.3)
        zone.fillColor = Self.warningColor.withAlphaComponent(0)
        zone.strokeColor = .clear
        zone.position = center
        zone.zPosition = -1
        node.addChild(zone)

        tentacle = TentacleChain(links: Self.tentacleLinks, cellSize: cellSize)
        tentacle.node.position = center
        tentacle.node.zPosition = 5
        tentacle.node.isHidden = true
        node.addChild(tentacle.node)
    }

    func covers(_ point: GridPoint) -> Bool {
        let size = Self.zoneSize
        return point.x >= corner.x && point.x < corner.x + size && point.y >= corner.y && point.y < corner.y + size
    }

    /// Advances the strike by `delta` real seconds.
    func update(delta: TimeInterval) {
        age += delta
        if !hasSplashedUp && age >= Self.strikeStart {
            hasSplashedUp = true
            splash(size: 1)
        }
        if !hasSplashedDown && age >= Self.retractStart + Self.retractDuration * 0.6 {
            hasSplashedDown = true
            splash(size: 0.7)
        }
    }

    /// Cuts the strike short (the kraken was defeated): a warning just goes away,
    /// and a tentacle that's already up sinks straight back under.
    func cancel() {
        if age < Self.strikeStart {
            age = Self.end
        } else if age < Self.retractStart {
            age = Self.retractStart
        }
    }

    /// Redraws the glow and the tentacle for the current moment. `time` drives
    /// only the tentacle's wriggle; everything else follows the strike's own age.
    func animate(time: Double) {
        zone.fillColor = Self.warningColor.withAlphaComponent(zoneAlpha())
        poseTentacle(time: time)
    }

    private func zoneAlpha() -> CGFloat {
        if age < Self.strikeStart {
            // Flashing faster and faster: about 1.6 flashes a second at first,
            // over 7 by the time the tentacle comes up. Red over the teal water
            // mixes toward grey at low strength, so even the dimmest part of a
            // flash stays strong enough to read as red.
            let flash = 0.5 + 0.5 * sin(2 * .pi * (1.6 * age + 1.4 * age * age))
            let fadeIn = min(1, age / 0.25)
            return CGFloat(fadeIn * (0.2 + 0.2 * flash))
        }
        if age < Self.retractStart {
            return 0.38
        }
        let progress = (age - Self.retractStart) / Self.retractDuration
        return CGFloat(0.38 * max(0, 1 - progress))
    }

    private func poseTentacle(time: Double) {
        let reach: CGFloat
        let sweep: Double
        // How fast it's swinging right now, 0...1: bends the arm back against the swing.
        var swing = 0.0

        if age < Self.strikeStart {
            tentacle.node.isHidden = true
            return
        } else if age < Self.sweepStart {
            reach = CGFloat(Self.easeOutBack((age - Self.strikeStart) / Self.emergeDuration))
            sweep = 0
        } else if age < Self.retractStart {
            let progress = (age - Self.sweepStart) / Self.sweepDuration
            reach = 1
            sweep = progress * progress * (3 - 2 * progress)
            swing = 4 * progress * (1 - progress)
        } else {
            let progress = min(1, (age - Self.retractStart) / Self.retractDuration)
            reach = CGFloat(1 - progress * progress)
            sweep = 1
        }

        guard reach > 0.01 else {
            tentacle.node.isHidden = true
            return
        }
        tentacle.node.isHidden = false

        let count = Self.tentacleLinks
        let step = Self.tentacleLength * cellSize * reach / CGFloat(count - 1)
        let spinDirection = Double(spin)
        var angle = startAngle + spin * CGFloat(2 * Double.pi * sweep)
        var point = CGPoint.zero
        var points: [CGPoint] = []
        var radii: [CGFloat] = []
        points.reserveCapacity(count)
        radii.reserveCapacity(count)

        for index in 0..<count {
            let along = Double(index) / Double(count - 1)
            points.append(point)
            radii.append(cellSize * (0.64 - 0.52 * CGFloat(along)) * (0.6 + 0.4 * reach))

            // Curvature, in radians over the arm's length: dragged back against the
            // swing, wriggling, and curling at the tip in the direction it sweeps.
            let lag = -spinDirection * 2.4 * swing * along
            let wriggle = 1.4 * sin(time * 7 - along * 6)
            let curl = spinDirection * 4 * along * along
            angle += CGFloat((lag + wriggle + curl) / Double(count - 1))
            point.x += cos(angle) * step
            point.y += sin(angle) * step
        }
        tentacle.layout(points: points, radii: radii)
    }

    /// A ring of foam and a spray of droplets where the tentacle breaks the surface.
    private func splash(size: CGFloat) {
        let ring = SKSpriteNode(texture: SpriteArt.splashRing(cellSize: cellSize))
        ring.position = center
        ring.zPosition = 5.5
        ring.setScale(0.3 * size)
        let spread = SKAction.scale(to: 2.4 * size, duration: 0.6)
        spread.timingMode = .easeOut
        ring.run(.sequence([.group([spread, .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        node.addChild(ring)

        let foam = SKColor(named: "Foam") ?? .white
        for index in 0..<9 {
            let droplet = SKSpriteNode(texture: SpriteArt.speck())
            droplet.color = foam
            droplet.colorBlendFactor = 1
            droplet.position = center
            droplet.zPosition = 5.6
            droplet.setScale(CGFloat.random(in: 0.6...1.3) * size)
            let angle = CGFloat(index) / 9 * 2 * .pi + .random(in: -0.3...0.3)
            let distance = cellSize * CGFloat.random(in: 0.9...1.9) * size
            let fling = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.5)
            fling.timingMode = .easeOut
            droplet.run(.sequence([.group([fling, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            node.addChild(droplet)
        }
    }

    private static func easeOutBack(_ progress: Double) -> Double {
        let overshoot = 1.70158
        let shifted = min(1, max(0, progress)) - 1
        return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
    }
}
