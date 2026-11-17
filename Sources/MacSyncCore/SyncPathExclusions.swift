import Darwin
import Foundation

/// Conservative incoming protection for ordinary rsync exclude globs. Advanced
/// include/merge rules disable automatic incoming rather than bypass a rule.
struct SyncPathExclusions {
    let patterns: [String]
    let requiresManualCopy: Bool

    init(file: String) throws {
        guard FileManager.default.fileExists(atPath: file) else { patterns = []; requiresManualCopy = false; return }
        guard let size = try URL(fileURLWithPath: file).resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
        patterns = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") }
        let advanced = ["+ ", "- ", ": ", "! ", "merge ", "dir-merge ", "include ", "exclude ", "show ", "hide ", "protect ", "risk ", "P ", "R ", "H ", "S ", ". "]
        requiresManualCopy = patterns.contains { pattern in pattern == "!" || advanced.contains(where: pattern.hasPrefix) }
    }

    func excludes(_ path: String, selection: [String]) -> Bool {
        if requiresManualCopy {
            return true
        }
        for root in selection where path == root || path.hasPrefix(root + "/") {
            let relative = path == root ? (path as NSString).lastPathComponent : String(path.dropFirst(root.count + 1))
            let parts = relative.split(separator: "/").map(String.init)
            for raw in patterns {
                let directoryOnly = raw.hasSuffix("/")
                let pattern = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if pattern.isEmpty {
                    continue
                }
                if !pattern.contains("/") {
                    let candidates = directoryOnly ? Array(parts.dropLast()) : parts
                    if candidates.contains(where: { fnmatch(pattern, $0, 0) == 0 }) {
                        return true
                    }
                } else {
                    // Matching extra suffixes is intentionally deny-only. A
                    // conservative false positive requires manual copying; it
                    // cannot cause an excluded file to be written silently.
                    let end = directoryOnly ? parts.count : parts.count + 1
                    for count in 1 ..< end {
                        let candidate = parts.prefix(count).joined(separator: "/")
                        if fnmatch(pattern, candidate, 0) == 0 || fnmatch("*/" + pattern, candidate, 0) == 0 {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
}
