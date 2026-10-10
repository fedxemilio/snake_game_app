import Foundation

/// The one clock every animated piece of the start menu reads, so the water, the sea
/// life, the title and the button all agree on what moment it is.
///
/// Counts from the first time anything reads it (in practice, the first frame of the
/// menu at launch) rather than using `timeIntervalSinceReferenceDate`: that's hundreds
/// of millions of seconds, too big to survive the trip into the water shader's 32-bit
/// `float` without the motion turning steppy. It keeps running across trips into a
/// game and back, so the serpent's passes carry on where they were.
enum MenuClock {
    private static let start = Date()

    /// Seconds since the clock started at `date`.
    static func seconds(at date: Date) -> Double {
        date.timeIntervalSince(start)
    }

    /// The moment everything is frozen at when Reduce Motion is on, chosen so the
    /// serpent is mid-pass overhead.
    static let still: Double = 13.1

    /// A repeatable pseudo-random number in 0..<1 for (index, salt), so scattered
    /// things (specks, bubbles, the serpent's route) can be pure functions of their
    /// index and the clock with nothing stored.
    static func random(_ index: Int, salt: Double) -> Double {
        let raw = sin(Double(index) * 12.9898 + salt * 78.233) * 43758.5453
        return raw - raw.rounded(.down)
    }
}
