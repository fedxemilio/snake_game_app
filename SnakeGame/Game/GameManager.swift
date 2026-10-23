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
    /// Zen mode, for testing: hits still show, but never cost a life, so a run
    /// never ends (see `hurtPlayer`).
    private let isZen: Bool

    private weak var scene: SKScene?
    private var snake: Snake!
    private var food: Food!
    private var powerUp: PowerUp?
    private var bombs: [Bomb] = []
    private var walls: Walls?
    /// Adventure: which `AdventureStage` the run is on, and its boss (one of
    /// these, depending on the stage; both nil in the other modes).
    private var stageIndex = 0
    private var stage: AdventureStage { AdventureStage.all[stageIndex] }
    private var kraken: Kraken?
    private var moray: Moray?
    private var galleon: Galleon?
    private var boss: Boss? {
        if let kraken { return kraken }
        if let moray { return moray }
        return galleon
    }
    /// Adventure: the storm over a stage that reaches the surface (the Shallows).
    private var surface: StormSurface?
    /// Cannonballs on their way into a boss that cannonballs hurt (the galleon's
    /// hull, the moray): seconds until each hits, where, and whom
    /// (`updateCannonHits`).
    private var cannonHits: [(timeLeft: TimeInterval, point: CGPoint, target: Boss)] = []
    /// The most loose cannonballs the galleon's shot leaves lying around; past
    /// this, its shot breaks up where it lands.
    private let maxLooseCannonballs = 6

    /// Adventure: seconds left of the beaten boss's send-off before the stage is
    /// reported cleared (the game plays on meanwhile). Nil otherwise.
    private var stageClearCountdown: TimeInterval?
    private let stageClearDelay: TimeInterval = 3.0

    /// True from a new Adventure run's start until `releaseStart()`: the board is
    /// set up but frozen while the voyage chart shows where the run begins.
    private var isWaitingToStart = false
    /// Adventure's rolling pushables (barrels, the stepping kind, are bombs).
    private var cannonballs: [Cannonball] = []

    /// Adventure only: a second fruit, always on the board like the mango. Eating
    /// `mineFruitPerMine` of them earns a mine the player drops with a tap
    /// (`dropMine()`). It doesn't grow the snake, score or speed it up.
    private var mineFruit: Food?
    private static let mineFruitPerMine = 3
    private var mineFruitTowardNext = 0
    private var minesReady = 0

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

    /// Reaction room a new bomb must leave the snake, in cells: this deep
    /// ahead of the head and this many cells to each side. At the starting
    /// speed that's ~1.4s of warning ahead; at top speed ~0.6s.
    private let bombReactionAhead = 8
    private let bombReactionSide = 3

    /// Adventure mode: no bombs within this many cells of an open map edge,
    /// so a wrap can't drop the snake next to a bomb it couldn't see coming.
    private let adventureBombEdgeMargin = 8

    /// Relative odds of each BombKind on a spawn -- weights need not sum to
    /// 1; `randomBombKind()` normalizes. `.timed`/`.drifter` are shelved at 0
    /// for now; `.mine`/`.sensor`/`.barrel` are the live kinds while sensor
    /// (and its barrel interaction) get hands-on testing, so `.sensor` stays
    /// deliberately overweighted and `.barrel` gets a modest slice just to
    /// make that interaction observable. Once confirmed working, `.sensor`
    /// should drop to ~20% with `.mine` picking up the rest.
    private static let bombKindWeights: [(BombKind, Double)] = [
        (.mine, 0.4),
        (.timed, 0.0),
        (.drifter, 0.0),
        (.sensor, 0.4),
        (.barrel, 0.2)
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

    /// Lives per run: three in Adventure, one elsewhere (so in Free play and
    /// Levels any hit still ends the run, exactly as before).
    private var maxLives: Int { mode == .adventure ? 3 : 1 }
    private(set) var lives = 0
    /// After a hit that doesn't end the run, the snake blinks and can't be hurt
    /// again for this long, in real seconds (like bomb-eater's timer). Walls
    /// still stop it; they just don't cost a life until this runs out.
    private let hitGraceDuration: TimeInterval = 2.0
    private var hitGraceRemaining: TimeInterval = 0
    /// True while the snake is stopped against a barrier, so the kraken aims at
    /// where it is rather than where it was headed.
    private var isSnakeBlocked = false

    private(set) var isGameOver = false
    private(set) var score = 0

    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: (() -> Void)?
    /// The boss's name and lives whenever they change, or nil when there's no
    /// boss this run (anything but Adventure).
    struct BossStatus: Equatable {
        let name: String
        let lives: Int
        let maxLives: Int
    }
    var onBossChanged: ((BossStatus?) -> Void)?

    /// Adventure: a stage's boss has been beaten and its send-off has played. The
    /// game is frozen (`isAwaitingNextLevel`) until `beginNextStage()`, or a new
    /// run. Passes the cleared stage's index into `AdventureStage.all`.
    var onStageCleared: ((Int) -> Void)?
    /// The snake's remaining lives whenever they change, or nil in modes where it
    /// only has the one (there's nothing to show).
    var onLivesChanged: ((Int?) -> Void)?

    /// Mine fruit progress and mines ready to drop, whenever either changes; nil
    /// in modes without mine fruit (anything but Adventure).
    struct MineSupply: Equatable {
        /// Mine fruit eaten toward the next mine, 0..<`fruitPerMine`.
        let progress: Int
        /// Mines ready to drop with a tap.
        let ready: Int
        static let fruitPerMine = GameManager.mineFruitPerMine
    }
    var onMineSupplyChanged: ((MineSupply?) -> Void)?

    /// Moments worth feeling: GameScene turns these into camera shake (Adventure)
    /// and haptics. An explosion carries its scene position, so ones off screen
    /// can be ignored.
    enum Jolt {
        case hit
        case death
        case explosion(CGPoint)
        /// The snake shoved something.
        case push
        /// The player dropped a mine.
        case drop
    }
    var onJolt: ((Jolt) -> Void)?

    /// What hurt the snake, for how the hit looks (`showImpact`).
    private enum Hurt {
        /// It pressed into a barrier at this cell.
        case barrier(GridPoint)
        case bomb
        case blast
        case tentacle
        case bite
    }

    init(scene: SKScene, mode: GameMode, isZen: Bool, columns: Int, rows: Int, cellSize: CGFloat, origin: CGPoint) {
        self.scene = scene
        self.mode = mode
        self.isZen = isZen
        self.columns = columns
        self.rows = rows
        self.cellSize = cellSize
        self.origin = origin
    }

    /// A fresh run. `holdingForCue` freezes the new board until `releaseStart()`
    /// (Adventure's first run, while the voyage chart shows where it begins).
    func startNewGame(holdingForCue: Bool = false) {
        snake?.removeFromScene()
        food?.removeFromScene()
        powerUp?.removeFromScene()
        powerUp = nil
        bombs.forEach { $0.removeFromScene() }
        bombs.removeAll()
        walls?.removeFromScene()
        walls = nil
        kraken?.removeFromScene()
        kraken = nil
        moray?.removeFromScene()
        moray = nil
        galleon?.removeFromScene()
        galleon = nil
        surface?.removeFromScene()
        surface = nil
        cannonHits.removeAll()
        cannonballs.forEach { $0.removeFromScene() }
        cannonballs.removeAll()
        mineFruit?.removeFromScene()
        mineFruit = nil
        mineFruitTowardNext = 0
        minesReady = 0

        isGameOver = false
        score = 0
        lives = maxLives
        hitGraceRemaining = 0
        isSnakeBlocked = false
        moveInterval = startingMoveInterval
        timeSinceLastMove = 0
        lastUpdateTime = 0
        isBombEaterActive = false
        bombEaterTimeRemaining = 0
        currentLevelIndex = 0
        levelProgress = 0
        isAwaitingNextLevel = false
        isWaitingToStart = holdingForCue
        stageIndex = 0
        stageClearCountdown = nil

        // Adventure's stages put their bosses in the middle.
        let start = mode == .adventure ? stage.snakeStart : GridPoint(x: columns / 2, y: rows / 2)
        let newSnake = Snake(startingAt: start, length: 3, direction: .right, cellSize: cellSize, origin: origin)
        if let scene {
            newSnake.addToScene(scene)
        }
        snake = newSnake

        switch mode {
        case .levels:
            loadCurrentLevelWalls()
        case .adventure:
            loadAdventureStage()
        case .freePlay:
            break
        }

        let newFood = Food(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupiedBySnakeWallsAndBombs)
        if let scene {
            newFood.addToScene(scene)
        }
        food = newFood

        if mode == .adventure {
            let newMineFruit = Food(kind: .mineFruit, columns: columns, rows: rows, cellSize: cellSize, origin: origin,
                                    avoiding: occupiedBySnakeWallsAndBombs + [newFood.position])
            if let scene {
                newMineFruit.addToScene(scene)
            }
            mineFruit = newMineFruit
        }

        onScoreChanged?(score)
        onLivesChanged?(maxLives > 1 ? lives : nil)
        reportMineSupply()
        reportBoss()
    }

    /// Lets a run held by `startNewGame(holdingForCue:)` begin.
    func releaseStart() {
        guard isWaitingToStart else { return }
        isWaitingToStart = false
        lastUpdateTime = 0
        timeSinceLastMove = 0
    }

    /// Adventure: sets the world up for the current `stage`: its walls, its boss
    /// and its fixtures, clearing whatever the last stage left (bombs included).
    /// The snake, fruit and lives are the callers' business.
    private func loadAdventureStage() {
        // The sky blocks like the walls do; the storm draws it.
        walls?.removeFromScene()
        let newWalls = Walls(positions: stage.walls.union(stage.sky), cellSize: cellSize, origin: origin, drawn: stage.walls)
        if let scene {
            newWalls.addToScene(scene)
        }
        walls = newWalls

        surface?.removeFromScene()
        surface = nil
        if let waterline = stage.waterline {
            let newSurface = StormSurface(waterline: waterline, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
            if let scene {
                newSurface.addToScene(scene)
            }
            surface = newSurface
        }

        kraken?.removeFromScene()
        kraken = nil
        moray?.removeFromScene()
        moray = nil
        galleon?.removeFromScene()
        galleon = nil
        cannonHits.removeAll()
        bombs.forEach { $0.removeFromScene() }
        bombs.removeAll()
        cannonballs.forEach { $0.removeFromScene() }
        cannonballs.removeAll()
        stageClearCountdown = nil

        switch stage.boss {
        case .kraken(let lair):
            let newKraken = Kraken(center: lair, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
            if let scene {
                newKraken.addToScene(scene)
            }
            kraken = newKraken
        case .moray(let body):
            let newMoray = Moray(body: body, columns: columns, rows: rows, cellSize: cellSize, origin: origin)
            if let scene {
                newMoray.addToScene(scene)
            }
            moray = newMoray
        case .galleon(let column):
            let newGalleon = Galleon(column: column, waterline: stage.waterline ?? rows, columns: columns,
                                     cellSize: cellSize, origin: origin)
            if let scene {
                newGalleon.addToScene(scene)
            }
            galleon = newGalleon
        }

        for position in stage.barrels {
            let barrel = Bomb(kind: .barrel, position: position, cellSize: cellSize, origin: origin)
            if let scene {
                barrel.addToScene(scene)
            }
            bombs.append(barrel)
        }
        for position in stage.cannonballs {
            let cannonball = Cannonball(position: position, cellSize: cellSize, origin: origin)
            if let scene {
                cannonball.addToScene(scene)
            }
            cannonballs.append(cannonball)
        }
        minesReady += stage.startingMines
    }

    /// Adventure: on to the next stage, once the player has moved on from the
    /// chart. Score, length, speed and banked mines carry over; lives refill.
    func beginNextStage() {
        guard mode == .adventure, isAwaitingNextLevel, stageIndex + 1 < AdventureStage.all.count else { return }
        stageIndex += 1
        enterStage()
        isAwaitingNextLevel = false
    }

    /// Zen mode's shortcut: while a new Adventure run is still waiting on the
    /// chart, starts it at stage `index` instead, as if it began there (with just
    /// that stage's starting mines).
    func chooseStartingStage(_ index: Int) {
        guard mode == .adventure, isWaitingToStart, AdventureStage.all.indices.contains(index), index != stageIndex else { return }
        stageIndex = index
        minesReady = 0
        enterStage()
    }

    /// Lays out the current `stage` and puts the snake at its start, with the
    /// fruit moved clear of it and lives refilled.
    private func enterStage() {
        loadAdventureStage()

        snake.recenter(at: stage.snakeStart, direction: .right)
        powerUp?.removeFromScene()
        powerUp = nil
        food.relocate(columns: columns, rows: rows, avoiding: occupiedBySnakeWallsAndBombs)
        mineFruit?.relocate(columns: columns, rows: rows, avoiding: occupiedBySnakeWallsAndBombs + [food.position])

        lives = maxLives
        hitGraceRemaining = 0
        isSnakeBlocked = false
        timeSinceLastMove = 0
        lastUpdateTime = 0

        onLivesChanged?(lives)
        reportMineSupply()
        reportBoss()
    }

    private func reportBoss() {
        guard mode == .adventure, let boss else {
            onBossChanged?(nil)
            return
        }
        onBossChanged?(BossStatus(name: stage.bossName, lives: boss.lives, maxLives: type(of: boss).maxLives))
    }

    /// A blow landed on the boss: costs it a life (unless it's still recovering),
    /// and if that was its last, its send-off starts the stage clear.
    private func strike(_ boss: Boss) {
        guard boss.takeHit() else { return }
        reportBoss()
        if boss.isDefeated {
            stageClearCountdown = stageClearDelay
        }
    }

    /// The snake's own body plus the current level's walls, the kraken's lair,
    /// anything pushable and the mine fruit, if any -- the baseline every
    /// spawn/relocate call should avoid landing on.
    private var occupiedBySnakeAndWalls: [GridPoint] {
        snake.segments
            + Array(walls?.positions ?? [])
            + Array(boss?.cells ?? [])
            + pushables.map(\.position)
            + [mineFruit?.position].compactMap { $0 }
    }

    /// `occupiedBySnakeAndWalls` plus every current bomb position -- food
    /// must never land on top of a bomb (most bombs, like `.mine`, never
    /// expire on their own, so landing there would make that fruit
    /// permanently uncollectable and progression impossible).
    private var occupiedBySnakeWallsAndBombs: [GridPoint] {
        occupiedBySnakeAndWalls + bombs.map(\.position)
    }

    /// World-space position of the snake's head -- the kraken's eyes follow it,
    /// and so does Adventure mode's camera (`cameraFocus`).
    var headWorldPosition: CGPoint {
        GridGeometry.position(for: snake.head, cellSize: cellSize, origin: origin)
    }

    /// What Adventure's camera centers on (GameScene clamps it to the map): the
    /// head, except that in a stage that reaches the surface it keeps to the top,
    /// so the sky and the galleon are always in view. Such a stage's playable water
    /// fits under them, so only its seabed is lost below.
    var cameraFocus: CGPoint {
        guard surface != nil else { return headWorldPosition }
        return CGPoint(x: headWorldPosition.x, y: origin.y + CGFloat(rows) * cellSize)
    }

    func turn(to direction: Direction) {
        guard !isGameOver, !isAwaitingNextLevel, !isWaitingToStart else { return }
        snake.turn(to: direction)
    }

    func tick(currentTime: TimeInterval) {
        guard !isGameOver, !isAwaitingNextLevel, !isWaitingToStart else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        if let countdown = stageClearCountdown {
            if countdown - delta <= 0 {
                stageClearCountdown = nil
                isAwaitingNextLevel = true
                onStageCleared?(stageIndex)
                return
            }
            stageClearCountdown = countdown - delta
        }

        updateBombEaterTimer(delta: delta)
        hitGraceRemaining = max(0, hitGraceRemaining - delta)
        updateBombs(delta: delta)
        guard !isGameOver else { return }
        updateKraken(delta: delta)
        guard !isGameOver else { return }
        updateMoray(delta: delta)
        guard !isGameOver else { return }
        updateGalleon(delta: delta)
        guard !isGameOver else { return }
        updateCannonHits(delta: delta)

        timeSinceLastMove += delta
        guard timeSinceLastMove >= moveInterval else { return }
        timeSinceLastMove = 0

        var result = advanceSnake()
        // Something pushable in the way gets shoved instead, if it has anywhere to
        // go, and then the snake moves into the cell it left. A blocked advance
        // commits nothing, so trying again resolves the same move.
        if case .blocked(let cell) = result,
           let object = pushables.first(where: { $0.position == cell }),
           push(object, awayFrom: snake.head) {
            result = advanceSnake()
        }
        if case .blocked = result {
            isSnakeBlocked = true
        } else {
            isSnakeBlocked = false
        }

        switch result {
        case .moved:
            break
        case .ateFood:
            scoreFruit()
        case .blocked(let cell):
            // Stopped against a wall, the lair or its own body: it stays put, and
            // every tick it's still pressing in tries to hurt it, which only lands
            // once the grace period from the last hit is over. No power-up
            // protects against this. Nothing else happens on a tick it didn't move.
            hurtPlayer(.barrier(cell))
            return
        }

        if let mineFruit, mineFruit.position == snake.head {
            collectMineFruit(mineFruit)
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

        // Touching a bomb sets it off: it explodes either way, and it costs a
        // life unless bomb-eater is active (or the snake is still in its grace
        // period).
        // A barrel primed on a mine has made that cell safe: the snake swims right
        // through both.
        let bombsAtHead = bombs.filter { $0.position == snake.head && $0.kind != .barrel && !$0.isUnderBarrel && !$0.isExpired }
        if !bombsAtHead.isEmpty {
            if let scene {
                bombsAtHead.forEach { $0.explode(in: scene) }
            }
            bombs.removeAll { bomb in bombsAtHead.contains { $0 === bomb } }
            onJolt?(.explosion(headWorldPosition))
            if !isBombEaterActive {
                hurtPlayer(.bomb)
                guard !isGameOver else { return }
            }
        }

        attemptPowerUpSpawn()
    }

    /// A mango eaten, whether by the head or by something the snake pushed into
    /// it: the score goes up, the fruit moves, the snake speeds up a touch, a bomb
    /// may spawn, and Levels progress advances. (Growth is `Snake`'s side.)
    private func scoreFruit() {
        score += 1
        onScoreChanged?(score)
        food.relocate(columns: columns, rows: rows, avoiding: occupiedBySnakeWallsAndBombs)
        moveInterval = max(0.08, moveInterval - 0.004)
        attemptBombSpawn()
        if mode == .levels {
            advanceLevelProgress()
        }
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

        let newFood = Food(columns: columns, rows: rows, cellSize: cellSize, origin: origin, avoiding: occupiedBySnakeWallsAndBombs)
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
    ///
    /// Never spawns inside the head's forward/side reaction zone, or (in
    /// Adventure mode) near an open map edge -- see `bombSpawnPosition()`.
    /// If no fair cell exists, the spawn is simply skipped.
    private func attemptBombSpawn() {
        guard Double.random(in: 0..<1) < bombSpawnChance else { return }
        guard let position = bombSpawnPosition() else { return }

        let bomb = Bomb(kind: randomBombKind(), position: position, cellSize: cellSize, origin: origin)
        if let scene {
            bomb.addToScene(scene)
        }
        bombs.append(bomb)
    }

    /// A random cell a new bomb may fairly occupy, or nil if none exists.
    /// Beyond the snake/walls/fruit baseline, excludes:
    /// - the head's reaction zone (`reactionZone()`), so a bomb can never
    ///   appear where the snake has no time to see it and steer away;
    /// - Adventure mode only: cells within `adventureBombEdgeMargin` of a
    ///   map edge the snake can wrap through (`isNearOpenEdge`), since the
    ///   viewport can't show the far side of a wrap.
    private func bombSpawnPosition() -> GridPoint? {
        var excluded = Set(occupiedBySnakeAndWalls)
        excluded.insert(food.position)
        excluded.formUnion(reactionZone())

        var candidates: [GridPoint] = []
        for x in 0..<columns {
            for y in 0..<rows {
                let point = GridPoint(x: x, y: y)
                if excluded.contains(point) { continue }
                if mode == .adventure && isNearOpenEdge(point) { continue }
                candidates.append(point)
            }
        }
        return candidates.randomElement()
    }

    /// The block of cells ahead of the head (`bombReactionAhead` deep,
    /// including the cells level with the head) and `bombReactionSide` wide
    /// on each side, wrapping at grid edges the way the snake does. Nothing
    /// behind the head: turning around takes long enough that the player
    /// sees a bomb appear back there.
    private func reactionZone() -> [GridPoint] {
        let forward = snake.direction.vector
        let side = (dx: -forward.dy, dy: forward.dx)
        var cells: [GridPoint] = []
        for ahead in 0...bombReactionAhead {
            for offset in -bombReactionSide...bombReactionSide {
                let x = snake.head.x + forward.dx * ahead + side.dx * offset
                let y = snake.head.y + forward.dy * ahead + side.dy * offset
                cells.append(GridPoint(
                    x: ((x % columns) + columns) % columns,
                    y: ((y % rows) + rows) % rows
                ))
            }
        }
        return cells
    }

    /// Whether `point` is within `adventureBombEdgeMargin` of an edge along
    /// a row/column the snake can actually wrap through. A wall at either
    /// end of that row (or column) blocks the crossing, so the far side
    /// can never be arrived at unseen there and the edge doesn't count.
    private func isNearOpenEdge(_ point: GridPoint) -> Bool {
        let margin = adventureBombEdgeMargin

        if point.x < margin || point.x >= columns - margin {
            let blocked = isWall(GridPoint(x: 0, y: point.y)) || isWall(GridPoint(x: columns - 1, y: point.y))
            if !blocked { return true }
        }
        if point.y < margin || point.y >= rows - margin {
            let blocked = isWall(GridPoint(x: point.x, y: 0)) || isWall(GridPoint(x: point.x, y: rows - 1))
            if !blocked { return true }
        }
        return false
    }

    private func isWall(_ point: GridPoint) -> Bool {
        walls?.contains(point) ?? false
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
    ///
    /// The sweep itself only drops expired bombs from this array -- it does
    /// *not* also call `removeFromScene()` on them. Every path that sets
    /// `isExpired` (a `.timed`/`.sensor` fuse running out, a `.barrel`
    /// exploding) already queues that bomb's own fade/scale-out SKAction;
    /// calling `removeFromScene()` here too would yank the node out of the
    /// scene before SpriteKit gets to animate it (actions are evaluated
    /// after `update(_:)` returns, i.e. after this same call), so the
    /// "fade away" would never actually be seen. The node keeps running its
    /// own action and removes itself once that finishes, independent of
    /// whether this array still references its Bomb wrapper.
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

        // Barrels whose fuse ran out on top of the bomb they were pushed onto.
        for barrel in bombs where barrel.hasFuseRunOut && !barrel.isExpired {
            detonate(barrel)
            guard !isGameOver else { return }
        }

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
    /// Removing nearby mines, arming nearby sensors, and setting off nearby
    /// barrels all happen regardless of immunity -- those are consequences
    /// for the *world*, not the player, so being immune doesn't stop a chain
    /// reaction from playing out (it only protects the player from dying to
    /// it, checked separately for this bomb and for each barrel below).
    private func resolveSensorDetonation(at position: GridPoint) {
        let vicinity = GameManager.vicinity(of: position, columns: columns, rows: rows)
        onJolt?(.explosion(GridGeometry.position(for: position, cellSize: cellSize, origin: origin)))

        if !isBombEaterActive && vicinity.contains(snake.head) {
            hurtPlayer(.blast)
            guard !isGameOver else { return }
        }
        setOffBombs(in: vicinity)
    }

    /// What a blast over `area` does to the bombs in it: mines go off too, one
    /// after another just behind it so the chain reads in order; dormant sensors
    /// arm; barrels detonate. Callers check `isGameOver`.
    private func setOffBombs(in area: [GridPoint]) {
        let minesToRemove = bombs.filter { $0.kind == .mine && area.contains($0.position) }
        if let scene {
            for (index, mine) in minesToRemove.enumerated() {
                mine.explode(in: scene, delay: 0.12 + 0.08 * Double(index))
            }
        }
        bombs.removeAll { $0.kind == .mine && area.contains($0.position) }

        for other in bombs where other.kind == .sensor && area.contains(other.position) {
            other.arm()
        }

        let barrelsToExplode = bombs.filter { $0.kind == .barrel && !$0.isExpired && area.contains($0.position) }
        for barrel in barrelsToExplode {
            detonate(barrel)
            guard !isGameOver else { return }
        }
    }

    /// A barrel going off, whether a sensor's blast set it off or its own fuse
    /// did after it was pushed onto a bomb: beams down its whole row and column
    /// (`Bomb.explodeBarrel`). They hurt the boss if they cross it (the kraken's
    /// lair, the moray's head, the galleon's hull), and the snake if its head is on that row or column (unless
    /// bomb-eater is active; the beams passing through its body are harmless).
    /// The bomb it was primed on goes off with it. Callers check `isGameOver`.
    private func detonate(_ barrel: Bomb) {
        let hitsHead = !isBombEaterActive && GameManager.cross(at: barrel.position, contains: snake.head)
        let trigger = barrel.primedOn.flatMap { primed in bombs.contains { $0 === primed } ? primed : nil }
        if let scene {
            barrel.explodeBarrel(columns: columns, rows: rows, scene: scene)
            trigger?.explode(in: scene)
        }
        if let trigger {
            bombs.removeAll { $0 === trigger }
        }
        onJolt?(.explosion(GridGeometry.position(for: barrel.position, cellSize: cellSize, origin: origin)))

        // Counted even if the same blast ends the snake's run.
        if let boss, boss.isCrossed(byBlastFrom: barrel.position) {
            strike(boss)
        }
        if hitsHead {
            hurtPlayer(.blast)
        }
    }

    // MARK: Pushing

    /// Everything the snake shoves rather than stops against (`Pushable`): barrels
    /// (including one primed on a mine, which is no longer solid) and cannonballs.
    /// A future movable object gets added here.
    private var pushables: [Pushable] {
        let barrels: [Pushable] = bombs.filter { $0.kind == .barrel && !$0.isExpired }
        return barrels + cannonballs
    }

    private func advanceSnake() -> SnakeAdvanceResult {
        snake.advance(
            columns: columns,
            rows: rows,
            foodPosition: food.position,
            halvedGrowth: mode == .levels,
            isBlocked: isBarrier
        )
    }

    /// Shoves `object` away from the head next to it (see `route(of:heading:)`).
    /// Returns false, leaving it be, if it can't move at all; then it's as solid
    /// as a wall, and bumping it costs a life like one. Fruit it touches on the
    /// way counts as eaten by the snake. A barrel pushed onto a bomb primes on
    /// top of it, its fuse starting once its move is over.
    ///
    /// A cannonball that rolls up into the galleon's hull holes it instead: see
    /// `fire(_:along:heading:)`. That works point blank too, from right under it.
    /// One that rolls into the moray, anywhere along its body, hurts it as it
    /// arrives, and comes to rest against it, ready to be pushed again. That one
    /// needs a run-up: a ball already touching the moray just won't move.
    private func push(_ object: Pushable, awayFrom head: GridPoint) -> Bool {
        guard object.isSolid else { return false }
        let heading = GameManager.step(from: head, to: object.position)
        let path = route(of: object, heading: heading)
        let beyond = GridPoint(x: path.destination.x + heading.dx, y: path.destination.y + heading.dy)
        if let ball = object as? Cannonball, let galleon, galleon.cells.contains(beyond) {
            fire(ball, along: path, heading: heading)
            return true
        }
        guard path.cells > 0 else { return false }

        let duration = object.move(to: path.destination, cells: path.cells)
        collectFruit(along: path.touched)
        onJolt?(.push)
        if let trigger = path.landedOn, let barrel = object as? Bomb {
            barrel.prime(on: trigger, after: duration)
        }
        if object is Cannonball, let moray, moray.cells.contains(beyond) {
            let stop = GridGeometry.position(for: path.destination, cellSize: cellSize, origin: origin)
            let contact = CGPoint(x: stop.x + CGFloat(heading.dx) * cellSize / 2, y: stop.y + CGFloat(heading.dy) * cellSize / 2)
            cannonHits.append((duration, contact, moray))
        }
        return true
    }

    /// Where a push takes `object` along `heading`: one cell for something that
    /// steps, as far as it goes for something that rolls. It stops before a
    /// barrier (wall, lair, another solid pushable), the snake, the power-up or
    /// the map's edge -- pushables don't wrap like the snake, since a roll around
    /// an open row would never end. Fruit doesn't stop it. A bomb ahead stops it in
    /// front, unless it `landsOnBombs` (a barrel), which stops it on top
    /// (`landedOn`) -- not on one another barrel is already primed on, though.
    private func route(of object: Pushable, heading: (dx: Int, dy: Int)) -> Route {
        let limit = object.pushStyle == .step ? 1 : max(columns, rows)
        var cell = object.position
        var touched: [GridPoint] = []
        while touched.count < limit {
            let next = GridPoint(x: cell.x + heading.dx, y: cell.y + heading.dy)
            guard next.x >= 0, next.x < columns, next.y >= 0, next.y < rows,
                  !isBarrier(next), !snake.segments.contains(next), next != powerUp?.position
            else { break }

            if let bomb = bombs.first(where: { $0.position == next && $0.kind != .barrel && !$0.isExpired }) {
                guard object.landsOnBombs, !bomb.isUnderBarrel else { break }
                touched.append(next)
                return (next, touched.count, touched, bomb)
            }
            cell = next
            touched.append(next)
        }
        return (cell, touched.count, touched, nil)
    }

    /// Where a push takes something (`route(of:heading:)`): where it ends up, how
    /// many cells that is, every cell it touches on the way, and the bomb it lands
    /// on, if it's a barrel that did.
    private typealias Route = (destination: GridPoint, cells: Int, touched: [GridPoint], landedOn: Bomb?)

    /// A cannonball pushed up into the galleon's hull: it rolls up, smashes in and
    /// is gone, and the hit lands as it gets there (`updateCannonHits`). Fruit it
    /// passes still counts.
    private func fire(_ ball: Cannonball, along path: Route, heading: (dx: Int, dy: Int)) {
        let impact = ball.smash(rollingTo: path.destination, cells: path.cells, heading: heading)
        cannonballs.removeAll { $0 === ball }
        collectFruit(along: path.touched)
        onJolt?(.push)
        let top = GridGeometry.position(for: path.destination, cellSize: cellSize, origin: origin)
        if let galleon {
            cannonHits.append((impact, CGPoint(x: top.x, y: top.y + cellSize / 2), galleon))
        }
    }

    /// Counts down the cannonballs on their way into a boss; each one that gets
    /// there costs it a life (if it isn't still recovering from the last): a hole
    /// blown in the galleon's hull, a heavy thud into the moray.
    private func updateCannonHits(delta: TimeInterval) {
        guard !cannonHits.isEmpty else { return }
        for index in cannonHits.indices {
            cannonHits[index].timeLeft -= delta
        }
        let arrived = cannonHits.filter { $0.timeLeft <= 0 }
        cannonHits.removeAll { $0.timeLeft <= 0 }
        for hit in arrived {
            if let scene {
                if hit.target is Galleon {
                    BoardEffects.explosion(at: hit.point, color: SKColor(red: 1, green: 0.6, blue: 0.3, alpha: 1),
                                           cellSize: cellSize, size: 1.4, in: scene)
                } else {
                    BoardEffects.impact(at: hit.point, color: SKColor(named: "Foam") ?? .white, cellSize: cellSize, in: scene)
                }
            }
            onJolt?(.explosion(hit.point))
            strike(hit.target)
        }
    }

    /// Fruit a pushed object touched on its way (every cell it passed through or
    /// came to rest on) counts as eaten by the snake: the mango scores and grows
    /// it, mine fruit counts toward a mine.
    private func collectFruit(along cells: [GridPoint]) {
        for cell in cells {
            if food.position == cell {
                snake.feed(halvedGrowth: mode == .levels)
                scoreFruit()
            }
            if let mineFruit, mineFruit.position == cell {
                collectMineFruit(mineFruit)
            }
        }
    }

    // MARK: Mines

    /// Eaten: counts toward the next mine, and moves elsewhere like the mango does.
    private func collectMineFruit(_ fruit: Food) {
        mineFruitTowardNext += 1
        if mineFruitTowardNext >= GameManager.mineFruitPerMine {
            mineFruitTowardNext = 0
            minesReady += 1
        }
        fruit.relocate(columns: columns, rows: rows, avoiding: occupiedBySnakeWallsAndBombs + [food.position])
        reportMineSupply()
    }

    /// The player tapped: drops a ready mine right where the head is. Only a
    /// head ever touches a mine, and this one is on its way out -- the mine check
    /// only runs after the snake moves, and its body passing over is harmless --
    /// so the snake leaves it behind safely. Ignored with no mine ready, or if a
    /// bomb is already there.
    func dropMine() {
        guard !isGameOver, !isAwaitingNextLevel, !isWaitingToStart, minesReady > 0 else { return }
        let cell = snake.head
        guard !bombs.contains(where: { $0.position == cell && !$0.isExpired }) else { return }

        minesReady -= 1
        let mine = Bomb(kind: .mine, position: cell, cellSize: cellSize, origin: origin)
        if let scene {
            mine.addToScene(scene)
            BoardEffects.bubbleBurst(at: headWorldPosition, count: 6, cellSize: cellSize, in: scene)
        }
        bombs.append(mine)
        onJolt?(.drop)
        reportMineSupply()
    }

    private func reportMineSupply() {
        onMineSupplyChanged?(mineFruit == nil ? nil : MineSupply(progress: mineFruitTowardNext, ready: minesReady))
    }

    /// The one-cell step from `point` to its neighbor `next`, undoing a wrap
    /// across the map's edge (where the raw difference is the map's width or
    /// height, not 1).
    private static func step(from point: GridPoint, to next: GridPoint) -> (dx: Int, dy: Int) {
        func unwrap(_ delta: Int) -> Int {
            abs(delta) > 1 ? (delta > 0 ? -1 : 1) : delta
        }
        return (unwrap(next.x - point.x), unwrap(next.y - point.y))
    }

    /// Advances the kraken's strikes by real time, like the bomb timers, so they
    /// don't speed up with the snake. A strike hits only while its tentacle is up,
    /// anywhere in its patch, and only the head counts -- same rule as a barrel
    /// blast. Bomb-eater doesn't protect against it: tentacles aren't bombs.
    private func updateKraken(delta: TimeInterval) {
        guard let kraken else { return }
        // Off the map is fine; the kraken clamps it.
        kraken.update(delta: delta, aim: aimAhead(by: TentacleStrike.warningDuration))
        if kraken.isStriking(snake.head) {
            hurtPlayer(.tentacle)
        }
    }

    /// Where the head will be in `seconds` if it keeps going straight, or where it
    /// is while it's stopped against something: an attack with a warning, aimed at
    /// its current cell, would always land behind a snake swimming straight. It may
    /// be off the map; callers clamp it or check.
    private func aimAhead(by seconds: TimeInterval) -> GridPoint {
        let lead = isSnakeBlocked ? 0 : Int(seconds / moveInterval)
        let heading = snake.direction.vector
        return GridPoint(x: snake.head.x + heading.dx * lead, y: snake.head.y + heading.dy * lead)
    }

    /// Lets the moray take its next step, if one's due. Into the snake, that's a
    /// bite; into a bomb (it can't see them), the bomb goes off and the moray takes
    /// the hit.
    private func updateMoray(delta: TimeInterval) {
        guard let moray, !moray.isDefeated,
              let next = moray.update(delta: delta, target: snake.head, isOpen: isOpenForMoray)
        else { return }

        if snake.segments.contains(next) {
            moray.bite(at: next)
            hurtPlayer(.bite)
            return
        }

        moray.advance(to: next)
        let struck = bombs.filter { $0.position == next && $0.kind != .barrel && !$0.isUnderBarrel && !$0.isExpired }
        guard !struck.isEmpty else { return }
        if let scene {
            struck.forEach { $0.explode(in: scene) }
        }
        bombs.removeAll { bomb in struck.contains { $0 === bomb } }
        onJolt?(.explosion(GridGeometry.position(for: next, cellSize: cellSize, origin: origin)))
        strike(moray)
    }

    /// Lets the galleon sail and fire, by real time like the kraken's strikes, and
    /// resolves whatever of its shot has landed.
    private func updateGalleon(delta: TimeInterval) {
        guard let galleon else { return }
        let landed = galleon.update(delta: delta, chasing: snake.head.x,
                                    aim: aimAhead(by: CannonShot.warningDuration), canLand: canCannonLand)
        for shot in landed {
            resolveCannonShot(shot)
        }
    }

    /// A cannon shot landing: the head anywhere in its 3x3 patch costs a life (and
    /// bomb-eater doesn't help: it isn't a bomb), and bombs there go off as they
    /// would in a sensor's blast. Then the ball comes to rest where it fell, a
    /// cannonball like any other, if the cell's clear and there aren't already
    /// plenty lying around.
    private func resolveCannonShot(_ shot: CannonShot) {
        let cell = shot.target
        onJolt?(.explosion(GridGeometry.position(for: cell, cellSize: cellSize, origin: origin)))
        if shot.covers(snake.head) {
            hurtPlayer(.blast)
        }
        if !isGameOver {
            setOffBombs(in: [cell] + GameManager.vicinity(of: cell, columns: columns, rows: rows))
        }

        let keepsBall = !isGameOver && cannonballs.count < maxLooseCannonballs && isClearForCannonball(cell)
        shot.settle(keepingBall: keepsBall)
        guard keepsBall else { return }
        let ball = Cannonball(position: cell, cellSize: cellSize, origin: origin)
        if let scene {
            ball.addToScene(scene)
        }
        cannonballs.append(ball)
    }

    /// Where the galleon's shot may land: open water with nothing solid over it all
    /// the way up, since a ball sinks straight down from the surface. So rock, a
    /// barrel or another cannonball overhead is shelter.
    private func canCannonLand(_ cell: GridPoint) -> Bool {
        guard let waterline = stage.waterline, cell.x >= 0, cell.x < columns, cell.y >= 0, cell.y < waterline else {
            return false
        }
        let solid = Set(pushables.filter(\.isSolid).map(\.position))
        return (cell.y..<waterline).allSatisfy { y in
            let point = GridPoint(x: cell.x, y: y)
            return !isWall(point) && !solid.contains(point)
        }
    }

    /// Whether a fallen cannonball can come to rest in `cell`: nothing else there.
    private func isClearForCannonball(_ cell: GridPoint) -> Bool {
        !isBarrier(cell) && !snake.segments.contains(cell)
            && cell != food.position && cell != mineFruit?.position && cell != powerUp?.position
            && !bombs.contains { $0.position == cell && !$0.isExpired }
    }

    /// Where the moray may go: not into walls or anything solid and pushable, but
    /// yes into the snake (what it's after) and into mines (it can't see them).
    private func isOpenForMoray(_ cell: GridPoint) -> Bool {
        !(walls?.contains(cell) ?? false) && !pushables.contains { $0.isSolid && $0.position == cell }
    }

    /// Every way the snake gets hurt comes through here: costs a life, unless it's
    /// still in its grace period from the last hit. Callers check `isGameOver`
    /// afterwards to decide whether to carry on.
    ///
    /// - Not the last life: a red flash and shudder, then it blinks, untouchable,
    ///   for `hitGraceDuration`.
    /// - The last life: the run stops at once (`isGameOver`), but `onGameOver`, and
    ///   so the overlay, waits for the snake's death animation to finish.
    /// - In zen mode it plays out like any hit that isn't the last, but no life is
    ///   lost, so the run never ends.
    private func hurtPlayer(_ hurt: Hurt) {
        guard !isGameOver, hitGraceRemaining <= 0 else { return }
        if !isZen {
            lives -= 1
            if maxLives > 1 {
                onLivesChanged?(lives)
            }
        }
        showImpact(hurt)

        guard lives > 0 else {
            isGameOver = true
            onJolt?(.death)
            snake.playDeath { [weak self] in
                self?.onGameOver?()
            }
            return
        }
        onJolt?(.hit)
        hitGraceRemaining = hitGraceDuration
        snake.playHitImpact()
        snake.playHitBlink(duration: hitGraceDuration)
    }

    /// Where the hit happened: a bump throws up a puff where the head met the
    /// barrier, a tentacle a red splash at the head. Bombs and blasts bring their
    /// own explosions.
    private func showImpact(_ hurt: Hurt) {
        guard let scene else { return }
        let head = headWorldPosition
        switch hurt {
        case .barrier(let cell):
            // Half a cell toward the barrier, worked out from the step rather than
            // the barrier's position, which may be across a wrap.
            func unwrap(_ delta: Int) -> CGFloat {
                CGFloat(abs(delta) > 1 ? (delta > 0 ? -1 : 1) : delta)
            }
            let contact = CGPoint(
                x: head.x + unwrap(cell.x - snake.head.x) * cellSize / 2,
                y: head.y + unwrap(cell.y - snake.head.y) * cellSize / 2
            )
            BoardEffects.impact(at: contact, color: SKColor(named: "Foam") ?? .white, cellSize: cellSize, in: scene)
        case .tentacle, .bite:
            BoardEffects.impact(at: head, color: SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), cellSize: cellSize, in: scene)
        case .bomb, .blast:
            break
        }
    }

    /// Cells the snake stops against instead of entering: walls (and the sky, in a
    /// stage that reaches the surface), the boss (the kraken's lair, the moray's
    /// body, the galleon's hull) and anything solid and pushable (which the tick then tries to shove out of the
    /// way). Its own body is the snake's business; see `Snake.advance`.
    private func isBarrier(_ point: GridPoint) -> Bool {
        (walls?.contains(point) ?? false)
            || (boss?.cells.contains(point) ?? false)
            || pushables.contains { $0.isSolid && $0.position == point }
    }

    /// Poses anything animated by the clock rather than by ticks (the kraken, the
    /// galleon, the storm), for `time` (`AmbientClock` seconds). Called every
    /// frame, including after a game over, so the boss keeps moving behind the
    /// overlay.
    func animate(time: Double) {
        kraken?.animate(time: time, focus: headWorldPosition)
        galleon?.animate(time: time)
        surface?.animate(time: time, focus: headWorldPosition)
    }

    /// How bright the storm's lightning is at `time` (`AmbientClock` seconds), so
    /// the water can be lit by it too: 0 in any stage without one.
    func lightning(at time: Double) -> Double {
        surface?.lightning(at: time) ?? 0
    }

    /// Whether `point` lies on `center`'s row or column -- the cross a
    /// `.barrel` blasts down when it explodes. Unlike `vicinity`, this never
    /// needs to wrap: `point`/`center` are always already-valid grid
    /// coordinates, so a plain equality check covers the whole row/column.
    private static func cross(at center: GridPoint, contains point: GridPoint) -> Bool {
        point.x == center.x || point.y == center.y
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
