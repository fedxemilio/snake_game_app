import SpriteKit

/// A one-node SpriteKit scene that fills the start menu with `AbyssWaterNode` at full
/// energy, plus `LivingSea.lightning(at:)` flashes overhead.
///
/// Driven by `AmbientClock`, not SpriteKit's own time, so it agrees with the rest of
/// the menu.
final class AbyssWaterScene: SKScene {
    private let water = AbyssWaterNode(energy: 1)

    override init(size: CGSize = CGSize(width: 1, height: 1)) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero
        addChild(water)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        water.size = size
    }

    override func update(_ currentTime: TimeInterval) {
        let time = AmbientClock.seconds(at: Date())
        water.update(time: time, flash: LivingSea.lightning(at: time))
    }
}
