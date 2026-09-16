import SpriteKit

/// Owns the food's own position and its own node, same shape as `Snake`.
final class Food {
    private(set) var position: GridPoint

    private let node: SKShapeNode
    private let cellSize: CGFloat
    private let origin: CGPoint

    init(columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint, avoiding occupied: [GridPoint]) {
        self.cellSize = cellSize
        self.origin = origin
        self.position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        node = SKShapeNode(circleOfRadius: (cellSize - 4) / 2)
        node.fillColor = .systemRed
        node.strokeColor = .clear
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }

    func relocate(columns: Int, rows: Int, avoiding occupied: [GridPoint]) {
        position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
    }
}
