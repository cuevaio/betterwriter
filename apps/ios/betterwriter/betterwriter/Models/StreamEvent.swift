import Foundation

enum ReadingStreamEvent {
    case start(eventId: String?)
    case delta(String, eventId: String?)
    case complete(APIClient.EntryResponse, eventId: String?)
    case end(status: String, eventId: String?)
    case heartbeat(eventId: String?)
    case error(String, eventId: String?)
}

enum PromptStreamEvent {
    case start(eventId: String?)
    case delta(String, eventId: String?)
    case complete(String, eventId: String?)
    case end(status: String, eventId: String?)
    case heartbeat(eventId: String?)
    case error(String, eventId: String?)
}
