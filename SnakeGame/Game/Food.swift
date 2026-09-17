import SpriteKit
import UIKit

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

        let diameter = cellSize - 4
        node = SKShapeNode(circleOfRadius: diameter / 2)
        // fillTexture is tinted (multiplied) by fillColor, so this needs to
        // be white for the gradient's own colors to show through untouched.
        node.fillColor = .white
        node.fillTexture = Food.mangoGradientTexture(diameter: diameter)
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

    /// Red-ish to orange-ish, diagonal -- a small one-off render, cheap
    /// enough to redo per instance (Food is only created on eat/relocate,
    /// never per frame).
    private static func mangoGradientTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [UIColor.systemRed.cgColor, UIColor.systemOrange.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
                return
            }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }
}
