/// The different kinds of power-up that can spawn. Each gets its own color
/// (see PowerUp) and, eventually, its own effect in GameManager — only
/// .tailCutter does anything so far.
enum PowerUpKind: CaseIterable {
    case bombEater
    case tailCutter
    case speedCooler
}
