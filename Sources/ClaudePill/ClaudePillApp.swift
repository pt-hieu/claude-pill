import AppKit
import SwiftUI

@main
@MainActor
enum ClaudePillApp {
    private static var statusController: StatusController?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        statusController = StatusController()
        application.run()
    }
}

@MainActor
final class StatusController: NSObject {
    private let store = EventStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let pillView = PassthroughHostingView(rootView: PillView(session: nil, unreadCount: 0, now: .now))
    private var refreshTimer: Timer?
    private var systemPadding: CGFloat = 0
    private var paddingObserver: NSObjectProtocol?

    override init() {
        super.init()

        popover.behavior = .transient
        popover.animates = false
        let hostingController = NSHostingController(
            rootView: SessionListView(store: store, onQuit: { NSApplication.shared.terminate(nil) }))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            paddingObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: button.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.measureSystemPadding() }
            }
        }

        store.onChange = { [weak self] in self?.renderPill() }
        // Keeps the relative time in the pill current.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderPill() }
        }
        renderPill()
    }

    private func renderPill() {
        guard let button = statusItem.button, let contentView = button.window?.contentView else { return }
        pillView.rootView = PillView(session: store.latestSession, unreadCount: store.unreadCount, now: .now)
        if pillView.superview !== contentView {
            pillView.frame = contentView.bounds
            pillView.autoresizingMask = [.width, .height]
            contentView.addSubview(pillView)
        }
        // The system pads the button inside the status item window and draws its click highlight across
        // the whole window. Size the item so the window, and so the highlight, is exactly the pill's width.
        // The window snaps to whole points, so round up: any shortfall truncates the pill's text.
        statusItem.length = max(1, pillView.fittingSize.width.rounded(.up) - systemPadding)
        button.toolTip = store.latestSession?.projectPath
    }

    /// The padding is only measurable after the first fixed length has been laid out, so measure it on
    /// that first resize, then stop observing: re-rendering on every resize would feed back into itself.
    private func measureSystemPadding() {
        guard let window = statusItem.button?.window, statusItem.length > 0, let observer = paddingObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        paddingObserver = nil
        systemPadding = (window.frame.width - statusItem.length).rounded(.down)
        renderPill()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApplication.shared.activate()
            store.markAllRead()
        }
    }
}

/// Draws the pill over the whole status item window while letting clicks reach the status item button.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
