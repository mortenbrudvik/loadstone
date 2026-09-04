import AppKit
import Combine

/// The slice of NSEvent monitor registration that `EdgeDragMonitor` uses. A global monitor is
/// only handed out to a process trusted for Accessibility, so without this seam the
/// setting-driven install/uninstall lifecycle would pass on a granted machine and fail in CI.
@MainActor
protocol MouseEventMonitoring {
    /// Installs the monitors. Returns false when the system refused the global one.
    @discardableResult
    func install(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Bool
    func uninstall()
}

/// The real monitors. `NSEvent.addGlobalMonitorForEvents` sees events destined for other apps;
/// the local one covers Loadstone's own windows, which the global monitor never reports.
@MainActor
final class SystemMouseEventMonitors: MouseEventMonitoring {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    @discardableResult
    func install(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Bool {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { handler($0); return $0 }
        return globalMonitor != nil
    }

    func uninstall() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

/// Watches left-button drags system-wide and snaps a window dragged to a screen edge. The
/// decisions live in `DragSnapTracker`; this class owns the event monitors, the preview, and
/// the Accessibility lookups.
@MainActor
final class EdgeDragMonitor {
    private let director: WindowDirector
    private let settings: AppSettings
    private let preview = SnapPreview()
    private var tracker = DragSnapTracker<AXWindow>()
    private var installed = false
    private var settingObserver: AnyCancellable?
    private let monitors: any MouseEventMonitoring

    init(
        director: WindowDirector = .shared,
        settings: AppSettings = .shared,
        monitors: any MouseEventMonitoring = SystemMouseEventMonitors()
    ) {
        self.director = director
        self.settings = settings
        self.monitors = monitors
    }

    /// True while the mouse monitors are installed. False when drag snapping is off, and also
    /// when the system refused the global monitor because Loadstone is not trusted for
    /// Accessibility — in both cases there is no drag snapping.
    var isMonitoring: Bool {
        installed
    }

    /// Installs the monitors while drag snapping is on and removes them while it is off,
    /// following the setting from then on. Calling it again is a no-op.
    func start() {
        guard settingObserver == nil else { return }
        settingObserver = settings.$dragSnappingEnabled.sink { [weak self] enabled in
            // @Published delivers synchronously on the thread that set the value, and
            // AppSettings is main-actor bound, so this is always the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                if enabled {
                    self.install()
                } else {
                    self.uninstall()
                }
            }
        }
    }

    func stop() {
        settingObserver = nil
        uninstall()
    }

    private func install() {
        guard !installed else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        installed = monitors.install(mask: mask) { [weak self] event in
            self?.enqueue(event)
        }
        guard installed else {
            // The local monitor may still have been installed; drop it rather than leaving a
            // half-armed pair that feeds the tracker events it can never complete a snap from.
            monitors.uninstall()
            Log.drag.error("could not install the global mouse monitor; drag snapping is off")
            return
        }
        Log.drag.info("drag snapping on")
    }

    private func uninstall() {
        monitors.uninstall()
        installed = false
        tracker.reset()
        preview.hide()
        Log.drag.info("drag snapping off")
    }

    /// The monitor closure is not main-actor isolated under strict concurrency and NSEvent is not
    /// Sendable, so pull out the two Sendable facts needed (event type, pointer in Cocoa screen
    /// space) and hop. `NSEvent.mouseLocation` rather than `event.locationInWindow` because
    /// global-monitor events carry no window.
    private nonisolated func enqueue(_ event: NSEvent) {
        let type = event.type
        let point = NSEvent.mouseLocation
        let time = event.timestamp
        DispatchQueue.main.async { [weak self] in
            self?.handle(type: type, at: point, time: time)
        }
    }

    private func handle(type: NSEvent.EventType, at point: CGPoint, time: TimeInterval) {
        switch type {
        case .leftMouseDown:
            tracker.mouseDown(at: point)

        case .leftMouseDragged:
            let target = tracker.mouseDragged(
                to: point,
                at: time,
                displays: Display.all,
                windowUnderPointer: { AXWindow.atCocoaPoint(point) },
                originOf: { $0.cocoaFrame?.origin }
            )
            if let target {
                preview.show(frame: target.tile.frame(in: target.display.visibleFrame))
            } else {
                preview.hide()
            }

        case .leftMouseUp:
            preview.hide()
            guard let (window, target) = tracker.mouseUp() else { return }
            let outcome = director.snap(target.tile, window: window, on: target.display)
            if outcome != .moved {
                Log.drag.error("snap to \(target.tile.rawValue, privacy: .public) failed: \(String(describing: outcome), privacy: .public)")
                NSSound.beep()
            }

        default:
            break
        }
    }
}
