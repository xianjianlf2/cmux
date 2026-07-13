import Foundation

/// A sanitized CLI snapshot of one agent process generation.
struct AgentSessionGraphNode: Codable, Sendable, Equatable {
    var provider: String
    var sessionId: String
    var runId: String
    var pid: Int?
    var processStartedAt: TimeInterval?
    var workspaceId: String
    var surfaceId: String
    var state: String
    var restoreAuthority: Bool
    var startedAt: TimeInterval
    var updatedAt: TimeInterval
    var endedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case provider
        case sessionId = "session_id"
        case runId = "run_id"
        case pid
        case processStartedAt = "process_started_at"
        case workspaceId = "workspace_id"
        case surfaceId = "surface_id"
        case state
        case restoreAuthority = "restore_authority"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
    }
}
