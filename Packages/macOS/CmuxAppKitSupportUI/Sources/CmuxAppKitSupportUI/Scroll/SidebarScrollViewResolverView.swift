public import AppKit

/// Resolves the sidebar list's enclosing `NSScrollView` for the SwiftUI layer
/// (``SidebarScrollViewResolver``), which applies the sidebar configuration in
/// ``AppKit/NSScrollView/applySidebarScrollIndicatorConfiguration()`` through
/// `onResolve`.
public final class SidebarScrollViewResolverView: NSView {
    /// Invoked with the resolved enclosing scroll view (or `nil`) after each
    /// deferred resolution hop.
    public var onResolve: ((NSScrollView?) -> Void)?

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveScrollView()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveScrollView()
    }

    /// Resolves the enclosing scroll view after one deferred main-actor hop so
    /// the view hierarchy settles before the configuration is applied.
    ///
    /// `nonisolated` keeps lifecycle callers from requiring a synchronous
    /// main-actor hop. The body only schedules a `@MainActor` task, so the
    /// actual resolution still runs on the main actor.
    public nonisolated func resolveScrollView() {
        // Deferred one main-actor hop so the view hierarchy settles before
        // enclosingScrollView is resolved.
        Task { @MainActor [weak self] in
            guard let self else { return }
            onResolve?(self.enclosingScrollView)
        }
    }
}
