import Foundation

struct Reading: Codable, Identifiable {
    var date: Date
    var celsius: Double
    var id: Date { date }
}

// Keeps one reading per minute for the last 24 hours, saved to
// ~/Library/Application Support/MacTemp/history.json so it survives restarts.
final class History {
    private(set) var readings: [Reading] = []
    private let url: URL
    private let window: TimeInterval = 24 * 60 * 60

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTemp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([Reading].self, from: data) {
            readings = saved
        }
        trim()
    }

    /// Adds a reading if at least a minute has passed since the last one. Returns true if added.
    @discardableResult
    func add(_ celsius: Double, at date: Date = Date()) -> Bool {
        if let last = readings.last, date.timeIntervalSince(last.date) < 60 { return false }
        readings.append(Reading(date: date, celsius: celsius))
        trim()
        save()
        return true
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-window)
        readings.removeAll { $0.date < cutoff }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(readings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
