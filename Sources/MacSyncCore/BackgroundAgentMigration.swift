import Darwin
import Foundation

public enum BackgroundAgentMigration {
    /// Migrate only app-owned jobs. Opening the UI does not start a sync.
    public static func migrate(homeDirectory: String, executable: String, runner: ProcessRunner) throws {
        let root = URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library/LaunchAgents")
        let agent = root.appendingPathComponent("tools.xyzzy.mac-sync.plist")
        guard let data = try? Data(contentsOf: agent),
              var values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values["Label"] as? String == "tools.xyzzy.mac-sync" else { return }
        let oldUI = root.appendingPathComponent("tools.xyzzy.mac-sync.app.plist")
        if FileManager.default.fileExists(atPath: oldUI.path) {
            _ = runner.run("/bin/launchctl", ["bootout", "gui/\(getuid())", oldUI.path], timeout: 10)
            try FileManager.default.removeItem(at: oldUI)
        }
        var stableExecutable = executable
        if let range = executable.range(of: "/Cellar/") {
            let formula = executable[range.upperBound...].split(separator: "/").first.map(String.init)
            if let formula, ["mac-sync", "mac-sync-current"].contains(formula) {
                stableExecutable = String(executable[..<range.lowerBound]) + "/opt/\(formula)/bin/mac-sync"
            }
        }
        values["ProgramArguments"] = [stableExecutable, "run"]
        values["ProcessType"] = "Background"
        values["Nice"] = 10
        values["LowPriorityIO"] = true
        let encoded = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        if encoded != data {
            try encoded.write(to: agent, options: .atomic)
        }
    }
}
