import AppKit
import Foundation

/// Watches every `NSScrollView` in the app and reports when one is in motion.
///
/// Wren uses this while the reader scrolls for two reasons:
/// - `AppSession` stops publishing, so the visible rows cannot re-sort or change
///   value under the finger (the background sampler keeps recording history);
/// - hover feedback snaps instead of easing. A scroll sweeps the pointer across
///   many rows, and each 0.28 s text-colour animation keeps the render loop
///   awake re-rasterizing glyphs at display refresh.
///
/// The notifications are process-wide, so one monitor covers every tab and
/// every ledger without a representable per scroll view. A short watchdog ends
/// the gesture for scrolling devices that post per-notch `didLiveScroll`
/// notifications without a matching `didEndLiveScroll`.
@MainActor
final class ScrollActivityMonitor {
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var lastActivity = Date.distantPast
    private var watchdog: DispatchWorkItem?
    private var isActive = false

    /// How long after the last scroll notification the gesture is considered
    /// over. Long enough to bridge trackpad momentum, short enough that the
    /// ledger resumes promptly when the reader stops.
    private static let quietPeriod: TimeInterval = 0.12

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let center = NotificationCenter.default
        let liveNames: [Notification.Name] = [
            NSScrollView.willStartLiveScrollNotification,
            NSScrollView.didLiveScrollNotification,
            NSScrollView.didEndLiveScrollNotification,
        ]
        for name in liveNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let view = note.object as? NSScrollView else { return }
                // Filter out scroll views that are being torn down with a tab;
                // their final notification should not start a gesture.
                let belongsToApp = view.window != nil
                MainActor.assumeIsolated {
                    self?.noteScroll(belongsToApp: belongsToApp)
                }
            })
        }

        // Live-scroll notifications are reliable for trackpad gestures, but a
        // notched mouse wheel or the keyboard can move a clip view without
        // posting them. The clip view's bounds change covers every input.
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let view = note.object as? NSClipView else { return }
            let belongsToApp = view.window != nil
            MainActor.assumeIsolated {
                self?.noteScroll(belongsToApp: belongsToApp)
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func noteScroll(belongsToApp: Bool) {
        guard belongsToApp else { return }
        lastActivity = Date()
        if !isActive {
            isActive = true
            onChange(true)
        }
        scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        // One pending check at a time: at 60 Hz a new work item per scroll event
        // would cost more than the thing it is measuring.
        guard watchdog == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.watchdog = nil
            if Date().timeIntervalSince(self.lastActivity) >= Self.quietPeriod {
                guard self.isActive else { return }
                self.isActive = false
                self.onChange(false)
            } else {
                self.scheduleWatchdog()
            }
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quietPeriod, execute: item)
    }
}
