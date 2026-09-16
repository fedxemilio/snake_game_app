import SpriteKit

/// A rare, independent spawn. Comes in a few kinds (PowerUpKind), each its
/// own color; GameManager decides when to spawn/despawn it and applies
/// whatever effect the kind has.
final class PowerUp {
    let kind: PowerUpKind
    private(set) var position: GridPoint

    private let node: SKShapeNode

    init(kind: PowerUpKind, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint, avoiding occupied: [GridPoint]) {
        self.kind = kind
        position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        let color = PowerUp.color(for: kind)
        node = SKShapeNode(circleOfRadius: (cellSize - 4) / 2)
        node.fillColor = color
        node.strokeColor = color
        node.lineWidth = 1
        node.glowWidth = 6
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
        case .bombEater: return .systemPurple
        case .tailCutter: return .systemYellow
        case .speedCooler: return .systemCyan
        }
    }
}
