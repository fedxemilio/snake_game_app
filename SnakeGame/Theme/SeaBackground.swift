import SwiftUI

/// The dark, atmospheric "storm/mythical" background from the style guide
/// (`sea-snake-style-guide.md`): a four-stop vertical gradient (deep navy
/// to abyss black) with two soft radial highlights near the top, plus a
/// light diagonal rain overlay. A standalone view since the look is meant
/// to extend beyond the start screen eventually (game-over/level-complete
/// overlays, etc.), not just live inline there.
///
/// The style guide's plankton-speckle texture isn't included here yet --
/// easy to add later the same way the rain overlay works.
struct SeaBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color("DeepNavy"), location: 0),
                        .init(color: Color("StormTeal"), location: 0.35),
                        .init(color: Color("DeepSea"), location: 0.65),
                        .init(color: Color("Abyss"), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [Color(red: 120.0 / 255, green: 140.0 / 255, blue: 160.0 / 255).opacity(0.22), .clear],
                    center: UnitPoint(x: 0.2, y: -0.1),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.9
                )

                RadialGradient(
                    colors: [Color(red: 90.0 / 255, green: 110.0 / 255, blue: 130.0 / 255).opacity(0.18), .clear],
                    center: UnitPoint(x: 0.9, y: 0.05),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.75
                )

                RainOverlay()
            }
        }
        .ignoresSafeArea()
    }
}

/// A light scatter of thin, low-opacity diagonal streaks -- static, not
/// animated, matching the style guide's CSS `repeating-linear-gradient`
/// rain texture rather than literal falling rain.
private struct RainOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            let tiltFromVertical = CGFloat.pi / 180 * 10 // matches the guide's slight 100deg CSS angle
            let dx = tan(tiltFromVertical) * size.height

            var x = -abs(dx) - spacing
            while x < size.width + spacing {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + dx, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 1)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    SeaBackground()
}
