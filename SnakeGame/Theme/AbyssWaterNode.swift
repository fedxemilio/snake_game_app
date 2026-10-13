import SpriteKit

/// The deep water everything in Sea Snake sits in: `SeaBackground`'s style-guide
/// gradient, stirred into slow, heavy murk, with light shafts leaning down from the
/// surface, caustics rippling just under it, and a vignette. One sprite running one
/// shader; size it to cover whatever it's behind.
///
/// - The start menu (`AbyssWaterScene`) runs it at full `energy`, with lightning.
/// - The game (`GameScene`) runs it calmer, so the board stays easy to read. In
///   Adventure it's sized to the whole map rather than the screen, so the water
///   gets darker the deeper the snake swims.
///
/// It's an `SKShader` (compiled at runtime) rather than a SwiftUI Metal shader on
/// purpose: SwiftUI shaders need `.metal` files, and Xcode 26 only builds those after
/// a separate Metal Toolchain download. This keeps the project building on a stock
/// Xcode.
final class AbyssWaterNode: SKSpriteNode {
    private let clock = SKUniform(name: "u_clock", float: 0)
    private let flash = SKUniform(name: "u_flash", float: 0)
    private let sizeUniform = SKUniform(name: "u_size", vectorFloat2: .one)
    private let energyUniform: SKUniform

    override var size: CGSize {
        didSet { sizeUniform.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height)) }
    }

    /// - Parameter energy: 1 for the menu's full churn. Lower values flatten the
    ///   murk and dim the light shafts, caustics, rain and vignette together.
    init(energy: Float) {
        energyUniform = SKUniform(name: "u_energy", float: energy)
        super.init(texture: nil, color: .black, size: CGSize(width: 1, height: 1))
        anchorPoint = .zero

        let shader = SKShader(source: Self.source)
        shader.uniforms = [clock, flash, sizeUniform, energyUniform]
        self.shader = shader
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Moves the water to `time` (`AmbientClock` seconds), with an optional
    /// lightning `flash` (0...1) lighting it from above.
    func update(time: Double, flash: Double = 0) {
        clock.floatValue = Float(time)
        self.flash.floatValue = Float(flash)
    }

    // `v_tex_coord` has y = 0 at the bottom; `depth` flips it so 0 is the surface.
    // Noise is scaled in points (`point / 360`), so the murk's swirls are the same
    // physical size whether the node covers one screen or a whole Adventure map.
    // The gradient stops and radial highlights mirror `SeaBackground` (and the style
    // guide's CSS); keep them in step if either changes.
    private static let source = """
    float hash(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
                   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    }

    float fbm(vec2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int octave = 0; octave < 4; octave++) {
            value += amplitude * noise(p);
            p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.03 + 1.7;
            amplitude *= 0.5;
        }
        return value;
    }

    vec3 seaGradient(float depth) {
        vec3 navy = vec3(0.043, 0.071, 0.125);
        vec3 storm = vec3(0.063, 0.125, 0.169);
        vec3 deepSea = vec3(0.039, 0.169, 0.204);
        vec3 abyss = vec3(0.016, 0.078, 0.102);
        if (depth < 0.35) { return mix(navy, storm, depth / 0.35); }
        if (depth < 0.65) { return mix(storm, deepSea, (depth - 0.35) / 0.3); }
        return mix(deepSea, abyss, (depth - 0.65) / 0.35);
    }

    void main() {
        float depth = 1.0 - v_tex_coord.y;
        vec2 point = vec2(v_tex_coord.x, depth) * u_size;
        vec2 p = point / 360.0;
        float t = u_clock * 0.035;
        float e = u_energy;

        // The style guide's two soft highlights near the surface, sized to a
        // screen's width at most: stretched across an Adventure map they'd fog the
        // whole thing grey.
        vec3 water = seaGradient(depth);
        float span = min(u_size.x, 450.0);
        float glowA = 0.22 * (1.0 - clamp(distance(point, vec2(0.2 * span, -0.1 * u_size.y)) / (span * 0.9), 0.0, 1.0));
        water = mix(water, vec3(0.47, 0.55, 0.63), glowA);
        float glowB = 0.18 * (1.0 - clamp(distance(point, vec2(u_size.x - 0.1 * span, 0.05 * u_size.y)) / (span * 0.75), 0.0, 1.0));
        water = mix(water, vec3(0.35, 0.43, 0.51), glowB);

        // Murk: noise warped by noise, so it swirls and folds like water stirred by
        // something big rather than just scrolling past.
        vec2 warp = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3) - t));
        float murk = fbm(p + 3.2 * warp + vec2(0.6 * t, -0.4 * t));

        // Troughs sink toward black; crests catch a cold, sickly teal.
        water *= mix(1.0 - 0.5 * e, 1.0 + 0.6 * e, smoothstep(0.25, 0.8, murk));
        water += vec3(0.07, 0.30, 0.27) * smoothstep(0.5, 0.9, murk) * 0.45 * e * (1.0 - 0.5 * depth);
        // The deepest folds get a faint green bruise.
        water += vec3(0.02, 0.10, 0.07) * smoothstep(0.55, 0.85, warp.y) * depth;

        // Light shafts from the surface: leaning, slowly swaying, gone by mid-depth.
        float shaftX = point.x / 870.0 + depth * 0.42 + 0.06 * sin(u_clock * 0.13);
        float shafts = noise(vec2(shaftX * 5.0, u_clock * 0.07))
                     * noise(vec2(shaftX * 11.0 + 3.0, u_clock * 0.10 + 7.0));
        shafts = pow(shafts, 1.5);
        float reach = pow(clamp(1.0 - depth * 1.25, 0.0, 1.0), 2.4);
        water += vec3(0.42, 0.62, 0.62) * shafts * reach * (0.26 * e + 0.9 * u_flash);

        // Caustics: thin bright ridges rippling just under the surface.
        float ridge = 1.0 - abs(2.0 * noise(p * 3.5 + vec2(t * 9.0, -t * 6.0)) - 1.0);
        ridge *= 1.0 - abs(2.0 * noise(p * 2.3 - vec2(t * 7.0, t * 5.0) + 4.0) - 1.0);
        water += vec3(0.55, 0.75, 0.72) * pow(ridge, 7.0) * 0.18 * e * (1.0 - smoothstep(0.0, 0.32, depth));

        // Lightning above the surface: a cold wash that fades with depth.
        water += vec3(0.55, 0.68, 0.75) * u_flash * pow(1.0 - depth, 2.5) * 0.22;

        // The style guide's diagonal rain streaks, fainter than its 0.035: under
        // moving water, full-strength static lines read as a screen pattern.
        float streak = fract((point.x + point.y * 0.176) / 16.0);
        water += vec3(0.018 * e) * step(streak, 1.0 / 16.0);

        // Vignette, heavier toward the floor so the edges fall away into nothing.
        vec2 centered = (vec2(v_tex_coord.x, depth) - vec2(0.5, 0.42)) * vec2(1.15, 0.85);
        water *= clamp(1.0 - dot(centered, centered) * 1.1 * e, 0.0, 1.0);

        // A touch of dither so the dark gradients don't band.
        water += (hash(point * 3.0) - 0.5) / 255.0;

        gl_FragColor = vec4(water, 1.0);
    }
    """
}
