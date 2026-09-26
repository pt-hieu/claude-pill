import SwiftUI

extension SessionStatus {
    var symbolName: String {
        switch self {
        case .working: "hourglass"
        case .finished: "checkmark.circle"
        case .needsInput: "hand.raised"
        case .ended: "stop.circle"
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

func shortRelativeTime(from date: Date, to now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86400: return "\(Int(seconds / 3600))h"
    default: return "\(Int(seconds / 86400))d"
    }
}

/// The menu bar pill. It stretches to the width it is given and uses the primary color,
/// which follows the menu bar's appearance (white on dark, black on light).
struct PillView: View {
    let session: Session?
    let unreadCount: Int
    let now: Date

    private static let maximumProjectNameLength = 18

    var body: some View {
        let isUnread = unreadCount > 0
        HStack(spacing: 6) {
            Image(systemName: session?.status.symbolName ?? "sparkle")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: isUnread ? .semibold : .regular))
            if unreadCount > 1 {
                Text("+\(unreadCount - 1)")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        // Matches the height of the system's status item highlight, so the pressed state fills the pill.
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .overlay(Capsule().strokeBorder(lineWidth: isUnread ? 1.5 : 1))
        .foregroundStyle(Color.primary.opacity(isUnread ? 1 : 0.6))
        .frame(maxHeight: .infinity)
    }

    private var text: String {
        guard let session else { return "Claude" }
        var projectName = session.projectName
        if projectName.count > Self.maximumProjectNameLength {
            projectName = projectName.prefix(Self.maximumProjectNameLength - 1) + "…"
        }
        if session.status == .working { return projectName }
        return "\(projectName)  ·  \(shortRelativeTime(from: session.updatedAt, to: now))"
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
            Image(systemName: session.status.symbolName)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.projectName).fontWeight(.semibold)
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
