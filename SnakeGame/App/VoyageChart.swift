import SpriteKit
import SwiftUI

/// Which leg of Adventure's ascent the voyage chart shows: the snake's marker
/// swims from `from` (a stage index into `AdventureStage.all`, or nil for the
/// abyss below the first) up to `to` (a stage index, or `AdventureStage.all.count`
/// for the surface itself, above the last, where the ascent ends).
struct Voyage: Equatable {
    let from: Int?
    let to: Int

    /// Past the last stage: the run is over.
    var isFinal: Bool { to >= AdventureStage.all.count }
}

/// Adventure's map: a chart of the ascent from the abyss to the stormy surface. A
/// dotted route winds up through each stage's stop (its boss's own sprite, its
/// depth) and on up to the surface; the stretch already swum glows, cleared stops
/// are ticked, and a little glowing serpent swims up to the next one. Shown when
/// an Adventure run starts, between stages, and at the end, when the last leg
/// takes it up through the surface.
struct VoyageChart: View {
    let voyage: Voyage
    /// Into the stage it's arrived at (BEGIN, or SWIM ON after a stage).
    let onSetOff: () -> Void
    /// Only past the last stage: a fresh run from the bottom.
    let onRestart: () -> Void
    /// Only past the last stage: back to the menu.
    let onSurface: () -> Void
    /// Zen mode, at the start of a run: a stop was tapped, to start there. Nil when
    /// stops can't be picked.
    var onPickStage: ((Int) -> Void)? = nil

    /// How far the marker has swum this leg, 0 (at `from`) ... 1 (at `to`).
    @State private var leg: CGFloat = 0
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Stop {
        let name: String
        let bossName: String
        let depth: Int
        let hint: String
        let icon: Image
    }

    private static let stops: [Stop] = AdventureStage.all.enumerated().map { index, stage in
        Stop(name: stage.name, bossName: stage.bossName, depth: stage.depth, hint: stage.hint, icon: icon(forStage: index))
    }

    /// Waypoints, as fractions of the chart: the abyss where a run begins, one per
    /// stop, winding up, and last the surface (on `SurfaceLine`). One more stop
    /// needs one more point.
    private static let waypoints: [CGPoint] = [
        CGPoint(x: 0.16, y: 0.84),
        CGPoint(x: 0.32, y: 0.71),
        CGPoint(x: 0.68, y: 0.51),
        CGPoint(x: 0.38, y: 0.29),
        CGPoint(x: 0.5, y: 0.2),
    ]

    private static let teal = Color("BioluminescentGlow")
    private static let gold = Color("PaleGold")

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let route = Route(size: size)
            let start = route.fraction(atWaypoint: voyage.from.map { $0 + 1 } ?? 0)
            let end = route.fraction(atWaypoint: voyage.to + 1)
            let traveled = start + (end - start) * leg

            ZStack {
                SeaBackground()

                SurfaceLine(isAnimated: !reduceMotion)
                    .frame(height: 40)
                    .position(x: size.width / 2, y: size.height * 0.2)

                route.path
                    .stroke(Color("Foam").opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
                route.path
                    .trim(from: 0, to: traveled)
                    .stroke(Self.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: Self.teal, radius: 6)

                ForEach(Self.stops.indices, id: \.self) { index in
                    stopView(index, at: route.point(atWaypoint: index + 1), in: size)
                }

                Traveler(progress: traveled, route: route)

                VStack(spacing: 0) {
                    FloatingTitle(lines: [
                        FloatingTitle.Line(text: "THE", fontSize: 22, tracking: 14, centerY: 0.26),
                        FloatingTitle.Line(text: "ASCENT", fontSize: 46, tracking: 6, centerY: 0.66),
                    ], height: 110)
                    if let caption {
                        Text(caption)
                            .font(.custom("Work Sans", size: 15))
                            .foregroundStyle(Self.gold.opacity(0.9))
                    }
                    Spacer()
                    buttons
                        .padding(.bottom, 24)
                }
                .padding(.top, 34)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else {
                leg = 1
                return
            }
            withAnimation(.easeInOut(duration: 2.4).delay(0.5)) {
                leg = 1
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) {
                isPulsing = true
            }
        }
    }

    /// A line under the title, when there's something to say.
    private var caption: String? {
        if voyage.isFinal {
            return "You've reached the surface"
        }
        return onPickStage == nil ? nil : "Zen: tap any stop to start there"
    }

    // MARK: Stops

