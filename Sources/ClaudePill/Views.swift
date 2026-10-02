import SwiftUI

extension SessionStatus {
    var iconName: String {
        switch self {
        case .working: "clock"
        case .finished: "circle-check"
        case .needsInput: "hand"
        case .ended: "circle-stop"
        }
    }

    var label: String {
        switch self {
        case .working: "Working"
        case .finished: "Done"
        case .needsInput: "Needs you"
        case .ended: "Ended"
        }
    }
}

/// A Lucide icon (lucide.dev), bundled as SVG by build.sh. Drawn as a template, so it takes the foreground style.
struct LucideIcon: View {
    let name: String
    let size: CGFloat

    @MainActor private static var images: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.image(named: name))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
    }

    @MainActor private static func image(named name: String) -> NSImage {
        if let image = images[name] { return image }
        let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        image.isTemplate = true
        images[name] = image
        return image
    }
}

extension PillStatus {
    var iconName: String {
        switch self {
        case .noSessions: "sparkle"
        case .latest(let status): status.iconName
        case .workingWithUnseenFinish: "clock-check"
        }
    }
}

func shortRelativeTime(from date: Date, to now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86400: return "\(Int(seconds / 3600))h"
    default: return "\(Int(seconds / 86400))d"
    }
}

/// The menu bar pill: a rounded rectangle filled with the primary color, which follows the menu bar's
/// appearance (white on dark, black on light), with the status icon cut out.
struct PillView: View {
    let status: PillStatus

    var body: some View {
        LucideIcon(name: status.iconName, size: 14)
            .padding(.horizontal, 6)
            // The content is cut out of a filled rounded rectangle, matching the filled system icons in the menu bar.
            .blendMode(.destinationOut)
            // Sized to the neighboring menu bar icons, so the system's taller click highlight surrounds the pill.
            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .compositingGroup()
            .foregroundStyle(Color.primary)
            .frame(maxHeight: .infinity)
    }
}

struct SessionListView: View {
    let store: EventStore
    let onSelect: (Session) -> Void
    let onQuit: () -> Void

    @State private var rowsHeight: CGFloat = 0
    private static let maximumListHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions")
                .font(.headline)
                .padding(12)

            Divider()

            if store.sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.sessions) { session in
                                if session.id != store.sessions.first?.id {
                                    Divider().padding(.leading, 38)
                                }
                                SessionRow(session: session, now: context.date) { onSelect(session) }
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    // A ScrollView fills whatever height it is offered, so size it to its rows explicitly.
                    .frame(height: min(rowsHeight, Self.maximumListHeight))
                }
            }

            Divider()

            HStack {
                IconButton(title: "Clear inactive", symbolName: "trash") { store.clearInactive() }
                    .disabled(!store.sessions.contains { !$0.status.isActive })
                Spacer()
                IconButton(title: "Quit ClaudePill", symbolName: "power", action: onQuit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

private struct IconButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(name: session.status.iconName, size: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayName).fontWeight(.semibold)
                    Spacer()
                    Text("\(session.status.label) · \(shortRelativeTime(from: session.updatedAt, to: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(session.projectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.head)
                if session.status == .needsInput, let message = session.message {
                    Text(message).font(.caption)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .help("Open in Ghostty")
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.projectPath)])
            }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.projectPath, forType: .string)
            }
        }
    }
}
