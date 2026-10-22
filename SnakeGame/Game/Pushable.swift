import Foundation

/// Something on the board the snake shoves out of its way, instead of stopping
/// against it or eating it. Run into one and it moves off in the direction it
/// was pushed, and the snake takes its place; if it can't move at all, it's as
/// solid as a wall. `GameManager.push(_:awayFrom:)` works out where it goes, by its
/// `pushStyle`; the object just moves and animates.
///
/// - Barrels (`Bomb` with kind `.barrel`) **step** one cell per push, so the snake
///   walks them along in front of its head.
/// - Cannonballs (`Cannonball`) **roll**: one push sends them off until something
///   stops them.
///
/// Anything else that should move this way conforms too, and gets listed in
/// `GameManager.pushables`.
protocol Pushable: AnyObject {
    var position: GridPoint { get }

    /// One cell per push, or as far as it'll go.
    var pushStyle: PushStyle { get }

    /// Whether it blocks the way at all, and so gets pushed when run into. A barrel
    /// primed on top of a mine doesn't: the snake can swim straight through.
    var isSolid: Bool { get }

    /// Whether pushing it onto a bomb puts it there, on top of the bomb (a barrel,
    /// which then primes), rather than the bomb stopping it.
    var landsOnBombs: Bool { get }

    /// Moves it to `destination`, `cells` away in a straight line. Gameplay treats
    /// it as there at once; the move is animated, and its length returned so
    /// anything that happens on arrival can wait for it.
    func move(to destination: GridPoint, cells: Int) -> TimeInterval
}

enum PushStyle {
    /// One cell per push.
    case step
    /// Until it's stopped.
    case roll
}
