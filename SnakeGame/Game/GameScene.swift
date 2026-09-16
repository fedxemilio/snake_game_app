import SpriteKit

final class GameScene: SKScene {
    private let columns = 16
    private let rows = 24

    private var gameManager: GameManager!
    private var scoreLabel: SKLabelNode!
    private var gameOverLabel: SKLabelNode?

    private var swipeDirections: [ObjectIdentifier: Direction] = [:]

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.09, green: 0.10, blue: 0.14, alpha: 1)

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
            self?.showGameOver()
        }

        setUpScoreLabel()
        setUpSwipeGestures(on: view)
        gameManager.startNewGame()
    }

    // MARK: - Setup

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

        if gameManager.isGameOver {
            gameOverLabel?.removeFromParent()
            gameOverLabel = nil
        }
        gameManager.turn(to: direction)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        gameManager.tick(currentTime: currentTime)
    }

    // MARK: - UI

    private func showGameOver() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "Game Over — swipe to restart"
        label.fontSize = 18
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.zPosition = 20
        addChild(label)
        gameOverLabel = label
    }
}
