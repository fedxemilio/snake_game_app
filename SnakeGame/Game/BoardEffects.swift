import SpriteKit

/// One-shot effects on the board: explosions, small impacts, a sensor's blast
/// filling its area, a barrel's cross-shaped blast, bursts of bubbles. Each adds a
/// short-lived node to `parent` (positioned in `parent`'s coordinates) that animates
/// and removes itself.
///
/// None of them touch gameplay: by the time one plays, whatever it shows has
/// already been decided. All drawing is `SpriteArt` textures on sprites (additive
/// where it's light), so even a chain reaction stays cheap.
enum BoardEffects {
    /// A bomb going off: a white-hot flash, light thrown on the water around it, a
    /// shockwave, scraps of casing and a stream of bubbles. `size` scales the whole
    /// thing; `delay` holds it back, so the explosions in a chain reaction read one
    /// after another.
    static func explosion(
        at point: CGPoint,
        color: SKColor,
        cellSize: CGFloat,
        size: CGFloat = 1,
        delay: TimeInterval = 0,
        in parent: SKNode
    ) {
        play(at: point, delay: delay, lifetime: 1.4, in: parent) { node in
            glow(color: color, cellSize: cellSize, from: 0.6 * size, to: 3.4 * size, alpha: 0.55, duration: 0.6, in: node)
            glow(color: .white, cellSize: cellSize, from: 0.3 * size, to: 1.5 * size, alpha: 1, duration: 0.28, in: node)
            ring(color: color, cellSize: cellSize, from: 0.2 * size, to: 2.6 * size, duration: 0.5, in: node)
            shards(count: 8, cellSize: cellSize, reach: 1.8 * size, in: node)
            bubbles(count: 8, cellSize: cellSize, spread: 0.6 * size, in: node)
        }
    }

    /// Something harmless running out (a timed bomb's fuse): a soft pop of light and
    /// a few bubbles, no shockwave, so it doesn't read as a blast.
    static func fizzle(at point: CGPoint, color: SKColor, cellSize: CGFloat, in parent: SKNode) {
        play(at: point, delay: 0, lifetime: 1.2, in: parent) { node in
            glow(color: color, cellSize: cellSize, from: 0.4, to: 1.2, alpha: 0.5, duration: 0.4, in: node)
            bubbles(count: 6, cellSize: cellSize, spread: 0.3, in: node)
        }
    }

    /// The snake getting hit: a quick flash in `color` and a puff of bubbles where
    /// it happened.
    static func impact(at point: CGPoint, color: SKColor, cellSize: CGFloat, in parent: SKNode) {
        play(at: point, delay: 0, lifetime: 1.2, in: parent) { node in
            glow(color: color, cellSize: cellSize, from: 0.4, to: 1.6, alpha: 0.8, duration: 0.35, in: node)
            ring(color: color, cellSize: cellSize, from: 0.2, to: 1.3, duration: 0.35, in: node)
            bubbles(count: 6, cellSize: cellSize, spread: 0.35, in: node)
        }
    }

    /// A sensor's blast filling its 3x3 area: the whole patch flares and fades,
    /// around an explosion at its middle.
    static func sensorBlast(at center: CGPoint, color: SKColor, cellSize: CGFloat, in parent: SKNode) {
        let patch = SKShapeNode(rectOf: CGSize(width: cellSize * 3 - 2, height: cellSize * 3 - 2), cornerRadius: cellSize * 0.3)
        patch.fillColor = color.withAlphaComponent(0.6)
        patch.strokeColor = .clear
        patch.blendMode = .add
        patch.position = center
        patch.zPosition = 5.9
        patch.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
        parent.addChild(patch)

        explosion(at: center, color: color, cellSize: cellSize, size: 1.2, in: parent)
    }

