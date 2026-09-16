import SpriteKit

/// A rare, independent spawn that doesn't do anything yet — just a visual
/// placeholder (distinct color from Food) for whatever effect gets attached
/// later. GameManager decides when to spawn/despawn it; PowerUp itself only
/// knows its own position and node, same shape as Food.
final class PowerUp {
    private(set) var position: GridPoint

    private let node: SKShapeNode

    init(columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint, avoiding occupied: [GridPoint]) {
        position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        node = SKShapeNode(circleOfRadius: (cellSize - 4) / 2)
        node.fillColor = .systemYellow
        node.strokeColor = .clear
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }
}
