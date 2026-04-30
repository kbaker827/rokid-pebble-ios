import Foundation

// MARK: - Source status

enum SourceStatus {
    case active, idle, error, disconnected
}

// MARK: - Shared data model pushed to both Rokid glasses and Pebble watch

struct SourceData {
    var line1: String = "--"
    var line2: String = ""
    var line3: String = ""
    var status: SourceStatus = .disconnected
    var sourceName: String = ""
    var sourceIcon: String = ""          // SF Symbol name
    var updatedAt: Date = .distantPast

    var age: TimeInterval { Date().timeIntervalSince(updatedAt) }
    var isStale: Bool { age > 120 }

    /// Compact single-line summary for glasses/watch
    var compact: String {
        [line1, line2].filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

// MARK: - App Message keys shared with the Pebble watchapp

enum PebbleKey: Int {
    case sourceName  = 0
    case line1       = 1
    case line2       = 2
    case line3       = 3
    case statusCode  = 4   // 0=active 1=idle 2=error 3=disconnected
    case buttonEvent = 5   // 0=up 1=select 2=down (watch→phone)
}

/// Watchapp UUID — must match appinfo.json in the watchapp
let watchappUUID = UUID(uuidString: "A7E23B4C-5D1F-4A3E-8C6B-9F2E1D0B4A5C")!
