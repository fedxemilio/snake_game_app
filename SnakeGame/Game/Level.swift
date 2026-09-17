/// A fixed layout for Levels mode: an ASCII grid (same idea as the Python
/// project's LEVELS -- rows of characters, '-' empty, anything else a
/// wall) plus the score needed to advance past it. All three share one
/// grid size since `cellSize` is computed once, from whichever level a run
/// starts on, and can't change mid-run without rebuilding the scene.
struct Level {
    let map: [String]
    let pointsToAdvance: Int

    var rows: Int { map.count }
    var columns: Int { map.first?.count ?? 0 }

    /// Parsed once per level load, not per frame -- GameManager only calls
    /// this when a level is loaded, not on every tick.
    var walls: Set<GridPoint> {
        var result: Set<GridPoint> = []
        for (rowFromTop, row) in map.enumerated() {
            let y = rows - 1 - rowFromTop
            for (x, character) in row.enumerated() where character != "-" {
                result.insert(GridPoint(x: x, y: y))
            }
        }
        return result
    }

    static let all: [Level] = [
        Level(map: level1Map, pointsToAdvance: 40),
        Level(map: level2Map, pointsToAdvance: 40),
        Level(map: level3Map, pointsToAdvance: 40),
    ]
}

/// A single short pillar in the upper third, another in the lower third,
/// on opposite sides -- easy to route around, off the spawn column.
private let level1Map: [String] = {
    let empty = "----------------"
    let pillarA = "--#-------------"
    let pillarB = "-------------#--"
    return Array(repeating: empty, count: 8) +
        Array(repeating: pillarA, count: 4) +
        Array(repeating: empty, count: 6) +
        Array(repeating: pillarB, count: 4) +
        Array(repeating: empty, count: 8)
}()

/// Two short parallel pillars, columns 5/10 -- leaves the center lane
/// (columns 6-9) and most of the grid clear.
private let level2Map: [String] = {
    let empty = "----------------"
    let pillars = "-----#----#-----"
    return Array(repeating: empty, count: 11) +
        Array(repeating: pillars, count: 8) +
        Array(repeating: empty, count: 11)
}()

/// Four small corner blocks, nothing in the middle -- no forced squeeze.
private let level3Map: [String] = {
    let empty = "----------------"
    let corners = "--##--------##--"
    return Array(repeating: empty, count: 5) +
        Array(repeating: corners, count: 2) +
        Array(repeating: empty, count: 16) +
        Array(repeating: corners, count: 2) +
        Array(repeating: empty, count: 5)
}()
