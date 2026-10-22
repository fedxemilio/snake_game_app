/// One stop on Adventure's ascent from the deep toward the surface: a map, a boss,
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
    }

    /// The place, as the chart labels it.
    let name: String
    /// The boss, as the HUD and victory screen name it.
    let bossName: String
    /// How far down it is, in meters, for the chart.
    let depth: Int
    /// One line about how to win, for the chart.
    let hint: String

    let walls: Set<GridPoint>
    /// Where the snake starts, heading right, with room behind it for its body.
    let snakeStart: GridPoint
    let barrels: [GridPoint]
    let cannonballs: [GridPoint]
    /// Mines the snake arrives with (on top of any it's banked).
    let startingMines: Int
    let boss: Boss

    static let all: [AdventureStage] = [krakensLair, morayHollows]

    /// Stage 1, at the bottom: the kraken. Hurt it with barrel blasts down a row or
    /// column through its lair (walk a barrel onto a mine you've dropped).
    static let krakensLair = AdventureStage(
        name: "Kraken's Lair",
        bossName: "KRAKEN",
        depth: 3_600,
        hint: "Walk a barrel onto a mine in line with the lair",
        walls: AdventureMap.walls(in: AdventureMap.krakensLair),
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
    /// and let it swim into them. Barrel blasts across its head hurt it too.
    static let morayHollows = AdventureStage(
        name: "Moray Hollows",
        bossName: "MORAY",
        depth: 1_900,
        hint: "It's blind: leave mines in its path",
        walls: AdventureMap.walls(in: AdventureMap.morayHollows),
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
}
