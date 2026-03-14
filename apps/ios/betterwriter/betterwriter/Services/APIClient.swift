import Foundation

/// HTTP client for communicating with the Better Writer backend.
/// Authenticates with a server-signed JWT obtained by exchanging the device UUID.
actor APIClient {
  static let shared = APIClient()

  #if DEBUG
    private let baseURL = "http://localhost:3000"
  #else
    private let baseURL = "https://betterwriter.vercel.app"
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
    /// Present when mode is "started" or "already-running". Nil when mode is "completed".
    let streamId: String?
    /// Present when mode is "completed" for readings.
    let entry: EntryResponse?
    /// Present when mode is "completed" for prompts.
    let prompt: String?
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

  /// Kick off a reading stream. The server owns stream identity.
  @discardableResult
  func startReadingStream() async throws -> StartStreamResponse {
    return try await post("/api/readings/generate/stream", body: [:])
  }

  func streamReading(
    lastEventId: String? = nil
  ) -> AsyncThrowingStream<ReadingStreamEvent, Error> {
    streamSSE(
      path: "/api/readings/generate/stream",
      label: "reading",
      lastEventId: lastEventId
    ) { eventType, data, eventId in
      switch eventType {
      case "start":
        return (.start(eventId: eventId), false)
      case "delta":
        if let text = Self.extractStringValue(fromJSON: data, key: "text") {
          return (.delta(text, eventId: eventId), false)
        }
        return nil
      case "complete":
        if let payload = Self.extractJSONObjectData(fromJSON: data),
          let entry = try? JSONDecoder().decode(EntryResponse.self, from: payload)
        {
          return (.complete(entry, eventId: eventId), true)
        }
        return (.end(status: "completed", eventId: eventId), true)
      case "end":
        let status =
          Self.extractStringValue(fromJSON: data, key: "status") ?? "completed"
        return (.end(status: status, eventId: eventId), true)
      case "heartbeat":
        return (.heartbeat(eventId: eventId), false)
      case "error":
        let message =
          Self.extractStringValue(fromJSON: data, key: "message")
          ?? "Unknown stream error"
        return (.error(message, eventId: eventId), true)
      default:
        return nil
      }
    }
  }

  // MARK: - Prompts

  /// Kick off a prompt stream. The server owns stream identity.
  @discardableResult
  func startPromptStream() async throws -> StartStreamResponse {
    return try await post("/api/prompts/generate/stream", body: [:])
  }

  func streamPrompt(
    lastEventId: String? = nil
  ) -> AsyncThrowingStream<PromptStreamEvent, Error> {
    streamSSE(
      path: "/api/prompts/generate/stream",
      label: "prompt",
      lastEventId: lastEventId
    ) { eventType, data, eventId in
      switch eventType {
      case "start":
        return (.start(eventId: eventId), false)
      case "delta":
        if let text = Self.extractStringValue(fromJSON: data, key: "text") {
          return (.delta(text, eventId: eventId), false)
        }
        return nil
      case "complete":
        if let prompt = Self.extractStringValue(fromJSON: data, key: "prompt") {
          return (.complete(prompt, eventId: eventId), true)
        }
        return (.end(status: "completed", eventId: eventId), true)
      case "end":
        let status =
          Self.extractStringValue(fromJSON: data, key: "status") ?? "completed"
        return (.end(status: status, eventId: eventId), true)
      case "heartbeat":
        return (.heartbeat(eventId: eventId), false)
      case "error":
        let message =
          Self.extractStringValue(fromJSON: data, key: "message")
          ?? "Unknown stream error"
        return (.error(message, eventId: eventId), true)
      default:
        return nil
      }
    }
  }

  // MARK: - Generic SSE streaming

  /// Generic SSE stream method. Handles connection, 401 retry, reconnection with
  /// cursor, and no-progress detection. The `parseFrame` closure maps raw SSE
  /// event data into the caller's event type plus a `isTerminal` flag.
  private func streamSSE<T: Sendable>(
    path: String,
    label: String,
    lastEventId: String?,
    parseFrame:
      @escaping @Sendable (
        _ eventType: String, _ data: String, _ eventId: String?
      ) -> (T, Bool)?
  ) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var retries = 0
        var cursor = lastEventId
        var noProgressReconnects = 0

        self.logStream(
          "\(label) connect requested lastEventId=\(lastEventId ?? "nil")")

        while retries <= 3 {
          do {
            let requestStartCursor = cursor
            let url = URL(string: "\(self.baseURL)\(path)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            try await self.ensureAuthenticated()
            if let auth = self.authorizationHeader {
              request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 300
            if let cursor {
              request.setValue(
                cursor, forHTTPHeaderField: "Last-Event-ID")
            }

            self.logStream(
              "\(label) opening SSE cursor=\(requestStartCursor ?? "nil") retry=\(retries)"
            )

            let (bytes, response) = try await self.session.bytes(for: request)

            // Handle 401 by re-authenticating and retrying
            if let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 401
            {
              self.logStream("\(label) SSE got 401, re-authenticating")
              try await self.authenticate()
              retries += 1
              continue
            }

            try self.validateResponse(response)
            if let httpResponse = response as? HTTPURLResponse {
              self.logStream(
                "\(label) SSE connected status=\(httpResponse.statusCode)")
            } else {
              self.logStream("\(label) SSE connected")
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
              self.logStream(
                "\(label) event=\(currentEvent) id=\(currentId ?? "nil")")
              if let (event, isTerminal) = parseFrame(
                currentEvent, data, currentId)
              {
                continuation.yield(event)
                if isTerminal { reachedTerminal = true }
              }
            }

            for try await line in bytes.lines {
              if line.isEmpty {
                emitFrame()
                if reachedTerminal {
                  self.logStream(
                    "\(label) stream finished terminal=true")
                  continuation.finish()
                  return
                }
                continue
              }

              // Flush previous frame when a new frame boundary is detected.
              // URLSession.AsyncBytes.lines may drop empty lines between
              // SSE frames, so we detect boundaries by seeing id:/event:
              // while data is pending.
              if (line.hasPrefix("id:") || line.hasPrefix("event:"))
                && !dataLines.isEmpty
              {
                emitFrame()
                if reachedTerminal {
                  self.logStream(
                    "\(label) stream finished terminal=true")
                  continuation.finish()
                  return
                }
              }

              if line.hasPrefix("id:") {
                currentId = String(line.dropFirst(3))
                  .trimmingCharacters(in: .whitespaces)
              } else if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6))
                  .trimmingCharacters(in: .whitespaces)
              } else if line.hasPrefix("data:") {
                dataLines.append(
                  String(line.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces))
              }
            }

            emitFrame()
            if reachedTerminal {
              self.logStream("\(label) stream finished terminal=true")
              continuation.finish()
              return
            }

            if !receivedFrame && requestStartCursor == cursor {
              self.logStream(
                "\(label) stream closed with no progress cursor=\(cursor ?? "nil")"
              )
              continuation.finish()
              return
            }

            if requestStartCursor == cursor {
              noProgressReconnects += 1
              self.logStream(
                "\(label) reconnect no progress count=\(noProgressReconnects)"
              )
            } else {
              noProgressReconnects = 0
            }
            if noProgressReconnects >= 2 {
              self.logStream(
                "\(label) stream failing after no-progress reconnects")
              continuation.finish(throwing: APIError.invalidResponse)
              return
            }

            retries = 0
            self.logStream(
              "\(label) reconnecting nextCursor=\(cursor ?? "nil")")
            try await Task.sleep(nanoseconds: 250_000_000)
          } catch {
            retries += 1
            self.logStream(
              "\(label) stream error retry=\(retries) error=\(error.localizedDescription)"
            )
            if retries > 3 {
              continuation.finish(throwing: error)
              return
            }
            try? await Task.sleep(
              nanoseconds: UInt64(250_000_000 * retries))
          }
        }

        continuation.finish(throwing: APIError.invalidResponse)
      }
      continuation.onTermination = { _ in task.cancel() }
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

  func sync(
    user: [String: Any]?, entries: [[String: Any]]?
  ) async throws -> SyncResponse {
    var body: [String: Any] = [:]
    if let user = user { body["user"] = user }
    if let entries = entries { body["entries"] = entries }
    return try await post("/api/sync", body: body)
  }

  // MARK: - Private HTTP Methods

  /// Consolidated request method with automatic 401 retry.
  private func performRequest<T: Decodable>(
    method: String,
    path: String,
    body: [String: Any]? = nil
  ) async throws -> T {
    try await ensureAuthenticated()
    let url = URL(string: "\(baseURL)\(path)")!

    func buildRequest() throws -> URLRequest {
      var request = URLRequest(url: url)
      request.httpMethod = method
      if let auth = authorizationHeader {
        request.setValue(auth, forHTTPHeaderField: "Authorization")
      }
      if let body {
        request.setValue(
          "application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
          withJSONObject: body)
      }
      return request
    }

    let request = try buildRequest()
    let (data, response) = try await session.data(for: request)

    // Auto-retry on 401: re-authenticate and repeat the request once
    if let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 401
    {
      try await authenticate()
      let retryRequest = try buildRequest()
      let (retryData, retryResponse) = try await session.data(
        for: retryRequest)
      try validateResponse(retryResponse)
      return try JSONDecoder().decode(T.self, from: retryData)
    }

    try validateResponse(response)
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func get<T: Decodable>(_ path: String) async throws -> T {
    try await performRequest(method: "GET", path: path)
  }

  private func post<T: Decodable>(
    _ path: String, body: [String: Any]
  ) async throws -> T {
    try await performRequest(method: "POST", path: path, body: body)
  }

  private func put<T: Decodable>(
    _ path: String, body: [String: Any]
  ) async throws -> T {
    try await performRequest(method: "PUT", path: path, body: body)
  }

  private func validateResponse(_ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw APIError.httpError(statusCode: httpResponse.statusCode)
    }
  }

  // MARK: - JSON helpers

  static func extractStringValue(
    fromJSON json: String, key: String
  ) -> String? {
    guard let obj = extractJSONObject(fromJSON: json) else {
      return nil
    }
    return obj[key] as? String
  }

  static func extractJSONObjectData(fromJSON json: String) -> Data? {
    guard let obj = extractJSONObject(fromJSON: json) else {
      return nil
    }
    return try? JSONSerialization.data(withJSONObject: obj)
  }

  static func extractJSONObject(
    fromJSON json: String
  ) -> [String: Any]? {
    guard let data = json.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data)
    else {
      return nil
    }

    if let object = parsed as? [String: Any] {
      return object
    }

    if let nested = parsed as? String,
      let nestedData = nested.data(using: .utf8),
      let nestedObject = try? JSONSerialization.jsonObject(
        with: nestedData) as? [String: Any]
    {
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