    private func stopView(_ index: Int, at point: CGPoint, in size: CGSize) -> some View {
        let stop = Self.stops[index]
        // Stages actually beaten: not ones a zen-mode run skipped past.
        let isCleared = voyage.from.map { index <= $0 } ?? false
        let isTarget = index == voyage.to
        let labelOnRight = point.x < size.width / 2
        let ring: Color = isCleared ? Self.teal : (isTarget ? Self.gold : Color("Foam").opacity(0.35))

        let medallion = ZStack {
            Circle()
                .fill(Color("Abyss").opacity(0.75))
            stop.icon
                .resizable()
                .scaledToFit()
                .padding(8)
                .saturation(isCleared ? 0.2 : 1)
                .opacity(isCleared ? 0.55 : 1)
            Circle()
                .strokeBorder(ring, lineWidth: isTarget ? 2.5 : 1.5)
                .shadow(color: ring.opacity(isTarget ? (isPulsing ? 0.9 : 0.3) : 0), radius: 8)
            if isCleared {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Self.teal)
                    .background(Circle().fill(Color("Abyss")))
                    .offset(x: 24, y: -24)
            }
        }
        .frame(width: 66, height: 66)

        let label = VStack(alignment: labelOnRight ? .leading : .trailing, spacing: 2) {
            Text(stop.name)
                .font(.custom("Cinzel", size: 17).weight(.semibold))
                .foregroundStyle(Color("Foam"))
            Text(stop.bossName)
                .font(.custom("Work Sans", size: 11).weight(.semibold))
                .tracking(2)
                .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(isCleared ? 0.5 : 0.9))
            Text("\(stop.depth.formatted()) m")
                .font(.custom("Work Sans", size: 11))
                .foregroundStyle(Color("Foam").opacity(0.55))
            if isTarget {
                Text(stop.hint)
                    .font(.custom("Work Sans", size: 12).italic())
                    .foregroundStyle(Self.gold.opacity(0.85))
                    .multilineTextAlignment(labelOnRight ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 180, alignment: labelOnRight ? .leading : .trailing)

        return HStack(spacing: 12) {
            if labelOnRight {
                medallion
                label
            } else {
                label
                medallion
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPickStage?(index)
        }
        // Centered on the medallion, wherever the label sits.
        .offset(x: labelOnRight ? 96 : -96)
        .position(point)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stop.name)
        .accessibilityValue(isCleared ? "Cleared" : (isTarget ? "Next: \(stop.hint)" : "Ahead"))
        .accessibilityAddTraits(onPickStage == nil ? [] : .isButton)
        .accessibilityHint(onPickStage == nil ? "" : "Starts the run here")
    }