    /// A barrel's blast: beams of light down its whole row and column (across
    /// `board`, in `parent`'s coordinates), around an explosion at the barrel.
    static func crossBlast(at center: CGPoint, color: SKColor, cellSize: CGFloat, board: CGRect, in parent: SKNode) {
        let beams: [(position: CGPoint, length: CGFloat, angle: CGFloat)] = [
            (CGPoint(x: board.midX, y: center.y), board.width, 0),
            (CGPoint(x: center.x, y: board.midY), board.height, .pi / 2),
        ]
        for beam in beams {
            let sprite = SKSpriteNode(texture: SpriteArt.beam(cellSize: cellSize))
            sprite.color = color
            sprite.colorBlendFactor = 0.6
            sprite.blendMode = .add
            sprite.position = beam.position
            sprite.zRotation = beam.angle
            sprite.xScale = beam.length / cellSize
            sprite.yScale = 1.3
            sprite.zPosition = 5.9
            let narrow = SKAction.scaleY(to: 0.3, duration: 0.5)
            narrow.timingMode = .easeIn
            sprite.run(.sequence([.group([narrow, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            parent.addChild(sprite)
        }

        explosion(at: center, color: color, cellSize: cellSize, size: 1.4, in: parent)
    }

    /// Bubbles welling up from `point`: the snake coming apart.
    static func bubbleBurst(at point: CGPoint, count: Int, cellSize: CGFloat, in parent: SKNode) {
        play(at: point, delay: 0, lifetime: 1.4, in: parent) { node in
            bubbles(count: count, cellSize: cellSize, spread: 0.35, in: node)
        }
    }

    // MARK: Pieces

    /// Adds a holder node at `point`, builds the effect into it (after `delay`),
    /// and removes it once everything's had `lifetime` seconds to finish.
    private static func play(
        at point: CGPoint,
        delay: TimeInterval,
        lifetime: TimeInterval,
        in parent: SKNode,
        build: @escaping (SKNode) -> Void
    ) {
        let node = SKNode()
        node.position = point
        node.zPosition = 6
        parent.addChild(node)
        if delay > 0 {
            node.run(.sequence([
                .wait(forDuration: delay),
                .run { build(node) },
                .wait(forDuration: lifetime),
                .removeFromParent(),
            ]))
        } else {
            build(node)
            node.run(.sequence([.wait(forDuration: lifetime), .removeFromParent()]))
        }
    }

    private static func glow(
        color: SKColor, cellSize: CGFloat, from start: CGFloat, to end: CGFloat,
        alpha: CGFloat, duration: TimeInterval, in node: SKNode
    ) {
        let sprite = SKSpriteNode(texture: SpriteArt.flare(cellSize: cellSize))
        sprite.color = color
        sprite.colorBlendFactor = 1
        sprite.blendMode = .add
        sprite.alpha = alpha
        sprite.setScale(start)
        let grow = SKAction.scale(to: end, duration: duration)
        grow.timingMode = .easeOut
        sprite.run(.sequence([.group([grow, .fadeOut(withDuration: duration)]), .removeFromParent()]))
        node.addChild(sprite)
    }

    private static func ring(color: SKColor, cellSize: CGFloat, from start: CGFloat, to end: CGFloat, duration: TimeInterval, in node: SKNode) {
        let sprite = SKSpriteNode(texture: SpriteArt.shockRing(cellSize: cellSize))
        sprite.color = color
        sprite.colorBlendFactor = 0.5
        sprite.blendMode = .add
        sprite.setScale(start)
        let grow = SKAction.scale(to: end, duration: duration)
        grow.timingMode = .easeOut
        sprite.run(.sequence([.group([grow, .fadeOut(withDuration: duration)]), .removeFromParent()]))
        node.addChild(sprite)
    }

    private static func shards(count: Int, cellSize: CGFloat, reach: CGFloat, in node: SKNode) {
        let texture = SpriteArt.shard(cellSize: cellSize)
        for index in 0..<count {
            let sprite = SKSpriteNode(texture: texture)
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + .random(in: -0.35...0.35)
            let distance = cellSize * reach * .random(in: 0.5...1)
            let fling = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.55)
            fling.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: .random(in: -3 * .pi...3 * .pi), duration: 0.55)
            let fade = SKAction.sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.3)])
            sprite.run(.sequence([.group([fling, spin, fade]), .removeFromParent()]))
            node.addChild(sprite)
        }
    }

    private static func bubbles(count: Int, cellSize: CGFloat, spread: CGFloat, in node: SKNode) {
        let texture = SpriteArt.bubble(cellSize: cellSize)
        for _ in 0..<count {
            let sprite = SKSpriteNode(texture: texture)
            sprite.position = CGPoint(
                x: cellSize * spread * .random(in: -1...1),
                y: cellSize * spread * .random(in: -1...1)
            )
            sprite.setScale(.random(in: 0.6...1.2))
            let duration = TimeInterval.random(in: 0.8...1.2)
            let rise = SKAction.moveBy(
                x: cellSize * .random(in: -0.4...0.4),
                y: cellSize * .random(in: 1.2...2.6),
                duration: duration
            )
            rise.timingMode = .easeOut
            let fade = SKAction.sequence([.wait(forDuration: duration * 0.5), .fadeOut(withDuration: duration * 0.5)])
            sprite.run(.sequence([.group([rise, fade]), .removeFromParent()]))
            node.addChild(sprite)
        }
    }
}
