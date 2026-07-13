import AppKit
import QuartzCore

@MainActor
final class SidebarScrollerVisibilityController {
    private static let fadeDuration: TimeInterval = 0.35

    private weak var scrollView: NSScrollView?
    private weak var scroller: NSScroller?
    private let notificationCenter: NotificationCenter
    private var state = SidebarScrollerVisibilityState()
    private var fadeGeneration = 0
    // Main-actor-owned until deinit, where removing the now-unreachable
    // controller's observer tokens is safe from the nonisolated destructor.
    private nonisolated(unsafe) var observerTokens: [any NSObjectProtocol] = []

    init(scrollView: NSScrollView, notificationCenter: NotificationCenter = .default) {
        self.scrollView = scrollView
        self.notificationCenter = notificationCenter
        synchronizeScroller()

        observe(NSScrollView.willStartLiveScrollNotification, event: .willStartLiveScroll)
        observe(NSScrollView.didLiveScrollNotification, event: .didLiveScroll)
        observe(NSScrollView.didEndLiveScrollNotification, event: .didEndLiveScroll)
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

    func synchronizeScroller() {
        guard let nextScroller = scrollView?.verticalScroller else { return }
        guard scroller !== nextScroller else { return }

        scroller = nextScroller
        nextScroller.alphaValue = 0
        nextScroller.isHidden = true
    }

    private func observe(
        _ name: Notification.Name,
        event: SidebarScrollerVisibilityEvent
    ) {
        guard let scrollView else { return }
        observerTokens.append(
            notificationCenter.addObserver(forName: name, object: scrollView, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
        )
    }

    private func handle(_ event: SidebarScrollerVisibilityEvent) {
        switch state.handle(event) {
        case .show:
            showScroller()
        case .fade:
            fadeScroller()
        case .showThenFade:
            showScroller()
            fadeScroller()
        }
    }

    private func showScroller() {
        guard let scroller else { return }
        fadeGeneration &+= 1
        scroller.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            scroller.animator().alphaValue = 1
        }
    }

    private func fadeScroller() {
        guard let scroller else { return }
        fadeGeneration &+= 1
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scroller.animator().alphaValue = 0
        } completionHandler: { [weak self, weak scroller] in
            Task { @MainActor [weak self, weak scroller] in
                guard let self, self.fadeGeneration == generation else { return }
                scroller?.isHidden = true
            }
        }
    }
}

@MainActor
enum SidebarScrollerVisibilityControllers {
    private static let controllers = NSMapTable<NSScrollView, SidebarScrollerVisibilityController>
        .weakToStrongObjects()

    static func attach(to scrollView: NSScrollView) {
        if let controller = controllers.object(forKey: scrollView) {
            controller.synchronizeScroller()
            return
        }
        controllers.setObject(
            SidebarScrollerVisibilityController(scrollView: scrollView),
            forKey: scrollView
        )
    }
}
