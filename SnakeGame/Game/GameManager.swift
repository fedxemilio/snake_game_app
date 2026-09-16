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
    private var bombs: [Bomb] = []

    /// Chance, per grid tick, of a power-up spawning while none is active.
    /// At the starting move speed (~5.5 ticks/sec) this averages roughly
    /// one spawn every 30 seconds. Tune this to taste.
    private let powerUpSpawnChance: Double = 0.006

    /// Chance, per fruit eaten, that a bomb spawns alongside the next fruit.
    private let bombSpawnChance: Double = 3.0 / 20.0

    /// How many segments a tail-cutter power-up removes (never below the
    /// snake's starting length -- Snake enforces that floor itself).
    private let tailCutterAmount = 5

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
        bombs.forEach { $0.removeFromScene() }
        bombs.removeAll()

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
        guard !isGameOver else { return }
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
            attemptBombSpawn()
        case .collided:
            isGameOver = true
            onGameOver?()
            return
        }

        if bombs.contains(where: { $0.position == snake.head }) {
            isGameOver = true
            onGameOver?()
            return
        }

        if let powerUp, powerUp.position == snake.head {
            applyPowerUpEffect(powerUp.kind)
            powerUp.removeFromScene()
            self.powerUp = nil
        }

        attemptPowerUpSpawn()
    }

    /// Rolls once per fruit eaten, alongside that fruit's replacement — never
    /// on an independent timer, so there's no bomb at game start and no
    /// bombs appearing while just cruising for fruit. Bombs accumulate and
    /// never expire, and are allowed to land on each other (but never on the
    /// fruit that was just placed, or on the snake).
    private func attemptBombSpawn() {
        guard Double.random(in: 0..<1) < bombSpawnChance else { return }

        var occupied = snake.segments
        occupied.append(food.position)
        let position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        let bomb = Bomb(position: position, cellSize: cellSize, origin: origin)
        if let scene {
            bomb.addToScene(scene)
        }
        bombs.append(bomb)
    }

    /// Rolls independently of whether one is already active — if it hits
    /// while a power-up is on the grid, the old one is replaced rather than
    /// stacking or being skipped.
    private func attemptPowerUpSpawn() {
        guard Double.random(in: 0..<1) < powerUpSpawnChance else { return }

        powerUp?.removeFromScene()

        var occupied = snake.segments
        occupied.append(food.position)
        let kind = PowerUpKind.allCases.randomElement()!
        let newPowerUp = PowerUp(kind: kind, columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupied)
        if let scene {
            newPowerUp.addToScene(scene)
        }
        powerUp = newPowerUp
    }

    /// Only .tailCutter does anything so far -- .bombEater and .speedCooler
    /// spawn and render with their own color but have no effect yet.
    private func applyPowerUpEffect(_ kind: PowerUpKind) {
        switch kind {
        case .tailCutter:
            snake.cutTail(by: tailCutterAmount)
        case .bombEater, .speedCooler:
            break
        }
    }
}
