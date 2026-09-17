import SpriteKit

final class GameScene: SKScene {
    private let mode: GameMode
    private let columns: Int
    private let rows: Int

    /// Fixed cell size for Adventure mode -- unlike free-play/levels, the
    /// grid doesn't need to fit the screen; it's meant to be larger than
    /// it, with the camera panning to follow the snake.
    private static let adventureCellSize: CGFloat = 24

    private var gameManager: GameManager!
    private var scoreLabel: SKLabelNode!

    /// Non-nil only in .adventure mode. Its presence is also what tells
    /// setUpScoreLabel() and update() to do camera-relative HUD placement
    /// and per-frame following, respectively.
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

    /// Fired each time a level's threshold is hit (.levels mode only). Same
    /// pattern as onGameOver -- the overlay lives in SwiftUI.
    var onLevelComplete: (() -> Void)?

    init(mode: GameMode) {
        self.mode = mode
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
        backgroundColor = SKColor(red: 0.03, green: 0.09, blue: 0.22, alpha: 1)

        let cellSize: CGFloat
        let origin: CGPoint
        switch mode {
        case .freePlay, .levels:
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)
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

        gameManager = GameManager(scene: self, mode: mode, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
        gameManager.onScoreChanged = { [weak self] score in
            self?.scoreLabel.text = "Score: \(score)"
        }
        gameManager.onGameOver = { [weak self] in
            self?.onGameOver?()
        }
        gameManager.onLevelComplete = { [weak self] in
            self?.onLevelComplete?()
        }

        // Free-play's grid doesn't fill the screen, so a border marks its
        // wrap boundary. Levels mode and Adventure mode already use (most
        // of, or far more than) the screen, so the edge is visible on its
        // own -- Adventure's map even has its own border walls baked in.
        if mode == .freePlay {
            drawGridBorder(cellSize: cellSize, origin: origin)
        }

        setUpScoreLabel()
        setUpInputGesture(on: view)
        gameManager.startNewGame()

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

    // MARK: - Setup

    private func drawGridBorder(cellSize: CGFloat, origin: CGPoint) {
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: CGFloat(columns) * cellSize,
            height: CGFloat(rows) * cellSize
        )
        let border = SKShapeNode(rect: rect)
        border.strokeColor = SKColor.white.withAlphaComponent(0.25)
        border.lineWidth = 2
        border.fillColor = .clear
        border.zPosition = -1
        addChild(border)
    }

    private func setUpScoreLabel() {
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        scoreLabel.text = "Score: 0"
        scoreLabel.fontSize = 20
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.zPosition = 10

        if let cameraNode {
            // A camera's children are positioned relative to *its own*
            // center, not the scene origin -- this is what keeps the HUD
            // pinned to the screen as the camera pans around the world.
            scoreLabel.position = CGPoint(x: -size.width / 2 + 16, y: size.height / 2 - 40)
            cameraNode.addChild(scoreLabel)
        } else {
            scoreLabel.position = CGPoint(x: 16, y: size.height - 40)
            addChild(scoreLabel)
        }
    }

    /// Adventure mode only: a camera the snake's head drives, clamped so
    /// the viewport never shows past the map's edges.
    private func setUpCamera() {
        let camera = SKCameraNode()
        addChild(camera)
        self.camera = camera
        cameraNode = camera
    }

    private func updateCamera() {
        guard let cameraNode else { return }

        let headPosition = gameManager.headWorldPosition
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let x = worldSize.width <= size.width
            ? worldSize.width / 2
            : min(max(headPosition.x, halfWidth), worldSize.width - halfWidth)
        let y = worldSize.height <= size.height
            ? worldSize.height / 2
            : min(max(headPosition.y, halfHeight), worldSize.height - halfHeight)

        cameraNode.position = CGPoint(x: x, y: y)
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
        gameManager.tick(currentTime: currentTime)
        if mode == .adventure {
            updateCamera()
        }
    }
}
