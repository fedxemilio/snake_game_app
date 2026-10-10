import SpriteKit
import SwiftUI

/// The start menu's backdrop: stirring deep water (`AbyssWaterScene`'s shader over the
/// style-guide gradient: murk, light shafts, caustics, the odd flash of lightning
/// overhead), with the deep's inhabitants drifting in front of it.
///
/// Everything is a pure function of `MenuClock`, so nothing is stored or stepped.
/// Reduce Motion swaps the moving water for the plain `SeaBackground` gradient and
/// freezes the sea life at `MenuClock.still`.
struct LivingSea: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var water = AbyssWaterScene()

    var body: some View {
        ZStack {
            if reduceMotion {
                // Not a paused SpriteView: one that starts paused never draws a frame.
                SeaBackground()
            } else {
                // The murk moves slowly enough that 30 fps is indistinguishable from
                // 60, and it's the one full-screen per-pixel cost here.
                SpriteView(scene: water, preferredFramesPerSecond: 30)
            }

            DeepSeaLife(isAnimated: !reduceMotion)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Storm overhead: most ~17-second stretches get one strike at a random moment,
    /// a bright flicker and a weaker echo. 0 (dark) ... 1 (full flash).
    static func lightning(at time: Double) -> Double {
        let period = 17.0
        let cycle = Int((time / period).rounded(.down))
        guard MenuClock.random(cycle, salt: 7) > 0.3 else { return 0 }

        let strikeAt = 3 + 10 * MenuClock.random(cycle, salt: 8)
        let age = time - Double(cycle) * period - strikeAt
        guard age >= 0 else { return 0 }

        let flicker = exp(-age / 0.07)
        let echo = age > 0.16 ? 0.7 * exp(-(age - 0.16) / 0.14) : 0
        return min(1, flicker + echo)
    }
}

/// What drifts in the water: the serpent lurking far off, marine snow sinking,
/// plankton blinking on and off, and a few bubbles rising.
private struct DeepSeaLife: View {
    let isAnimated: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { timeline in
            Canvas { context, size in
                let time = isAnimated ? MenuClock.seconds(at: timeline.date) : MenuClock.still

                // Far to near, so nearer things cross in front.
                LurkingSerpent.paint(time: time, size: size, in: context)
                Self.marineSnow(time: time, size: size, in: context)
                Self.plankton(time: time, size: size, in: context)
                Self.bubbles(time: time, size: size, in: context)
            }
        }
    }

    private static let foam = Color("Foam")
    private static let glow = Color("BioluminescentGlow")

    /// Specks of debris sinking and meandering. Each has a depth that sets its size,
    /// brightness and speed, so the field has parallax.
    private static func marineSnow(time: Double, size: CGSize, in context: GraphicsContext) {
        for index in 0..<70 {
            let depth = MenuClock.random(index, salt: 1)   // 0 far ... 1 near
            let radius = 0.5 + 1.5 * depth
            let fall = 3 + 11 * depth
            let drift = 2 + 5 * MenuClock.random(index, salt: 2)

            let travel = size.height + 10
            let y = (MenuClock.random(index, salt: 3) * travel + time * fall)
                .truncatingRemainder(dividingBy: travel) - 5
            let meander = 9 * sin(time * 0.35 + Double(index) * 1.7)
            let x = (MenuClock.random(index, salt: 4) * size.width + time * drift + meander)
                .truncatingRemainder(dividingBy: size.width + 10) - 5

            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(foam.opacity(0.08 + 0.3 * depth))
            )
        }
    }

    /// Bioluminescent plankton: mostly dark, each one now and then swelling into a
    /// soft teal glow and fading out again, at its own unhurried rhythm.
    private static func plankton(time: Double, size: CGSize, in context: GraphicsContext) {
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for index in 0..<18 {
                let rate = 0.25 + 0.35 * MenuClock.random(index, salt: 5)
                let wave = sin(time * rate + 6.3 * MenuClock.random(index, salt: 6))
                let brightness = pow(max(0, wave), 5)
                guard brightness > 0.01 else { continue }

                let center = CGPoint(
                    x: size.width * (0.05 + 0.9 * MenuClock.random(index, salt: 7))
                        + 18 * sin(time * 0.11 + Double(index)),
                    y: size.height * (0.1 + 0.85 * MenuClock.random(index, salt: 8))
                        + 14 * cos(time * 0.09 + Double(index) * 2.3)
                )
                let haloRadius = 9 + 7 * MenuClock.random(index, salt: 9)

                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - haloRadius, y: center.y - haloRadius,
                        width: haloRadius * 2, height: haloRadius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [glow.opacity(0.45 * brightness), glow.opacity(0)]),
                        center: center, startRadius: 0, endRadius: haloRadius
                    )
                )
                layer.fill(
                    Path(ellipseIn: CGRect(x: center.x - 1.3, y: center.y - 1.3, width: 2.6, height: 2.6)),
                    with: .color(Color.white.opacity(0.8 * brightness))
                )
            }
        }
    }

    /// A few small bubbles wobbling up from the deep and wrapping back to the bottom.
    private static func bubbles(time: Double, size: CGSize, in context: GraphicsContext) {
        for index in 0..<10 {
            let radius = 1.8 + 4.5 * MenuClock.random(index, salt: 10)
            let speed = 14 + 26 * MenuClock.random(index, salt: 11)
            let travel = size.height + 4 * radius
            let progress = (time * speed / travel + MenuClock.random(index, salt: 12))
                .truncatingRemainder(dividingBy: 1)

            let center = CGPoint(
                x: size.width * (0.06 + 0.88 * MenuClock.random(index, salt: 13))
                    + (3 + radius) * sin(time * 2.2 + Double(index)),
                y: size.height + 2 * radius - travel * progress
            )
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            // Dimmer near the floor, catching more light as they rise.
            let light = 0.35 + 0.5 * (1 - center.y / size.height)

            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [foam.opacity(0.02), foam.opacity(0.14 * light)]),
                    center: center, startRadius: 0, endRadius: radius
                )
            )
            context.stroke(Path(ellipseIn: rect), with: .color(foam.opacity(0.5 * light)), lineWidth: 0.8)
            let glint = radius * 0.35
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius * 0.5 - glint / 2, y: center.y - radius * 0.5 - glint / 2,
                    width: glint, height: glint
                )),
                with: .color(Color.white.opacity(0.75 * light))
            )
        }
    }
}

#Preview {
    LivingSea()
}
