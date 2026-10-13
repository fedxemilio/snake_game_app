import SwiftUI

/// Carved, glowing letters riding a slow swell: each letter bobs and rocks on its own
/// part of the wave, the glow behind them breathes, and every few seconds a band of
/// water-light sweeps across their faces. "SEA SNAKE" on the menu by default; the
/// game's overlays pass their own lines.
///
/// Like the math game's `FloatingText`, everything is drawn into one `Canvas` from a
/// clock value, and the view has a fixed height so it lays out like a normal view.
struct FloatingTitle: View {
    struct Line {
        let text: String
        let fontSize: CGFloat
        let tracking: CGFloat
        /// Vertical center of the line, as a fraction of the view's height.
        let centerY: CGFloat
    }

    static let seaSnake = [
        Line(text: "SEA", fontSize: 30, tracking: 18, centerY: 0.24),
        Line(text: "SNAKE", fontSize: 70, tracking: 5, centerY: 0.64),
    ]

    var lines: [Line] = FloatingTitle.seaSnake
    var height: CGFloat = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let foam = Color("Foam")
    private static let gold = Color("PaleGold")
    /// Foam three-quarters of the way to pale gold: the bottom of each letter's face.
    private static let faceBottom = Color(red: 0.89, green: 0.87, blue: 0.69)

    /// The carved sides, front to back: deep teal fading to near-black.
    private static let depthLayers = 7
    private static let sideShades: [Color] = (1...depthLayers).map { depth in
        let back = Double(depth) / Double(depthLayers)
        return Color(red: 0.06 - 0.05 * back, green: 0.24 - 0.18 * back, blue: 0.25 - 0.17 * back)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? AmbientClock.still : AmbientClock.seconds(at: timeline.date)
            Canvas { context, size in
                Self.draw(lines: lines, time: time, size: size, in: context)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(lines.map(\.text).joined(separator: " ").capitalized)
        .accessibilityAddTraits(.isHeader)
    }

    private struct Glyph {
        let text: GraphicsContext.ResolvedText
        let center: CGPoint
        let fontSize: CGFloat
        let tilt: Double
    }

    private static func draw(lines: [Line], time: Double, size: CGSize, in context: GraphicsContext) {
        let glyphs = layOut(lines: lines, time: time, size: size, in: context)
        let breath = 0.5 + 0.5 * sin(time * 2 * .pi / 5.5)

        // The glow, matching the style guide's title text-shadow (a foam glow inside a
        // wider gold one), breathing slowly.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 24))
            for glyph in glyphs {
                stamp(glyph, shading: .color(gold.opacity(0.22 + 0.2 * breath)), in: layer)
            }
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            for glyph in glyphs {
                stamp(glyph, shading: .color(foam.opacity(0.3 + 0.25 * breath)), in: layer)
            }
        }

        // Carved depth: stacked copies dropping down and slightly right, as if lit
        // from the surface above.
        for glyph in glyphs {
            let unit = glyph.fontSize / 70
            for depth in stride(from: depthLayers, through: 1, by: -1) {
                stamp(
                    glyph,
                    offset: CGSize(width: 0.35 * unit * CGFloat(depth), height: 0.9 * unit * CGFloat(depth)),
                    shading: .color(sideShades[depth - 1]),
                    in: context
                )
            }
        }

        // The faces: foam fading to pale gold, plus a sweep of water-light every
        // seven seconds or so.
        let sweepCycle = 7.0
        let sweepAge = time.truncatingRemainder(dividingBy: sweepCycle)
        let sweepX = -60 + (size.width + 120) * CGFloat(sweepAge / 2.6)

        for glyph in glyphs {
            let half = glyph.fontSize * 0.45
            stamp(
                glyph,
                shading: .linearGradient(
                    Gradient(colors: [foam, faceBottom]),
                    startPoint: CGPoint(x: 0, y: -half),
                    endPoint: CGPoint(x: 0, y: half)
                ),
                in: context
            )

            guard sweepAge < 2.6 else { continue }
            // The band in the letter's own coordinates, slanted like the light shafts.
            let localX = sweepX - glyph.center.x
            stamp(
                glyph,
                shading: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.7), location: 0.5),
                        .init(color: .white.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: localX - 26, y: -half * 0.6),
                    endPoint: CGPoint(x: localX + 26, y: half * 0.6)
                ),
                in: context
            )
        }
    }

    /// Where every letter is this frame: laid out on its line, then lifted and rocked
    /// by the swell. The wave runs left to right through all the lines as one sequence.
    private static func layOut(lines: [Line], time: Double, size: CGSize, in context: GraphicsContext) -> [Glyph] {
        var glyphs: [Glyph] = []
        var sequence = 0

        for line in lines {
            let font = Font.custom("Cinzel", size: line.fontSize).weight(.semibold)
            let letters = line.text.map { context.resolve(Text(String($0)).font(font)) }
            let widths = letters.map { $0.measure(in: size).width }
            let totalWidth = widths.reduce(0, +) + line.tracking * CGFloat(max(0, letters.count - 1))

            // Small letters ride the swell less than big ones.
            let swell = line.fontSize / 70
            var cursor = (size.width - totalWidth) / 2

            for (index, letter) in letters.enumerated() {
                let phase = Double(sequence) * 0.55
                let rise = CGFloat(sin(time * 2 * .pi / 3.6 - phase)) * 6 * swell
                let tilt = sin(time * 2 * .pi / 4.6 - phase + 0.9) * 3.2 * .pi / 180
                let sway = CGFloat(sin(time * 2 * .pi / 5.3 + phase * 0.7)) * 1.5

                glyphs.append(Glyph(
                    text: letter,
                    center: CGPoint(x: cursor + widths[index] / 2 + sway, y: size.height * line.centerY - rise),
                    fontSize: line.fontSize,
                    tilt: tilt
                ))
                cursor += widths[index] + line.tracking
                sequence += 1
            }
        }
        return glyphs
    }

    /// Draws one letter at its place, rocked by its tilt, with the given shading.
    private static func stamp(
        _ glyph: Glyph,
        offset: CGSize = .zero,
        shading: GraphicsContext.Shading,
        in context: GraphicsContext
    ) {
        var layer = context
        layer.translateBy(x: glyph.center.x + offset.width, y: glyph.center.y + offset.height)
        layer.rotate(by: .radians(glyph.tilt))
        var text = glyph.text
        text.shading = shading
        layer.draw(text, at: .zero, anchor: .center)
    }
}

#Preview {
    ZStack {
        SeaBackground()
        FloatingTitle()
    }
}
