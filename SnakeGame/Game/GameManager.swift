import SpriteKit

/// Owns the Snake and Food instances, runs the tick timer, and makes the
/// cross-cutting calls neither of them should make on their own: whether a
/// move counts as eating, when to speed up, when the game is over.
final class GameManager {
    private let columns: Int
    private let rows: Int
    private let cellSize: CGFloat
    private let origin: CGPoint

    private let mode: GameMode

    private weak var scene: SKScene?
    private var snake: Snake!
    private var food: Food!
    private var powerUp: PowerUp?
    private var bombs: [Bomb] = []
    private var walls: Walls?

    /// Index into Level.all. Only meaningful in .levels mode.
    private var currentLevelIndex = 0

    /// Score earned since the current level loaded -- separate from the
    /// run's total `score`, so cycling back to level 1 after the last level
    /// doesn't instantly re-trigger every threshold on the next tick.
    private var levelProgress = 0

    /// True from the moment a level's threshold is hit until beginNextLevel()
    /// is called (from the Level Complete overlay's tap) -- freezes the tick
    /// loop entirely, same as isGameOver, but isn't a loss.
    private var isAwaitingNextLevel = false
    var onLevelComplete: (() -> Void)?

    /// Chance, per grid tick, of a power-up spawning while none is active.
    /// At the starting move speed (~5.5 ticks/sec) this averages roughly
    /// one spawn every 30 seconds. Tune this to taste.
    private let powerUpSpawnChance: Double = 0.006

    /// Chance, per fruit eaten, that a bomb spawns alongside the next fruit.
    private let bombSpawnChance: Double = 3.0 / 20.0

    /// How many tail segments a tail-cutter removes -- one per flash, up
    /// to this many, stopping early once the snake reaches its minimum
    /// length (Snake enforces that floor itself).
    private let tailCutterMaxPops = 5
    private let tailCutterFlashInterval: TimeInterval = 0.12
    private let tailCutterFallbackFlashDuration: TimeInterval = 1.0

    /// The move speed a run starts at, and the slowest a speed-cooler is
    /// allowed to push things back to -- it undoes fruit-driven speed-up,
    /// it doesn't make the game slower than when you started.
    private let startingMoveInterval: TimeInterval = 0.18

    /// How much slower a speed-cooler makes each move, undoing roughly half
    /// the full fruit-driven speed-up range in one hit.
    private let speedCoolerSlowdown: TimeInterval = 0.05
    private let speedCoolerFlashDuration: TimeInterval = 1.0

    /// Bomb-eater's immunity, in real seconds (independent of move speed --
    /// ticked down every frame, not every grid move): `bombEaterMainDuration`
    /// of solid color (with a couple of warning flashes near the end), then
    /// `bombEaterGraceDuration` more of a still-immune "grace" glow before
    /// reverting to normal. Total immunity = main + grace.
    private let bombEaterMainDuration: TimeInterval = 5.0
    private let bombEaterWarningFlashes = 2
    private let bombEaterWarningFlashInterval: TimeInterval = 0.15
    private let bombEaterGraceDuration: TimeInterval = 0.5
    private var isBombEaterActive = false
    private var bombEaterTimeRemaining: TimeInterval = 0

    private var moveInterval: TimeInterval = 0
    private var timeSinceLastMove: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    private(set) var isGameOver = false
    private(set) var score = 0

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?

    init(scene: SKScene, mode: GameMode, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        self.scene = scene
        self.mode = mode
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
        walls?.removeFromScene()
        walls = nil

        isGameOver = false
        score = 0
        moveInterval = startingMoveInterval
        timeSinceLastMove = 0
        lastUpdateTime = 0
        isBombEaterActive = false
        bombEaterTimeRemaining = 0
        currentLevelIndex = 0
        levelProgress = 0
        isAwaitingNextLevel = false

        let start = GridPoint(x: columns / 2, y: rows / 2)
        let newSnake = Snake(startingAt: start, length: 3, direction: .right, cellSize: cellSize, origin: origin)
        if let scene {
            newSnake.addToScene(scene)
        }
        snake = newSnake

        if mode == .levels {
            loadCurrentLevelWalls()
        }

        let newFood = Food(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupiedBySnakeAndWalls)
        if let scene {
            newFood.addToScene(scene)
        }
        food = newFood

        onScoreChanged?(score)
    }

    /// The snake's own body plus the current level's walls, if any -- the
    /// baseline every spawn/relocate call should avoid landing on.
    private var occupiedBySnakeAndWalls: [GridPoint] {
        snake.segments + Array(walls?.positions ?? [])
    }

    func turn(to direction: Direction) {
        guard !isGameOver, !isAwaitingNextLevel else { return }
        snake.turn(to: direction)
    }

