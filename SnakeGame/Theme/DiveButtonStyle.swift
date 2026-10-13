import SwiftUI

/// The start menu's play button: a dark orb with something alive inside it. It glows
/// to a slow double heartbeat, sends sonar rings out into the water on each beat, and
/// is circled by a slowly turning ring of light and a counter-turning ring of runes.
/// Pressing it sinks it a little and flares the glow.
///
/// The glow, halo and rings draw in a background that spills past the orb's frame,
/// so they don't affect layout and only the orb itself is tappable.
struct DiveButtonStyle: ButtonStyle {
    var diameter: CGFloat = 150

    func makeBody(configuration: Configuration) -> some View {
        DiveOrb(label: configuration.label, isPressed: configuration.isPressed, diameter: diameter)
    }
}

private struct DiveOrb<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var glow: Color { Color("BioluminescentGlow") }
    private static var gold: Color { Color("PaleGold") }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? AmbientClock.still : AmbientClock.seconds(at: timeline.date)
            let beat = Heartbeat.strength(at: time)
            let intensity = min(1, (isPressed ? 0.45 : 0) + 0.35 + 0.65 * beat)

            ZStack {
                core(time: time, intensity: intensity)
                rings(time: time, intensity: intensity)

                label
                    .foregroundStyle(Self.gold)
                    .shadow(color: Self.gold.opacity(0.35 + 0.4 * intensity), radius: 6)
                    .shadow(color: Self.glow.opacity(0.5 * intensity), radius: 14)
            }
            .frame(width: diameter, height: diameter)
            .background { aura(time: time, intensity: intensity) }
            .scaleEffect(isPressed ? 0.93 : 1 + 0.018 * beat)
        }
        .contentShape(Circle())
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isPressed)
    }

    /// The orb: near-black glass with a teal depth, a slow vortex turning inside it,
    /// and an inner rim that brightens with each beat.
    private func core(time: Double, intensity: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.03, green: 0.16, blue: 0.17),
                            Color(red: 0.01, green: 0.06, blue: 0.08),
                            Color(red: 0.0, green: 0.02, blue: 0.03),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.38),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )

            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Self.glow.opacity(0), Self.glow.opacity(0.28), Self.glow.opacity(0),
                            Self.gold.opacity(0.12), Self.glow.opacity(0),
                            Self.glow.opacity(0.22), Self.glow.opacity(0),
                        ],
                        center: .center,
                        angle: .degrees(-time * 22)
                    )
                )
                .blur(radius: 10)
                .opacity(0.5 + 0.5 * intensity)
                .clipShape(Circle())
                .blendMode(.plusLighter)

            Circle()
                .strokeBorder(Self.glow, lineWidth: 2.5)
                .blur(radius: 4)
                .opacity(0.25 + 0.75 * intensity)

            // A cold glint on the top of the glass.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.5, height: diameter * 0.2)
                .blur(radius: 3)
                .offset(y: -diameter * 0.32)
        }
    }

    /// A ring of light turning one way, a dotted ring of "runes" turning the other.
    private func rings(time: Double, intensity: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Self.glow, Self.glow.opacity(0), Self.gold.opacity(0.7),
                            Self.glow.opacity(0), Self.glow,
                        ],
                        center: .center,
                        angle: .degrees(time * 30)
                    ),
                    lineWidth: 1.5
                )
                .padding(-9)
                .opacity(0.45 + 0.55 * intensity)

            Circle()
                .stroke(Self.gold.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 9, 4, 9]))
                .padding(-17)
                .rotationEffect(.degrees(-time * 9))
                .opacity(0.4 + 0.3 * intensity)
        }
    }

    /// Everything outside the orb: the halo bleeding into the water and the sonar
    /// rings, one per beat of the heart.
    private func aura(time: Double, intensity: Double) -> some View {
        let reach = diameter * 2.6

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Self.glow.opacity(0.5 * intensity), Self.glow.opacity(0.12 * intensity), .clear],
                        center: .center,
                        startRadius: diameter * 0.35,
                        endRadius: reach / 2
                    )
                )

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let phase = time.truncatingRemainder(dividingBy: Heartbeat.period)

                // The first beat's ring, then the weaker echo of the second.
                for (start, strength) in [(0.0, 1.0), (Heartbeat.secondBeat, 0.55)] where phase >= start {
                    let age = (phase - start) / (Heartbeat.period - start)
                    let eased = CGFloat(1 - pow(1 - age, 2.2))
                    let radius = diameter / 2 + 6 + eased * (reach / 2 - diameter / 2 - 6)
                    let fade = pow(1 - age, 1.6) * strength
                    context.stroke(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Self.glow.opacity(0.55 * fade)),
                        lineWidth: 1 + 2.5 * fade
                    )
                }
            }
            .blur(radius: 1.2)
        }
        .frame(width: reach, height: reach)
        .allowsHitTesting(false)
    }
}

/// A slow "lub-dub": a strong beat, a weaker one right behind it, then a long
/// silence. Outside `DiveOrb` because a generic type can't hold static constants.
private enum Heartbeat {
    static let period = 2.8
    static let secondBeat = 0.32

    /// 0 (resting) ... 1 (peak).
    static func strength(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period)
        let attack = min(1, phase / 0.06)
        let lub = attack * exp(-phase / 0.3)
        let dub = phase > secondBeat ? 0.65 * min(1, (phase - secondBeat) / 0.06) * exp(-(phase - secondBeat) / 0.35) : 0
        return min(1, lub + dub)
    }
}

#Preview {
    ZStack {
        SeaBackground()
        Button("DIVE IN") {}
            .font(.custom("Cinzel", size: 22).weight(.semibold))
            .buttonStyle(DiveButtonStyle())
    }
}
