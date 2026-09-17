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

    /// Relative odds of each BombKind on a spawn -- weights need not sum to
    /// 1; `randomBombKind()` normalizes. `.timed`/`.drifter` are shelved at 0
    /// for now (mine + the new `.sensor` are the only two live kinds while
    /// sensor gets hands-on testing); `.sensor` is deliberately overweighted
    /// at 50% for that, and should drop to ~20% (`.mine` picking up the rest)
    /// once it's confirmed working.
    private static let bombKindWeights: [(BombKind, Double)] = [
        (.mine, 0.5),
        (.timed, 0.0),
        (.drifter, 0.0),
        (.sensor, 0.5)
    ]

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

        switch mode {
        case .levels:
            loadCurrentLevelWalls()
        case .adventure:
            let newWalls = Walls(positions: AdventureMap.walls, cellSize: cellSize, origin: origin)
            if let scene {
                newWalls.addToScene(scene)
            }
            walls = newWalls
        case .freePlay:
            break
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

    /// World-space position of the snake's head -- GameScene uses this to
    /// drive Adventure mode's camera. Meaningless (but harmless) elsewhere.
    var headWorldPosition: CGPoint {
        GridGeometry.position(for: snake.head, cellSize: cellSize, origin: origin)
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
        updateBombs(delta: delta)
        guard !isGameOver else { return }

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

        armSensorBombsNearHead()

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
    /// bombs appearing while just cruising for fruit. Bombs are allowed to
    /// land on each other (but never on the fruit that was just placed, or
    /// on the snake). Most bombs (`.mine`) still accumulate and never expire
    /// on their own; `.timed` and `.drifter` are the exceptions (see
    /// `BombKind`), swept or repositioned by `updateBombs(delta:)`.
    private func attemptBombSpawn() {
        guard Double.random(in: 0..<1) < bombSpawnChance else { return }

        var occupied = occupiedBySnakeAndWalls
        occupied.append(food.position)
        let position = GridGeometry.randomPosition(columns: columns, rows: rows, avoiding: occupied)

        let bomb = Bomb(kind: randomBombKind(), position: position, cellSize: cellSize, origin: origin)
        if let scene {
            bomb.addToScene(scene)
        }
        bombs.append(bomb)
    }

    private func randomBombKind() -> BombKind {
        let totalWeight = GameManager.bombKindWeights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<totalWeight)
        for (kind, weight) in GameManager.bombKindWeights {
            if roll < weight { return kind }
            roll -= weight
        }
        return .mine
    }

    /// Ticks every bomb's own fuse/movement by real elapsed time --
    /// unconditional every frame, like the bomb-eater timer, so `.timed`'s
    /// fuse, `.drifter`'s roaming, and an armed `.sensor`'s countdown don't
    /// speed up or slow down with the snake's own move interval. Runs before
    /// the snake-vs-bomb collision check later this tick, so a drifter that
    /// just moved onto the head (or a mine the head just moved onto) is
    /// still caught the same tick.
    ///
    /// A sensor's detonation is resolved *before* the generic expired-bomb
    /// sweep below, while `bombs` still holds every other bomb to check its
    /// vicinity against -- `resolveSensorDetonation(at:)` may itself end the
    /// game, in which case this bails immediately rather than continuing to
    /// process other bombs against state that no longer matters.
    private func updateBombs(delta: TimeInterval) {
        var occupied = occupiedBySnakeAndWalls
        occupied.append(food.position)
        for bomb in bombs {
            bomb.update(delta: delta, columns: columns, rows: rows, avoiding: occupied)
        }

        for sensor in bombs where sensor.kind == .sensor && sensor.isExpired {
            resolveSensorDetonation(at: sensor.position)
            guard !isGameOver else { return }
        }

        let expired = bombs.filter(\.isExpired)
        guard !expired.isEmpty else { return }
        expired.forEach { $0.removeFromScene() }
        bombs.removeAll(where: \.isExpired)
    }

    /// An armed `.sensor` bomb's fuse just ran out. "Vicinity" is the 8
    /// cells surrounding `position` -- never `position` itself, since
    /// stepping directly onto any bomb is already caught unconditionally by
    /// the bomb-contact check later this tick. Bomb-eater immunity already
    /// protects direct contact with any bomb, so it's extended here too --
    /// otherwise "immune to bombs" would quietly mean "immune to touching
    /// one," which isn't what picking it up promises.
    ///
    /// Removing nearby mines and arming nearby sensors happen regardless of
    /// immunity -- those are consequences for the *world*, not the player,
    /// so being immune doesn't stop a chain reaction from playing out.
    private func resolveSensorDetonation(at position: GridPoint) {
        let vicinity = GameManager.vicinity(of: position, columns: columns, rows: rows)

        if !isBombEaterActive && vicinity.contains(snake.head) {
            isGameOver = true
            onGameOver?()
            return
        }

        let minesToRemove = bombs.filter { $0.kind == .mine && vicinity.contains($0.position) }
        minesToRemove.forEach { $0.removeFromScene() }
        bombs.removeAll { $0.kind == .mine && vicinity.contains($0.position) }

        for other in bombs where other.kind == .sensor && vicinity.contains(other.position) {
            other.arm()
        }
    }

    /// A dormant `.sensor` bomb arms the instant the snake's head enters any
    /// of its 8 surrounding cells. `Bomb.arm()` is a no-op for anything
    /// already armed (or not a sensor), so this can run unconditionally
    /// every tick without tracking which bombs it's already touched.
    private func armSensorBombsNearHead() {
        for bomb in bombs where bomb.kind == .sensor {
            if GameManager.vicinity(of: bomb.position, columns: columns, rows: rows).contains(snake.head) {
                bomb.arm()
            }
        }
    }

    /// The 8 cells surrounding `position`, wrapping at the grid's edges the
    /// same way movement does -- never `position` itself.
    private static func vicinity(of position: GridPoint, columns: Int, rows: Int) -> [GridPoint] {
        var cells: [GridPoint] = []
        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let x = (position.x + dx + columns) % columns
                let y = (position.y + dy + rows) % rows
                cells.append(GridPoint(x: x, y: y))
            }
        }
        return cells
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
