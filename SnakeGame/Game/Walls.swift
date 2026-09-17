import SpriteKit

/// Static for the lifetime of a level -- unlike Snake/Food/Bomb there's no
/// per-tick movement or reuse logic needed, just draw once and remove on
/// level change/restart.
final class Walls {
    let positions: Set<GridPoint>
    private let container = SKNode()

    init(positions: Set<GridPoint>, cellSize: CGFloat, origin: CGPoint) {
        self.positions = positions

        for point in positions {
            let node = SKShapeNode(rectOf: CGSize(width: cellSize, height: cellSize))
            node.fillColor = SKColor(white: 0.5, alpha: 1)
            node.strokeColor = SKColor(white: 0.7, alpha: 1)
            node.lineWidth = 1
            node.position = GridGeometry.position(for: point, cellSize: cellSize, origin: origin)
            container.addChild(node)
        }
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(container)
    }

    func removeFromScene() {
        container.removeFromParent()
    }

    func contains(_ point: GridPoint) -> Bool {
        positions.contains(point)
    }
}
