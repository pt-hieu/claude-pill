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

/// The menu bar pill: a rounded rectangle filled with the primary color, which follows the menu bar's
/// appearance (white on dark, black on light), with its content cut out. It stretches to the width it is given.
struct PillView: View {
    let session: Session?
    let unreadCount: Int
    let now: Date

    // Each part has a fixed width, so the pill keeps its size and layout as the content updates.
    private static let symbolWidth: CGFloat = 14
    private static let titleWidth: CGFloat = 110
    private static let timeWidth: CGFloat = 26

    var body: some View {
        let isUnread = unreadCount > 0
        HStack(spacing: 6) {
            Image(systemName: session?.status.symbolName ?? "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.symbolWidth)
            Text(session?.displayName ?? "Claude")
                .truncationMode(.tail)
                .frame(width: Self.titleWidth, alignment: .leading)
            Text(time)
                .monospacedDigit()
                .frame(width: Self.timeWidth, alignment: .trailing)
            if unreadCount > 1 {
                Text("+\(unreadCount - 1)")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .font(.system(size: 12, weight: isUnread ? .semibold : .regular))
        .lineLimit(1)
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

    /// Blank while working: the time since the last update is only worth showing once Claude stops.
    private var time: String {
        guard let session, session.status != .working else { return "" }
        return shortRelativeTime(from: session.updatedAt, to: now)
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
