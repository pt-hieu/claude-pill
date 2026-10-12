import Foundation
import Testing

@testable import ClaudePill

@MainActor
struct EventStoreTests {
    /// A store reading a fresh log holding the given lines, timestamped in order.
    private func store(with events: [String]) throws -> EventStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        let lines = events.enumerated().map { index, fields in
            #"{"session_id":"session","cwd":"/project",\#(fields),"ts":\#(now + Double(index))}"#
        }
        let logURL = directory.appendingPathComponent("events.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        return EventStore(logURL: logURL)
    }

    private func onlySession(of store: EventStore) throws -> Session {
        try #require(store.sessions.count == 1)
        return store.sessions[0]
    }

    @Test func staysWorkingAfterStopWhileAWorkflowRuns() throws {
        let session = try onlySession(of: store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"SubagentStart","agent_id":"w1","agent_type":"workflow-subagent""#,
            #""hook_event_name":"Stop","background_tasks":[{"id":"wf","type":"workflow","status":"running","description":"Review changed files","name":"review-changes"}]"#,
        ]))

        #expect(session.status == .working)
        #expect(session.runningTasks.map(\.label) == ["Review changed files"])
        #expect(session.runningTasks.map(\.kind) == [.workflow])
    }

    @Test func keepsBackgroundSubagentsListedAtStopAndDropsTheRest() throws {
        let session = try onlySession(of: store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"SubagentStart","agent_id":"background","agent_type":"general-purpose""#,
            #""hook_event_name":"SubagentStart","agent_id":"foreground","agent_type":"Explore""#,
            #""hook_event_name":"Stop","background_tasks":[{"id":"background","type":"subagent","status":"running","description":"Sleep then reply ok","agent_type":"general-purpose"}]"#,
        ]))

        #expect(session.status == .working)
        #expect(session.runningTasks.map(\.label) == ["Sleep then reply ok"])
        #expect(session.runningTasks.map(\.kind) == [.subagent])
    }

    @Test func finishesOnceTheLastBackgroundTaskEnds() throws {
        let session = try onlySession(of: store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"SubagentStart","agent_id":"background","agent_type":"general-purpose""#,
            #""hook_event_name":"Stop","background_tasks":[{"id":"background","type":"subagent","status":"running","description":"Sleep then reply ok"}]"#,
            #""hook_event_name":"SubagentStop","agent_id":"background","agent_type":"general-purpose","background_tasks":[{"id":"background","type":"subagent","status":"running","description":"Sleep then reply ok"}]"#,
            #""hook_event_name":"Stop","background_tasks":[]"#,
        ]))

        #expect(session.status == .finished)
        #expect(session.runningTasks.isEmpty)
    }

    @Test func listsRunningForegroundSubagentsByType() throws {
        let session = try onlySession(of: store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"SubagentStart","agent_id":"done","agent_type":"Plan""#,
            #""hook_event_name":"SubagentStop","agent_id":"done","agent_type":"Plan""#,
            #""hook_event_name":"SubagentStart","agent_id":"running","agent_type":"Explore""#,
        ]))

        #expect(session.status == .working)
        #expect(session.runningTasks.map(\.label) == ["Explore"])
    }

    @Test func showsAWorkflowBeforeItIsFirstListed() throws {
        let session = try onlySession(of: store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"SubagentStart","agent_id":"w1","agent_type":"workflow-subagent""#,
            #""hook_event_name":"SubagentStart","agent_id":"w2","agent_type":"workflow-subagent""#,
        ]))

        #expect(session.runningTasks.map(\.label) == ["Workflow"])
        #expect(session.runningTasks.map(\.kind) == [.workflow])
    }

    @Test func keepsSubagentFieldsWhenTheLogIsRewritten() throws {
        let original = try store(with: [
            #""hook_event_name":"UserPromptSubmit""#,
            #""hook_event_name":"Stop","background_tasks":[{"id":"wf","type":"workflow","status":"running","description":"Review changed files"}]"#,
        ])
        // Clearing inactive sessions rewrites the log; the working session must keep its tasks.
        original.clearInactive()
        let reopened = EventStore(logURL: original.logURL)

        let session = try onlySession(of: reopened)
        #expect(session.status == .working)
        #expect(session.runningTasks.map(\.label) == ["Review changed files"])
    }
}
