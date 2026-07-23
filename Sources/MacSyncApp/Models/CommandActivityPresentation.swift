import Foundation

enum CommandActivityTone: Equatable {
    case normal
    case pending
    case success
    case new
    case updated
    case removed
    case skipped
    case warning
    case error
}

struct CommandActivityLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let tone: CommandActivityTone
}

enum CommandActivityPresentation {
    static func lines(for output: String) -> [CommandActivityLine] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, text in
                CommandActivityLine(id: index, text: text, tone: tone(for: text))
            }
    }

    static func tone(for line: String) -> CommandActivityTone {
        let normalised = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalised.hasPrefix("error:") || normalised.contains("fatal:")
            || normalised.contains(" error") || normalised.contains("failed")
        {
            return .error
        }
        if normalised.hasPrefix("warn:") || normalised.contains("warning") {
            return .warning
        }
        if normalised.contains("skip") || normalised.contains("unchanged")
            || normalised.contains("already up to date") || normalised.contains("no machine snapshot changes")
            || normalised.contains("no local commits")
        {
            return .skipped
        }
        if normalised.contains("new snapshot file") || normalised.contains("new local file") {
            return .new
        }
        if normalised.contains("updated snapshot file") || normalised.contains("updated local file") {
            return .updated
        }
        if normalised.contains("removed") {
            return .removed
        }
        if normalised.hasPrefix("⠓") || normalised.hasPrefix("would ") {
            return .pending
        }
        if normalised.hasPrefix("✔") {
            return .success
        }
        return .normal
    }
}
