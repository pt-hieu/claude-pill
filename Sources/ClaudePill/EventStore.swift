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

/// What the menu bar pill shows, summarizing every session.
enum PillStatus {
    case noSessions
    case latest(SessionStatus)
    /// Some session is still working and another finished since the panel was last seen.
    case workingWithUnseenFinish
}

/// A workflow or subagent that a session is running.
struct AgentTask: Identifiable {
    enum Kind { case workflow, subagent }

    let id: String
    let kind: Kind
    let label: String
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
    let runningTasks: [AgentTask]

    var projectName: String {
        projectPath.isEmpty ? "unknown" : URL(fileURLWithPath: projectPath).lastPathComponent
    }

    /// The title, or the project name until the session has one.
    var displayName: String { title ?? projectName }
}

/// An entry of the `background_tasks` list that Claude Code sends with Stop and SubagentStop:
/// a workflow or background subagent still running when the event fired.
private struct BackgroundTask: Codable {
    let id: String
    let type: String
    let description: String?
    let name: String?

    var isWorkflow: Bool { type == "workflow" }
}

private struct HookEvent: Codable {
    let sessionId: String
    let cwd: String?
    let hookEventName: String
    let notificationType: String?
    let message: String?
    let agentId: String?
    let agentType: String?
    let backgroundTasks: [BackgroundTask]?
    let title: String?
    let tty: String?
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case message
        case agentId = "agent_id"
        case agentType = "agent_type"
        case backgroundTasks = "background_tasks"
        case title
        case tty
        case timestamp = "ts"
    }

    /// Nil for events that do not change a session's status. Claude Code sends an idle reminder
    /// about a minute after every finished turn, which is not a request for input.
    var status: SessionStatus? {
        notificationType == "idle_prompt" ? nil : SessionStatus(hookEventName: hookEventName)
    }
}

/// Reads the append-only event log written by hooks/log-event.sh and folds it into one entry per session.
@MainActor
@Observable
final class EventStore {
    private(set) var sessions: [Session] = []
    private var panelSeenAt: Date

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    private static let retention: TimeInterval = 7 * 24 * 60 * 60
    private static let panelSeenAtKey = "panelSeenAt"

    static let defaultLogURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudePill/events.jsonl")

    let logURL: URL

    init(logURL: URL = defaultLogURL) {
        self.logURL = logURL
        panelSeenAt = UserDefaults.standard.object(forKey: Self.panelSeenAtKey) as? Date ?? .distantPast
        ensureLogExists()
        rewriteLog { $0.timestamp > Date().timeIntervalSince1970 - Self.retention }
        reload()
        startWatching()
    }

    var latestSession: Session? { sessions.first }

    /// A session needing input wins, since it is blocked on the user. Otherwise any working session
    /// keeps the pill on working, and the latest session decides once none is.
    var pillStatus: PillStatus {
        if sessions.contains(where: { $0.status == .needsInput }) { return .latest(.needsInput) }
        if sessions.contains(where: { $0.status == .working }) {
            let hasUnseenFinish = sessions.contains { $0.status == .finished && $0.updatedAt > panelSeenAt }
            return hasUnseenFinish ? .workingWithUnseenFinish : .latest(.working)
        }
        return latestSession.map { .latest($0.status) } ?? .noSessions
    }

    func markPanelSeen() {
        panelSeenAt = .now
        UserDefaults.standard.set(panelSeenAt, forKey: Self.panelSeenAtKey)
        onChange?()
    }

    func clearInactive() {
        let activeSessionIds = Set(sessions.filter { $0.status.isActive }.map(\.id))
        rewriteLog { activeSessionIds.contains($0.sessionId) }
        reload()
    }

