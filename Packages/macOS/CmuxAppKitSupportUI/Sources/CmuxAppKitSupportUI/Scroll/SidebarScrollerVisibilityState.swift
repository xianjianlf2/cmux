enum SidebarScrollerVisibilityEvent {
    case willStartLiveScroll
    case didLiveScroll
    case didEndLiveScroll
}

enum SidebarScrollerVisibilityAction: Equatable {
    case show
    case fade
    case showThenFade
}

/// Converts AppKit's two user-scroll notification shapes into explicit
/// scroller presentation actions.
///
/// Trackpads and scroller drags normally produce a start/end pair. Legacy
/// mouse wheels may only produce `didLiveScroll`, so each unbracketed event
/// restarts the fade instead of waiting for an end notification that will
/// never arrive.
struct SidebarScrollerVisibilityState {
    private var isLiveScrollBracketed = false

    mutating func handle(_ event: SidebarScrollerVisibilityEvent) -> SidebarScrollerVisibilityAction {
        switch event {
        case .willStartLiveScroll:
            isLiveScrollBracketed = true
            return .show
        case .didLiveScroll:
            return isLiveScrollBracketed ? .show : .showThenFade
        case .didEndLiveScroll:
            isLiveScrollBracketed = false
            return .fade
        }
    }
}
