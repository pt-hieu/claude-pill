import Foundation
import Observation

enum SessionStatus {
    case working, finished, needsInput, ended

    init?(hookEventName: String) {
        switch hookEventName {
        case "UserPromptSubmit": self = .working
        case "Stop": self = .finished
        case "Notification": self = .needsInput
        case "SessionEnd": self = .ended
        default: return nil
        }
    }

    var isActive: Bool { self == .working || self == .needsInput }
}

struct Session: Identifiable {
    let id: String
    let projectPath: String
    /// The title Claude Code shows for the session, set with /rename or generated from the conversation.
    let title: String?
    let status: SessionStatus
    let message: String?
    /// The device of the terminal running the session, e.g. /dev/ttys003.
    let terminalDevice: String?
    let updatedAt: Date

    var projectName: String {
        projectPath.isEmpty ? "unknown" : URL(fileURLWithPath: projectPath).lastPathComponent
    }

    /// The title, or the project name until the session has one.
    var displayName: String { title ?? projectName }
}

private struct HookEvent: Codable {
    let sessionId: String
    let cwd: String?
    let hookEventName: String
    let message: String?
    let title: String?
    let tty: String?
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case message
        case title
        case tty
        case timestamp = "ts"
    }
}

/// Reads the append-only event log written by hooks/log-event.sh and folds it into one entry per session.
@MainActor
@Observable
final class EventStore {
    private(set) var sessions: [Session] = []
    private var readTimestamps: [String: Double]

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    private static let retention: TimeInterval = 7 * 24 * 60 * 60
    private static let readTimestampsKey = "readTimestamps"

    let logURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudePill/events.jsonl")

    init() {
        readTimestamps = UserDefaults.standard.dictionary(forKey: Self.readTimestampsKey) as? [String: Double] ?? [:]
        ensureLogExists()
        rewriteLog { $0.timestamp > Date().timeIntervalSince1970 - Self.retention }
        reload()
        startWatching()
    }

    var latestSession: Session? { sessions.first }

    var unreadCount: Int { sessions.filter(isUnread).count }

    func isUnread(_ session: Session) -> Bool {
        session.updatedAt.timeIntervalSince1970 > readTimestamps[session.id, default: 0]
    }

    func markAllRead() {
        for session in sessions {
            readTimestamps[session.id] = session.updatedAt.timeIntervalSince1970
        }
        UserDefaults.standard.set(readTimestamps, forKey: Self.readTimestampsKey)
        onChange?()
    }

    func clearInactive() {
        let activeSessionIds = Set(sessions.filter { $0.status.isActive }.map(\.id))
        rewriteLog { activeSessionIds.contains($0.sessionId) }
        reload()
    }

    private func reload() {
        var latestEventBySession: [String: HookEvent] = [:]
        // Events logged before the title exists carry none, so keep the latest title from any event.
        var latestTitleBySession: [String: (title: String, timestamp: Double)] = [:]
        for event in readEvents() where SessionStatus(hookEventName: event.hookEventName) != nil {
            if let title = event.title, event.timestamp >= latestTitleBySession[event.sessionId]?.timestamp ?? 0 {
                latestTitleBySession[event.sessionId] = (title, event.timestamp)
            }
            if let existing = latestEventBySession[event.sessionId], existing.timestamp > event.timestamp { continue }
            latestEventBySession[event.sessionId] = event
        }
        sessions = latestEventBySession.values
            .map { event in
                Session(
                    id: event.sessionId,
                    projectPath: event.cwd ?? "",
                    title: latestTitleBySession[event.sessionId]?.title,
                    status: SessionStatus(hookEventName: event.hookEventName)!,
                    message: event.message,
                    terminalDevice: event.tty,
                    updatedAt: Date(timeIntervalSince1970: event.timestamp)
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        onChange?()
    }

    private func readEvents() -> [HookEvent] {
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return contents.split(separator: "\n").compactMap { line in
            try? decoder.decode(HookEvent.self, from: Data(line.utf8))
        }
    }

    /// Rewrites in place (not atomically) so the file keeps its inode and the watcher stays attached.
    private func rewriteLog(keeping shouldKeep: (HookEvent) -> Bool) {
        let encoder = JSONEncoder()
        let lines = readEvents().filter(shouldKeep).compactMap { event in
            (try? encoder.encode(event)).flatMap { String(data: $0, encoding: .utf8) }
        }
        let contents = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? contents.write(to: logURL, atomically: false, encoding: .utf8)
    }

    private func ensureLogExists() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    private func startWatching() {
        let descriptor = open(logURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let watcher = self.watcher else { return }
                if !watcher.data.isDisjoint(with: [.delete, .rename]) {
                    // The log was replaced or removed; follow the new file at the same path.
                    watcher.cancel()
                    self.ensureLogExists()
                    self.startWatching()
                }
                self.reload()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
}
