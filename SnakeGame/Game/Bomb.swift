import SpriteKit

/// A permanent hazard: once placed it never relocates or expires. Running
/// the snake's head into one is a loss. Visually pulses/glows so it reads
/// as distinct from Food and PowerUp even though the base palette is
/// similar — a "mine" rather than a collectible.
final class Bomb {
    let position: GridPoint

    private let node: SKShapeNode

    init(position: GridPoint, cellSize: CGFloat, origin: CGPoint) {
        self.position = position

        let radius = (cellSize - 4) / 2
        node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = SKColor(white: 0.15, alpha: 1)
        node.strokeColor = .systemRed
        node.lineWidth = 2
        node.glowWidth = 6
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)

        let pulseOut = SKAction.scale(to: 1.2, duration: 0.6)
        pulseOut.timingMode = .easeInEaseOut
        let pulseIn = SKAction.scale(to: 1.0, duration: 0.6)
        pulseIn.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([pulseOut, pulseIn])))
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }
}
