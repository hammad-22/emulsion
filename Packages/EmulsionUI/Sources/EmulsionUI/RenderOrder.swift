/// Shows a finished render unless a newer one already is, so a moving slider never freezes the photo.
struct RenderOrder {
    private var started = 0
    private var shown = 0

    mutating func begin() -> Int {
        started += 1
        return started
    }

    mutating func shouldShow(_ ticket: Int) -> Bool {
        guard ticket > shown else { return false }
        shown = ticket
        return true
    }
}
