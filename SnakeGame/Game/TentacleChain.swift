import SpriteKit

/// A kraken arm drawn as a chain of overlapping round links (`SpriteArt.tentacleLink`),
/// posed fresh each frame from points along its length. Any curve can be drawn
/// without new art, and every arm on screen shares one texture. Every other link
/// (bar the thin tip) carries a sucker on one side.
final class TentacleChain {
    let node = SKNode()
    private let links: [SKSpriteNode]
    private let cellSize: CGFloat

    init(links count: Int, cellSize: CGFloat) {
        self.cellSize = cellSize
        let linkTexture = SpriteArt.tentacleLink(cellSize: cellSize)
        let suckerTexture = SpriteArt.sucker(cellSize: cellSize)

        var links: [SKSpriteNode] = []
        for index in 0..<count {
            let link = SKSpriteNode(texture: linkTexture)
            // Base drawn over tip, so the arm overlaps itself outward like a real one.
            link.zPosition = CGFloat(count - index) * 0.001
            if index % 2 == 1 && index < count * 4 / 5 {
                let sucker = SKSpriteNode(texture: suckerTexture)
                sucker.position = CGPoint(x: 0, y: -cellSize * 0.24)
                sucker.zPosition = 0.0005
                link.addChild(sucker)
            }
            node.addChild(link)
            links.append(link)
        }
        self.links = links
    }

    /// Poses the arm: link `i` centered on `points[i]` (in `node`'s coordinates) with
    /// radius `radii[i]`, turned to lie along the curve. Both arrays must have one
    /// entry per link.
    func layout(points: [CGPoint], radii: [CGFloat]) {
        let last = points.count - 1
        for (index, link) in links.enumerated() {
            let ahead = points[min(index + 1, last)]
            let behind = points[max(index - 1, 0)]
            link.position = points[index]
            link.zRotation = atan2(ahead.y - behind.y, ahead.x - behind.x)
            link.setScale(radii[index] * 2 / cellSize)
        }
    }
}
