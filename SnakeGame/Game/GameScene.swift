import SpriteKit

final class GameScene: SKScene {
    private let mode: GameMode
    /// Zen mode (for testing): nothing costs a life. See `GameManager.hurtPlayer`.
    private let isZen: Bool
    private let columns: Int
    private let rows: Int

    /// Fixed cell size for Adventure mode -- unlike free-play/levels, the
    /// grid doesn't need to fit the screen; it's meant to be larger than
    /// it, with the camera panning to follow the snake.
    private static let adventureCellSize: CGFloat = 24

    private var gameManager: GameManager!

    /// The deep water behind everything (see `AbyssWaterNode`), calmer than the
    /// menu's so the board stays easy to read.
    private let water = AbyssWaterNode(energy: 0.45)

    /// Matches the system setting when the scene starts: the water holds still and
    /// the marine snow is left out.
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    /// Camera shake in progress (Adventure only): seconds left, its full length,
    /// and how far it throws the view at the start, in points.
    private var shakeRemaining: TimeInterval = 0
    private var shakeDuration: TimeInterval = 0
    private var shakeStrength: CGFloat = 0
    private var lastFrameTime: TimeInterval = 0

    private let hitHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let explosionHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let deathHaptic = UINotificationFeedbackGenerator()
    private let pushHaptic = UIImpactFeedbackGenerator(style: .light)

    /// Non-nil only in .adventure mode. Its presence is also what tells
    /// setUpMarineSnow() and update() to do camera-relative placement and
    /// per-frame following, respectively.
    private var cameraNode: SKCameraNode?
    private var worldSize: CGSize = .zero

    /// How far (in points) a drag has to travel along its dominant axis
    /// before it registers as a turn. Small enough that quick back-to-back
    /// direction changes (e.g. down-then-right in a tight corner) don't
    /// each need a full separate gesture -- the translation resets to zero
    /// after every registered turn, so the next turn only needs to clear
    /// this threshold again from the finger's *current* position.
    private let dragTurnThreshold: CGFloat = 24

    /// Fired once, when a run ends. The Game Over UI itself lives in
    /// SwiftUI (GameOverOverlay), not in the scene.
    var onGameOver: (() -> Void)?

    /// Fired whenever the score changes (including the reset to 0 at the start
    /// of a run). The score HUD lives in SwiftUI, like the overlays.
    var onScoreChanged: ((Int) -> Void)?

    /// Fired each time a level's threshold is hit (.levels mode only). Same
    /// pattern as onGameOver -- the overlay lives in SwiftUI.
    var onLevelComplete: (() -> Void)?

    /// Fired with the boss's name and lives whenever they change, or nil when
    /// this run has no boss. Its HUD lives in SwiftUI, like the score's. Setting
    /// it replays the current value: the first report comes from `didMove(to:)`,
    /// which can run before SwiftUI has attached this.
    var onBossChanged: ((GameManager.BossStatus?) -> Void)? {
        didSet { onBossChanged?(boss) }
    }
    private var boss: GameManager.BossStatus?

    /// Adventure: a stage's boss is beaten and its send-off has played; the game
    /// waits for `beginNextStage()` (or a new run). Passes the stage's index into
    /// `AdventureStage.all`. The victory screen and voyage chart live in SwiftUI.
    var onStageCleared: ((Int) -> Void)?

    /// Fired with the snake's remaining lives whenever they change, or nil in
    /// modes where it only has one. Replays on set, like `onBossChanged`.
    var onLivesChanged: ((Int?) -> Void)? {
        didSet { onLivesChanged?(lives) }
    }
    private var lives: Int?

    /// Fired with mine fruit progress and mines ready whenever they change, or nil
    /// in modes without mine fruit. Replays on set, like `onBossChanged`.
    var onMineSupplyChanged: ((GameManager.MineSupply?) -> Void)? {
        didSet { onMineSupplyChanged?(mineSupply) }
    }
    private var mineSupply: GameManager.MineSupply?

