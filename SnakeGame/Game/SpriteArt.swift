import SpriteKit
import UIKit

/// Pre-rendered textures for everything on the board, in the style guide's look
/// (`sea-snake-style-guide.md`): glowing teal snake segments, a serpent's head with
/// glowing gold eyes, glowing mango-colored fruit, power-up orbs, horned sea mines,
/// reef-rock walls and the free-play board.
///
/// Each texture is drawn once per cell size with Core Graphics and cached, so the
/// board is sprites sharing a handful of textures. That's both prettier and cheaper
/// than `SKShapeNode`s: their `glowWidth` re-renders a blur every frame, and shape
/// nodes can't be batched (Adventure's map alone has hundreds of wall cells).
///
/// Textures with a glow are padded by `glowPad` on every side, so a sprite made from
/// one is still centered on its cell; only its *visible* shape is cell-sized.
enum SpriteArt {
    // MARK: Snake

    /// A body segment: a rounded square with the style guide's 135° body gradient
    /// and its teal glow. A touch bigger than its cell, so neighbors overlap and the
    /// body reads as one serpent rather than a string of beads.
    static func snakeBody(cellSize c: CGFloat) -> SKTexture {
        padded("body", cellSize: c) { ctx, cell in
            let shape = UIBezierPath(roundedRect: cell.insetBy(dx: -0.5, dy: -0.5), cornerRadius: c * 0.26).cgPath
            glow(shape, in: ctx, color: glowTeal.withAlphaComponent(0.5), blur: c * 0.35)
            fillLinear(shape, in: ctx, colors: [color("SnakeBodyStart"), color("SnakeBodyEnd")],
                       from: cell.origin, to: CGPoint(x: cell.maxX, y: cell.maxY))
            sheen(on: cell.insetBy(dx: 1, dy: 1), in: ctx)
        }
    }

