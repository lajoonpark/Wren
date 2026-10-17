import AppKit
import SwiftUI

/// Reports whether the main window is actually on screen: not closed,
/// miniaturized, hidden, or fully occluded. The session uses this to drop to
/// a slow background sampling interval while nothing is looking.
struct WindowVisibilityObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        VisibilityView()
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        // The representable can be updated in place, so keep the closure fresh.
        view.onChange = onChange
    }

    /// Watches its window's occlusion, miniaturization and close state plus
    /// the app's hidden state, all on the main thread.
    final class VisibilityView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private weak var observedWindow: NSWindow?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            if let window {
                observedWindow = window
                addObservers(for: window)
            }
            report()
        }

        private func addObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            tokens.append(center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.report() })
            tokens.append(center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.report() })
            tokens.append(center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.report() })
            tokens.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.report() })
            // App-level notifications carry no window, so they go unfiltered.
            tokens.append(center.addObserver(
                forName: NSApplication.didHideNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.report() })
            tokens.append(center.addObserver(
                forName: NSApplication.didUnhideNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.report() })
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            for token in tokens {
                center.removeObserver(token)
            }
            tokens.removeAll()
        }

        private func report() {
            onChange(isVisible)
        }

        private var isVisible: Bool {
            guard let window = observedWindow else { return false }
            return window.isVisible
                && window.occlusionState.contains(.visible)
                && !window.isMiniaturized
                && !NSApp.isHidden
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        deinit {
            let center = NotificationCenter.default
            for token in tokens {
                center.removeObserver(token)
            }
            tokens.removeAll()
        }
    }
}
