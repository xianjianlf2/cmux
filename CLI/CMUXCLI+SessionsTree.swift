import Foundation

extension CMUXCLI {
    func runSessionsTreeCommand(
        commandArgs: [String],
        jsonOutput: Bool,
        processEnv: [String: String],
        fileManager: FileManager
    ) throws {
        let (agentFilter, remainder0) = parseOption(commandArgs, name: "--agent")
        let (sessionFilter, remainder1) = parseOption(remainder0, name: "--session")
        let (workspaceFilter, remainder2) = parseOption(remainder1, name: "--workspace")
        let (surfaceFilter, remainder3) = parseOption(remainder2, name: "--surface")
        let (stateDirOverride, remainder4) = parseOption(remainder3, name: "--state-dir")
        let (relationshipFilter, remainder5) = parseOption(remainder4, name: "--relation")
        let (depthRaw, remainder6) = parseOption(remainder5, name: "--depth")

        var localJSONOutput = jsonOutput
        var includeAll = false
        for argument in remainder6 {
            switch argument {
            case "--json": localJSONOutput = true
            case "--all", "--history": includeAll = true
            case "--live", "--processes": break
            default:
                throw CLIError(message: "sessions tree: unexpected argument '\(argument)'")
            }
        }
        let maximumDepth: Int
        if let depthRaw {
            guard let parsed = Int(depthRaw), parsed > 0 else {
                throw CLIError(message: "sessions tree: --depth must be a positive integer")
            }
            maximumDepth = parsed
        } else {
            maximumDepth = 64
        }

        let stateDirectory = sessionsTreeExpandedPath(
            stateDirOverride
                ?? processEnv["CMUX_AGENT_HOOK_STATE_DIR"]
                ?? URL(fileURLWithPath: processEnv["HOME"] ?? NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent(".cmuxterm", isDirectory: true)
                    .path
        )
        let normalizedAgent = sessionsTreeNormalized(agentFilter)?.lowercased()
        let normalizedSession = sessionsTreeNormalized(sessionFilter)?.lowercased()
        let normalizedWorkspace = sessionsTreeNormalizedID(workspaceFilter)?.lowercased()
        let normalizedSurface = sessionsTreeNormalizedID(surfaceFilter)?.lowercased()
        let normalizedRelationship = sessionsTreeNormalized(relationshipFilter)?.lowercased()
        if let normalizedRelationship,
           normalizedRelationship != "all",
           AgentSessionRelationship(rawValue: normalizedRelationship) == nil {
            throw CLIError(message: "sessions tree: unknown relationship '\(normalizedRelationship)'")
        }

        let specifications = [(name: "claude", suffix: "claude")] + Self.agentDefs.map {
            (name: $0.name, suffix: $0.sessionStoreSuffix)
        }
        var nodes: [AgentSessionGraphNode] = []
        var edges: [AgentSessionGraphEdge] = []
        let decoder = JSONDecoder()

        for specification in specifications {
            if let normalizedAgent, specification.name.lowercased() != normalizedAgent { continue }
            let url = URL(fileURLWithPath: stateDirectory, isDirectory: true)
                .appendingPathComponent("\(specification.suffix)-hook-sessions.json", isDirectory: false)
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let store = try? decoder.decode(ClaudeHookSessionStoreFile.self, from: data) else {
                continue
            }
            let activeSessionIds = Set(store.activeSessionsBySurface.values.map(\.sessionId))
                .union(store.activeSessionsByWorkspace.values.map(\.sessionId))
            for record in store.sessions.values {
                if let normalizedSession, record.sessionId.lowercased() != normalizedSession { continue }
                if let normalizedWorkspace, record.workspaceId.lowercased() != normalizedWorkspace { continue }
                if let normalizedSurface, record.surfaceId.lowercased() != normalizedSurface { continue }
                if !includeAll,
                   !activeSessionIds.contains(record.sessionId),
                   record.isRestorable != true,
                   record.transcriptPath == nil,
                   record.launchCommand == nil {
                    continue
                }

                let runs = sessionsTreeRuns(record: record, provider: specification.name)
                for run in runs {
                    let node = AgentSessionGraphNode(
                        provider: specification.name,
                        sessionId: record.sessionId,
                        runId: run.runId,
                        pid: run.pid,
                        processStartedAt: run.processStartedAt,
                        workspaceId: record.workspaceId,
                        surfaceId: record.surfaceId,
                        state: sessionsTreeState(record: record, run: run, activeSessionIds: activeSessionIds),
                        restoreAuthority: run.restoreAuthority,
                        startedAt: run.startedAt,
                        updatedAt: run.updatedAt,
                        endedAt: run.endedAt
                    )
                    nodes.append(node)
                    if let relationship = run.relationship,
                       normalizedRelationship == nil || normalizedRelationship == "all" || relationship.rawValue == normalizedRelationship {
                        edges.append(AgentSessionGraphEdge(
                            fromRunId: run.parentRunId,
                            fromSessionId: run.parentSessionId,
                            toRunId: run.runId,
                            relationship: relationship
                        ))
                    }
                }
            }
        }

        nodes.sort { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.runId < rhs.runId
        }
        edges.sort { lhs, rhs in
            if lhs.toRunId != rhs.toRunId { return lhs.toRunId < rhs.toRunId }
            return lhs.relationship.rawValue < rhs.relationship.rawValue
        }
        let snapshot = AgentSessionGraphSnapshot(nodes: nodes, edges: edges)
        if localJSONOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        } else {
            print(sessionsTreeText(snapshot: snapshot, maximumDepth: maximumDepth))
        }
    }