    private func reload() {
        // Ended sessions clear themselves: drop their events before folding the log.
        let endedSessionIds = Set(readEvents().filter { $0.hookEventName == "SessionEnd" }.map(\.sessionId))
        if !endedSessionIds.isEmpty {
            rewriteLog { !endedSessionIds.contains($0.sessionId) }
        }
        let events = readEvents()
        var latestEventBySession: [String: HookEvent] = [:]
        // Events logged before the title exists carry none, so keep the latest title from any event.
        var latestTitleBySession: [String: (title: String, timestamp: Double)] = [:]
        for event in events where event.status != nil {
            if let title = event.title, event.timestamp >= latestTitleBySession[event.sessionId]?.timestamp ?? 0 {
                latestTitleBySession[event.sessionId] = (title, event.timestamp)
            }
            if let existing = latestEventBySession[event.sessionId], existing.timestamp > event.timestamp { continue }
            latestEventBySession[event.sessionId] = event
        }
        let eventsBySession = Dictionary(grouping: events, by: \.sessionId)
        sessions = latestEventBySession.values
            .map { event in
                let runningTasks = Self.runningTasks(
                    from: (eventsBySession[event.sessionId] ?? []).sorted { $0.timestamp < $1.timestamp })
                // Claude Code fires Stop while workflows and background subagents keep running.
                let status = event.status == .finished && !runningTasks.isEmpty ? .working : event.status!
                return Session(
                    id: event.sessionId,
                    projectPath: event.cwd ?? "",
                    title: latestTitleBySession[event.sessionId]?.title,
                    status: status,
                    message: event.message,
                    terminalDevice: event.tty,
                    updatedAt: Date(timeIntervalSince1970: event.timestamp),
                    runningTasks: runningTasks
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        onChange?()
    }

    private static let workflowAgentType = "workflow-subagent"

    /// Folds a session's events, oldest first, into the workflows and subagents it is still running.
    /// Subagents open and close with SubagentStart and SubagentStop. Workflows are known only from the
    /// `background_tasks` snapshots; their agents stand in for them until the first snapshot arrives.
    private static func runningTasks(from events: [HookEvent]) -> [AgentTask] {
        var openAgents: [(id: String, agentType: String)] = []
        var workflows: [BackgroundTask] = []
        var subagentDescriptions: [String: String] = [:]
        for event in events {
            let snapshot = event.backgroundTasks
            for task in snapshot ?? [] where !task.isWorkflow {
                subagentDescriptions[task.id] = task.description
            }
            switch event.hookEventName {
            case "SubagentStart":
                if let agentId = event.agentId, !openAgents.contains(where: { $0.id == agentId }) {
                    openAgents.append((agentId, event.agentType ?? ""))
                }
            case "SubagentStop":
                openAgents.removeAll { $0.id == event.agentId }
                if let snapshot { workflows = snapshot.filter(\.isWorkflow) }
            case "Stop":
                guard let snapshot else { break }
                workflows = snapshot.filter(\.isWorkflow)
                // The turn is over, so only agents running in the background can still be open.
                let backgroundAgentIds = Set(snapshot.filter { !$0.isWorkflow }.map(\.id))
                openAgents.removeAll { agent in
                    agent.agentType == workflowAgentType ? workflows.isEmpty : !backgroundAgentIds.contains(agent.id)
                }
            default:
                break
            }
        }
        let workflowTasks = workflows.map { workflow in
            AgentTask(id: workflow.id, kind: .workflow, label: workflow.description ?? workflow.name ?? "Workflow")
        }
        let unlistedWorkflowTasks =
            workflows.isEmpty && openAgents.contains(where: { $0.agentType == workflowAgentType })
            ? [AgentTask(id: workflowAgentType, kind: .workflow, label: "Workflow")] : []
        let subagentTasks = openAgents.filter { $0.agentType != workflowAgentType }.map { agent in
            AgentTask(
                id: agent.id, kind: .subagent,
                label: subagentDescriptions[agent.id] ?? (agent.agentType.isEmpty ? "Subagent" : agent.agentType))
        }
        return workflowTasks + unlistedWorkflowTasks + subagentTasks
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