    init(mode: GameMode, isZen: Bool = false) {
        self.mode = mode
        self.isZen = isZen
        switch mode {
        case .freePlay:
            columns = 16
            rows = 24
        case .levels:
            // All levels share one grid size -- see Level.swift.
            columns = Level.all[0].columns
            rows = Level.all[0].rows
        case .adventure:
            columns = AdventureMap.columns
            rows = AdventureMap.rows
        }
        super.init(size: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(named: "Abyss") ?? .black

        let cellSize: CGFloat
        let origin: CGPoint
        switch mode {
        case .freePlay, .levels:
            // Free play leaves room around the grid for its board panel's
            // rounded edge and glow; at 16 columns it would otherwise run
            // edge to edge and the panel would spill off the screen.
            let margin: CGFloat = mode == .freePlay ? 14 : 0
            let cellWidth = (size.width - margin * 2) / CGFloat(columns)
            let cellHeight = (size.height - margin * 2) / CGFloat(rows)
            cellSize = min(cellWidth, cellHeight)
            origin = CGPoint(
                x: (size.width - CGFloat(columns) * cellSize) / 2,
                y: (size.height - CGFloat(rows) * cellSize) / 2
            )
        case .adventure:
            cellSize = Self.adventureCellSize
            origin = .zero
            worldSize = CGSize(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
            setUpCamera()
        }

        gameManager = GameManager(scene: self, mode: mode, isZen: isZen, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
        gameManager.onScoreChanged = { [weak self] score in
            self?.onScoreChanged?(score)
        }
        gameManager.onGameOver = { [weak self] in
            self?.onGameOver?()
        }
        gameManager.onJolt = { [weak self] jolt in
            self?.feel(jolt)
        }
        gameManager.onMineSupplyChanged = { [weak self] supply in
            self?.mineSupply = supply
            self?.onMineSupplyChanged?(supply)
        }
        gameManager.onLivesChanged = { [weak self] lives in
            self?.lives = lives
            self?.onLivesChanged?(lives)
        }
        gameManager.onBossChanged = { [weak self] status in
            self?.boss = status
            self?.onBossChanged?(status)
        }
        gameManager.onStageCleared = { [weak self] stage in
            self?.onStageCleared?(stage)
        }
        gameManager.onLevelComplete = { [weak self] in
            self?.onLevelComplete?()
        }

        setUpWater()

        // Free-play's grid doesn't fill the screen, so a board panel marks its
        // wrap boundary. Levels mode and Adventure mode already use (most
        // of, or far more than) the screen, so the edge is visible on its
        // own -- Adventure's map even has its own border walls baked in.
        if mode == .freePlay {
            drawBoard(cellSize: cellSize, origin: origin)
        }

        setUpMarineSnow()
        setUpInputGesture(on: view)
        // Adventure's first run waits on the voyage chart (`releaseStart()`).
        gameManager.startNewGame(holdingForCue: mode == .adventure)

        // Set the camera to its correct starting position before the first
        // frame renders, rather than letting it snap there on frame two.
        if mode == .adventure {
            updateCamera()
        }
    }

    /// Called from the Game Over overlay's Play Again button.
    func startNewGame() {
        gameManager.startNewGame()
    }

    /// Called from the Level Complete overlay's tap.
    func beginNextLevel() {
        gameManager.beginNextLevel()
    }

    /// Called when the player sets off from the voyage chart at the start of an
    /// Adventure run.
    func releaseStart() {
        gameManager.releaseStart()
    }

    /// Zen mode: called when a stop is picked on the voyage chart at the start of an
    /// Adventure run, to start there instead.
    func chooseStartingStage(_ index: Int) {
        gameManager.chooseStartingStage(index)
    }

    /// Called when the player sets off from the voyage chart after a stage is
    /// cleared.
    func beginNextStage() {
        gameManager.beginNextStage()
    }

    // MARK: - Setup

    /// The water covers the screen, or in Adventure the whole map: there it stays
    /// put while the camera moves over it, so the water darkens toward the bottom
    /// of the map like real depth, and drifts past as the snake swims.
    private func setUpWater() {
        water.size = mode == .adventure ? worldSize : size
        water.zPosition = -10
        water.update(time: AmbientClock.still)
        addChild(water)
    }

    /// The style guide's board panel around the free-play grid, padded a little
    /// so its rounded corners don't clip the corner cells.
    private func drawBoard(cellSize: CGFloat, origin: CGPoint) {
        let padding: CGFloat = 6
        let gridSize = CGSize(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
        let boardSize = CGSize(width: gridSize.width + padding * 2, height: gridSize.height + padding * 2)

        let board = SKSpriteNode(texture: SpriteArt.board(size: boardSize, cornerRadius: 20))
        board.position = CGPoint(x: origin.x + gridSize.width / 2, y: origin.y + gridSize.height / 2)
        board.zPosition = -5
        addChild(board)
    }

    /// Specks of marine snow sinking slowly behind the board. In Adventure the
    /// emitter rides along the top of the camera's view, but its specks are
    /// left behind in the world (`targetNode`), so they scroll past like the
    /// water does.
    private func setUpMarineSnow() {
        guard !reduceMotion else { return }

        let snow = SKEmitterNode()
        snow.particleTexture = SpriteArt.speck()
        snow.particleBirthRate = 3
        snow.particleLifetime = 26
        snow.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0)
        snow.emissionAngle = -.pi / 2
        snow.emissionAngleRange = 0.5
        snow.particleSpeed = 30
        snow.particleSpeedRange = 18
        snow.particleAlpha = 0.28
        snow.particleAlphaRange = 0.18
        snow.particleScale = 0.45
        snow.particleScaleRange = 0.35
        snow.particleColor = SKColor(named: "Foam") ?? .white
        snow.particleColorBlendFactor = 1
        snow.zPosition = -8

        if let cameraNode {
            snow.position = CGPoint(x: 0, y: size.height / 2 + 10)
            snow.targetNode = self
            cameraNode.addChild(snow)
        } else {
            snow.position = CGPoint(x: size.width / 2, y: size.height + 10)
            addChild(snow)
        }
        // Start with the screen already full of snow rather than a first fall.
        snow.advanceSimulationTime(24)
    }

    /// Adventure mode only: a camera that follows the snake (`GameManager.cameraFocus`), clamped so
    /// the viewport never shows past the map's edges.
    private func setUpCamera() {
        let camera = SKCameraNode()
        addChild(camera)
        self.camera = camera
        cameraNode = camera
    }

    private func updateCamera(delta: TimeInterval = 0) {
        guard let cameraNode else { return }

        let focus = gameManager.cameraFocus
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let x = worldSize.width <= size.width
            ? worldSize.width / 2
            : min(max(focus.x, halfWidth), worldSize.width - halfWidth)
        let y = worldSize.height <= size.height
            ? worldSize.height / 2
            : min(max(focus.y, halfHeight), worldSize.height - halfHeight)

        let shake = shakeOffset(delta: delta)
        cameraNode.position = CGPoint(x: x + shake.x, y: y + shake.y)
    }

    /// This frame's shake, dying away over its duration. Advances the shake by
    /// `delta`.
    private func shakeOffset(delta: TimeInterval) -> CGPoint {
        shakeRemaining = max(0, shakeRemaining - delta)
        guard shakeRemaining > 0, shakeDuration > 0 else { return .zero }
        let reach = shakeStrength * CGFloat(shakeRemaining / shakeDuration)
        return CGPoint(x: .random(in: -reach...reach), y: .random(in: -reach...reach))
    }

    private func shake(strength: CGFloat, duration: TimeInterval) {
        guard !reduceMotion, cameraNode != nil else { return }
        // A stronger jolt takes over; a weaker one doesn't cut a stronger one short.
        let current = shakeDuration > 0 ? shakeStrength * CGFloat(shakeRemaining / shakeDuration) : 0
        guard strength >= current else { return }
        shakeStrength = strength
        shakeDuration = duration
        shakeRemaining = duration
    }

    private func feel(_ jolt: GameManager.Jolt) {
        switch jolt {
        case .hit:
            shake(strength: 6, duration: 0.3)
            hitHaptic.impactOccurred()
        case .death:
            shake(strength: 10, duration: 0.55)
            deathHaptic.notificationOccurred(.error)
        case .explosion(let point):
            guard isOnScreen(point) else { return }
            shake(strength: 4, duration: 0.25)
            explosionHaptic.impactOccurred(intensity: 0.7)
        case .push, .drop:
            pushHaptic.impactOccurred()
        }
    }

    /// Whether `point` (scene coordinates) is in view. Only Adventure scrolls, so
    /// everywhere else the whole board always is.
    private func isOnScreen(_ point: CGPoint) -> Bool {
        guard let cameraNode else { return true }
        return abs(point.x - cameraNode.position.x) < size.width / 2 + 24
            && abs(point.y - cameraNode.position.y) < size.height / 2 + 24
    }

    /// Continuous drag-to-steer rather than discrete swipes: a swipe
    /// recognizer only fires once its *entire* gesture clears UIKit's own
    /// distance/velocity thresholds, which made quick direction reversals
    /// at high speed feel like they needed two full separate flicks. A pan
    /// recognizes translation live, so a turn registers the moment the
    /// finger crosses `dragTurnThreshold` -- no need to lift and re-swipe.
    private func setUpInputGesture(on view: SKView) {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(recognizer)

        // A tap (a touch that doesn't travel, so it never competes with a steering
        // drag) drops a mine, when one's ready.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        gameManager.dropMine()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }

        let translation = recognizer.translation(in: recognizer.view)
        let direction: Direction
        if abs(translation.x) > abs(translation.y) {
            guard abs(translation.x) >= dragTurnThreshold else { return }
            direction = translation.x > 0 ? .right : .left
        } else {
            guard abs(translation.y) >= dragTurnThreshold else { return }
            // UIKit's translation is screen-space (y grows downward),
            // matching "down" here regardless of the scene's y-up grid.
            direction = translation.y > 0 ? .down : .up
        }

        gameManager.turn(to: direction)
        recognizer.setTranslation(.zero, in: recognizer.view)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let delta = lastFrameTime == 0 ? 0 : currentTime - lastFrameTime
        lastFrameTime = currentTime

        gameManager.tick(currentTime: currentTime)
        if mode == .adventure {
            updateCamera(delta: delta)
        }
        let time = AmbientClock.seconds(at: Date())
        if !reduceMotion {
            water.update(time: time, flash: gameManager.lightning(at: time))
        }
        gameManager.animate(time: time)
    }
}
