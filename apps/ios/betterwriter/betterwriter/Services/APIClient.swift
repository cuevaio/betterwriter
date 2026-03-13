import Foundation

/// HTTP client for communicating with the Better Writer backend.
/// Authenticates with a server-signed JWT obtained by exchanging the device UUID.
actor APIClient {
    static let shared = APIClient()

    #if DEBUG
    private let baseURL = "http://localhost:3000"
    #else
    private let baseURL = "https://betterwriter.app"
    #endif

    private let deviceId: UUID
    private let session: URLSession

    /// The current JWT token. Loaded from Keychain on init, refreshed via authenticate().
    private var authToken: String?

    private func logStream(_ message: String) {
        #if DEBUG
        print("APIClient[stream]: \(message)")
        #endif
    }

    private init() {
        self.deviceId = KeychainService.getOrCreateDeviceId()
        self.authToken = KeychainService.getAuthToken()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    struct AuthResponse: Codable {
        let token: String
        let expiresAt: String
        let user: UserResponse
    }

    /// Exchange the device UUID for a signed JWT from the server.
    /// Stores the token in Keychain for persistence across app launches.
    @discardableResult
    func authenticate(installDate: Date? = nil) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/api/auth")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["deviceId": deviceId.uuidString]
        if let installDate {
            body["installDate"] = ISO8601DateFormatter().string(from: installDate)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)

        // Persist the token
        self.authToken = authResponse.token
        KeychainService.saveAuthToken(authResponse.token)

        return authResponse
    }

    /// Ensure we have a valid token. If not, authenticate.
    private func ensureAuthenticated() async throws {
        if authToken == nil {
            try await authenticate()
        }
    }

    /// The current Authorization header value, or nil if not yet authenticated.
    private var authorizationHeader: String? {
        guard let token = authToken else { return nil }
        return "Bearer \(token)"
    }

    // MARK: - User

    struct UserResponse: Codable {
        let id: String
        let createdAt: String
        let installDate: String
        let currentStreak: Int?
        let longestStreak: Int?
        let totalWordsWritten: Int?
        let onboardingDay0Done: Bool?
        let onboardingDay1Done: Bool?
    }

    func getUser() async throws -> UserResponse {
        return try await get("/api/users")
    }

    func updateUser(_ fields: [String: Any]) async throws -> UserResponse {
        return try await put("/api/users", body: fields)
    }

    // MARK: - Stream kickoff response

    struct StartStreamResponse: Codable {
        let ok: Bool
        let mode: String
        let streamId: String
    }

    // MARK: - Readings

    struct EntryResponse: Codable {
        let id: String
        let userId: String
        let dayIndex: Int
        let calendarDate: String
        let readingBody: String?
        let readingCompleted: Bool?
        let writingPrompt: String?
        let writingText: String?
        let writingWordCount: Int?
        let writingCompleted: Bool?
        let isBonusReading: Bool?
        let isFreeWrite: Bool?
        let skipped: Bool?
    }

    /// Kick off a reading stream. The server computes the dayIndex.
    /// Returns the server's response which may contain a different `streamId`
    /// if a generation was already running.
    @discardableResult
    func startReadingStream(streamId: String) async throws -> StartStreamResponse {
        let body: [String: Any] = [
            "streamId": streamId,
        ]
        return try await post("/api/readings/generate/stream", body: body)
    }

    func streamReading(streamId: String, lastEventId: String? = nil) -> AsyncThrowingStream<ReadingStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var retries = 0
                var cursor = lastEventId
                var noProgressReconnects = 0

                self.logStream("reading connect requested streamId=\(streamId) lastEventId=\(lastEventId ?? "nil")")

                while retries <= 3 {
                    do {
                        let requestStartCursor = cursor
                        let url = URL(string: "\(baseURL)/api/readings/generate/stream?streamId=\(streamId)")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"
                        try await self.ensureAuthenticated()
                        if let auth = self.authorizationHeader {
                            request.setValue(auth, forHTTPHeaderField: "Authorization")
                        }
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.timeoutInterval = 300
                        if let cursor {
                            request.setValue(cursor, forHTTPHeaderField: "Last-Event-ID")
                        }

                        self.logStream("reading opening SSE streamId=\(streamId) cursor=\(requestStartCursor ?? "nil") retry=\(retries)")

                        let (bytes, response) = try await self.session.bytes(for: request)

                        // Handle 401 by re-authenticating and retrying
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                            self.logStream("reading SSE got 401, re-authenticating")
                            try await self.authenticate()
                            retries += 1
                            continue
                        }

                        try self.validateResponse(response)
                        if let httpResponse = response as? HTTPURLResponse {
                            self.logStream("reading SSE connected streamId=\(streamId) status=\(httpResponse.statusCode)")
                        } else {
                            self.logStream("reading SSE connected streamId=\(streamId)")
                        }

                        var currentEvent = "message"
                        var currentId: String?
                        var dataLines: [String] = []
                        var reachedTerminal = false
                        var receivedFrame = false

                        func emitFrame() {
                            let data = dataLines.joined(separator: "\n")
                            defer {
                                currentEvent = "message"
                                currentId = nil
                                dataLines.removeAll()
                            }
                            guard !data.isEmpty else { return }
                            receivedFrame = true
                            if let currentId {
                                cursor = currentId
                            }

                            switch currentEvent {
                            case "start":
                                self.logStream("reading event=start id=\(currentId ?? "nil")")
                                continuation.yield(.start(eventId: currentId))
                            case "delta":
                                if let text = Self.extractStringValue(fromJSON: data, key: "text") {
                                    self.logStream("reading event=delta id=\(currentId ?? "nil") chars=\(text.count)")
                                    continuation.yield(.delta(text, eventId: currentId))
                                }
                            case "complete":
                                self.logStream("reading event=complete id=\(currentId ?? "nil")")
                                if let payload = Self.extractJSONObjectData(fromJSON: data),
                                   let entry = try? JSONDecoder().decode(EntryResponse.self, from: payload) {
                                    continuation.yield(.complete(entry, eventId: currentId))
                                    reachedTerminal = true
                                } else {
                                    self.logStream("reading complete decode failed id=\(currentId ?? "nil") raw=\(data.prefix(180))")
                                    continuation.yield(.end(status: "completed", eventId: currentId))
                                    reachedTerminal = true
                                }
                            case "end":
                                let status = Self.extractStringValue(fromJSON: data, key: "status") ?? "completed"
                                self.logStream("reading event=end id=\(currentId ?? "nil") status=\(status)")
                                continuation.yield(.end(status: status, eventId: currentId))
                                reachedTerminal = true
                            case "heartbeat":
                                self.logStream("reading event=heartbeat id=\(currentId ?? "nil")")
                                continuation.yield(.heartbeat(eventId: currentId))
                            case "error":
                                let message = Self.extractStringValue(fromJSON: data, key: "message") ?? "Unknown stream error"
                                self.logStream("reading event=error id=\(currentId ?? "nil") message=\(message)")
                                continuation.yield(.error(message, eventId: currentId))
                                reachedTerminal = true
                            default:
                                break
                            }
                        }

                        for try await line in bytes.lines {
                            if line.isEmpty {
                                emitFrame()
                                if reachedTerminal {
                                    self.logStream("reading stream finished streamId=\(streamId) terminal=true")
                                    continuation.finish()
                                    return
                                }
                                continue
                            }

                            // Flush previous frame when a new frame boundary is detected.
                            // URLSession.AsyncBytes.lines may drop empty lines between SSE frames,
                            // so we detect boundaries by seeing id:/event: while data is pending.
                            if (line.hasPrefix("id:") || line.hasPrefix("event:")) && !dataLines.isEmpty {
                                emitFrame()
                                if reachedTerminal {
                                    self.logStream("reading stream finished streamId=\(streamId) terminal=true")
                                    continuation.finish()
                                    return
                                }
                            }

                            if line.hasPrefix("id:") {
                                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            }
                        }

                        emitFrame()
                        if reachedTerminal {
                            self.logStream("reading stream finished streamId=\(streamId) terminal=true")
                            continuation.finish()
                            return
                        }

                        if !receivedFrame && requestStartCursor == cursor {
                            self.logStream("reading stream closed with no progress streamId=\(streamId) cursor=\(cursor ?? "nil")")
                            continuation.finish()
                            return
                        }

                        if requestStartCursor == cursor {
                            noProgressReconnects += 1
                            self.logStream("reading reconnect no progress streamId=\(streamId) count=\(noProgressReconnects)")
                        } else {
                            noProgressReconnects = 0
                        }
                        if noProgressReconnects >= 2 {
                            self.logStream("reading stream failing after no-progress reconnects streamId=\(streamId)")
                            continuation.finish(throwing: APIError.invalidResponse)
                            return
                        }

                        retries = 0
                        self.logStream("reading reconnecting streamId=\(streamId) nextCursor=\(cursor ?? "nil")")
                        try await Task.sleep(nanoseconds: 250_000_000)
                    } catch {
                        retries += 1
                        self.logStream("reading stream error streamId=\(streamId) retry=\(retries) error=\(error.localizedDescription)")
                        if retries > 3 {
                            continuation.finish(throwing: error)
                            return
                        }
                        try? await Task.sleep(nanoseconds: UInt64(250_000_000 * retries))
                    }
                }

                continuation.finish(throwing: APIError.invalidResponse)
            }
        }
    }

    // MARK: - Prompts

    /// Kick off a prompt stream. The server computes the dayIndex.
    /// Returns the server's response which may contain a different `streamId`
    /// if a generation was already running.
    @discardableResult
    func startPromptStream(streamId: String) async throws -> StartStreamResponse {
        let body: [String: Any] = [
            "streamId": streamId,
        ]
        return try await post("/api/prompts/generate/stream", body: body)
    }

    func streamPrompt(streamId: String, lastEventId: String? = nil) -> AsyncThrowingStream<PromptStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var retries = 0
                var cursor = lastEventId
                var noProgressReconnects = 0

                self.logStream("prompt connect requested streamId=\(streamId) lastEventId=\(lastEventId ?? "nil")")

                while retries <= 3 {
                    do {
                        let requestStartCursor = cursor
                        let url = URL(string: "\(baseURL)/api/prompts/generate/stream?streamId=\(streamId)")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"
                        try await self.ensureAuthenticated()
                        if let auth = self.authorizationHeader {
                            request.setValue(auth, forHTTPHeaderField: "Authorization")
                        }
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        request.timeoutInterval = 300
                        if let cursor {
                            request.setValue(cursor, forHTTPHeaderField: "Last-Event-ID")
                        }

                        self.logStream("prompt opening SSE streamId=\(streamId) cursor=\(requestStartCursor ?? "nil") retry=\(retries)")

                        let (bytes, response) = try await self.session.bytes(for: request)

                        // Handle 401 by re-authenticating and retrying
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                            self.logStream("prompt SSE got 401, re-authenticating")
                            try await self.authenticate()
                            retries += 1
                            continue
                        }

                        try self.validateResponse(response)
                        if let httpResponse = response as? HTTPURLResponse {
                            self.logStream("prompt SSE connected streamId=\(streamId) status=\(httpResponse.statusCode)")
                        } else {
                            self.logStream("prompt SSE connected streamId=\(streamId)")
                        }

                        var currentEvent = "message"
                        var currentId: String?
                        var dataLines: [String] = []
                        var reachedTerminal = false
                        var receivedFrame = false

                        func emitFrame() {
                            let data = dataLines.joined(separator: "\n")
                            defer {
                                currentEvent = "message"
                                currentId = nil
                                dataLines.removeAll()
                            }
                            guard !data.isEmpty else { return }
                            receivedFrame = true
                            if let currentId {
                                cursor = currentId
                            }

                            switch currentEvent {
                            case "start":
                                self.logStream("prompt event=start id=\(currentId ?? "nil")")
                                continuation.yield(.start(eventId: currentId))
                            case "delta":
                                if let text = Self.extractStringValue(fromJSON: data, key: "text") {
                                    self.logStream("prompt event=delta id=\(currentId ?? "nil") chars=\(text.count)")
                                    continuation.yield(.delta(text, eventId: currentId))
                                }
                            case "complete":
                                self.logStream("prompt event=complete id=\(currentId ?? "nil")")
                                if let prompt = Self.extractStringValue(fromJSON: data, key: "prompt") {
                                    continuation.yield(.complete(prompt, eventId: currentId))
                                    reachedTerminal = true
                                } else {
                                    continuation.yield(.end(status: "completed", eventId: currentId))
                                    reachedTerminal = true
                                }
                            case "end":
                                let status = Self.extractStringValue(fromJSON: data, key: "status") ?? "completed"
                                self.logStream("prompt event=end id=\(currentId ?? "nil") status=\(status)")
                                continuation.yield(.end(status: status, eventId: currentId))
                                reachedTerminal = true
                            case "heartbeat":
                                self.logStream("prompt event=heartbeat id=\(currentId ?? "nil")")
                                continuation.yield(.heartbeat(eventId: currentId))
                            case "error":
                                let message = Self.extractStringValue(fromJSON: data, key: "message") ?? "Unknown stream error"
                                self.logStream("prompt event=error id=\(currentId ?? "nil") message=\(message)")
                                continuation.yield(.error(message, eventId: currentId))
                                reachedTerminal = true
                            default:
                                break
                            }
                        }

                        for try await line in bytes.lines {
                            if line.isEmpty {
                                emitFrame()
                                if reachedTerminal {
                                    self.logStream("prompt stream finished streamId=\(streamId) terminal=true")
                                    continuation.finish()
                                    return
                                }
                                continue
                            }

                            // Flush previous frame when a new frame boundary is detected.
                            // URLSession.AsyncBytes.lines may drop empty lines between SSE frames,
                            // so we detect boundaries by seeing id:/event: while data is pending.
                            if (line.hasPrefix("id:") || line.hasPrefix("event:")) && !dataLines.isEmpty {
                                emitFrame()
                                if reachedTerminal {
                                    self.logStream("prompt stream finished streamId=\(streamId) terminal=true")
                                    continuation.finish()
                                    return
                                }
                            }

                            if line.hasPrefix("id:") {
                                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("event:") {
                                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            }
                        }

                        emitFrame()
                        if reachedTerminal {
                            self.logStream("prompt stream finished streamId=\(streamId) terminal=true")
                            continuation.finish()
                            return
                        }

                        if !receivedFrame && requestStartCursor == cursor {
                            self.logStream("prompt stream closed with no progress streamId=\(streamId) cursor=\(cursor ?? "nil")")
                            continuation.finish()
                            return
                        }

                        if requestStartCursor == cursor {
                            noProgressReconnects += 1
                            self.logStream("prompt reconnect no progress streamId=\(streamId) count=\(noProgressReconnects)")
                        } else {
                            noProgressReconnects = 0
                        }
                        if noProgressReconnects >= 2 {
                            self.logStream("prompt stream failing after no-progress reconnects streamId=\(streamId)")
                            continuation.finish(throwing: APIError.invalidResponse)
                            return
                        }

                        retries = 0
                        self.logStream("prompt reconnecting streamId=\(streamId) nextCursor=\(cursor ?? "nil")")
                        try await Task.sleep(nanoseconds: 250_000_000)
                    } catch {
                        retries += 1
                        self.logStream("prompt stream error streamId=\(streamId) retry=\(retries) error=\(error.localizedDescription)")
                        if retries > 3 {
                            continuation.finish(throwing: error)
                            return
                        }
                        try? await Task.sleep(nanoseconds: UInt64(250_000_000 * retries))
                    }
                }

                continuation.finish(throwing: APIError.invalidResponse)
            }
        }
    }

    // MARK: - Entries

    func getEntry(dayIndex: Int) async throws -> EntryResponse {
        return try await get("/api/entries?dayIndex=\(dayIndex)")
    }

    /// Get the entry for the server-computed current day.
    func getCurrentEntry() async throws -> EntryResponse {
        return try await get("/api/entries?dayIndex=current")
    }

    func getAllEntries() async throws -> [EntryResponse] {
        return try await get("/api/entries")
    }

    /// Update an entry. The server resolves the target entry from context flags
    /// (isBonusReading, isFreeWrite) or defaults to the current day.
    func updateEntry(fields: [String: Any]) async throws -> EntryResponse {
        return try await put("/api/entries", body: fields)
    }

    // MARK: - User Input (memories)

    struct UserInputResponse: Codable {
        let entry: EntryResponse?
    }

    /// Send user writing to the memory system. Server resolves dayIndex.
    func sendUserInput(text: String) async throws -> UserInputResponse {
        return try await post("/api/user-input", body: ["text": text])
    }

    // MARK: - Sync

    struct SyncResponse: Codable {
        let user: UserResponse?
        let entries: [EntryResponse]
        let currentDayIndex: Int?
    }

    func sync(user: [String: Any]?, entries: [[String: Any]]?) async throws -> SyncResponse {
        var body: [String: Any] = [:]
        if let user = user { body["user"] = user }
        if let entries = entries { body["entries"] = entries }
        return try await post("/api/sync", body: body)
    }

    // MARK: - Private HTTP Methods

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await ensureAuthenticated()
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        // Auto-retry on 401: re-authenticate and repeat the request once
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await authenticate()
            var retryRequest = URLRequest(url: url)
            retryRequest.httpMethod = "GET"
            if let auth = authorizationHeader {
                retryRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            try validateResponse(retryResponse)
            return try JSONDecoder().decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await ensureAuthenticated()
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        // Auto-retry on 401
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await authenticate()
            var retryRequest = URLRequest(url: url)
            retryRequest.httpMethod = "POST"
            if let auth = authorizationHeader {
                retryRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            try validateResponse(retryResponse)
            return try JSONDecoder().decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await ensureAuthenticated()
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        // Auto-retry on 401
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await authenticate()
            var retryRequest = URLRequest(url: url)
            retryRequest.httpMethod = "PUT"
            if let auth = authorizationHeader {
                retryRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retryRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            try validateResponse(retryResponse)
            return try JSONDecoder().decode(T.self, from: retryData)
        }

        try validateResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private static func extractStringValue(fromJSON json: String, key: String) -> String? {
        guard let obj = extractJSONObject(fromJSON: json) else {
            return nil
        }
        return obj[key] as? String
    }

    private static func extractJSONObjectData(fromJSON json: String) -> Data? {
        guard let obj = extractJSONObject(fromJSON: json) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    private static func extractJSONObject(fromJSON json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let object = parsed as? [String: Any] {
            return object
        }

        if let nested = parsed as? String,
           let nestedData = nested.data(using: .utf8),
           let nestedObject = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any] {
            return nestedObject
        }

        return nil
    }
}

enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        }
    }
}
