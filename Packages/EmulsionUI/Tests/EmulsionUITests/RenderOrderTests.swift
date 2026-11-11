import Testing

@testable import EmulsionUI

struct RenderOrderTests {
    @Test func aSupersededRenderStillShowsWhenItIsTheNewestFinished() {
        var order = RenderOrder()
        let first = order.begin()
        let second = order.begin()
        let showsFirst = order.shouldShow(first)
        let showsSecond = order.shouldShow(second)
        #expect(showsFirst, "During a drag the earlier render is newer than what's on screen")
        #expect(showsSecond)
    }

    @Test func anOlderRenderNeverReplacesANewerOne() {
        var order = RenderOrder()
        let first = order.begin()
        let second = order.begin()
        let showsSecond = order.shouldShow(second)
        let showsFirst = order.shouldShow(first)
        #expect(showsSecond)
        #expect(!showsFirst)
    }
}
