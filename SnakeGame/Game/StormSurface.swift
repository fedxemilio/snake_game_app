import SpriteKit
import UIKit

/// The top of a stage that reaches the surface (the Shallows): a storm sky over the
/// sky rows, waves rolling along the waterline, rain, and lightning. Purely for
/// show; the sky rows are walls as far as gameplay goes (see `AdventureStage.sky`).
///
/// The lightning is a pure function of `AmbientClock` (`lightning(at:)`), so the
/// game's water can be lit by the same flashes (`GameScene` reads it through
/// `GameManager`). Under Reduce Motion the rain is left out and the storm holds
/// still, with no lightning.
final class StormSurface {
    private static let period = 6.5
    private static let cloudCount = 10

    private let cellSize: CGFloat
    private let left: CGFloat
    private let width: CGFloat
    private let waterlineY: CGFloat
    private let skyHeight: CGFloat
    private let isAnimated = !UIAccessibility.isReduceMotionEnabled

    private let container = SKNode()
    private let skyFlash: SKSpriteNode
    private let bolt: SKSpriteNode
    private let bolts: [SKTexture]
    private let waves = SKNode()
    private let waveLength: CGFloat
    private var clouds: [(node: SKSpriteNode, startX: CGFloat, speed: CGFloat)] = []

    private static let cloudColor = SKColor(red: 0.16, green: 0.2, blue: 0.26, alpha: 1)
    private static let litCloudColor = SKColor(red: 0.62, green: 0.7, blue: 0.82, alpha: 1)

    /// - Parameter waterline: the lowest sky row; everything from it up is sky.
    init(waterline: Int, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        self.cellSize = cellSize
        left = origin.x
        width = CGFloat(columns) * cellSize
        waterlineY = origin.y + CGFloat(waterline) * cellSize
        skyHeight = CGFloat(rows - waterline) * cellSize
        let middle = CGPoint(x: left + width / 2, y: waterlineY + skyHeight / 2)

        let sky = SKSpriteNode(texture: SpriteArt.stormSky(height: skyHeight))
        sky.size = CGSize(width: width, height: skyHeight)
        sky.position = middle
        sky.zPosition = -3
        container.addChild(sky)

        // Low, heavy clouds, drifting.
        for index in 0..<Self.cloudCount {
            let cloud = SKSpriteNode(texture: SpriteArt.inkCloud(cellSize: cellSize))
            cloud.color = Self.cloudColor
            cloud.colorBlendFactor = 1
            cloud.alpha = 0.75
            cloud.xScale = 2.4 + 1.6 * CGFloat(AmbientClock.random(index, salt: 41))
            cloud.yScale = 0.9 + 0.5 * CGFloat(AmbientClock.random(index, salt: 42))
            cloud.position.y = waterlineY + skyHeight * (0.55 + 0.4 * CGFloat(AmbientClock.random(index, salt: 43)))
            cloud.zPosition = -2.95
            container.addChild(cloud)
            clouds.append((cloud, width * CGFloat(AmbientClock.random(index, salt: 44)),
                           cellSize * (0.25 + 0.35 * CGFloat(AmbientClock.random(index, salt: 45)))))
        }

        bolts = (0..<2).map { SpriteArt.lightningBolt(cellSize: cellSize, variant: $0) }
        bolt = SKSpriteNode(texture: bolts[0])
        bolt.anchorPoint = CGPoint(x: 0.5, y: 0)
        bolt.setScale(skyHeight / bolt.size.height)
        bolt.position.y = waterlineY
        bolt.blendMode = .add
        bolt.zPosition = -2.9
        bolt.isHidden = true
        container.addChild(bolt)

        skyFlash = SKSpriteNode(color: SKColor(red: 0.7, green: 0.8, blue: 1, alpha: 1), size: sky.size)
        skyFlash.position = middle
        skyFlash.blendMode = .add
        skyFlash.alpha = 0
        skyFlash.zPosition = -2.85
        container.addChild(skyFlash)

        // Waves along the waterline, over the galleon's hull so they lap at it.
        let tile = SpriteArt.surfaceWaves(cellSize: cellSize)
        waveLength = tile.size().width
        let count = Int((width / waveLength).rounded(.up)) + 2
        for index in -1..<count {
            let wave = SKSpriteNode(texture: tile)
            wave.anchorPoint = CGPoint(x: 0, y: 0.5)
            wave.position = CGPoint(x: left + CGFloat(index) * waveLength, y: waterlineY)
            waves.addChild(wave)
        }
        waves.zPosition = 3
        container.addChild(waves)

        if isAnimated {
            container.addChild(rain())
        }
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
    }

