import Foundation

struct StreamSession: Codable {
    let streamId: String
    let kind: String
    let dayIndex: Int
    let aboutDayIndex: Int?
    var lastEventId: String?
    let startedAt: Date
}

final class StreamSessionStore {
    static let shared = StreamSessionStore()

    private let defaults = UserDefaults.standard
    private let maxAgeSeconds: TimeInterval = 15 * 60

    /// In-memory set preventing concurrent loads for the same entity.
    /// Keyed by the same strings used for UserDefaults (e.g. "stream.reading.5").
    private var activeLoads: Set<String> = []

    private init() {}

    // MARK: - Concurrency guard

    /// Returns `true` if the load was claimed; `false` if one is already in progress.
    func beginLoad(key: String) -> Bool {
        guard !activeLoads.contains(key) else { return false }
        activeLoads.insert(key)
        return true
    }

    func endLoad(key: String) {
        activeLoads.remove(key)
    }

    func loadReading(dayIndex: Int) -> StreamSession? {
        load(key: readingKey(dayIndex: dayIndex))
    }

    func loadFreshReading(dayIndex: Int) -> StreamSession? {
        guard let session = loadReading(dayIndex: dayIndex) else { return nil }
        if Date().timeIntervalSince(session.startedAt) > maxAgeSeconds {
            clearReading(dayIndex: dayIndex)
            return nil
        }
        return session
    }

    func saveReading(dayIndex: Int, streamId: String, lastEventId: String?) {
        let session = StreamSession(
            streamId: streamId,
            kind: "reading",
            dayIndex: dayIndex,
            aboutDayIndex: nil,
            lastEventId: lastEventId,
            startedAt: Date()
        )
        save(session, key: readingKey(dayIndex: dayIndex))
    }

    func updateReadingCursor(dayIndex: Int, eventId: String) {
        guard var session = loadReading(dayIndex: dayIndex) else { return }
        session.lastEventId = eventId
        save(session, key: readingKey(dayIndex: dayIndex))
    }

    func clearReading(dayIndex: Int) {
        defaults.removeObject(forKey: readingKey(dayIndex: dayIndex))
    }

    func loadPrompt(dayIndex: Int, aboutDayIndex: Int) -> StreamSession? {
        load(key: promptKey(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex))
    }

    func loadFreshPrompt(dayIndex: Int, aboutDayIndex: Int) -> StreamSession? {
        guard let session = loadPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex) else {
            return nil
        }
        if Date().timeIntervalSince(session.startedAt) > maxAgeSeconds {
            clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
            return nil
        }
        return session
    }

    func savePrompt(dayIndex: Int, aboutDayIndex: Int, streamId: String, lastEventId: String?) {
        let session = StreamSession(
            streamId: streamId,
            kind: "prompt",
            dayIndex: dayIndex,
            aboutDayIndex: aboutDayIndex,
            lastEventId: lastEventId,
            startedAt: Date()
        )
        save(session, key: promptKey(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex))
    }

    func updatePromptCursor(dayIndex: Int, aboutDayIndex: Int, eventId: String) {
        guard var session = loadPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex) else { return }
        session.lastEventId = eventId
        save(session, key: promptKey(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex))
    }

    func clearPrompt(dayIndex: Int, aboutDayIndex: Int) {
        defaults.removeObject(forKey: promptKey(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex))
    }

    private func readingKey(dayIndex: Int) -> String {
        "stream.reading.\(dayIndex)"
    }

    private func promptKey(dayIndex: Int, aboutDayIndex: Int) -> String {
        "stream.prompt.\(dayIndex).\(aboutDayIndex)"
    }

    private func load(key: String) -> StreamSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StreamSession.self, from: data)
    }

    private func save(_ session: StreamSession, key: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}
