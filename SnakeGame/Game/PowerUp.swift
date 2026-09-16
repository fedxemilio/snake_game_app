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

        node = SKShapeNode(circleOfRadius: (cellSize - 4) / 2)
        node.fillColor = PowerUp.color(for: kind)
        node.strokeColor = .clear
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }

    private static func color(for kind: PowerUpKind) -> SKColor {
        switch kind {
        case .bombEater: return .systemPurple
        case .tailCutter: return .systemYellow
        case .speedCooler: return .systemCyan
        }
    }
}
