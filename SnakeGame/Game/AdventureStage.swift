/// One stop on Adventure's ascent from the deep up to the surface: a map, a boss,
/// and what the snake has to work with. Beat the boss and the run carries on to
/// the next stage (score and length carried over, lives refilled), by way of the
/// voyage chart (`VoyageChart`).
///
/// Every stage uses `AdventureMap`'s one size; only what's in the world changes.
struct AdventureStage {
    enum Boss {
        /// The kraken, its lair centered on this cell (see `Kraken`).
        case kraken(lair: GridPoint)
        /// The blind moray, starting coiled along these cells, head first (see
        /// `Moray`).
        case moray(body: [GridPoint])
        /// The galleon, starting with its hull centered over this column (see
        /// `Galleon`). Needs a stage with sky.
        case galleon(column: Int)
    }

    /// The place, as the chart labels it.
    let name: String
    /// The boss, as the HUD and victory screen name it.
    let bossName: String
    /// How far down it is, in meters, for the chart.
    let depth: Int
    /// One line about how to win, for the chart.
    let hint: String
    /// The victory screen's word under the boss's name, and its line below that.
    let victoryWord: String
    let victoryLine: String

    let walls: Set<GridPoint>
    /// Cells above the surface, if the stage reaches it: they block like walls, but
    /// show as stormy sky (`StormSurface`) rather than rock.
    let sky: Set<GridPoint>
    /// Where the snake starts, heading right, with room behind it for its body.
    let snakeStart: GridPoint
    let barrels: [GridPoint]
    let cannonballs: [GridPoint]
    /// Mines the snake arrives with (on top of any it's banked).
    let startingMines: Int
    let boss: Boss

    /// The lowest row of sky, the one sitting on the water, or nil for a stage
    /// that's all underwater.
    var waterline: Int? { sky.map(\.y).min() }

    static let all: [AdventureStage] = [krakensLair, morayHollows, shallows]

    /// Stage 1, at the bottom: the kraken. Hurt it with barrel blasts down a row or
    /// column through its lair (walk a barrel onto a mine you've dropped).
    static let krakensLair = AdventureStage(
        name: "Kraken's Lair",
        bossName: "KRAKEN",
        depth: 3_600,
        hint: "Walk a barrel onto a mine in line with the lair",
        victoryWord: "SLAIN",
        victoryLine: "Kraken's Lair lies behind you",
        walls: AdventureMap.walls(in: AdventureMap.krakensLair),
        sky: [],
        snakeStart: GridPoint(x: 24, y: 8),
        // A line of barrels down the left side, one at the head of every other
        // row (so the snake can get in behind each), ready to be walked out
        // along it. Rows 17 to 23 run through the lair.
        barrels: stride(from: 11, through: 25, by: 2).map { GridPoint(x: 5, y: $0) },
        // On the right side, to try rolling around.
        cannonballs: [GridPoint(x: 62, y: 12), GridPoint(x: 62, y: 17), GridPoint(x: 62, y: 24)],
        startingMines: 0,
        boss: .kraken(lair: GridPoint(x: 35, y: 20))
    )

    /// Stage 2: the blind moray, a giant eel that hunts the snake through a trench
    /// of rock pillars. It can't see mines: drop them in its path (it follows you)
    /// and let it swim into them. A cannonball rolled into it, or a barrel blast
    /// across its head, hurts it too.
    static let morayHollows = AdventureStage(
        name: "Moray Hollows",
        bossName: "MORAY",
        depth: 1_900,
        hint: "It's blind: leave mines in its path, or roll a cannonball into it",
        victoryWord: "SLAIN",
        victoryLine: "Moray Hollows lies behind you",
        walls: AdventureMap.walls(in: AdventureMap.morayHollows),
        sky: [],
        snakeStart: GridPoint(x: 40, y: 2),
        barrels: [GridPoint(x: 30, y: 15), GridPoint(x: 40, y: 15), GridPoint(x: 20, y: 25), GridPoint(x: 50, y: 25)],
        cannonballs: [GridPoint(x: 5, y: 10), GridPoint(x: 64, y: 10)],
        // One to start with, so the trick can be tried before any mine fruit.
        startingMines: 1,
        // Coiled inside its cave at the top middle, head at the cave's mouth.
        boss: .moray(body: [
            GridPoint(x: 35, y: 34), GridPoint(x: 36, y: 34), GridPoint(x: 37, y: 34), GridPoint(x: 38, y: 34),
            GridPoint(x: 39, y: 34), GridPoint(x: 40, y: 34), GridPoint(x: 40, y: 35), GridPoint(x: 39, y: 35),
            GridPoint(x: 38, y: 35), GridPoint(x: 37, y: 35), GridPoint(x: 36, y: 35), GridPoint(x: 35, y: 35),
            GridPoint(x: 34, y: 35), GridPoint(x: 33, y: 35), GridPoint(x: 32, y: 35), GridPoint(x: 31, y: 35),
        ])
    )

    /// Stage 3, the last, just under the stormy surface: a ghost galleon that sails
    /// overhead, following the snake, and fires its cannons down into the water
    /// around it. Its shot comes to rest where it lands, as cannonballs: roll them
    /// straight up into its hull. Barrel blasts up through it hurt it too.
    static let shallows = AdventureStage(
        name: "The Shallows",
        bossName: "GALLEON",
        depth: 40,
        hint: "Roll its own shot back up into its hull",
        victoryWord: "SUNK",
        victoryLine: "Nothing stands between you and the surface",
        walls: AdventureMap.walls(in: AdventureMap.shallows),
        sky: AdventureMap.sky(in: AdventureMap.shallows),
        snakeStart: GridPoint(x: 35, y: 6),
        barrels: [GridPoint(x: 13, y: 14), GridPoint(x: 56, y: 14)],
        // In columns clear all the way to the surface, so each can be rolled up
        // as soon as the galleon is over it.
        cannonballs: [GridPoint(x: 21, y: 8), GridPoint(x: 48, y: 8), GridPoint(x: 39, y: 13)],
        startingMines: 1,
        boss: .galleon(column: 35)
    )
}
