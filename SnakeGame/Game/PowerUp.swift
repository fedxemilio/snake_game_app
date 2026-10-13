import SpriteKit

/// A rare, independent spawn. Comes in a few kinds (PowerUpKind), each its
/// own color and symbol; GameManager decides when to spawn/despawn it and
/// applies whatever effect the kind has.
final class PowerUp {
    let kind: PowerUpKind
    private(set) var position: GridPoint

    private let node: SKSpriteNode

    init(kind: PowerUpKind, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint, avoiding occupied: [GridPoint]) {
        self.kind = kind
        position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        node = SKSpriteNode(texture: SpriteArt.powerUpOrb(color: PowerUp.color(for: kind), symbol: PowerUp.symbol(for: kind), cellSize: cellSize))
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)

        let floatDistance = cellSize * 0.18
        let floatUp = SKAction.moveBy(x: 0, y: floatDistance, duration: 0.7)
        floatUp.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([floatUp, floatUp.reversed()])))
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }

    /// Not private: GameManager reuses this to tint the snake to match
    /// while a bomb-eater is active, instead of duplicating the palette.
    static func color(for kind: PowerUpKind) -> SKColor {
        switch kind {
        case .bombEater: return SKColor(red: 0.66, green: 0.48, blue: 1.0, alpha: 1)
        case .tailCutter: return SKColor(red: 1.0, green: 0.8, blue: 0.36, alpha: 1)
        case .speedCooler: return SKColor(red: 0.42, green: 0.88, blue: 1.0, alpha: 1)
        }
    }

    /// The SF Symbol on the orb's face: what the kind does, not just its color.
    private static func symbol(for kind: PowerUpKind) -> String {
        switch kind {
        case .bombEater: return "shield.fill"
        case .tailCutter: return "scissors"
        case .speedCooler: return "snowflake"
        }
    }
}