    func tick(currentTime: TimeInterval) {
        guard !isGameOver, !isAwaitingNextLevel else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        updateBombEaterTimer(delta: delta)

        timeSinceLastMove += delta
        guard timeSinceLastMove >= moveInterval else { return }
        timeSinceLastMove = 0

        switch snake.advance(columns: columns, rows: rows, foodPosition: food.position, halvedGrowth: mode == .levels) {
        case .moved:
            break
        case .ateFood:
            score += 1
            onScoreChanged?(score)
            food.relocate(columns: columns, rows: rows, avoiding: occupiedBySnakeAndWalls)
            moveInterval = max(0.08, moveInterval - 0.004)
            attemptBombSpawn()
            if mode == .levels {
                advanceLevelProgress()
            }
        case .collided:
            isGameOver = true
            onGameOver?()
            return
        }

        // Walls are absolute -- no power-up grants immunity to them, so this
        // is checked immediately, unlike the bomb-eater/bomb interplay below.
        if let walls, walls.contains(snake.head) {
            isGameOver = true
            onGameOver?()
            return
        }

        // Resolve the power-up before the bomb: picking up a bomb-eater and
        // stepping onto a bomb in the same tick should grant immunity for
        // that same collision, not kill the run a moment too early.
        if let powerUp, powerUp.position == snake.head {
            applyPowerUpEffect(powerUp.kind)
            powerUp.removeFromScene()
            self.powerUp = nil
        }

        let bombsAtHead = bombs.filter { $0.position == snake.head }
        if !bombsAtHead.isEmpty {
            if isBombEaterActive {
                bombsAtHead.forEach { $0.removeFromScene() }
                bombs.removeAll { $0.position == snake.head }
            } else {
                isGameOver = true
                onGameOver?()
                return
            }
        }

        attemptPowerUpSpawn()
    }

    /// Tracks progress toward the *current* level's threshold, separate
    /// from the run's total score -- so this resets on every advance,
    /// rather than comparing against a total that keeps climbing. Hitting
    /// the threshold pauses the game (see isAwaitingNextLevel) rather than
    /// loading the next level immediately -- that happens in
    /// beginNextLevel(), once the Level Complete overlay is tapped.
    private func advanceLevelProgress() {
        levelProgress += 1
        guard levelProgress >= Level.all[currentLevelIndex].pointsToAdvance else { return }

        levelProgress = 0
        isAwaitingNextLevel = true
        onLevelComplete?()
    }

    /// Called from the Level Complete overlay's tap.
    func beginNextLevel() {
        guard isAwaitingNextLevel else { return }
        isAwaitingNextLevel = false

        currentLevelIndex = (currentLevelIndex + 1) % Level.all.count
        loadCurrentLevelWalls()

        // Recenter first: a stale position could now sit inside the new
        // level's walls, and food/bombs/power-up need the *new* position
        // to avoid. Length and total score carry over unchanged.
        snake.recenter(at: GridPoint(x: columns / 2, y: rows / 2), direction: .right)

        food.removeFromScene()
        bombs.forEach { $0.removeFromScene() }
        bombs.removeAll()
        powerUp?.removeFromScene()
        powerUp = nil

        let newFood = Food(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupiedBySnakeAndWalls)
        if let scene {
            newFood.addToScene(scene)
        }
        food = newFood

        // Avoid a runaway "catch-up" tick using a delta spanning the pause.
        timeSinceLastMove = 0
        lastUpdateTime = 0
    }

    private func loadCurrentLevelWalls() {
        walls?.removeFromScene()
        let newWalls = Walls(positions: Level.all[currentLevelIndex].walls, cellSize: cellSize, origin: origin)
        if let scene {
            newWalls.addToScene(scene)
        }
        walls = newWalls
    }

    /// Only tracks *gameplay* immunity -- the matching visual (solid color,
    /// warning flashes, grace glow, revert) is a single SKAction sequence
    /// kicked off once in activateBombEater(), timed to the same total
    /// duration rather than driven from here frame by frame.
    private func updateBombEaterTimer(delta: TimeInterval) {
        guard isBombEaterActive else { return }
        bombEaterTimeRemaining -= delta
        if bombEaterTimeRemaining <= 0 {
            isBombEaterActive = false
            bombEaterTimeRemaining = 0
        }
    }

    /// Rolls once per fruit eaten, alongside that fruit's replacement — never
    /// on an independent timer, so there's no bomb at game start and no
    /// bombs appearing while just cruising for fruit. Bombs accumulate and
    /// never expire, and are allowed to land on each other (but never on the
    /// fruit that was just placed, or on the snake).
    private func attemptBombSpawn() {
        guard Double.random(in: 0..<1) < bombSpawnChance else { return }

        var occupied = occupiedBySnakeAndWalls
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

        var occupied = occupiedBySnakeAndWalls
        occupied.append(food.position)
        let kind = PowerUpKind.allCases.randomElement()!
        let newPowerUp = PowerUp(kind: kind, columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupied)
        if let scene {
            newPowerUp.addToScene(scene)
        }
        powerUp = newPowerUp
    }

    private func applyPowerUpEffect(_ kind: PowerUpKind) {
        switch kind {
        case .tailCutter:
            snake.playTailCutterEffect(
                color: PowerUp.color(for: .tailCutter),
                maxPops: tailCutterMaxPops,
                flashInterval: tailCutterFlashInterval,
                fallbackFlashDuration: tailCutterFallbackFlashDuration
            )
        case .speedCooler:
            moveInterval = min(startingMoveInterval, moveInterval + speedCoolerSlowdown)
            snake.flashBodyColor(PowerUp.color(for: .speedCooler), duration: speedCoolerFlashDuration)
        case .bombEater:
            activateBombEater()
        }
    }

    /// Re-collecting one while already active simply refreshes the timer
    /// back to the full duration, rather than stacking -- and restarts the
    /// visual sequence from the top too (Snake cancels its own in-flight
    /// actions before starting a new one).
    private func activateBombEater() {
        isBombEaterActive = true
        bombEaterTimeRemaining = bombEaterMainDuration + bombEaterGraceDuration
        snake.playBombEaterEffect(
            color: PowerUp.color(for: .bombEater),
            mainDuration: bombEaterMainDuration,
            warningFlashes: bombEaterWarningFlashes,
            warningFlashInterval: bombEaterWarningFlashInterval,
            graceDuration: bombEaterGraceDuration
        )
    }
}
