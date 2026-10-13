import SwiftUI

/// Something enormous in the deep: a sea serpent's silhouette, far off and blurred by
/// the murk, gliding across the menu every so often with a ridge of fins along its
/// back, lights rippling down its flank and one pale eye.
///
/// Stateless, like the rest of the menu's drawing: each pass's depth, size, heading
/// and route come from `AmbientClock.random` seeded with the pass number, and its body is
/// worked out fresh each frame from the clock.
enum LurkingSerpent {
    /// Seconds from the start of one pass to the next. The gap after `swimDuration`
    /// is empty water, so it reads as a sighting rather than a screensaver.
    private static let period = 32.0
    private static let swimDuration = 24.0
    /// Points along the spine. The body is drawn through them, so more is smoother.
    private static let spineCount = 56
    /// Half the body's thickness at its widest, before the per-pass scale.
    private static let maxRadius: CGFloat = 12

    private static let body = Color(red: 0.012, green: 0.035, blue: 0.05)
    private static let glow = Color("BioluminescentGlow")
    private static let eye = Color("PaleGold")

    static func paint(time: Double, size: CGSize, in context: GraphicsContext) {
        let pass = Int((time / period).rounded(.down))
        let elapsed = time - Double(pass) * period
        guard elapsed < swimDuration else { return }
        let progress = CGFloat(elapsed / swimDuration)

        // Each pass picks its own depth (smaller = farther = fainter), route and
        // heading. Passes alternate between the two stretches of open water the menu
        // leaves: overhead, above the title, and the gap between the title and the
        // mode picker. Anywhere else it would spend the pass hidden behind the UI.
        let scale = 0.8 + 0.4 * CGFloat(AmbientClock.random(pass, salt: 20))
        let isOverhead = pass.isMultiple(of: 2)
        let baseY = size.height * (isOverhead ? 0.12 : 0.385)
            + size.height * 0.03 * CGFloat(AmbientClock.random(pass, salt: 21) - 0.5)
        let routePhase = 6.3 * AmbientClock.random(pass, salt: 22)
        let heading: CGFloat = AmbientClock.random(pass, salt: 23) < 0.5 ? 1 : -1

        let spacing = 8 * scale
        let length = spacing * CGFloat(spineCount - 1)
        let margin: CGFloat = 40
        // Distance of the head along its route; starts with the whole body off one
        // side and ends with the tail clear of the other.
        let headDistance = -margin + progress * (size.width + length + 2 * margin)

        // The head follows a gentle rise and fall; the body trails along the same
        // route, with its own swimming undulation on top.
        func routeY(_ distance: CGFloat) -> CGFloat {
            baseY + size.height * 0.025 * CGFloat(sin(Double(distance / size.width) * 3.6 + routePhase))
        }

        var spine: [CGPoint] = []
        var radii: [CGFloat] = []
        for index in 0..<spineCount {
            let along = headDistance - CGFloat(index) * spacing
            let u = Double(index) / Double(spineCount - 1)
            // The wave travels head to tail and swings wider toward the tail.
            let swing = 11 * scale * CGFloat((0.2 + 0.8 * u) * sin(Double(index) * 0.21 - time * 2.3))
            spine.append(CGPoint(
                x: heading > 0 ? along : size.width - along,
                y: routeY(along) + swing
            ))
            radii.append(Self.maxRadius * scale * radiusProfile(u))
        }

        // Unit vectors pointing toward the head, and the side of the body facing up.
        let forward = spine.indices.map { index -> CGPoint in
            let ahead = spine[max(0, index - 1)]
            let behind = spine[min(spineCount - 1, index + 1)]
            return normalized(CGPoint(x: ahead.x - behind.x, y: ahead.y - behind.y))
        }
        let up = forward.map { CGPoint(x: $0.y * heading, y: -$0.x * heading) }

        let outline = bodyOutline(spine: spine, radii: radii, forward: forward, up: up)
        let finPath = fins(spine: spine, radii: radii, forward: forward, up: up, scale: scale)

        var silhouette = context
        silhouette.opacity = 0.75 + 0.2 * Double((scale - 0.8) / 0.4)

        // A wide, soft darkness around the body: something big blotting out what
        // little light there is. This is most of what makes it read in dark water.
        silhouette.drawLayer { layer in
            layer.addFilter(.blur(radius: 16 * scale))
            layer.fill(outline, with: .color(.black.opacity(0.45)))
        }

        silhouette.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.5 + 3 * (1.2 - scale)))
            layer.fill(outline, with: .color(body))
            layer.fill(finPath, with: .color(body))
            layer.stroke(outline, with: .color(glow.opacity(0.15)), lineWidth: 1)
            // Light from the surface catching the length of its back.
            layer.stroke(
                smoothOpenPath(through: spine.indices.map { offset(spine[$0], along: up[$0], by: radii[$0] * 0.85) }),
                with: .color(glow.opacity(0.32)),
                style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round)
            )
        }

        // Lights rippling down the flank, and the eye. Added light, so they glow
        // through the murk rather than sitting on top of it.
        silhouette.drawLayer { layer in
            layer.blendMode = .plusLighter
            for index in stride(from: 6, to: spineCount - 8, by: 3) {
                let pulse = pow(0.5 + 0.5 * sin(time * 2.6 - Double(index) * 0.32), 3)
                let point = offset(spine[index], along: up[index], by: -radii[index] * 0.45)
                light(at: point, core: 1.5 * scale, halo: 7 * scale, color: glow,
                      brightness: 0.35 + 0.65 * pulse, in: layer)
            }

            let eyePoint = offset(
                offset(spine[0], along: forward[0], by: radii[0] * 0.45),
                along: up[0],
                by: radii[0] * 0.3
            )
            let flicker = 0.85 + 0.15 * sin(time * 7.3) * sin(time * 3.1)
            light(at: eyePoint, core: 1.6 * scale, halo: 9 * scale, color: eye, brightness: flicker, in: layer)
        }
    }

    /// Body thickness along its length, 0 (snout) ... 1 (tail tip): a rounded head, a
    /// slight neck, then a long taper to the tail.
    private static func radiusProfile(_ u: Double) -> CGFloat {
        let snout = 0.75 + 0.25 * min(1, u / 0.04)
        let neck = 1 - 0.2 * exp(-pow((u - 0.09) / 0.045, 2))
        let taper = 1 - 0.9 * smoothstep(0.3, 1, u)
        return CGFloat(snout * neck * taper)
    }

    /// The closed outline around the spine, rounded at both ends.
    private static func bodyOutline(
        spine: [CGPoint], radii: [CGFloat], forward: [CGPoint], up: [CGPoint]
    ) -> Path {
        let last = spineCount - 1
        var points: [CGPoint] = [offset(spine[0], along: forward[0], by: radii[0] * 1.2)]
        for index in 0...last {
            points.append(offset(spine[index], along: up[index], by: radii[index]))
        }
        points.append(offset(spine[last], along: forward[last], by: -radii[last] * 1.5))
        for index in stride(from: last, through: 0, by: -1) {
            points.append(offset(spine[index], along: up[index], by: -radii[index]))
        }
        return smoothClosedPath(through: points)
    }

    /// A ridge of small swept-back fins along the back.
    private static func fins(
        spine: [CGPoint], radii: [CGFloat], forward: [CGPoint], up: [CGPoint], scale: CGFloat
    ) -> Path {
        var path = Path()
        for index in stride(from: 8, to: spineCount - 14, by: 4) {
            let base = spine[index]
            let height = (4 + 3 * radii[index] / (Self.maxRadius * scale)) * scale
            let front = offset(offset(base, along: up[index], by: radii[index] * 0.8), along: forward[index], by: 3 * scale)
            let back = offset(offset(base, along: up[index], by: radii[index] * 0.8), along: forward[index], by: -4 * scale)
            let tip = offset(offset(base, along: up[index], by: radii[index] + height), along: forward[index], by: -5 * scale)
            path.move(to: front)
            path.addQuadCurve(to: tip, control: offset(front, along: up[index], by: height * 0.7))
            path.addLine(to: back)
            path.closeSubpath()
        }
        return path
    }

    private static func light(
        at point: CGPoint, core: CGFloat, halo: CGFloat, color: Color, brightness: Double,
        in context: GraphicsContext
    ) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.55 * brightness), color.opacity(0)]),
                center: point, startRadius: 0, endRadius: halo
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
            with: .color(color.opacity(brightness))
        )
    }

    // MARK: Geometry helpers

    /// A smooth closed curve through `points`: quadratic segments between the
    /// midpoints, with each point as the control.
    private static func smoothClosedPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first, let lastPoint = points.last else { return path }
        path.move(to: midpoint(lastPoint, first))
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(point, next), control: point)
        }
        path.closeSubpath()
        return path
    }

    /// A smooth open curve through `points`, the same midpoint construction as
    /// `smoothClosedPath`.
    private static func smoothOpenPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        path.move(to: points[0])
        for index in 1..<(points.count - 1) {
            path.addQuadCurve(to: midpoint(points[index], points[index + 1]), control: points[index])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func offset(_ point: CGPoint, along direction: CGPoint, by distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.x * distance, y: point.y + direction.y * distance)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func normalized(_ vector: CGPoint) -> CGPoint {
        let length = max(0.0001, hypot(vector.x, vector.y))
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