    private func sessionsTreeRuns(
        record: ClaudeHookSessionRecord,
        provider: String
    ) -> [AgentSessionRunRecord] {
        if let runs = record.runs, !runs.isEmpty { return runs }
        return [AgentSessionRunRecord(
            runId: record.runId ?? "session:\(provider):\(record.sessionId)",
            pid: record.pid,
            processStartedAt: nil,
            parentRunId: record.parentRunId,
            parentSessionId: record.parentSessionId,
            relationship: record.relationship,
            restoreAuthority: record.restoreAuthority ?? record.relationship != .spawned,
            startedAt: record.startedAt,
            updatedAt: record.updatedAt
        )]
    }

    private func sessionsTreeState(
        record: ClaudeHookSessionRecord,
        run: AgentSessionRunRecord,
        activeSessionIds: Set<String>
    ) -> String {
        if run.endedAt != nil { return "ended" }
        if activeSessionIds.contains(record.sessionId) { return "active" }
        switch record.runtimeStatus {
        case .running?: return "working"
        case .needsInput?: return "needs_input"
        case .error?: return "error"
        case .idle?, nil: return "idle"
        }
    }

    private func sessionsTreeText(snapshot: AgentSessionGraphSnapshot, maximumDepth: Int) -> String {
        guard !snapshot.nodes.isEmpty else { return "No saved agent session runs matched." }
        let nodeByRunId = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.runId, $0) })
        let childrenByRunId = Dictionary(grouping: snapshot.edges.compactMap { edge -> (String, AgentSessionGraphEdge)? in
            guard let parent = edge.fromRunId, nodeByRunId[parent] != nil else { return nil }
            return (parent, edge)
        }, by: \.0).mapValues { $0.map(\.1) }
        let childRunIds = Set(snapshot.edges.compactMap { edge in
            edge.fromRunId.flatMap { nodeByRunId[$0] == nil ? nil : edge.toRunId }
        })
        let roots = snapshot.nodes.filter { !childRunIds.contains($0.runId) }
        var lines: [String] = []
        var visited: Set<String> = []

        func append(_ node: AgentSessionGraphNode, prefix: String, depth: Int) {
            guard depth <= maximumDepth, visited.insert(node.runId).inserted else { return }
            let authority = node.restoreAuthority ? " restore-owner" : " child"
            lines.append("\(prefix)\(node.provider) \(node.sessionId) \(node.state.uppercased())\(authority) \(node.surfaceId)")
            let children = (childrenByRunId[node.runId] ?? []).compactMap { nodeByRunId[$0.toRunId] }
            for (index, child) in children.enumerated() {
                append(child, prefix: prefix + (index == children.count - 1 ? "└── " : "├── "), depth: depth + 1)
            }
        }
        for root in roots { append(root, prefix: "", depth: 0) }
        for node in snapshot.nodes where !visited.contains(node.runId) { append(node, prefix: "", depth: 0) }
        return lines.joined(separator: "\n")
    }

    private func sessionsTreeExpandedPath(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private func sessionsTreeNormalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func sessionsTreeNormalizedID(_ value: String?) -> String? {
        guard let value = sessionsTreeNormalized(value) else { return nil }
        return value.split(separator: ":", maxSplits: 1).last.map(String.init)
    }
}
