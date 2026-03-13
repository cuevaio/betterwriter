import Foundation

struct SSEEventFrame {
    let event: String
    let data: String
    let id: String?
}

enum SSEParser {
    static func parseLineStream(_ lines: [String]) -> [SSEEventFrame] {
        var frames: [SSEEventFrame] = []
        var currentEvent = "message"
        var currentId: String?
        var dataLines: [String] = []

        func flush() {
            guard !dataLines.isEmpty else { return }
            frames.append(SSEEventFrame(event: currentEvent, data: dataLines.joined(separator: "\n"), id: currentId))
            currentEvent = "message"
            currentId = nil
            dataLines.removeAll()
        }

        for line in lines {
            if line.isEmpty {
                flush()
                continue
            }

            if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("id:") {
                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        flush()
        return frames
    }
}
