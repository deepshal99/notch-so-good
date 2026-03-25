import Foundation
import Network

/// Local TCP server that receives permission requests from Claude Code's PreToolUse hook.
/// Safe tools (Read, Grep, etc.) are auto-approved instantly.
/// Dangerous tools (Bash, Edit, Write) block until the user clicks Approve/Deny in the notch.
class PermissionServer {
    static let shared = PermissionServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.notchsogood.permission-server")
    private let port: UInt16 = 27182

    struct PendingRequest {
        let id: String
        let toolName: String
        let toolInput: String
        let sessionId: String?
        let connection: NWConnection
    }

    private var pendingRequests: [String: PendingRequest] = [:]
    private let lock = NSLock()

    // Read-only tools that never need user approval
    static let safeTools: Set<String> = [
        "Read", "Glob", "Grep", "LSP", "Agent", "ToolSearch",
        "EnterPlanMode", "ExitPlanMode", "EnterWorktree", "ExitWorktree",
        "TaskGet", "TaskList", "TaskOutput", "CronList",
        "ListMcpResourcesTool", "ReadMcpResourceTool",
        "Skill",
    ]

    func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    try? String(self.port).write(
                        toFile: "/tmp/notchsogood.port",
                        atomically: true,
                        encoding: .utf8
                    )
                case .failed(let error):
                    print("PermissionServer failed: \(error)")
                    // Try to restart after a brief delay
                    self.listener = nil
                    self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.start()
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("PermissionServer: Failed to start on port \(port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: "/tmp/notchsogood.port")
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        // Read the full HTTP request in one chunk (requests are tiny, <2KB)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil,
                  let raw = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Extract body from HTTP POST
            guard let bodyRange = raw.range(of: "\r\n\r\n") else {
                // Might be a health check or incomplete request
                self.sendHTTPResponse(connection: connection, body: "{}")
                return
            }

            let body = String(raw[bodyRange.upperBound...])
            self.processRequest(body: body, connection: connection)
        }
    }

    private func processRequest(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendHTTPResponse(connection: connection, body: "{}")
            return
        }

        let toolName = json["tool_name"] as? String ?? "Unknown"
        let toolInput = json["tool_input"] as? String ?? ""
        let sessionId = json["session_id"] as? String

        // Auto-approve safe tools instantly (< 1ms round trip)
        if Self.safeTools.contains(toolName) {
            sendHTTPResponse(connection: connection, body: "{\"decision\":\"approve\"}")
            return
        }

        // Dangerous tool — need user approval
        let requestId = UUID().uuidString
        let request = PendingRequest(
            id: requestId,
            toolName: toolName,
            toolInput: toolInput,
            sessionId: sessionId,
            connection: connection
        )

        lock.lock()
        pendingRequests[requestId] = request
        lock.unlock()

        // Show approval UI on main thread
        DispatchQueue.main.async {
            NotificationManager.shared.showPermissionRequest(
                requestId: requestId,
                toolName: toolName,
                toolInput: toolInput,
                sessionId: sessionId
            )
        }

        // Timeout after 2 minutes — send empty response so hook outputs nothing
        // (Claude Code falls back to its normal terminal permission flow)
        queue.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.timeoutRequest(requestId: requestId)
        }
    }

    // MARK: - User response

    func respond(requestId: String, approve: Bool) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        let decision = approve ? "approve" : "deny"
        var json: [String: String] = ["decision": decision]
        if !approve {
            json["reason"] = "Denied from Notch So Good"
        }

        if let bodyData = try? JSONSerialization.data(withJSONObject: json),
           let body = String(data: bodyData, encoding: .utf8) {
            queue.async {
                self.sendHTTPResponse(connection: request.connection, body: body)
            }
        }
    }

    private func timeoutRequest(requestId: String) {
        lock.lock()
        guard let request = pendingRequests.removeValue(forKey: requestId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Empty body → hook outputs nothing → Claude Code uses normal terminal flow
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        request.connection.send(
            content: response.data(using: .utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in request.connection.cancel() }
        )

        DispatchQueue.main.async {
            NotificationManager.shared.windowController.dismiss()
        }
    }

    // MARK: - HTTP response

    private func sendHTTPResponse(connection: NWConnection, body: String) {
        let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
            content: http.data(using: .utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }
}
