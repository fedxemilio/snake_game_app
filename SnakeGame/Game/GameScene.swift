import SpriteKit

final class GameScene: SKScene {
    private let columns = 16
    private let rows = 24

    private var gameManager: GameManager!
    private var scoreLabel: SKLabelNode!

    private var swipeDirections: [ObjectIdentifier: Direction] = [:]

    /// Fired once, when a run ends. The Game Over UI itself lives in
    /// SwiftUI (GameOverOverlay), not in the scene.
    var onGameOver: (() -> Void)?

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.03, green: 0.09, blue: 0.22, alpha: 1)

        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        let cellSize = min(cellWidth, cellHeight)
        let origin = CGPoint(
            x: (size.width - CGFloat(columns) * cellSize) / 2,
            y: (size.height - CGFloat(rows) * cellSize) / 2
        )

        gameManager = GameManager(scene: self, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
        gameManager.onScoreChanged = { [weak self] score in
            self?.scoreLabel.text = "Score: \(score)"
        }
        gameManager.onGameOver = { [weak self] in
            self?.onGameOver?()
        }

        drawGridBorder(cellSize: cellSize, origin: origin)
        setUpScoreLabel()
        setUpSwipeGestures(on: view)
        gameManager.startNewGame()
    }

    /// Called from the Game Over overlay's Play Again button.
    func startNewGame() {
        gameManager.startNewGame()
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
        scoreLabel.position = CGPoint(x: 16, y: size.height - 40)
        scoreLabel.zPosition = 10
        addChild(scoreLabel)
    }

    private func setUpSwipeGestures(on view: SKView) {
        let directions: [(UISwipeGestureRecognizer.Direction, Direction)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right)
        ]
        for (uiDirection, gameDirection) in directions {
            let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            recognizer.direction = uiDirection
            recognizer.numberOfTouchesRequired = 1
            view.addGestureRecognizer(recognizer)
            swipeDirections[ObjectIdentifier(recognizer)] = gameDirection
        }
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard let direction = swipeDirections[ObjectIdentifier(recognizer)] else { return }
        gameManager.turn(to: direction)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        gameManager.tick(currentTime: currentTime)
    }
}
