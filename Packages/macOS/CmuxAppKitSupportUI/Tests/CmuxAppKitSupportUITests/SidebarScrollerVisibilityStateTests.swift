import AppKit
import Testing

@testable import CmuxAppKitSupportUI

@Suite struct SidebarScrollerVisibilityStateTests {
    @Test func bracketedLiveScrollStaysVisibleUntilScrollEnds() {
        var state = SidebarScrollerVisibilityState()

        #expect(state.handle(.willStartLiveScroll) == .show)
        #expect(state.handle(.didLiveScroll) == .show)
        #expect(state.handle(.didEndLiveScroll) == .fade)
    }

    @Test func unbracketedLegacyMouseScrollShowsThenFades() {
        var state = SidebarScrollerVisibilityState()

        #expect(state.handle(.didLiveScroll) == .showThenFade)
    }

    @MainActor
    @Test func controllerHidesAtRestAndShowsForLiveScroll() async throws {
        let center = NotificationCenter()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        scrollView.hasVerticalScroller = true
        let controller = SidebarScrollerVisibilityController(
            scrollView: scrollView,
            notificationCenter: center
        )
        let scroller = try #require(scrollView.verticalScroller)

        #expect(scroller.isHidden)
        #expect(scroller.alphaValue == 0)
        scroller.isHidden = false
        #expect(scroller.isHidden, "an AppKit layout pass must not reveal the idle scroller")

        center.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        await Task.yield()

        #expect(!scroller.isHidden)
        #expect(scroller.alphaValue == 1)
        scroller.isHidden = true
        #expect(!scroller.isHidden, "AppKit must not hide the scroller while user scrolling owns visibility")
        _ = controller
    }
}
