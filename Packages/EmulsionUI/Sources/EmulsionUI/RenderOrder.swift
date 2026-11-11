/// Orders renders that overlap while a slider moves. Each change starts a render and
/// supersedes the last, so discarding superseded results would leave the photo frozen until
/// the finger stops; instead a finished render is shown unless a newer one already is.
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
