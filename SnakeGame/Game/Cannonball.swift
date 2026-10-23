import SpriteKit

/// A heavy iron ball the snake can shove: one push and it rolls off in that
/// direction until something stops it (see `Pushable` and
/// `GameManager.push(_:awayFrom:)`). Bombs stop it like anything else; it doesn't
/// set them off. Rolled into the moray or the galleon's hull, it hurts it and
/// breaks (`smash`). In the Shallows the galleon's own shot comes to rest as more
/// of them.
///
/// Owns its own position and node, like the board's other entities.
final class Cannonball: Pushable {
    private(set) var position: GridPoint

    private let node: SKSpriteNode
    private let cellSize: CGFloat
    private let origin: CGPoint

    init(position: GridPoint, cellSize: CGFloat, origin: CGPoint) {
        self.position = position
        self.cellSize = cellSize
        self.origin = origin
        node = SKSpriteNode(texture: SpriteArt.cannonball(cellSize: cellSize))
        node.position = GridGeometry.position(for: position, cellSize: cellSize, origin: origin)
        node.zPosition = 0.5
    }

    func addToScene(_ scene: SKScene) {
        scene.addChild(node)
    }

    func removeFromScene() {
        node.removeFromParent()
    }

    // MARK: Pushable

    var pushStyle: PushStyle { .roll }
    var isSolid: Bool { true }
    var landsOnBombs: Bool { false }

    /// Rolls there at about 25 cells a second, never taking more than half a
    /// second, spinning as it goes and leaving a few bubbles where it started.
    func move(to destination: GridPoint, cells: Int) -> TimeInterval {
        if let parent = node.parent {
            BoardEffects.bubbleBurst(at: node.position, count: 4, cellSize: cellSize, in: parent)
        }
        let from = position
        position = destination

        let duration = min(0.5, 0.04 * Double(cells))
        let roll = SKAction.move(to: GridGeometry.position(for: destination, cellSize: cellSize, origin: origin), duration: duration)
        roll.timingMode = .easeOut
        // Spin the way it's rolling: clockwise when heading right or up.
        let rightward = destination.x > from.x || destination.y > from.y
        let spin = SKAction.rotate(byAngle: (rightward ? -1 : 1) * CGFloat(cells) * 0.9, duration: duration)
        spin.timingMode = .easeOut
        node.run(.group([roll, spin]), withKey: "roll")
        return duration
    }

    /// Rolled into something it breaks against (the moray, the galleon's hull): rolls to
    /// `destination` as `move` would, then carries on along `heading` into it and is
    /// gone. Returns how long until it hits.
    func smash(rollingTo destination: GridPoint, cells: Int, heading: (dx: Int, dy: Int)) -> TimeInterval {
        let roll = move(to: destination, cells: cells)
        let thrust: TimeInterval = 0.06
        node.run(.sequence([
            .wait(forDuration: roll),
            .moveBy(x: CGFloat(heading.dx) * cellSize * 0.5, y: CGFloat(heading.dy) * cellSize * 0.5, duration: thrust),
            .removeFromParent(),
        ]))
        return roll + thrust
    }
}