    /// The last segment: the body tapering to a rounded point, pointing right (rotate
    /// the sprite to point away from the body). Its base reaches back under the
    /// segment before it, so the join never shows a corner.
    static func snakeTail(cellSize c: CGFloat) -> SKTexture {
        padded("tail", cellSize: c) { ctx, cell in
            func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
                CGPoint(x: cell.minX + px * c, y: cell.midY + py * c)
            }
            let shape = CGMutablePath()
            shape.move(to: point(-0.35, -0.5))
            shape.addLine(to: point(0.05, -0.5))
            shape.addQuadCurve(to: point(1.0, 0), control: point(0.62, -0.47))
            shape.addQuadCurve(to: point(0.05, 0.5), control: point(0.62, 0.47))
            shape.addLine(to: point(-0.35, 0.5))
            shape.closeSubpath()

            glow(shape, in: ctx, color: glowTeal.withAlphaComponent(0.5), blur: c * 0.35)
            fillLinear(shape, in: ctx, colors: [color("SnakeBodyStart"), color("SnakeBodyEnd")],
                       from: cell.origin, to: CGPoint(x: cell.maxX, y: cell.maxY))
        }
    }

    /// The head, facing right (rotate the sprite to face elsewhere): a serpent's, not a
    /// worm's (see `serpentHeadPath`), with the head gradient and a stronger glow. The
    /// face is a separate texture (`snakeFace`) so tinting the head for a power-up
    /// doesn't tint its eyes.
    static func snakeHead(cellSize c: CGFloat) -> SKTexture {
        padded("head", cellSize: c) { ctx, cell in
            let shape = serpentHeadPath(in: cell)
            glow(shape, in: ctx, color: glowTeal.withAlphaComponent(0.65), blur: c * 0.45)
            fillLinear(shape, in: ctx, colors: [color("SnakeHeadStart"), color("SnakeHeadEnd")],
                       from: cell.origin, to: CGPoint(x: cell.maxX, y: cell.maxY))
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            sheen(on: cell.insetBy(dx: 1, dy: 1), in: ctx)
            ctx.restoreGState()
        }
    }

    /// The face, facing right like `snakeHead`: slanted, sunken eyes set on the sides
    /// of the head, each holding nothing but a pale-gold glow (the menu serpent's eye,
    /// up close; no pupils, so there's nothing to read in them) and two nostrils at
    /// the snout. The slant does the glaring; brow ridges read as cartoon eyebrows.
    /// Deliberately far from the style guide's big white eyes and whiskers: more sea
    /// serpent, less mascot.
    static func snakeFace(cellSize c: CGFloat) -> SKTexture {
        padded("face", cellSize: c) { ctx, cell in
            let x = cell.minX
            let cy = cell.midY

            // -1 is the side nearer the top of the texture, +1 the bottom.
            for side: CGFloat in [-1, 1] {
                let center = CGPoint(x: x + 0.52 * c, y: cy + side * 0.31 * c)
                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                // Slanted, so the front of each eye dips toward the snout.
                ctx.rotate(by: -side * 0.22)

                // A dark, sunken socket...
                ctx.setFillColor(UIColor(red: 0.02, green: 0.06, blue: 0.07, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: -0.13 * c, y: -0.085 * c, width: 0.26 * c, height: 0.17 * c))

                // ...holding only a pale-gold glow.
                let glowCenter = CGPoint(x: 0.015 * c, y: 0)
                let light = CGPath(ellipseIn: CGRect(x: glowCenter.x - 0.085 * c, y: -0.05 * c, width: 0.17 * c, height: 0.1 * c), transform: nil)
                glow(light, in: ctx, color: color("PaleGold").withAlphaComponent(0.55), blur: c * 0.3)
                glow(light, in: ctx, color: color("PaleGold").withAlphaComponent(0.9), blur: c * 0.14)
                fillRadial(light, in: ctx,
                           colors: [UIColor(red: 1.0, green: 0.96, blue: 0.7, alpha: 1), color("PaleGold"),
                                    UIColor(red: 0.74, green: 0.58, blue: 0.28, alpha: 1)],
                           center: glowCenter, radius: 0.09 * c)
                ctx.restoreGState()

                circle(CGPoint(x: x + 0.95 * c, y: cy + side * 0.085 * c), radius: 0.022 * c, in: ctx,
                       color: UIColor(red: 0.03, green: 0.15, blue: 0.14, alpha: 0.7))
            }
        }
    }

    /// A soft white halo the size of a segment, tinted at runtime: the bomb-eater
    /// "grace" glow. Drawn behind its segment, which covers the solid middle.
    static func snakeAura(cellSize c: CGFloat) -> SKTexture {
        padded("aura", cellSize: c) { ctx, cell in
            let shape = UIBezierPath(roundedRect: cell.insetBy(dx: -0.5, dy: -0.5), cornerRadius: c * 0.26).cgPath
            glow(shape, in: ctx, color: .white, blur: c * 0.4)
            glow(shape, in: ctx, color: .white, blur: c * 0.2)
        }
    }

    // MARK: Food and power-ups

    /// The food: a glowing round fruit in the game's original "mango" colors, red at
    /// the top left to orange at the bottom right. (The style guide's food is a
    /// pale-gold pearl; the mango colors were kept on purpose.)
    static func fruit(cellSize c: CGFloat) -> SKTexture {
        padded("fruit", cellSize: c) { ctx, cell in
            let diameter = c * 0.6
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let bounds = square(center, diameter)
            let shape = CGPath(ellipseIn: bounds, transform: nil)
            glow(shape, in: ctx, color: UIColor.systemOrange.withAlphaComponent(0.7), blur: c * 0.45)
            fillLinear(shape, in: ctx, colors: [.systemRed, .systemOrange],
                       from: bounds.origin, to: CGPoint(x: bounds.maxX, y: bounds.maxY))
            circle(CGPoint(x: center.x - diameter * 0.17, y: center.y - diameter * 0.2), radius: diameter * 0.09,
                   in: ctx, color: UIColor.white.withAlphaComponent(0.6))
        }
    }

    /// The mine fruit: a glowing crimson sea urchin, round and fruit-sized like the
    /// mango so it reads as something to collect, with soft spines so it reads as
    /// the stuff mines are made of. Every few eaten earns the snake a mine to drop.
    static func mineFruit(cellSize c: CGFloat) -> SKTexture {
        padded("mine-fruit", cellSize: c) { ctx, cell in
            let diameter = c * 0.5
            let center = CGPoint(x: cell.midX, y: cell.midY)

            ctx.setLineCap(.round)
            ctx.setLineWidth(max(1, c * 0.045))
            ctx.setStrokeColor(UIColor(red: 0.95, green: 0.32, blue: 0.42, alpha: 0.9).cgColor)
            for index in 0..<12 {
                let angle = CGFloat(index) / 12 * 2 * .pi
                let inner = diameter * 0.4
                let outer = diameter * (index.isMultiple(of: 2) ? 0.8 : 0.68)
                ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                ctx.strokePath()
            }

            let shape = CGPath(ellipseIn: square(center, diameter), transform: nil)
            glow(shape, in: ctx, color: UIColor(red: 1.0, green: 0.25, blue: 0.35, alpha: 0.75), blur: c * 0.4)
            fillRadial(shape, in: ctx,
                       colors: [UIColor(red: 1.0, green: 0.55, blue: 0.6, alpha: 1),
                                UIColor(red: 0.78, green: 0.12, blue: 0.26, alpha: 1),
                                UIColor(red: 0.34, green: 0.03, blue: 0.12, alpha: 1)],
                       center: CGPoint(x: center.x - diameter * 0.16, y: center.y - diameter * 0.18),
                       radius: diameter * 0.7)
            circle(CGPoint(x: center.x - diameter * 0.17, y: center.y - diameter * 0.2), radius: diameter * 0.09,
                   in: ctx, color: UIColor.white.withAlphaComponent(0.7))
        }
    }

    /// A glowing orb in the power-up's color with its symbol on the front, so each
    /// kind reads at a glance rather than by color alone.
    static func powerUpOrb(color tint: UIColor, symbol: String, cellSize c: CGFloat) -> SKTexture {
        padded("orb-\(symbol)", cellSize: c) { ctx, cell in
            let diameter = c * 0.82
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let shape = CGPath(ellipseIn: square(center, diameter), transform: nil)
            glow(shape, in: ctx, color: tint.withAlphaComponent(0.8), blur: c * 0.4)
            fillRadial(shape, in: ctx,
                       colors: [tint.mixed(with: .white, by: 0.45), tint, tint.mixed(with: .black, by: 0.4)],
                       center: CGPoint(x: center.x - diameter * 0.15, y: center.y - diameter * 0.18),
                       radius: diameter * 0.7)

            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(max(1, c * 0.04))
            ctx.strokeEllipse(in: square(center, diameter - c * 0.06))

            let configuration = UIImage.SymbolConfiguration(pointSize: c * 0.36, weight: .bold)
            if let image = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                image.draw(at: CGPoint(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2))
            }
        }
    }

    // MARK: Bombs

    /// A horned sea mine: dark metal, eight horns, and a glowing light at its heart in
    /// the bomb kind's color (`light`). `ringed` circles the light, for the sensor.
    static func seaMine(light: UIColor, ringed: Bool, cellSize c: CGFloat) -> SKTexture {
        padded("mine-\(light.hashKey)-\(ringed)", cellSize: c) { ctx, cell in
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let radius = c * 0.34
            let body = CGPath(ellipseIn: square(center, radius * 2), transform: nil)

            // A haze of the light's color around the whole mine, so kinds are told
            // apart at a glance and it reads as a hazard, not a collectible.
            glow(body, in: ctx, color: light.withAlphaComponent(0.6), blur: c * 0.4)

            ctx.setLineCap(.round)
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                // Horns end right about at the cell's edge.
                let tip = CGPoint(x: center.x + direction.x * (radius + c * 0.11), y: center.y + direction.y * (radius + c * 0.11))
                ctx.setStrokeColor(UIColor(red: 0.2, green: 0.25, blue: 0.27, alpha: 1).cgColor)
                ctx.setLineWidth(c * 0.09)
                ctx.move(to: CGPoint(x: center.x + direction.x * radius * 0.7, y: center.y + direction.y * radius * 0.7))
                ctx.addLine(to: tip)
                ctx.strokePath()
                circle(tip, radius: c * 0.045, in: ctx, color: UIColor(red: 0.36, green: 0.43, blue: 0.45, alpha: 1))
            }

            fillRadial(body, in: ctx,
                       colors: [UIColor(red: 0.32, green: 0.38, blue: 0.40, alpha: 1),
                                UIColor(red: 0.11, green: 0.14, blue: 0.16, alpha: 1),
                                UIColor(red: 0.03, green: 0.05, blue: 0.06, alpha: 1)],
                       center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
                       radius: radius * 1.3)

            let core = CGPath(ellipseIn: square(center, radius * 0.75), transform: nil)
            glow(core, in: ctx, color: light, blur: c * 0.3)
            glow(core, in: ctx, color: light, blur: c * 0.12)
            circle(center, radius: radius * 0.12, in: ctx, color: UIColor.white.withAlphaComponent(0.9))

            if ringed {
                ctx.setStrokeColor(light.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(max(1, c * 0.03))
                ctx.strokeEllipse(in: square(center, radius * 1.15))
            }
        }
    }

    /// A cannonball: a heavy, dark iron sphere with a cold rim of light so it reads
    /// on dark water, and a cast seam so you can see it roll.
    static func cannonball(cellSize c: CGFloat) -> SKTexture {
        padded("cannonball", cellSize: c) { ctx, cell in
            let diameter = c * 0.8
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let ball = CGPath(ellipseIn: square(center, diameter), transform: nil)
            glow(ball, in: ctx, color: color("Foam").withAlphaComponent(0.5), blur: c * 0.3)
            fillRadial(ball, in: ctx,
                       colors: [UIColor(red: 0.62, green: 0.67, blue: 0.7, alpha: 1),
                                UIColor(red: 0.24, green: 0.27, blue: 0.3, alpha: 1),
                                UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)],
                       center: CGPoint(x: center.x - diameter * 0.2, y: center.y - diameter * 0.22),
                       radius: diameter * 0.75)

            ctx.saveGState()
            ctx.addPath(ball)
            ctx.clip()
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(max(1, c * 0.04))
            ctx.strokeEllipse(in: CGRect(x: center.x - diameter * 0.18, y: center.y - diameter / 2, width: diameter * 0.36, height: diameter))
            ctx.restoreGState()

            circle(CGPoint(x: center.x - diameter * 0.2, y: center.y - diameter * 0.22), radius: diameter * 0.08,
                   in: ctx, color: UIColor.white.withAlphaComponent(0.6))
        }
    }

    /// The barrel: a squat, banded wooden cask with a glowing hazard mark, the one
    /// bomb that isn't round.
    static func barrel(light: UIColor, cellSize c: CGFloat) -> SKTexture {
        padded("barrel", cellSize: c) { ctx, cell in
            let size = CGSize(width: c * 0.7, height: c * 0.82)
            let rect = CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.3).cgPath
            glow(shape, in: ctx, color: light.withAlphaComponent(0.4), blur: c * 0.3)
            // Shaded across, like a cylinder lit from the left.
            fillLinear(shape, in: ctx,
                       colors: [UIColor(red: 0.34, green: 0.19, blue: 0.09, alpha: 1),
                                UIColor(red: 0.62, green: 0.38, blue: 0.2, alpha: 1),
                                UIColor(red: 0.22, green: 0.11, blue: 0.05, alpha: 1)],
                       from: CGPoint(x: rect.minX, y: rect.midY), to: CGPoint(x: rect.maxX, y: rect.midY))

            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setFillColor(UIColor(red: 0.1, green: 0.07, blue: 0.05, alpha: 0.9).cgColor)
            for bandY in [0.2, 0.8] {
                ctx.fill(CGRect(x: rect.minX, y: rect.minY + rect.height * bandY - c * 0.035, width: rect.width, height: c * 0.07))
            }
            ctx.restoreGState()

            let mark = CGMutablePath()
            let half = c * 0.09
            mark.move(to: CGPoint(x: rect.midX, y: rect.midY - half))
            mark.addLine(to: CGPoint(x: rect.midX + half, y: rect.midY))
            mark.addLine(to: CGPoint(x: rect.midX, y: rect.midY + half))
            mark.addLine(to: CGPoint(x: rect.midX - half, y: rect.midY))
            mark.closeSubpath()
            glow(mark, in: ctx, color: light, blur: c * 0.15)
        }
    }

    // MARK: Kraken

    private static let krakenLight = UIColor(red: 0.86, green: 0.32, blue: 0.38, alpha: 1)
    private static let krakenSkin = UIColor(red: 0.62, green: 0.13, blue: 0.23, alpha: 1)
    private static let krakenShadow = UIColor(red: 0.2, green: 0.03, blue: 0.08, alpha: 1)
    private static let krakenGlow = UIColor(red: 0.9, green: 0.18, blue: 0.3, alpha: 1)

    /// One link of a kraken arm: a shaded crimson disc a cell across with a faint red
    /// glow. Chains of these, scaled down toward the tip, make every arm (see
    /// `TentacleChain`), so the whole kraken shares one texture.
    static func tentacleLink(cellSize c: CGFloat) -> SKTexture {
        padded("tentacle", cellSize: c) { ctx, cell in
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let disc = CGPath(ellipseIn: square(center, c), transform: nil)
            glow(disc, in: ctx, color: krakenGlow.withAlphaComponent(0.35), blur: c * 0.25)
            fillRadial(disc, in: ctx, colors: [krakenLight, krakenSkin, krakenShadow],
                       center: CGPoint(x: center.x - c * 0.18, y: center.y - c * 0.2), radius: c * 0.62)
        }
    }

    /// A sucker: a pale ring around a dark cup.
    static func sucker(cellSize c: CGFloat) -> SKTexture {
        let side = c * 0.36
        return cached("sucker-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            ctx.setFillColor(UIColor(red: 0.97, green: 0.7, blue: 0.66, alpha: 0.95).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: side * 0.08, dy: side * 0.08))
            ctx.setFillColor(UIColor(red: 0.45, green: 0.1, blue: 0.16, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: side * 0.32, dy: side * 0.32))
        }
    }

    /// The kraken from above: a bulbous, mottled mantle swelling up behind a broad
    /// head, dotted with a few glowing spots, all with a red glow. The texture's
    /// center is the kraken's center cell, with the head below it and the mantle
    /// above (see `Kraken.headCenter`). The eyes are separate sprites (`krakenEye`,
    /// `krakenPupil`) so they can follow the snake.
    static func krakenBody(cellSize c: CGFloat) -> SKTexture {
        let size = CGSize(width: c * 3.8, height: c * 6)
        return cached("kraken-body-\(c)", size: size) { ctx in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            // UIKit's y runs down: the mantle sits above `mid`, the head below.
            let mantle = CGRect(x: mid.x - 1.15 * c, y: mid.y - 2.5 * c, width: 2.3 * c, height: 3.1 * c)
            let head = CGRect(x: mid.x - 1.3 * c, y: mid.y - 0.4 * c, width: 2.6 * c, height: 2.1 * c)
            let shape = CGMutablePath()
            shape.addEllipse(in: mantle)
            shape.addEllipse(in: head)

            glow(shape, in: ctx, color: krakenGlow.withAlphaComponent(0.45), blur: c * 0.5)
            fillRadial(shape, in: ctx, colors: [krakenLight, krakenSkin, krakenShadow],
                       center: CGPoint(x: mid.x - 0.4 * c, y: mid.y - 1.6 * c), radius: 3.6 * c)

            // Darker mottling across the skin.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            var seed: UInt32 = 1337
            func next() -> CGFloat {
                seed = seed &* 1_103_515_245 &+ 12345
                return CGFloat((seed >> 16) & 0x7FFF) / CGFloat(0x7FFF)
            }
            ctx.setFillColor(krakenShadow.withAlphaComponent(0.3).cgColor)
            for _ in 0..<28 {
                let width = c * (0.14 + 0.3 * next())
                let point = CGPoint(x: mid.x + c * (2.4 * next() - 1.2), y: mid.y + c * (4.0 * next() - 2.4))
                ctx.fillEllipse(in: CGRect(x: point.x - width / 2, y: point.y - width * 0.35, width: width, height: width * 0.7))
            }
            // A pale crease where the mantle meets the head.
            ctx.setStrokeColor(krakenLight.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(c * 0.05)
            ctx.addArc(center: CGPoint(x: mid.x, y: mid.y + 0.9 * c), radius: 1.05 * c,
                       startAngle: -.pi * 0.8, endAngle: -.pi * 0.2, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()

            // A few bioluminescent spots on the mantle.
            for (dx, dy) in [(-0.55, -1.7), (0.5, -1.45), (-0.2, -2.1), (0.7, -0.6), (-0.75, -0.75)] {
                let spot = CGPath(ellipseIn: square(CGPoint(x: mid.x + CGFloat(dx) * c, y: mid.y + CGFloat(dy) * c), c * 0.12), transform: nil)
                glow(spot, in: ctx, color: UIColor(red: 1.0, green: 0.5, blue: 0.32, alpha: 0.9), blur: c * 0.2)
            }
        }
    }

    /// A kraken eye: a glowing amber ball in a dark socket. Its horizontal pupil
    /// (`krakenPupil`) is a separate sprite so it can look around.
    static func krakenEye(cellSize c: CGFloat) -> SKTexture {
        padded("kraken-eye", cellSize: c) { ctx, cell in
            let center = CGPoint(x: cell.midX, y: cell.midY)
            let diameter = c * 0.82
            circle(center, radius: diameter / 2 + c * 0.07, in: ctx, color: krakenShadow)
            let ball = CGPath(ellipseIn: square(center, diameter), transform: nil)
            glow(ball, in: ctx, color: UIColor(red: 1.0, green: 0.72, blue: 0.22, alpha: 0.75), blur: c * 0.35)
            fillRadial(ball, in: ctx,
                       colors: [UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1),
                                UIColor(red: 1.0, green: 0.76, blue: 0.26, alpha: 1),
                                UIColor(red: 0.78, green: 0.38, blue: 0.08, alpha: 1)],
                       center: CGPoint(x: center.x - diameter * 0.15, y: center.y - diameter * 0.18),
                       radius: diameter * 0.62)
        }
    }

    /// The octopus's signature pupil: a dark horizontal bar.
    static func krakenPupil(cellSize c: CGFloat) -> SKTexture {
        let size = CGSize(width: c * 0.48, height: c * 0.16)
        return cached("kraken-pupil-\(c)", size: size) { ctx in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).cgPath
            ctx.setFillColor(UIColor(red: 0.04, green: 0.02, blue: 0.03, alpha: 1).cgColor)
            ctx.addPath(shape)
            ctx.fillPath()
        }
    }

    /// A cloud of ink: a dark, soft-edged blot, for the kraken's flinch and death.
    static func inkCloud(cellSize c: CGFloat) -> SKTexture {
        let side = c * 4
        return cached("ink-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let center = CGPoint(x: side / 2, y: side / 2)
            let shape = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side), transform: nil)
            fillRadial(shape, in: ctx,
                       colors: [UIColor(red: 0.03, green: 0.02, blue: 0.06, alpha: 0.85),
                                UIColor(red: 0.05, green: 0.03, blue: 0.08, alpha: 0.5),
                                UIColor(red: 0.05, green: 0.03, blue: 0.08, alpha: 0)],
                       center: center, radius: side / 2)
        }
    }

    /// A ring of foam, scaled up and faded out where a tentacle breaks the surface.
    static func splashRing(cellSize c: CGFloat) -> SKTexture {
        let side = c * 2
        return cached("splash-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let ring = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: c * 0.2, dy: c * 0.2), transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: c * 0.15, color: UIColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setStrokeColor(color("Foam").withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(c * 0.09)
            ctx.addPath(ring)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: Moray

    private static let morayLight = UIColor(red: 0.36, green: 0.47, blue: 0.22, alpha: 1)
    private static let moraySkin = UIColor(red: 0.17, green: 0.24, blue: 0.1, alpha: 1)
    private static let morayShadow = UIColor(red: 0.03, green: 0.05, blue: 0.02, alpha: 1)
    private static let moraySpot = UIColor(red: 0.8, green: 1.0, blue: 0.35, alpha: 1)

    /// A length of the moray: thicker than the snake (well over a cell, so lengths
    /// overlap into one body rather than reading as beads), dark olive, with a
    /// sickly green rim glow and a couple of glowing chartreuse spots. Two variants
    /// of spot pattern, alternated down the body.
    static func morayBody(cellSize c: CGFloat, variant: Int) -> SKTexture {
        padded("moray-body-\(variant)", cellSize: c) { ctx, cell in
            let shape = UIBezierPath(roundedRect: cell.insetBy(dx: -c * 0.13, dy: -c * 0.13), cornerRadius: c * 0.32).cgPath
            glow(shape, in: ctx, color: UIColor(red: 0.5, green: 0.75, blue: 0.2, alpha: 0.35), blur: c * 0.3)
            fillRadial(shape, in: ctx, colors: [morayLight, moraySkin, morayShadow],
                       center: CGPoint(x: cell.midX - c * 0.15, y: cell.midY - c * 0.2), radius: c * 0.75)
            let spots: [(CGFloat, CGFloat, CGFloat)] = variant == 0
                ? [(0.3, 0.32, 0.05), (0.64, 0.66, 0.04)]
                : [(0.66, 0.3, 0.04), (0.34, 0.68, 0.05)]
            for (x, y, radius) in spots {
                let spot = CGPath(ellipseIn: square(CGPoint(x: cell.minX + x * c, y: cell.minY + y * c), radius * 2 * c), transform: nil)
                glow(spot, in: ctx, color: moraySpot, blur: c * 0.12)
            }
        }
    }

    /// The moray's head, facing right: a long, blunt wedge with its jaw hanging
    /// open, needle teeth along the gape, and two milky, faintly glowing eyes, no
    /// pupils, because it's blind.
    static func morayHead(cellSize c: CGFloat) -> SKTexture {
        padded("moray-head", cellSize: c) { ctx, cell in
            func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
                CGPoint(x: cell.minX + px * c, y: cell.midY + py * c)
            }
            // Upper and lower jaw, parted at the front by a dark gape.
            let head = CGMutablePath()
            head.move(to: point(-0.1, -0.52))
            head.addQuadCurve(to: point(1.18, -0.16), control: point(0.75, -0.62))
            head.addLine(to: point(0.72, 0))
            head.addLine(to: point(1.18, 0.16))
            head.addQuadCurve(to: point(-0.1, 0.52), control: point(0.75, 0.62))
            head.closeSubpath()
            glow(head, in: ctx, color: UIColor(red: 0.5, green: 0.75, blue: 0.2, alpha: 0.4), blur: c * 0.35)
            fillRadial(head, in: ctx, colors: [morayLight, moraySkin, morayShadow],
                       center: point(0.35, -0.2), radius: c * 0.9)

            let gape = CGMutablePath()
            gape.move(to: point(1.2, -0.16))
            gape.addLine(to: point(0.7, 0))
            gape.addLine(to: point(1.2, 0.16))
            gape.closeSubpath()
            ctx.setFillColor(UIColor(red: 0.12, green: 0.01, blue: 0.03, alpha: 1).cgColor)
            ctx.addPath(gape)
            ctx.fillPath()

            ctx.setFillColor(UIColor(white: 0.95, alpha: 0.95).cgColor)
            for index in 0..<4 {
                let along = 0.78 + CGFloat(index) * 0.1
                let spread = (along - 0.7) * 0.32
                for side: CGFloat in [-1, 1] {
                    let tooth = CGMutablePath()
                    tooth.move(to: point(along - 0.035, side * spread))
                    tooth.addLine(to: point(along + 0.035, side * spread))
                    tooth.addLine(to: point(along, side * (spread - 0.09)))
                    tooth.closeSubpath()
                    ctx.addPath(tooth)
                    ctx.fillPath()
                }
            }

            for side: CGFloat in [-1, 1] {
                let eye = CGPath(ellipseIn: square(point(0.42, side * 0.3), c * 0.17), transform: nil)
                glow(eye, in: ctx, color: UIColor(red: 0.82, green: 0.9, blue: 0.95, alpha: 0.75), blur: c * 0.18)
                fillRadial(eye, in: ctx,
                           colors: [UIColor(white: 1, alpha: 1), UIColor(red: 0.74, green: 0.8, blue: 0.84, alpha: 1)],
                           center: point(0.42, side * 0.3), radius: c * 0.09)
            }
        }
    }

    /// The moray's tail, pointing right: the body thinning into a frilled fin.
    static func morayTail(cellSize c: CGFloat) -> SKTexture {
        padded("moray-tail", cellSize: c) { ctx, cell in
            func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
                CGPoint(x: cell.minX + px * c, y: cell.midY + py * c)
            }
            let fin = CGMutablePath()
            fin.move(to: point(-0.35, -0.55))
            fin.addQuadCurve(to: point(1.15, 0), control: point(0.6, -0.6))
            fin.addQuadCurve(to: point(-0.35, 0.55), control: point(0.6, 0.6))
            fin.closeSubpath()
            glow(fin, in: ctx, color: UIColor(red: 0.5, green: 0.75, blue: 0.2, alpha: 0.35), blur: c * 0.3)
            fillLinear(fin, in: ctx, colors: [moraySkin, morayShadow],
                       from: point(0, -0.5), to: point(1, 0.5))
        }
    }

    // MARK: Effects

    /// A soft white glow fading to nothing, two cells across: tinted and blended
    /// additively at runtime for flashes and light thrown on the water.
    static func flare(cellSize c: CGFloat) -> SKTexture {
        let side = c * 2
        return cached("flare-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let shape = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side), transform: nil)
            fillRadial(shape, in: ctx,
                       colors: [.white, UIColor.white.withAlphaComponent(0.45), UIColor.white.withAlphaComponent(0)],
                       center: CGPoint(x: side / 2, y: side / 2), radius: side / 2)
        }
    }

    /// A thin, soft-edged white ring, two cells across: an explosion's shockwave.
    static func shockRing(cellSize c: CGFloat) -> SKTexture {
        let side = c * 2
        return cached("shock-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let ring = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: c * 0.18, dy: c * 0.18), transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: c * 0.14, color: UIColor.white.cgColor)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(c * 0.07)
            ctx.addPath(ring)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// A small bubble: a pale rim with a glint, for bursts and the snake coming apart.
    static func bubble(cellSize c: CGFloat) -> SKTexture {
        let side = (c * 0.34).rounded(.up)
        return cached("bubble-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let rect = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 1, dy: 1)
            ctx.setFillColor(color("Foam").withAlphaComponent(0.12).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(color("Foam").withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(max(0.8, side * 0.08))
            ctx.strokeEllipse(in: rect)
            circle(CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.3), radius: side * 0.1,
                   in: ctx, color: UIColor.white.withAlphaComponent(0.9))
        }
    }

    /// A jagged scrap of dark mine casing, thrown out by an explosion.
    static func shard(cellSize c: CGFloat) -> SKTexture {
        let side = (c * 0.22).rounded(.up)
        return cached("shard-\(c)", size: CGSize(width: side, height: side)) { ctx in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: side * 0.1, y: side * 0.25))
            path.addLine(to: CGPoint(x: side * 0.85, y: side * 0.05))
            path.addLine(to: CGPoint(x: side * 0.95, y: side * 0.6))
            path.addLine(to: CGPoint(x: side * 0.35, y: side * 0.95))
            path.closeSubpath()
            ctx.setFillColor(UIColor(red: 0.3, green: 0.36, blue: 0.38, alpha: 1).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    /// A horizontal band of light, bright along its middle and soft at the edges:
    /// stretched along a row or column for a barrel's blast.
    static func beam(cellSize c: CGFloat) -> SKTexture {
        let size = CGSize(width: c, height: c * 1.6)
        return cached("beam-\(c)", size: size) { ctx in
            let rect = CGRect(origin: .zero, size: size)
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.white.withAlphaComponent(0), UIColor.white.withAlphaComponent(0.55),
                         UIColor.white, UIColor.white.withAlphaComponent(0.55), UIColor.white.withAlphaComponent(0)].map(\.cgColor) as CFArray,
                locations: [0, 0.3, 0.5, 0.7, 1]
            ) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
    }

    // MARK: Walls and board

    /// One cell of reef rock. A few variants (`variant` 0..<`reefVariants`) with
    /// their own barnacle scatter, so a wall reads as rock rather than tiles.
    static let reefVariants = 3

    static func reefRock(cellSize c: CGFloat, variant: Int) -> SKTexture {
        cached("reef-\(variant)-\(c)", size: CGSize(width: c, height: c)) { ctx in
            let rect = CGRect(x: 0, y: 0, width: c, height: c).insetBy(dx: 0.5, dy: 0.5)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: c * 0.16).cgPath
            let lift = CGFloat(variant) * 0.012
            fillLinear(shape, in: ctx,
                       colors: [UIColor(red: 0.15 + lift, green: 0.29 + lift, blue: 0.31, alpha: 1),
                                UIColor(red: 0.05, green: 0.12, blue: 0.14, alpha: 1)],
                       from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))

            // Light from the surface catching the top edge.
            ctx.setStrokeColor(color("Foam").withAlphaComponent(0.16).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: rect.minX + c * 0.16, y: rect.minY + 1))
            ctx.addLine(to: CGPoint(x: rect.maxX - c * 0.16, y: rect.minY + 1))
            ctx.strokePath()

            var seed = UInt32(variant * 7919 + 17)
            func next() -> CGFloat {
                seed = seed &* 1_103_515_245 &+ 12345
                return CGFloat((seed >> 16) & 0x7FFF) / CGFloat(0x7FFF)
            }
            for _ in 0..<4 {
                let point = CGPoint(x: rect.minX + c * (0.2 + 0.6 * next()), y: rect.minY + c * (0.25 + 0.6 * next()))
                let radius = c * (0.035 + 0.04 * next())
                circle(point, radius: radius, in: ctx, color: UIColor(red: 0.5, green: 0.68, blue: 0.64, alpha: 0.2))
                circle(CGPoint(x: point.x, y: point.y + radius * 0.3), radius: radius * 0.45, in: ctx,
                       color: UIColor.black.withAlphaComponent(0.25))
            }
        }
    }

    /// The style guide's board: a rounded panel of darker water with an inner shadow,
    /// a soft teal glow around it and the faint board-border line. Sized to `size`
    /// plus `boardGlowPad` on every side.
    static let boardGlowPad: CGFloat = 28

    static func board(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
        let pad = boardGlowPad
        let canvas = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        return cached("board-\(size.width)x\(size.height)", size: canvas) { ctx in
            let rect = CGRect(origin: CGPoint(x: pad, y: pad), size: size)
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath

            glow(shape, in: ctx, color: UIColor(red: 30 / 255, green: 80 / 255, blue: 90 / 255, alpha: 0.4), blur: 24)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.addPath(shape)
            ctx.fillPath()
            ctx.restoreGState()

            // Translucent, so the moving water still shows faintly through.
            fillRadial(shape, in: ctx,
                       colors: [UIColor(red: 20 / 255, green: 60 / 255, blue: 70 / 255, alpha: 0.45),
                                UIColor(red: 4 / 255, green: 15 / 255, blue: 20 / 255, alpha: 0.75)],
                       center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.3),
                       radius: max(rect.width, rect.height) * 0.8)

            // Inner shadow: fill everything *outside* the panel with a shadow, clipped
            // to the inside, so only the shadow lands.
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let surround = CGMutablePath()
            surround.addRect(rect.insetBy(dx: -60, dy: -60))
            surround.addPath(shape)
            ctx.setShadow(offset: .zero, blur: 30, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.addPath(surround)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            ctx.setStrokeColor(color("BoardBorder").cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(shape)
            ctx.strokePath()
        }
    }

    /// A tiny soft speck of marine snow, for particle emitters.
    static func speck() -> SKTexture {
        cached("speck", size: CGSize(width: 8, height: 8)) { ctx in
            let shape = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 8, height: 8), transform: nil)
            fillRadial(shape, in: ctx, colors: [.white, UIColor.white.withAlphaComponent(0)],
                       center: CGPoint(x: 4, y: 4), radius: 4)
        }
    }

    // MARK: - Drawing helpers

    /// Room around a cell for glows and horns.
    static func glowPad(cellSize: CGFloat) -> CGFloat {
        (cellSize * 0.45).rounded(.up)
    }

    private static let glowTeal = UIColor(red: 60 / 255, green: 200 / 255, blue: 170 / 255, alpha: 1)
    private static var cache: [String: SKTexture] = [:]

    private static func color(_ name: String) -> UIColor {
        UIColor(named: name) ?? .white
    }

    /// A cell-sized drawing padded by `glowPad` all round; `draw` gets the cell's rect
    /// within the padded canvas.
    private static func padded(_ name: String, cellSize: CGFloat, draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let pad = glowPad(cellSize: cellSize)
        let side = cellSize + pad * 2
        return cached("\(name)-\(cellSize)", size: CGSize(width: side, height: side)) { ctx in
            draw(ctx, CGRect(x: pad, y: pad, width: cellSize, height: cellSize))
        }
    }

    private static func cached(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> SKTexture {
        if let texture = cache[key] { return texture }
        let image = UIGraphicsImageRenderer(size: size).image { draw($0.cgContext) }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// Fills `path` in its glow color with a blurred shadow of the same color around
    /// it. Whatever's drawn next on top covers the solid part, leaving the glow.
    private static func glow(_ path: CGPath, in ctx: CGContext, color: UIColor, blur: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur, color: color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func fillLinear(_ path: CGPath, in ctx: CGContext, colors: [UIColor], from start: CGPoint, to end: CGPoint) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func fillRadial(_ path: CGPath, in ctx: CGContext, colors: [UIColor], center: CGPoint, radius: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// A soft highlight across the top-left of a shape, the light from the surface.
    private static func sheen(on rect: CGRect, in ctx: CGContext) {
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.1,
                                   width: rect.width * 0.46, height: rect.height * 0.26))
    }

    private static func circle(_ center: CGPoint, radius: CGFloat, in ctx: CGContext, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: square(center, radius * 2))
    }

    private static func square(_ center: CGPoint, _ side: CGFloat) -> CGRect {
        CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// A serpent's head facing right, in `cell`: a touch narrower than the body where
    /// it meets the neck, swelling to broad temples a third of the way along (wider
    /// than the body, as a snake's head is wider than its neck), then tapering to a
    /// narrower, blunt snout that pokes just past the cell.
    private static func serpentHeadPath(in cell: CGRect) -> CGPath {
        let c = cell.width
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: cell.minX + px * c, y: cell.midY + py * c)
        }
        let path = CGMutablePath()
        path.move(to: point(0, -0.44))
        path.addQuadCurve(to: point(0.62, -0.47), control: point(0.3, -0.66))
        path.addQuadCurve(to: point(1.06, 0), control: point(1.02, -0.38))
        path.addQuadCurve(to: point(0.62, 0.47), control: point(1.02, 0.38))
        path.addQuadCurve(to: point(0, 0.44), control: point(0.3, 0.66))
        path.closeSubpath()
        return path
    }
}

private extension UIColor {
    /// A blend toward `other` by `fraction` (0 = self, 1 = other).
    func mixed(with other: UIColor, by fraction: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * fraction, green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction, alpha: a1 + (a2 - a1) * fraction)
    }

    /// Distinguishes cache entries by color.
    var hashKey: String {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f-%.3f-%.3f-%.3f", r, g, b, a)
    }
}
