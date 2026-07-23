import Foundation

enum SyncFormatting {
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "No snapshot timestamp" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ seconds: Int?) -> String {
        guard let seconds else { return "Not recorded" }
        if seconds < 60 {
            return "\(seconds)s"
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
