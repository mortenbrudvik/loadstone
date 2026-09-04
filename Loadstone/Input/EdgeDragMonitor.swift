import AppKit
import Combine

/// Watches left-button drags system-wide and snaps a window dragged to a screen edge. The
/// decisions live in `DragSnapTracker`; this class owns the event monitors, the preview, and
/// the Accessibility lookups.
@MainActor
final class EdgeDragMonitor {
    private let director: WindowDirector
    private let settings: AppSettings
    private let preview = SnapPreview()
    private var tracker = DragSnapTracker<AXWindow>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var settingObserver: AnyCancellable?

    init(director: WindowDirector = .shared, settings: AppSettings = .shared) {
        self.director = director
        self.settings = settings
    }

    /// True while the mouse monitors are installed.
    var isMonitoring: Bool {
        globalMonitor != nil
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
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.enqueue(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.enqueue(event)
            return event
        }
        if globalMonitor == nil {
            Log.drag.error("could not install the global mouse monitor; drag snapping is off")
        } else {
            Log.drag.info("drag snapping on")
        }
    }

    private func uninstall() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.handle(type: type, at: point)
        }
    }

    private func handle(type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            tracker.mouseDown(at: point)

        case .leftMouseDragged:
            let target = tracker.mouseDragged(
                to: point,
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