    func removeFromScene() {
        container.removeFromParent()
    }

    /// How bright the lightning is at `time` (`AmbientClock` seconds), 0...1: most
    /// `period`s bring a strike, a flicker with a fainter echo just after.
    func lightning(at time: Double) -> Double {
        guard isAnimated else { return 0 }
        let cycle = Int((time / Self.period).rounded(.down))
        guard AmbientClock.random(cycle, salt: 31) > 0.2 else { return 0 }
        let strikeAt = 0.5 + 5 * AmbientClock.random(cycle, salt: 32)
        let age = time - Double(cycle) * Self.period - strikeAt
        guard age >= 0 else { return 0 }
        let flicker = exp(-age / 0.07)
        let echo = age > 0.14 ? 0.8 * exp(-(age - 0.14) / 0.12) : 0
        return min(1, flicker + echo)
    }

    /// Poses the storm for `time`: clouds drifting, waves rolling, and lightning,
    /// which strikes somewhere around `focus` (the snake's head, in scene
    /// coordinates) so it's seen.
    func animate(time: Double, focus: CGPoint) {
        let flash = lightning(at: time)
        skyFlash.alpha = 0.3 * CGFloat(flash)

        let cycle = Int((time / Self.period).rounded(.down))
        bolt.isHidden = flash < 0.2
        if !bolt.isHidden {
            bolt.texture = bolts[AmbientClock.random(cycle, salt: 33) > 0.5 ? 1 : 0]
            bolt.alpha = CGFloat(flash)
            bolt.xScale = abs(bolt.xScale) * (AmbientClock.random(cycle, salt: 34) > 0.5 ? 1 : -1)
            bolt.position.x = focus.x + cellSize * 7 * CGFloat(2 * AmbientClock.random(cycle, salt: 35) - 1)
        }

        let drift = isAnimated ? time : AmbientClock.still
        let span = width + cellSize * 10
        for cloud in clouds {
            let x = (cloud.startX + CGFloat(drift) * cloud.speed).truncatingRemainder(dividingBy: span)
            cloud.node.position.x = left + x - cellSize * 5
            cloud.node.color = Self.cloudColor.mixed(with: Self.litCloudColor, by: CGFloat(flash))
        }
        waves.position = CGPoint(
            x: -(CGFloat(drift) * cellSize * 0.9).truncatingRemainder(dividingBy: waveLength),
            y: cellSize * 0.05 * CGFloat(sin(drift * 1.5))
        )
    }

    /// Rain over the whole map, slanting a little, falling only as far as the water.
    private func rain() -> SKEmitterNode {
        let slant: CGFloat = 0.22
        let speed: CGFloat = 640
        let rain = SKEmitterNode()
        rain.particleTexture = SpriteArt.rainStreak()
        rain.position = CGPoint(x: left + width / 2, y: waterlineY + skyHeight)
        rain.particlePositionRange = CGVector(dx: width + cellSize * 4, dy: 0)
        rain.emissionAngle = -.pi / 2 - slant
        rain.particleRotation = -slant
        rain.particleSpeed = speed
        rain.particleBirthRate = width * 0.45
        rain.particleLifetime = skyHeight / (speed * cos(slant))
        rain.particleAlpha = 0.3
        rain.particleAlphaRange = 0.15
        rain.particleScale = 0.8
        rain.particleScaleRange = 0.3
        rain.particleColor = SKColor(named: "Foam") ?? .white
        rain.particleColorBlendFactor = 1
        rain.zPosition = -2.5
        rain.advanceSimulationTime(1)
        return rain
    }
}