    @ViewBuilder private var buttons: some View {
        if voyage.isFinal {
            VStack(spacing: 18) {
                Button(action: onRestart) {
                    Text("DIVE\nAGAIN")
                        .font(.custom("Cinzel", size: 17).weight(.semibold))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(DiveButtonStyle(diameter: 112))
                .accessibilityLabel("Dive again")

                Button(action: onSurface) {
                    Label("SURFACE", systemImage: "arrow.up")
                        .font(.custom("Cinzel", size: 15).weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Color("Foam"))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(Color("Abyss").opacity(0.6))
                                .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Returns to the main menu")
            }
        } else {
            Button(action: onSetOff) {
                Text(voyage.from == nil ? "BEGIN" : "SWIM\nON")
                    .font(.custom("Cinzel", size: 18).weight(.semibold))
                    .tracking(2)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(DiveButtonStyle(diameter: 112))
            .accessibilityLabel(voyage.from == nil ? "Begin" : "Swim on")
            .accessibilityHint("Starts \(Self.stops[voyage.to].name)")
        }
    }

    /// A stage's boss, from its game art: the kraken's body, the moray's head, the
    /// galleon.
    private static func icon(forStage index: Int) -> Image {
        let cellSize: CGFloat = 24
        let texture: SKTexture
        switch AdventureStage.all[index].boss {
        case .kraken:
            texture = SpriteArt.krakenBody(cellSize: cellSize)
        case .moray:
            texture = SpriteArt.morayHead(cellSize: cellSize)
        case .galleon:
            texture = SpriteArt.galleon(cellSize: cellSize)
        }
        return Image(decorative: texture.cgImage(), scale: 1)
    }

    // MARK: Route

    /// The winding route through the waypoints, scaled to the chart, sampled finely
    /// enough that a point can be found at any fraction of its length.
    fileprivate struct Route {
        let samples: [CGPoint]
        /// Cumulative length at each sample.
        let lengths: [CGFloat]
        /// Index into `samples` of each waypoint.
        let waypointSamples: [Int]

        private static let samplesPerLeg = 40

        init(size: CGSize) {
            let points = VoyageChart.waypoints.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            var samples: [CGPoint] = [points[0]]
            var waypointSamples = [0]
            for (from, to) in zip(points, points.dropFirst()) {
                // An S-bend: leave going up from `from`, arrive going up into `to`.
                let middle = (from.y + to.y) / 2
                let control1 = CGPoint(x: from.x, y: middle)
                let control2 = CGPoint(x: to.x, y: middle)
                for step in 1...Route.samplesPerLeg {
                    let t = CGFloat(step) / CGFloat(Route.samplesPerLeg)
                    let u = 1 - t
                    samples.append(CGPoint(
                        x: u * u * u * from.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * to.x,
                        y: u * u * u * from.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * to.y
                    ))
                }
                waypointSamples.append(samples.count - 1)
            }
            var lengths: [CGFloat] = [0]
            for (a, b) in zip(samples, samples.dropFirst()) {
                lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
            }
            self.samples = samples
            self.lengths = lengths
            self.waypointSamples = waypointSamples
        }

        var path: Path {
            Path { path in
                path.addLines(samples)
            }
        }

        private var total: CGFloat { max(1, lengths[lengths.count - 1]) }

        func fraction(atWaypoint index: Int) -> CGFloat {
            lengths[waypointSamples[min(index, waypointSamples.count - 1)]] / total
        }

        func point(atWaypoint index: Int) -> CGPoint {
            samples[waypointSamples[min(index, waypointSamples.count - 1)]]
        }

        /// The point `fraction` of the way along the route, by length.
        func point(at fraction: CGFloat) -> CGPoint {
            let target = min(max(fraction, 0), 1) * total
            guard let upper = lengths.firstIndex(where: { $0 >= target }), upper > 0 else { return samples[0] }
            let lower = upper - 1
            let span = lengths[upper] - lengths[lower]
            let t = span > 0 ? (target - lengths[lower]) / span : 0
            return CGPoint(
                x: samples[lower].x + (samples[upper].x - samples[lower].x) * t,
                y: samples[lower].y + (samples[upper].y - samples[lower].y) * t
            )
        }
    }

    /// The snake's marker: a glowing teal head with a few fading beads trailing
    /// behind it along the route. Animatable, so it swims rather than jumps.
    private struct Traveler: View, Animatable {
        var progress: CGFloat
        let route: Route

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        var body: some View {
            ZStack {
                ForEach((1...4).reversed(), id: \.self) { bead in
                    Circle()
                        .fill(VoyageChart.teal.opacity(0.55 - Double(bead) * 0.1))
                        .frame(width: 10 - CGFloat(bead), height: 10 - CGFloat(bead))
                        .position(route.point(at: progress - CGFloat(bead) * 0.012))
                }
                Circle()
                    .fill(VoyageChart.teal)
                    .frame(width: 13, height: 13)
                    .shadow(color: VoyageChart.teal, radius: 8)
                    .position(route.point(at: progress))
            }
            .accessibilityHidden(true)
        }
    }
}

/// The surface far overhead: a lighter band of water under a slow, wavy line.
private struct SurfaceLine: View {
    let isAnimated: Bool

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { timeline in
            let time = isAnimated ? AmbientClock.seconds(at: timeline.date) : AmbientClock.still
            Canvas { context, size in
                var wave = Path()
                let steps = 60
                for step in 0...steps {
                    let x = size.width * CGFloat(step) / CGFloat(steps)
                    let y = size.height / 2 + 4 * CGFloat(sin(Double(x) / 28 + time * 1.2))
                    if step == 0 {
                        wave.move(to: CGPoint(x: x, y: y))
                    } else {
                        wave.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(wave, with: .color(Color("Foam").opacity(0.45)), lineWidth: 1.5)
                var above = wave
                above.addLine(to: CGPoint(x: size.width, y: 0))
                above.addLine(to: .zero)
                above.closeSubpath()
                context.fill(above, with: .color(Color("Foam").opacity(0.06)))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VoyageChart(voyage: Voyage(from: 0, to: 1), onSetOff: {}, onRestart: {}, onSurface: {})
}
