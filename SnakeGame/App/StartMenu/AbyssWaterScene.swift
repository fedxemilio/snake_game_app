import SpriteKit

/// A one-node SpriteKit scene whose only job is to run the start menu's water shader
/// across the whole screen: `SeaBackground`'s style-guide gradient, stirred into slow,
/// heavy murk, with light shafts leaning down from the surface, caustics rippling
/// just under it, a vignette, and the odd flash of lightning overhead.
///
/// It's an `SKShader` (compiled at runtime) rather than a SwiftUI Metal shader on
/// purpose: SwiftUI shaders need `.metal` files, and Xcode 26 only builds those after
/// a separate Metal Toolchain download. This keeps the project building on a stock
/// Xcode.
///
/// The shader is driven by `MenuClock`, not SpriteKit's own `u_time`, so it agrees
/// with the rest of the menu (the lightning in particular is shared logic).
final class AbyssWaterScene: SKScene {
    private let water = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    private let clock = SKUniform(name: "u_clock", float: 0)
    private let flash = SKUniform(name: "u_flash", float: 0)
    private let sizeUniform = SKUniform(name: "u_size", vectorFloat2: .one)

    override init(size: CGSize = CGSize(width: 1, height: 1)) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero

        let shader = SKShader(source: Self.source)
        shader.uniforms = [clock, flash, sizeUniform]
        water.shader = shader
        water.anchorPoint = .zero
        addChild(water)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        water.size = size
        sizeUniform.vectorFloat2Value = SIMD2(Float(size.width), Float(size.height))
    }

    override func update(_ currentTime: TimeInterval) {
        let time = MenuClock.seconds(at: Date())
        clock.floatValue = Float(time)
        flash.floatValue = Float(LivingSea.lightning(at: time))
    }

    // `v_tex_coord` has y = 0 at the bottom; `depth` flips it so 0 is the surface.
    // The gradient stops and radial highlights mirror `SeaBackground` (and the
    // style guide's CSS); keep them in step if either changes.
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
        float aspect = u_size.x / u_size.y;
        vec2 p = vec2(v_tex_coord.x * aspect, depth) * 2.4;
        float t = u_clock * 0.035;

        vec3 water = seaGradient(depth);
        float glowA = 0.22 * (1.0 - clamp(distance(point, u_size * vec2(0.2, -0.1)) / (u_size.x * 0.9), 0.0, 1.0));
        water = mix(water, vec3(0.47, 0.55, 0.63), glowA);
        float glowB = 0.18 * (1.0 - clamp(distance(point, u_size * vec2(0.9, 0.05)) / (u_size.x * 0.75), 0.0, 1.0));
        water = mix(water, vec3(0.35, 0.43, 0.51), glowB);

        // Murk: noise warped by noise, so it swirls and folds like water stirred by
        // something big rather than just scrolling past.
        vec2 warp = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3) - t));
        float murk = fbm(p + 3.2 * warp + vec2(0.6 * t, -0.4 * t));

        // Troughs sink toward black; crests catch a cold, sickly teal.
        water *= mix(0.5, 1.6, smoothstep(0.25, 0.8, murk));
        water += vec3(0.07, 0.30, 0.27) * smoothstep(0.5, 0.9, murk) * 0.45 * (1.0 - 0.5 * depth);
        // The deepest folds get a faint green bruise.
        water += vec3(0.02, 0.10, 0.07) * smoothstep(0.55, 0.85, warp.y) * depth;

        // Light shafts from the surface: leaning, slowly swaying, gone by mid-depth.
        float shaftX = v_tex_coord.x * aspect + depth * 0.42 + 0.06 * sin(u_clock * 0.13);
        float shafts = noise(vec2(shaftX * 5.0, u_clock * 0.07))
                     * noise(vec2(shaftX * 11.0 + 3.0, u_clock * 0.10 + 7.0));
        shafts = pow(shafts, 1.5);
        float reach = pow(clamp(1.0 - depth * 1.25, 0.0, 1.0), 2.4);
        water += vec3(0.42, 0.62, 0.62) * shafts * reach * (0.26 + 0.9 * u_flash);

        // Caustics: thin bright ridges rippling just under the surface.
        float ridge = 1.0 - abs(2.0 * noise(p * 3.5 + vec2(t * 9.0, -t * 6.0)) - 1.0);
        ridge *= 1.0 - abs(2.0 * noise(p * 2.3 - vec2(t * 7.0, t * 5.0) + 4.0) - 1.0);
        water += vec3(0.55, 0.75, 0.72) * pow(ridge, 7.0) * 0.18 * (1.0 - smoothstep(0.0, 0.32, depth));

        // Lightning above the surface: a cold wash that fades with depth.
        water += vec3(0.55, 0.68, 0.75) * u_flash * pow(1.0 - depth, 2.5) * 0.22;

        // The style guide's diagonal rain streaks, fainter than its 0.035: under
        // moving water, full-strength static lines read as a screen pattern.
        float streak = fract((point.x + point.y * 0.176) / 16.0);
        water += vec3(0.018) * step(streak, 1.0 / 16.0);

        // Vignette, heavier toward the floor so the edges fall away into nothing.
        vec2 centered = (vec2(v_tex_coord.x, depth) - vec2(0.5, 0.42)) * vec2(1.15, 0.85);
        water *= clamp(1.0 - dot(centered, centered) * 1.1, 0.0, 1.0);

        // A touch of dither so the dark gradients don't band.
        water += (hash(point * 3.0) - 0.5) / 255.0;

        gl_FragColor = vec4(water, 1.0);
    }
    """
}
