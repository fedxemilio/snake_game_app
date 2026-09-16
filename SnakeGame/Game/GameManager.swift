import SpriteKit

/// Owns the Snake and Food instances, runs the tick timer, and makes the
/// cross-cutting calls neither of them should make on their own: whether a
/// move counts as eating, when to speed up, when the game is over.
final class GameManager {
    private let columns: Int
    private let rows: Int
    private let cellSize: CGFloat
    private let origin: CGPoint

    private weak var scene: SKScene?
    private var snake: Snake!
    private var food: Food!
    private var powerUp: PowerUp?

    /// Chance, per grid tick, of a power-up spawning while none is active.
    /// At the starting move speed (~5.5 ticks/sec) this averages roughly
    /// one spawn every 30 seconds. Tune this to taste.
    private let powerUpSpawnChance: Double = 0.006

    private var moveInterval: TimeInterval = 0.18
    private var timeSinceLastMove: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    private(set) var isGameOver = false
    private(set) var score = 0

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?

    init(scene: SKScene, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        self.scene = scene
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        self.origin = origin
    }

    func startNewGame() {
        snake?.removeFromScene()
        food?.removeFromScene()
        powerUp?.removeFromScene()
        powerUp = nil

        isGameOver = false
        score = 0
        moveInterval = 0.18
        timeSinceLastMove = 0
        lastUpdateTime = 0

        let start = GridPoint(x: columns / 2, y: rows / 2)
        let newSnake = Snake(startingAt: start, length: 3, direction: .right, cellSize: cellSize, origin: origin)
        let newFood = Food(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: newSnake.segments)

        if let scene {
            newSnake.addToScene(scene)
            newFood.addToScene(scene)
        }

        snake = newSnake
        food = newFood

        onScoreChanged?(score)
    }

    func turn(to direction: Direction) {
        if isGameOver {
            startNewGame()
            return
        }
        snake.turn(to: direction)
    }

    func tick(currentTime: TimeInterval) {
        guard !isGameOver else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        timeSinceLastMove += delta

        guard timeSinceLastMove >= moveInterval else { return }
        timeSinceLastMove = 0

        switch snake.advance(columns: columns, rows: rows, foodPosition: food.position) {
        case .moved:
            break
        case .ateFood:
            score += 1
            onScoreChanged?(score)
            food.relocate(columns: columns, rows: rows, avoiding: snake.segments)
            moveInterval = max(0.08, moveInterval - 0.004)
        case .collided:
            isGameOver = true
            onGameOver?()
            return
        }

        if let powerUp, powerUp.position == snake.head {
            powerUp.removeFromScene()
            self.powerUp = nil
        }

        attemptPowerUpSpawn()
    }

    /// Rolls independently of whether one is already active — if it hits
    /// while a power-up is on the grid, the old one is replaced rather than
    /// stacking or being skipped.
    private func attemptPowerUpSpawn() {
        guard Double.random(in: 0..<1) < powerUpSpawnChance else { return }

        powerUp?.removeFromScene()

        var occupied = snake.segments
        occupied.append(food.position)
        let newPowerUp = PowerUp(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupied)
        if let scene {
            newPowerUp.addToScene(scene)
        }
        powerUp = newPowerUp
    }
}
