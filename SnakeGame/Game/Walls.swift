import SpriteKit

/// Static for the lifetime of a level -- unlike Snake/Food/Bomb there's no
/// per-tick movement or reuse logic needed, just draw once and remove on
/// level change/restart.
final class Walls {
    let positions: Set<GridPoint>
    private let container = SKNode()

    /// - Parameter drawn: the cells to draw as rock, if not all of them. The rest
    ///   (Adventure's sky above the surface) block just the same, and something
    ///   else draws them.
    init(positions: Set<GridPoint>, cellSize: CGFloat, origin: CGPoint, drawn: Set<GridPoint>? = nil) {
        self.positions = positions

        // Reef rock, in a few variants picked by position so the same wall always
        // looks the same. All cells share those few textures, so even Adventure's
        // hundreds of wall cells draw cheaply.
        for point in drawn ?? positions {
            let variant = abs(point.x &* 73_856_093 ^ point.y &* 19_349_663) % SpriteArt.reefVariants
            let node = SKSpriteNode(texture: SpriteArt.reefRock(cellSize: cellSize, variant: variant))
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
