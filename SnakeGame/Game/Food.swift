import SpriteKit

/// Owns the food's own position and its own node, same shape as `Snake`. Drawn as
/// a glowing mango-colored fruit (`SpriteArt.fruit`), gently pulsing.
final class Food {
    private(set) var position: GridPoint

    private let node: SKSpriteNode
    private let cellSize: CGFloat
    private let origin: CGPoint

    init(columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint, avoiding occupied: [GridPoint]) {
        self.cellSize = cellSize
        self.origin = origin
        self.position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        node = SKSpriteNode(texture: SpriteArt.fruit(cellSize: cellSize))
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)

        let swell = SKAction.scale(to: 1.12, duration: 0.9)
        swell.timingMode = .easeInEaseOut
        let settle = SKAction.scale(to: 1.0, duration: 0.9)
        settle.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([swell, settle])))
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
