import AppKit
import Testing

@testable import CmuxAppKitSupportUI

@Suite struct SidebarScrollIndicatorVisibilityStateTests {
    @Test func bracketedLiveScrollStaysVisibleUntilScrollEnds() {
        var state = SidebarScrollIndicatorVisibilityState()

        #expect(state.handle(.willStartLiveScroll) == .show)
        #expect(state.handle(.didLiveScroll) == .show)
        #expect(state.handle(.didEndLiveScroll) == .fade)
    }

    @Test func unbracketedLegacyMouseScrollShowsThenFades() {
        var state = SidebarScrollIndicatorVisibilityState()

        #expect(state.handle(.didLiveScroll) == .showThenFade)
    }

    @MainActor
    @Test func controllerHidesAtRestAndShowsForLiveScroll() async throws {
        let center = NotificationCenter()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 800))
        let controller = SidebarScrollIndicatorVisibilityController(
            scrollView: scrollView,
            notificationCenter: center
        )
        scrollView.layoutSubtreeIfNeeded()
        let indicator = controller.indicatorView

        #expect(indicator.isHidden)
        #expect(indicator.alphaValue == 0)

        center.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        await Task.yield()

        #expect(!indicator.isHidden)
        #expect(indicator.alphaValue == 1)
        _ = controller
    }
}
