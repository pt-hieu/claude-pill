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

    override init() {
        super.init()

        popover.behavior = .transient
        popover.animates = false
        let hostingController = NSHostingController(
            rootView: SessionListView(
                store: store,
                onSelect: { [weak self] session in
                    self?.popover.performClose(nil)
                    Ghostty.open(session)
                },
                onQuit: { NSApplication.shared.terminate(nil) }))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        store.onChange = { [weak self] in self?.renderPill() }
        // Keeps the relative time in the pill current.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderPill() }
        }
        renderPill()
    }

    private func renderPill() {
        guard let button = statusItem.button else { return }
        pillView.rootView = PillView(session: store.latestSession, unreadCount: store.unreadCount, now: .now)
        if pillView.superview !== button {
            pillView.frame = button.bounds
            pillView.autoresizingMask = [.width, .height]
            button.addSubview(pillView)
        }
        // The button snaps to whole points, so round up: any shortfall truncates the pill's text.
        statusItem.length = max(1, pillView.fittingSize.width.rounded(.up))
        button.toolTip = store.latestSession?.projectPath
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

/// Draws the pill inside the status item button while letting clicks reach the button.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
