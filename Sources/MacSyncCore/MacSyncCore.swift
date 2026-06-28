import Darwin
import Foundation

private struct ExitError: Error {
    let code: Int
}

private struct Config {
    let originalArgs: [String]
    let selfPath: String
    let selfDir: String
    let scriptName: String
    let homeDir: String
    let repoDir: String
    let machinesRepoDir: String
    let installPath: String
    let installDir: String
    let spinnerInstallPath: String
    let hourlyMinute: String
    let launchAgentPathEnv: String
    let dryRun: String
    let dynamicRefs: String
    let homebrewSync: String
    let vscodeExtensionsSync: String
    let githubRootDir: String
    let githubReposSync: String
    let secretsSync: String
    let manifestSource: String
    let selfUpdate: String
    let selfUpdateMode: String
    let selfUpdateRemote: String
    let selfUpdateRef: String
    let brewBundleInstallFlags: String
    let pathsFile: String
    let excludesFile: String
    let secretPathsFile: String
    let ageRecipientsFile: String
    let keychainService: String
    let keychainAccount: String
    let repoScript: String
    let repoSpinner: String
    let selfSpinner: String
    let launchAgentLabel: String
    let launchAgentPlist: String
    let logOut: String
    let logErr: String
    let machineName: String
    let machinesRootDir: String
    let machineDir: String
    let machineHomeDir: String
    let machineAbsoluteDir: String
    let dynamicPathsFile: String
    let homebrewDir: String
    let editorDir: String
    let vscodeExtensionsFile: String
    let githubReposDir: String
    let githubReposFile: String
    let secretsDir: String
    let secretsArchive: String
    let secretsIncludedPathsFile: String
    let lockDir: String
    let statusDir: String
    let syncStatusFile: String
    let syncWarningsFile: String
    let syncErrorsFile: String
    let selfUpdateStatusFile: String

    init(environment env: [String: String], originalArgs: [String], runner: ProcessRunner) {
        let selfPath = Config.realpathExisting(originalArgs.first ?? "mac-sync")
        let home = env["HOME"] ?? NSHomeDirectory()
        let repo = env["MAC_SYNC_REPO"] ?? "\(home)/github/mac-sync"
        let machinesRepo = env["MAC_SYNC_MACHINES_REPO"] ?? "\(home)/github/dot-files"
        let install = env["MAC_SYNC_INSTALL_PATH"] ?? "\(home)/bin/mac-sync"
        let installDir = (install as NSString).deletingLastPathComponent
        let machine = Config.computeMachineName(environment: env, runner: runner)
        let statusDir = env["MAC_SYNC_STATUS_DIR"] ?? "\(home)/Library/Application Support/mac-sync/status"
        let tmpDir = env["TMPDIR"] ?? "/tmp"

        self.originalArgs = Array(originalArgs.dropFirst())
        self.selfPath = selfPath
        self.selfDir = (selfPath as NSString).deletingLastPathComponent
        self.scriptName = (selfPath as NSString).lastPathComponent
        self.homeDir = home
        self.repoDir = repo
        self.machinesRepoDir = machinesRepo
        self.installPath = install
        self.installDir = installDir
        self.spinnerInstallPath = "\(installDir)/mac-spinner"
        self.hourlyMinute = env["MAC_SYNC_HOURLY_MINUTE"] ?? env["MAC_SYNC_DAILY_MINUTE"] ?? "0"
        self.launchAgentPathEnv = env["MAC_SYNC_LAUNCH_AGENT_PATH"] ?? "\(home)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        self.dryRun = env["MAC_SYNC_DRY_RUN"] ?? "0"
        self.dynamicRefs = env["MAC_SYNC_DYNAMIC_REFS"] ?? "1"
        self.homebrewSync = env["MAC_SYNC_HOMEBREW"] ?? "1"
        self.vscodeExtensionsSync = env["MAC_SYNC_VSCODE_EXTENSIONS"] ?? "1"
        self.githubRootDir = env["MAC_SYNC_GITHUB_ROOT"] ?? "\(home)/github"
        self.githubReposSync = env["MAC_SYNC_GITHUB_REPOS"] ?? "1"
        self.secretsSync = env["MAC_SYNC_SECRETS"] ?? "1"
        self.manifestSource = env["MAC_SYNC_MANIFEST_SOURCE"] ?? "config"
        self.selfUpdate = env["MAC_SYNC_SELF_UPDATE"] ?? "1"
        self.selfUpdateMode = env["MAC_SYNC_SELF_UPDATE_MODE"] ?? "restart"
        self.selfUpdateRemote = env["MAC_SYNC_SELF_UPDATE_REMOTE"] ?? ""
        self.selfUpdateRef = env["MAC_SYNC_SELF_UPDATE_REF"] ?? "main"
        self.brewBundleInstallFlags = env["MAC_SYNC_BREW_BUNDLE_INSTALL_FLAGS"] ?? env["BREW_BUNDLE_INSTALL_FLAGS"] ?? ""
        self.pathsFile = env["MAC_SYNC_PATHS_FILE"] ?? "\(repo)/config/sync-paths.txt"
        self.excludesFile = env["MAC_SYNC_EXCLUDES_FILE"] ?? "\(repo)/config/excludes.txt"
        self.secretPathsFile = env["MAC_SYNC_SECRET_PATHS_FILE"] ?? "\(repo)/config/secret-paths.txt"
        self.ageRecipientsFile = env["MAC_SYNC_AGE_RECIPIENTS_FILE"] ?? "\(repo)/config/age-recipients.txt"
        self.keychainService = env["MAC_SYNC_KEYCHAIN_SERVICE"] ?? "mac-sync age identity"
        self.keychainAccount = env["MAC_SYNC_KEYCHAIN_ACCOUNT"] ?? env["USER"] ?? runner.shell("id -un").stdout.trimmed
        self.repoScript = "\(repo)/bin/mac-sync"
        self.repoSpinner = "\(repo)/bin/mac-spinner"
        self.selfSpinner = "\(self.selfDir)/mac-spinner"
        self.launchAgentLabel = "tools.xyzzy.mac-sync"
        self.launchAgentPlist = "\(home)/Library/LaunchAgents/tools.xyzzy.mac-sync.plist"
        self.logOut = "/tmp/mac-sync.out"
        self.logErr = "/tmp/mac-sync.err"
        self.machineName = machine
        self.machinesRootDir = "\(machinesRepo)/machines"
        self.machineDir = "\(machinesRepo)/machines/\(machine)"
        self.machineHomeDir = "\(machinesRepo)/machines/\(machine)/home"
        self.machineAbsoluteDir = "\(machinesRepo)/machines/\(machine)/absolute"
        self.dynamicPathsFile = "\(machinesRepo)/machines/\(machine)/dynamic-sync-paths.txt"
        self.homebrewDir = "\(machinesRepo)/machines/\(machine)/homebrew"
        self.editorDir = "\(machinesRepo)/machines/\(machine)/editor"
        self.vscodeExtensionsFile = "\(machinesRepo)/machines/\(machine)/editor/vscode-extensions.txt"
        self.githubReposDir = "\(machinesRepo)/machines/\(machine)/github-repositories"
        self.githubReposFile = "\(machinesRepo)/machines/\(machine)/github-repositories/repositories.txt"
        self.secretsDir = "\(machinesRepo)/machines/\(machine)/secrets"
        self.secretsArchive = "\(machinesRepo)/machines/\(machine)/secrets/secrets.tar.gz.age"
        self.secretsIncludedPathsFile = "\(machinesRepo)/machines/\(machine)/secrets/included-paths.txt"
        self.lockDir = "\(tmpDir)/mac-sync-\(machine).lock"
        self.statusDir = statusDir
        self.syncStatusFile = "\(statusDir)/\(machine).env"
        self.syncWarningsFile = "\(statusDir)/\(machine).warnings.log"
        self.syncErrorsFile = "\(statusDir)/\(machine).errors.log"
        self.selfUpdateStatusFile = "\(statusDir)/\(machine).self-update.env"
    }

    static func realpathExisting(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return stringFromNullTerminatedBuffer(buffer)
        }
        let dir = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        if realpath(dir, &buffer) != nil {
            return "\(stringFromNullTerminatedBuffer(buffer))/\(base)"
        }
        return path
    }

    private static func stringFromNullTerminatedBuffer(_ buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func computeMachineName(environment env: [String: String], runner: ProcessRunner) -> String {
        var raw = env["MAC_SYNC_MACHINE"] ?? ""
        if raw.isEmpty, runner.commandExists("scutil") {
            raw = runner.run("scutil", ["--get", "LocalHostName"]).stdout.trimmed
        }
        if raw.isEmpty, runner.commandExists("scutil") {
            raw = runner.run("scutil", ["--get", "ComputerName"]).stdout.trimmed
        }
        if raw.isEmpty {
            raw = runner.run("hostname", ["-s"]).stdout.trimmed
            if raw.isEmpty {
                raw = runner.run("hostname").stdout.trimmed
            }
        }
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func splitLines() -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
    }
}

public final class MacSyncApp {
    private let environment: [String: String]
    private let invocationArguments: [String]
    private var runner: ProcessRunner
    private let config: Config
    private let fm = FileManager.default
    private var warningMessages: [String] = []
    private var errorMessages: [String] = []
    private var lastCommandOutput = ""
    private var runActive = false
    private var runStartedAt = ""
    private var runStartedEpoch = 0
    private var warningCount = 0
    private var errorCount = 0
    private var startedFileCount = 0
    private var startedByteCount = 0
    private var lastUpdatedFileCount = 0
    private var lastUpdatedByteCount = 0
    private var lastNetByteChange = 0
    private var lastStorageFileCount = 0
    private var lastStorageByteCount = 0
    private var selfUpdateScriptChanged = false

    public convenience init() {
        self.init(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    }

    public init(arguments: [String], environment: [String: String]) {
        self.environment = environment
        self.invocationArguments = arguments
        self.runner = ProcessRunner(environment: environment)
        self.config = Config(environment: environment, originalArgs: arguments, runner: self.runner)
    }

    public func run() -> Int {
        do {
            try main(Array(invocationArguments.dropFirst()))
            return 0
        } catch let error as ExitError {
            return error.code
        } catch {
            errorMessage("\(error)")
            return 1
        }
    }

    private func main(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty {
            args.removeFirst()
        }
        switch command {
        case "install", "bootstrap":
            try cmdInstall()
        case "uninstall":
            cmdUninstall()
        case "sync", "run":
            try cmdSync()
        case "restore":
            try cmdRestore(args)
        case "secrets":
            try cmdSecrets(args)
        case "packages":
            try cmdPackages(args)
        case "editor":
            try cmdEditor(args)
        case "manifest":
            try cmdManifest(args)
        case "list", "paths":
            try cmdList()
        case "status":
            cmdStatus()
        case "help", "-h", "--help":
            try cmdHelp(args)
        default:
            try fail("unknown command: \(command)", code: 2, usage: true)
        }
    }

    private func usage() {
        print(
            """
            USAGE:
              \(config.scriptName) <command>

            COMMANDS:
              install     Install or refresh mac-sync and its hourly LaunchAgent
              bootstrap   Alias for install
              uninstall   Unload the LaunchAgent and remove the installed command
              sync        Sync configured paths, commit machine changes, and push
              run         LaunchAgent mode; alias for sync
              restore     Restore this machine snapshot back into $HOME
              restore [--from <machine>|--select] [--force]
                          Restore another machine snapshot back into $HOME
              secrets     Manage encrypted secret snapshots with age and Keychain
              packages    Manage Homebrew package snapshots and restore commands
              editor      Manage VS Code extension snapshots and restore commands
              manifest    Show configured and discovered backup paths
              list        Show configured source paths and repo destinations
              paths       Alias for list
              status      Show install, repo, LaunchAgent, git, and last-sync state
              help [topic]
                          Show this help text or command-specific help
              -h, --help  Show this help text

            ENVIRONMENT:
              MAC_SYNC_REPO          mac-sync repo path. Default: $HOME/github/mac-sync
              MAC_SYNC_MACHINES_REPO Machine snapshot repo. Default: $HOME/github/dot-files
              MAC_SYNC_MACHINE       Machine directory name. Default: macOS host name
              MAC_SYNC_INSTALL_PATH  Installed command. Default: $HOME/bin/mac-sync
              MAC_SYNC_HOURLY_MINUTE LaunchAgent minute, 0-59. Default: 0
              MAC_SYNC_DAILY_MINUTE  Legacy alias for MAC_SYNC_HOURLY_MINUTE
              MAC_SYNC_LAUNCH_AGENT_PATH
                                     PATH used by the LaunchAgent
              MAC_SYNC_STATUS_DIR    Local status directory
              MAC_SYNC_DRY_RUN       Set to 1 to preview sync and restore actions
              MAC_SYNC_DYNAMIC_REFS  Set to 0 to disable dotfile reference discovery
              MAC_SYNC_HOMEBREW      Set to 0 to disable Homebrew package snapshots
              MAC_SYNC_VSCODE_EXTENSIONS
                                     Set to 0 to disable VS Code extension snapshots
              MAC_SYNC_GITHUB_ROOT   Directory containing local GitHub clones. Default: $HOME/github
              MAC_SYNC_GITHUB_REPOS  Set to 0 to disable GitHub repository snapshots
              MAC_SYNC_SECRETS       Set to 0 to disable encrypted secret snapshots
              MAC_SYNC_MANIFEST_SOURCE
                                     config, auto, or dot-files. Default: config
              MAC_SYNC_SELF_UPDATE   Set to 0 to disable remote self-update checks
              MAC_SYNC_SELF_UPDATE_MODE
                                     restart or exit. Default: restart
              MAC_SYNC_SELF_UPDATE_REMOTE
                                     Git remote used for self-updates
              MAC_SYNC_SELF_UPDATE_REF
                                     Git branch used for self-updates. Default: main
              MAC_SYNC_KEYCHAIN_SERVICE
                                     Keychain service for the age identity
              MAC_SYNC_KEYCHAIN_ACCOUNT
                                     Keychain account. Default: $USER or id -un
              SCRIPT_COLOUR          Set to off, false, or 0 to disable colour

            EXAMPLES:
              ./bin/mac-sync install
              mac-sync list
              mac-sync sync
              mac-sync restore --from old-mbp
              mac-sync secrets init
              mac-sync packages diff --from old-mbp
              mac-sync editor install --from old-mbp
              mac-sync secrets list --from old-mbp
              mac-sync help restore
              mac-sync help secrets
              MAC_SYNC_MACHINE=work-mbp mac-sync install
            """
        )
    }

    private func usageRestore() {
        print(
            """
            USAGE:
              \(config.scriptName) restore [--from <machine>|--select|--list-machines] [--force]

            OPTIONS:
              --from <machine>   Restore from another machine snapshot.
              --select           Prompt for a machine snapshot even when the current machine exists.
              --list-machines    List available machine snapshots and exit.
              --force            Overwrite newer local files and resolve file/directory conflicts.
              -h, --help         Show this help text.

            BEHAVIOR:
              Restore pulls both repos first when their worktrees are clean.
              When --from is omitted, restore defaults to the current machine snapshot when
              it exists. Otherwise it offers machine snapshots from the dot-files repo.
              It restores configured paths plus that machine's persisted dynamic paths.
              Missing real GitHub repositories from the selected snapshot are cloned back
              into the configured GitHub root without overwriting existing paths.
              Newer local files are kept unless --force is used.
              Homebrew and VS Code extension differences are printed as manual commands.
              Encrypted secrets are not restored automatically; restore prints the secrets
              commands when an encrypted snapshot exists.

            EXAMPLES:
              \(config.scriptName) restore
              \(config.scriptName) restore --select
              \(config.scriptName) restore --list-machines
              \(config.scriptName) restore --from old-mbp
              \(config.scriptName) restore --from old-mbp --force
              MAC_SYNC_DRY_RUN=1 \(config.scriptName) restore --from old-mbp
            """
        )
    }

    private func usageSecrets() {
        print(
            """
            USAGE:
              \(config.scriptName) secrets <command>

            COMMANDS:
              init       Create or reuse this Mac's Keychain age identity
              sync       Update the encrypted secret snapshot and push machine state
              list       List files in an encrypted secret snapshot
              restore    Restore files from an encrypted secret snapshot
              test       Check Keychain identity and current archive decryption
              help       Show this help text

            OPTIONS:
              list --from <machine>
              restore --from <machine> [--force]

            NOTES:
              Private age identity is stored in Apple Keychain under the configured service.
              Public recipients are stored in config/age-recipients.txt.
              Secret paths are configured in config/secret-paths.txt.
              Normal restore never decrypts secrets automatically.

            EXAMPLES:
              \(config.scriptName) secrets init
              \(config.scriptName) secrets sync
              \(config.scriptName) secrets list --from old-mbp
              \(config.scriptName) secrets restore --from old-mbp
              \(config.scriptName) secrets restore --from old-mbp --force
              \(config.scriptName) secrets test
            """
        )
    }

    private func usagePackages() {
        print(
            """
            USAGE:
              \(config.scriptName) packages <command>

            COMMANDS:
              sync       Update this Mac's Homebrew snapshot and push machine state
              diff       Print Homebrew commands needed to match a machine snapshot
              install    Run brew bundle from a machine snapshot
              list       Show the Homebrew snapshot files for a machine
              help       Show this help text

            OPTIONS:
              diff --from <machine>
              install --from <machine> [--formulae-only] [--admin-user <user>]
              list --from <machine>

            EXAMPLES:
              \(config.scriptName) packages sync
              \(config.scriptName) packages diff --from old-mbp
              \(config.scriptName) packages install --from old-mbp
              \(config.scriptName) packages install --from old-mbp --formulae-only
              \(config.scriptName) packages install --from old-mbp --admin-user adm-sclarke
            """
        )
    }

    private func usageEditor() {
        print(
            """
            USAGE:
              \(config.scriptName) editor <command>

            COMMANDS:
              sync       Update this Mac's VS Code extension snapshot and push machine state
              diff       Print VS Code extension changes needed to match a machine snapshot
              install    Reconcile VS Code extensions to a machine snapshot
              list       Show the VS Code extension snapshot for a machine
              help       Show this help text

            OPTIONS:
              diff --from <machine>
              install --from <machine>
              list --from <machine>

            EXAMPLES:
              \(config.scriptName) editor sync
              \(config.scriptName) editor diff --from old-mbp
              \(config.scriptName) editor install --from old-mbp
            """
        )
    }

    private func usageManifest() {
        print(
            """
            USAGE:
              \(config.scriptName) manifest <command>

            COMMANDS:
              list        Print the full backup manifest, including dynamic paths
              configured  Print only the configured backup manifest
              dynamic     Print only dynamically discovered backup paths
              source      Print the active configured manifest source
              help        Show this help text

            EXAMPLES:
              \(config.scriptName) manifest list
              \(config.scriptName) manifest configured
              \(config.scriptName) manifest source
            """
        )
    }

    private func cmdHelp(_ args: [String]) throws {
        guard args.count <= 1 else {
            try fail("too many help arguments", code: 2, usage: true)
        }
        switch args.first ?? "" {
        case "":
            usage()
        case "restore":
            usageRestore()
        case "secrets":
            usageSecrets()
        case "packages":
            usagePackages()
        case "editor":
            usageEditor()
        case "manifest":
            usageManifest()
        case "help", "-h", "--help":
            usage()
        default:
            try fail("unknown help topic: \(args.first!)", code: 2, usage: true)
        }
    }

    private func errorMessage(_ message: String) {
        errorCount += 1
        let line = "ERROR: \(message)"
        if runActive { errorMessages.append(line) }
        fputs("\(line)\n", stderr)
    }

    private func warning(_ message: String) {
        warningCount += 1
        let line = "WARN: \(message)"
        if runActive { warningMessages.append(line) }
        fputs("\(line)\n", stderr)
    }

    private func fail(_ message: String, code: Int = 1, usage: Bool = false) throws -> Never {
        errorMessage(message)
        if usage { self.usage() }
        throw ExitError(code: code)
    }

    private func info(_ message: String = "") {
        print(message)
    }

    private var pendingMark: String { "\u{2813}" }
    private var doneMark: String { "\u{2714}\u{FE0E}" }

    private func progressPending(_ message: String) {
        info("\(pendingMark) \(message)")
    }

    private func progressDone(_ message: String) {
        info("\(doneMark) \(message)")
    }

    private func runWithProgress(_ message: String, body: () throws -> Void) rethrows {
        progressPending(message)
        try body()
    }

    private func runWithProgressCommand(
        _ message: String,
        _ executable: String,
        _ arguments: [String],
        workingDirectory: String? = nil
    ) -> Bool {
        progressPending(message)
        let result = runner.run(executable, arguments, workingDirectory: workingDirectory)
        lastCommandOutput = result.combinedOutput
        return result.status == 0
    }

    private func printProgressCommandOutput() {
        guard !lastCommandOutput.isEmpty else { return }
        fputs(lastCommandOutput.hasSuffix("\n") ? lastCommandOutput : "\(lastCommandOutput)\n", stderr)
    }

    private func need(_ command: String) throws {
        guard runner.commandExists(command) else {
            try fail("missing required command: \(command)")
        }
    }

    private func enabled(_ value: String, noValues: Set<String> = ["0", "off", "OFF", "false", "FALSE"]) -> Bool {
        !noValues.contains(value)
    }

    private func dynamicRefsEnabled() -> Bool { enabled(config.dynamicRefs) }
    private func homebrewSyncEnabled() -> Bool { enabled(config.homebrewSync) }
    private func vscodeExtensionsSyncEnabled() -> Bool { enabled(config.vscodeExtensionsSync) }
    private func githubReposSyncEnabled() -> Bool { enabled(config.githubReposSync) }
    private func secretsSyncEnabled() -> Bool { enabled(config.secretsSync) }
    private func selfUpdateEnabled() -> Bool {
        enabled(config.selfUpdate, noValues: ["0", "off", "OFF", "false", "FALSE", "no", "NO"])
    }

    private func validateIntRange(name: String, value: String, min: Int, max: Int) throws {
        guard let number = Int(value), number >= min, number <= max else {
            try fail("\(name) must be an integer from \(min) to \(max)", code: 2)
        }
    }

    private func pathExists(_ path: String) -> Bool {
        fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func ensureDirectory(_ path: String) throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func removePath(_ path: String) throws {
        guard pathExists(path) else { return }
        try fm.removeItem(atPath: path)
    }

    private func readText(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeText(_ path: String, _ text: String) throws {
        try ensureDirectory((path as NSString).deletingLastPathComponent)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func tempPath(prefix: String, directory: Bool = false) throws -> String {
        let root = environment["TMPDIR"] ?? "/tmp"
        let path = "\(root)/\(prefix).\(UUID().uuidString)"
        if directory {
            try ensureDirectory(path)
        } else {
            fm.createFile(atPath: path, contents: Data())
        }
        return path
    }

    private func readConfigLines(_ path: String) -> [String] {
        readText(path).splitLines().compactMap { line in
            let trimmed = line.trimmed
            return trimmed.isEmpty || trimmed.hasPrefix("#") ? nil : line
        }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmed.isEmpty })).sorted()
    }

    private func sourcePath(for rel: String) -> String {
        rel.hasPrefix("/") ? rel : "\(config.homeDir)/\(rel)"
    }

    private func destPath(for rel: String) -> String {
        rel.hasPrefix("/") ? "\(config.machineAbsoluteDir)\(rel)" : "\(config.machineHomeDir)/\(rel)"
    }

    private func snapshotPath(machine: String, rel: String) -> String {
        rel.hasPrefix("/") ? "\(config.machinesRootDir)/\(machine)/absolute\(rel)" : "\(config.machinesRootDir)/\(machine)/home/\(rel)"
    }

    private func checkRuntime() throws {
        for command in ["cksum", "comm", "find", "git", "rsync", "sed", "awk", "sort", "wc"] {
            try need(command)
        }
        guard isDirectory("\(config.repoDir)/.git") else {
            errorMessage("not a git repository: \(config.repoDir)")
            errorMessage("clone or create the repo there, or set MAC_SYNC_REPO")
            throw ExitError(code: 1)
        }
        guard isDirectory("\(config.machinesRepoDir)/.git") else {
            errorMessage("not a git repository: \(config.machinesRepoDir)")
            errorMessage("clone https://github.com/stephenlclarke/dot-files there, or set MAC_SYNC_MACHINES_REPO")
            throw ExitError(code: 1)
        }
    }

    private func repoHasOrigin(_ repo: String? = nil) -> Bool {
        runner.run("git", ["-C", repo ?? config.repoDir, "remote", "get-url", "origin"]).status == 0
    }

    private func repoClean(_ repo: String? = nil) -> Bool {
        runner.run("git", ["-C", repo ?? config.repoDir, "status", "--porcelain"]).stdout.trimmed.isEmpty
    }

    private func repoPathClean(_ repo: String, _ pathspec: String) -> Bool {
        runner.run("git", ["-C", repo, "status", "--porcelain", "--", pathspec]).stdout.trimmed.isEmpty
    }

    private func repoCommitVersion(_ repo: String? = nil) -> String {
        let result = runner.run("git", ["-C", repo ?? config.repoDir, "rev-parse", "--short", "HEAD"])
        return result.status == 0 ? result.stdout.trimmed : "unknown"
    }

    private func branchHasUpstream(_ repo: String) -> Bool {
        runner.run("git", ["-C", repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]).status == 0
    }

    private func branchAheadOfUpstream(_ repo: String) -> Bool {
        guard branchHasUpstream(repo) else { return false }
        let result = runner.run("git", ["-C", repo, "rev-list", "--count", "@{u}..HEAD"])
        return result.stdout.trimmed != "0"
    }

    private func configuredManifestPathsFromFile() throws -> [String] {
        guard fm.fileExists(atPath: config.pathsFile) else {
            try fail("missing paths file: \(config.pathsFile)")
        }
        return readConfigLines(config.pathsFile)
    }

    private func configuredManifestPathsFromDotFiles() -> [String]? {
        guard fm.fileExists(atPath: "\(config.machinesRepoDir)/Makefile"), runner.commandExists("make") else {
            return nil
        }
        let result = runner.run(
            "make",
            ["--no-print-directory", "-s", "-C", config.machinesRepoDir, "print-mac-sync-paths"],
            extraEnvironment: ["BASH_ENV": "", "ENV": ""]
        )
        guard result.status == 0 else { return nil }
        let lines = result.stdout.splitLines().filter { !$0.trimmed.isEmpty }
        guard !lines.isEmpty else { return nil }
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    private func configuredManifestPaths() throws -> [String] {
        switch config.manifestSource {
        case "auto":
            if let paths = configuredManifestPathsFromDotFiles() {
                return paths
            }
            return try configuredManifestPathsFromFile()
        case "dot-files":
            guard let paths = configuredManifestPathsFromDotFiles() else {
                try fail("dot-files manifest source is unavailable: \(config.machinesRepoDir)/Makefile")
            }
            return paths
        case "config":
            return try configuredManifestPathsFromFile()
        default:
            try fail("MAC_SYNC_MANIFEST_SOURCE must be auto, dot-files, or config", code: 2)
        }
    }

    private func configuredManifestSourceLabel() -> String {
        switch config.manifestSource {
        case "auto":
            return configuredManifestPathsFromDotFiles() == nil ? "config" : "dot-files"
        case "dot-files", "config":
            return config.manifestSource
        default:
            return "invalid"
        }
    }

    private func storedDynamicManifestPaths(_ file: String? = nil) -> [String] {
        readConfigLines(file ?? config.dynamicPathsFile)
    }

    private func pathsOverlap(_ left: String, _ right: String) -> Bool {
        left == right || left.hasPrefix("\(right)/") || right.hasPrefix("\(left)/")
    }

    private func pathOverlaps(_ rel: String, listedIn file: String) -> Bool {
        readConfigLines(file).contains { pathsOverlap(rel, $0) }
    }

    private func homeRelativePath(_ path: String) -> String? {
        guard path.hasPrefix("\(config.homeDir)/") else { return nil }
        var rel = String(path.dropFirst(config.homeDir.count + 1))
        if rel.hasPrefix("./") { rel.removeFirst(2) }
        while rel.hasSuffix("/") { rel.removeLast() }
        return rel.isEmpty ? nil : rel
    }

    private func safeDynamicRelPath(_ rel: String) -> Bool {
        if rel.isEmpty || rel.hasPrefix("/") || rel.hasPrefix("../") || rel.contains("/../") || rel == "." {
            return false
        }
        guard rel.hasPrefix(".") || rel.hasPrefix("bin/") || rel.hasPrefix("Library/Application Support/Code/User/") else {
            return false
        }
        let blockedExact = [
            ".CFUserTextEncoding", ".DS_Store", ".bash_history", ".zsh_history",
            ".viminfo", ".vault-pass", ".aws/credentials", ".config/ansible/vault.pass",
            ".config/argocd/config", ".config/gh/hosts.yml", ".docker/config.json",
            ".git-credentials", ".kube/config", ".netrc", ".npmrc", ".pypirc",
            ".gem/credentials", ".codex/auth.json", ".codex/installation_id",
        ]
        if blockedExact.contains(rel) || rel.hasPrefix(".zcompdump") {
            return false
        }
        for prefix in [".cache/", ".local/", ".Trash/", ".cargo/bin/", ".colima/_lima/", ".secrets/", ".codex-secrets/"] {
            if rel == String(prefix.dropLast()) || rel.hasPrefix(prefix) { return false }
        }
        if rel.hasPrefix(".gnupg/") && rel != ".gnupg/common.conf" {
            return false
        }
        if rel.hasPrefix(".ssh/") {
            if rel == ".ssh/config" || rel.hasSuffix(".pub") { return true }
            return false
        }
        for suffix in [".pem", ".ppk", ".p12", ".pfx", ".key"] where rel.hasSuffix(suffix) {
            return false
        }
        return true
    }

    private func dynamicSyncRoot(for rel: String) -> String {
        let parts = rel.split(separator: "/").map(String.init)
        if parts.count >= 3, (rel.hasPrefix(".config/") || rel.hasPrefix(".zsh/")) {
            return "\(parts[0])/\(parts[1])"
        }
        if parts.count >= 4, rel.hasPrefix(".tmux/plugins/") {
            return "\(parts[0])/\(parts[1])/\(parts[2])"
        }
        return rel
    }

    private func isTextFile(_ file: String) -> Bool {
        guard fm.fileExists(atPath: file), !isDirectory(file) else { return false }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else { return false }
        return data.isEmpty || !data.prefix(1024).contains(0)
    }

    private func extractReferenceCandidates(from file: String) -> [String] {
        let escapedHome = NSRegularExpression.escapedPattern(for: config.homeDir)
        let referencePattern = "\(escapedHome)/(\\.|bin/|Library/Application Support/Code/User/)[^\"'\\s;|<>)]*"
        let regex = try? NSRegularExpression(pattern: referencePattern)
        let loopRegex = try? NSRegularExpression(pattern: #"for\s+shell_config\s+in\s+([^;]+)"#)
        return readText(file).splitLines().flatMap { rawLine -> [String] in
            var line = rawLine
            if !line.contains("shellcheck source=") {
                line = line.replacingOccurrences(of: #"\s+#.*$"#, with: "", options: .regularExpression)
            }
            line = line.replacingOccurrences(of: "${HOME}", with: config.homeDir)
                .replacingOccurrences(of: "$HOME", with: config.homeDir)
                .replacingOccurrences(of: "~", with: config.homeDir)
            var matches: [String] = []
            let nsLine = line as NSString
            if let loopRegex,
               let match = loopRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
               match.numberOfRanges > 1 {
                let names = nsLine.substring(with: match.range(at: 1)).split { $0 == " " || $0 == "\t" }
                matches.append(contentsOf: names.filter { $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }.map { "\(config.homeDir)/.\($0)" })
            }
            if let regex {
                for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                    let candidate = nsLine.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ",:"))
                    matches.append(candidate)
                }
            }
            return matches
        }
    }

    private func dynamicHomeDotfiles() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: config.homeDir) else { return [] }
        return entries.sorted().compactMap { entry in
            guard entry.hasPrefix(".") else { return nil }
            let path = "\(config.homeDir)/\(entry)"
            guard !isDirectory(path), let rel = homeRelativePath(path), safeDynamicRelPath(rel) else { return nil }
            return path
        }
    }

    private func dynamicManifestPaths() -> [String] {
        guard dynamicRefsEnabled() else { return [] }
        var discovered: [String] = []
        var scanQueue = dynamicHomeDotfiles()
        var seen = Set<String>()
        var index = 0
        while index < scanQueue.count {
            let file = scanQueue[index]
            index += 1
            guard seen.insert(file).inserted, isTextFile(file) else { continue }
            for ref in extractReferenceCandidates(from: file) {
                guard let rel = homeRelativePath(ref), safeDynamicRelPath(rel) else { continue }
                let syncRel = dynamicSyncRoot(for: rel)
                guard safeDynamicRelPath(syncRel), pathExists(sourcePath(for: syncRel)) else { continue }
                if !discovered.contains(syncRel) {
                    discovered.append(syncRel)
                }
                let refSource = sourcePath(for: rel)
                if fm.fileExists(atPath: refSource), !scanQueue.contains(refSource) {
                    scanQueue.append(refSource)
                }
            }
        }
        return discovered
    }

    private func writeDynamicPathsManifest(_ paths: [String]) throws {
        try writeText(
            config.dynamicPathsFile,
            "# Generated by mac-sync. Do not edit.\n# HOME-relative dynamic paths discovered from dotfile references.\n" + paths.joined(separator: "\n") + (paths.isEmpty ? "" : "\n")
        )
    }

    private func dynamicExtraPaths(dynamic: [String], configured: [String]) -> [String] {
        dynamic.filter { rel in
            safeDynamicRelPath(rel) && !configured.contains { pathsOverlap(rel, $0) }
        }
    }

    private func pruneStaleDynamicPaths(currentDynamic: [String], configured: [String]) throws {
        guard dynamicRefsEnabled(), fm.fileExists(atPath: config.dynamicPathsFile) else { return }
        for rel in storedDynamicManifestPaths() where safeDynamicRelPath(rel) {
            if currentDynamic.contains(where: { pathsOverlap(rel, $0) }) { continue }
            if configured.contains(where: { pathsOverlap(rel, $0) }) { continue }
            let dest = destPath(for: rel)
            guard pathExists(dest) else { continue }
            if config.dryRun == "1" {
                info("would remove stale dynamic snapshot: \(dest)")
            } else {
                try removePath(dest)
                info("removed stale dynamic snapshot: \(dest)")
            }
        }
    }

    private func manifestPaths() throws -> [String] {
        var seen = Set<String>()
        return (try configuredManifestPaths() + dynamicManifestPaths()).filter { !$0.trimmed.isEmpty && seen.insert($0).inserted }
    }

    private func restoreManifestPaths(machine: String) throws -> [String] {
        var seen = Set<String>()
        let dynamicFile = "\(config.machinesRootDir)/\(machine)/dynamic-sync-paths.txt"
        return (try configuredManifestPaths() + storedDynamicManifestPaths(dynamicFile)).filter { !$0.trimmed.isEmpty && seen.insert($0).inserted }
    }

    private func machineSnapshotNames() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: config.machinesRootDir) else { return [] }
        return entries.filter { isDirectory("\(config.machinesRootDir)/\($0)") }.sorted()
    }

    private func resolveMachineSnapshotName(_ requested: String) -> String? {
        if isDirectory("\(config.machinesRootDir)/\(requested)") { return requested }
        let lower = requested.lowercased()
        let matches = machineSnapshotNames().filter { $0.lowercased() == lower }
        return matches.count == 1 ? matches[0] : nil
    }

    private func machineSnapshotSuggestionLines() {
        info("Available machine snapshots in \(config.machinesRootDir):")
        let names = machineSnapshotNames()
        if names.isEmpty {
            info("  (none)")
            return
        }
        for name in names {
            info(name == config.machineName ? "  \(name) (current default)" : "  \(name)")
        }
    }

    private func resolveRequestedMachine(_ requested: String) throws -> String {
        guard MacSyncPaths.safeMachineName(requested) else {
            try fail("invalid machine name: \(requested)", code: 2)
        }
        guard let resolved = resolveMachineSnapshotName(requested) else {
            machineSnapshotSuggestionLines()
            try fail("missing machine snapshot: \(config.machinesRootDir)/\(requested)")
        }
        return resolved
    }

    private func homebrewDir(for machine: String) -> String {
        "\(config.machinesRootDir)/\(machine)/homebrew"
    }

    private func homebrewListFileLines(_ file: String) -> [String] {
        readConfigLines(file)
    }

    private func currentHomebrewList(_ kind: String) -> [String] {
        guard runner.commandExists("brew") else { return [] }
        let result: CommandResult
        switch kind {
        case "taps":
            result = runner.run("brew", ["tap"])
        case "formulae":
            result = runner.run("brew", ["list", "--formula", "-1"])
        case "casks":
            result = runner.run("brew", ["list", "--cask", "-1"])
        case "outdated-formulae":
            result = runner.run("brew", ["outdated", "--formula", "--quiet"])
        case "outdated-casks":
            result = runner.run("brew", ["outdated", "--cask", "--quiet"])
        default:
            return []
        }
        return uniqueSorted(result.stdout.splitLines().filter { !$0.trimmed.isEmpty })
    }

    private func brewfileQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func writeHomebrewSnapshot() throws {
        try ensureDirectory(config.homebrewDir)
        let lists: [(String, String, [String])] = [
            ("taps.txt", "Installed Homebrew taps.", currentHomebrewList("taps")),
            ("formulae.txt", "Installed Homebrew formulae.", currentHomebrewList("formulae")),
            ("casks.txt", "Installed Homebrew casks.", currentHomebrewList("casks")),
        ]
        for (file, description, values) in lists {
            try writeText(
                "\(config.homebrewDir)/\(file)",
                "# Generated by mac-sync. Do not edit.\n# \(description)\n" + values.joined(separator: "\n") + (values.isEmpty ? "" : "\n")
            )
        }
        try writeHomebrewBrewfile(homebrewDir: config.homebrewDir, formulaeOnly: false, target: "\(config.homebrewDir)/Brewfile", restore: false)
    }

    private func writeHomebrewBrewfile(homebrewDir: String, formulaeOnly: Bool, target: String, restore: Bool) throws {
        var lines = [restore ? "# Generated by mac-sync for restore." : "# Generated by mac-sync. Do not edit."]
        lines += homebrewListFileLines("\(homebrewDir)/taps.txt").map { #"tap "\#(brewfileQuote($0))""# }
        lines += homebrewListFileLines("\(homebrewDir)/formulae.txt").map { #"brew "\#(brewfileQuote($0))""# }
        if !formulaeOnly {
            lines += homebrewListFileLines("\(homebrewDir)/casks.txt").map { #"cask "\#(brewfileQuote($0))""# }
        }
        try writeText(target, lines.joined(separator: "\n") + "\n")
    }

    private func syncHomebrewPackages() throws {
        guard homebrewSyncEnabled() else { return }
        guard runner.commandExists("brew") else {
            warning("Homebrew not found; skipping Homebrew package snapshot")
            return
        }
        if config.dryRun == "1" {
            progressPending("would update Homebrew package snapshot: \(config.homebrewDir)")
            return
        }
        try runWithProgress("updating Homebrew package snapshot") {
            try writeHomebrewSnapshot()
        }
        progressDone("updated Homebrew package snapshot: \(config.homebrewDir)")
    }

    private func printBrewCommand(prefix: String, values: [String]) {
        guard !values.isEmpty else { return }
        info("  \(prefix) \(values.map(ShellQuoter.quote).joined(separator: " "))")
    }

    private func printHomebrewRestoreCommands(machine: String) {
        guard homebrewSyncEnabled() else { return }
        let dir = homebrewDir(for: machine)
        guard fm.fileExists(atPath: "\(dir)/taps.txt") || fm.fileExists(atPath: "\(dir)/formulae.txt") || fm.fileExists(atPath: "\(dir)/casks.txt") else {
            return
        }
        let desiredTaps = uniqueSorted(homebrewListFileLines("\(dir)/taps.txt"))
        let desiredFormulae = uniqueSorted(homebrewListFileLines("\(dir)/formulae.txt"))
        let desiredCasks = uniqueSorted(homebrewListFileLines("\(dir)/casks.txt"))
        let currentTaps = Set(currentHomebrewList("taps"))
        let currentFormulae = Set(currentHomebrewList("formulae"))
        let currentCasks = Set(currentHomebrewList("casks"))
        let outdatedFormulae = Set(currentHomebrewList("outdated-formulae"))
        let outdatedCasks = Set(currentHomebrewList("outdated-casks"))

        let missingTaps = desiredTaps.filter { !currentTaps.contains($0) }
        let missingFormulae = desiredFormulae.filter { !currentFormulae.contains($0) }
        let missingCasks = desiredCasks.filter { !currentCasks.contains($0) }
        let upgradeFormulae = desiredFormulae.filter { outdatedFormulae.contains($0) }
        let upgradeCasks = desiredCasks.filter { outdatedCasks.contains($0) }
        guard !missingTaps.isEmpty || !missingFormulae.isEmpty || !missingCasks.isEmpty || !upgradeFormulae.isEmpty || !upgradeCasks.isEmpty else {
            return
        }
        if !runner.commandExists("brew") {
            warning("Homebrew not found; install Homebrew before running these commands")
        }
        info()
        info("Homebrew packages differ from the \(machine) snapshot.")
        info("Run these commands manually:")
        info("  brew update")
        printBrewCommand(prefix: "brew tap", values: missingTaps)
        printBrewCommand(prefix: "brew install", values: missingFormulae)
        printBrewCommand(prefix: "brew install --cask", values: missingCasks)
        printBrewCommand(prefix: "brew upgrade", values: upgradeFormulae)
        printBrewCommand(prefix: "brew upgrade --cask", values: upgradeCasks)
    }

    private func installHomebrewSnapshot(machine: String, formulaeOnly: Bool, adminUser: String) throws {
        let dir = homebrewDir(for: machine)
        guard isDirectory(dir) else { try fail("missing Homebrew snapshot: \(dir)") }
        guard runner.commandExists("brew") else { try fail("missing dependency: brew") }
        let brewfile = try tempPath(prefix: "mac-sync-Brewfile")
        defer { try? removePath(brewfile) }
        try writeHomebrewBrewfile(homebrewDir: dir, formulaeOnly: formulaeOnly, target: brewfile, restore: true)
        if config.dryRun == "1" {
            info("would run brew bundle install from: \(dir)")
            return
        }
        if !adminUser.isEmpty {
            let brewPath = runner.shell("command -v brew").stdout.trimmed
            let tmpBrewfile = try tempPath(prefix: "mac-sync-Brewfile-admin")
            try fm.copyItem(atPath: brewfile, toPath: tmpBrewfile)
            info("running brew bundle as admin user \(adminUser)")
            let commandLine = "\(ShellQuoter.quote(brewPath)) bundle install --file=\(ShellQuoter.quote(tmpBrewfile)) \(config.brewBundleInstallFlags)"
            let result = runner.run("/usr/bin/su", ["-l", adminUser, "-c", commandLine])
            try? removePath(tmpBrewfile)
            if result.status != 0 { throw ExitError(code: Int(result.status)) }
            return
        }
        let flags = config.brewBundleInstallFlags.split(separator: " ").map(String.init)
        let result = runner.run("brew", ["bundle", "install", "--file=\(brewfile)"] + flags)
        if result.status != 0 {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
    }

    private func listHomebrewSnapshot(machine: String) throws {
        let dir = homebrewDir(for: machine)
        guard isDirectory(dir) else { try fail("missing Homebrew snapshot: \(dir)") }
        for file in ["taps.txt", "formulae.txt", "casks.txt", "Brewfile"] {
            let path = "\(dir)/\(file)"
            guard fm.fileExists(atPath: path) else { continue }
            info(path)
            for line in readText(path).splitLines() {
                info("  \(line)")
            }
        }
    }

    private func vscodeExtensionsFile(for machine: String) -> String {
        "\(config.machinesRootDir)/\(machine)/editor/vscode-extensions.txt"
    }

    private func currentVscodeExtensions() -> [String] {
        guard runner.commandExists("code") else { return [] }
        return uniqueSorted(runner.run("code", ["--list-extensions", "--show-versions"]).stdout.splitLines().filter { !$0.trimmed.isEmpty })
    }

    private func writeVscodeExtensionsSnapshot() throws {
        try writeText(
            config.vscodeExtensionsFile,
            "# Generated by mac-sync. Do not edit.\n# Installed VS Code extensions with versions.\n" + currentVscodeExtensions().joined(separator: "\n") + "\n"
        )
    }

    private func syncVscodeExtensions() throws {
        guard vscodeExtensionsSyncEnabled() else { return }
        guard runner.commandExists("code") else {
            warning("VS Code CLI not found; skipping VS Code extension snapshot")
            return
        }
        if config.dryRun == "1" {
            progressPending("would update VS Code extension snapshot: \(config.vscodeExtensionsFile)")
            return
        }
        try runWithProgress("updating VS Code extension snapshot") {
            try writeVscodeExtensionsSnapshot()
        }
        progressDone("updated VS Code extension snapshot: \(config.vscodeExtensionsFile)")
    }

    private func vscodeExtensionLines(_ file: String) -> [String] {
        uniqueSorted(readConfigLines(file))
    }

    private func vscodeExtensionDiff(snapshotFile: String) -> (install: [String], remove: [String]) {
        let desired = Set(vscodeExtensionLines(snapshotFile))
        let current = Set(currentVscodeExtensions())
        return (Array(desired.subtracting(current)).sorted(), Array(current.subtracting(desired)).sorted())
    }

    private func printVscodeExtensionRestoreCommands(machine: String) {
        guard vscodeExtensionsSyncEnabled() else { return }
        let file = vscodeExtensionsFile(for: machine)
        guard fm.fileExists(atPath: file) else { return }
        let diff = vscodeExtensionDiff(snapshotFile: file)
        guard !diff.install.isEmpty || !diff.remove.isEmpty else { return }
        info()
        info("VS Code extensions differ from the \(machine) snapshot.")
        info("Run these commands manually:")
        for ext in diff.remove {
            info("  code --uninstall-extension \(ShellQuoter.quote(String(ext.split(separator: "@").first ?? "")))")
        }
        for ext in diff.install {
            info("  code --install-extension \(ShellQuoter.quote(ext))")
        }
    }

    private func installVscodeExtensionsSnapshot(machine: String) throws {
        let file = vscodeExtensionsFile(for: machine)
        guard fm.fileExists(atPath: file) else { try fail("missing VS Code extension snapshot: \(file)") }
        guard runner.commandExists("code") else { try fail("missing dependency: code") }
        let diff = vscodeExtensionDiff(snapshotFile: file)
        for ext in diff.remove {
            let extID = String(ext.split(separator: "@").first ?? "")
            info("remove VS Code extension \(extID)")
            if config.dryRun != "1" {
                _ = runner.run("code", ["--uninstall-extension", extID])
            }
        }
        for ext in diff.install {
            info("install VS Code extension \(ext)")
            if config.dryRun != "1" {
                _ = runner.run("code", ["--install-extension", ext])
            }
        }
        info("applied VS Code extensions from \(file)")
    }

    private func githubRepositoriesFile(for machine: String) -> String {
        "\(config.machinesRootDir)/\(machine)/github-repositories/repositories.txt"
    }

    private func githubRemoteForRepo(_ repoDir: String) -> String? {
        let origin = runner.run("git", ["-C", repoDir, "remote", "get-url", "origin"])
        if origin.status == 0, let normalized = MacSyncPaths.normalizeGitHubRemoteURL(origin.stdout.trimmed) {
            return normalized
        }
        let remotes = runner.run("git", ["-C", repoDir, "remote"]).stdout.splitLines().filter { $0 != "origin" }.sorted()
        for remote in remotes {
            let result = runner.run("git", ["-C", repoDir, "remote", "get-url", remote])
            if result.status == 0, let normalized = MacSyncPaths.normalizeGitHubRemoteURL(result.stdout.trimmed) {
                return normalized
            }
        }
        return nil
    }

    private func githubRepositoryCandidateDirs(root: String) -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var candidates: [String] = []
        for entry in entries.sorted() where entry != ".git" {
            let child = "\(root)/\(entry)"
            guard isDirectory(child) else { continue }
            if pathExists("\(child)/.git") {
                candidates.append(child)
            } else {
                candidates += githubRepositoryCandidateDirs(root: child)
            }
        }
        return candidates
    }

    private func githubRepoHasParentWorktree(repoReal: String, rootReal: String) -> Bool {
        var parent = (repoReal as NSString).deletingLastPathComponent
        while parent != rootReal && parent != "/" && !parent.isEmpty {
            let top = runner.run("git", ["-C", parent, "rev-parse", "--show-toplevel"]).stdout.trimmed
            if !top.isEmpty {
                let ancestor = Config.realpathExisting(top)
                if ancestor != repoReal, repoReal.hasPrefix("\(ancestor)/") { return true }
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return false
    }

    private func localGitHubRepositoryLines() -> [String] {
        guard isDirectory(config.githubRootDir) else { return [] }
        let rootReal = Config.realpathExisting(config.githubRootDir)
        var lines: [String] = []
        for repoDir in githubRepositoryCandidateDirs(root: config.githubRootDir) {
            let repoReal = Config.realpathExisting(repoDir)
            guard repoReal.hasPrefix("\(rootReal)/") else { continue }
            let rel = String(repoReal.dropFirst(rootReal.count + 1))
            guard MacSyncPaths.safeGitHubRepositoryRelativePath(rel) else { continue }
            guard runner.run("git", ["-C", repoDir, "rev-parse", "--is-inside-work-tree"]).status == 0 else { continue }
            let top = runner.run("git", ["-C", repoDir, "rev-parse", "--show-toplevel"]).stdout.trimmed
            guard !top.isEmpty, Config.realpathExisting(top) == repoReal else { continue }
            guard !githubRepoHasParentWorktree(repoReal: repoReal, rootReal: rootReal) else { continue }
            guard runner.run("git", ["-C", repoDir, "rev-parse", "--show-superproject-working-tree"]).stdout.trimmed.isEmpty else { continue }
            guard let cloneURL = githubRemoteForRepo(repoDir) else { continue }
            lines.append("\(rel)\t\(cloneURL)")
        }
        return uniqueSorted(lines)
    }

    private func writeGitHubRepositoriesSnapshot() throws {
        try writeText(
            config.githubReposFile,
            "# Generated by mac-sync. Do not edit.\n# Format: relative-path<TAB>github-clone-url\n" + localGitHubRepositoryLines().joined(separator: "\n") + "\n"
        )
    }

    private func syncGitHubRepositories() throws {
        guard githubReposSyncEnabled() else { return }
        if config.dryRun == "1" {
            progressPending("would update GitHub repository snapshot: \(config.githubReposFile)")
            return
        }
        try runWithProgress("updating GitHub repository snapshot") {
            try writeGitHubRepositoriesSnapshot()
        }
        progressDone("updated GitHub repository snapshot: \(config.githubReposFile)")
    }

    private func restoreGitHubRepositories(machine: String) throws {
        guard githubReposSyncEnabled() else { return }
        let file = githubRepositoriesFile(for: machine)
        guard fm.fileExists(atPath: file) else { return }
        info("restoring GitHub repositories from: \(file)")
        if config.dryRun != "1" { try ensureDirectory(config.githubRootDir) }
        for rawLine in readText(file).splitLines() {
            if rawLine.isEmpty || rawLine.hasPrefix("#") { continue }
            let parts = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                warning("skip malformed GitHub repository manifest line for: \(parts.first ?? rawLine)")
                continue
            }
            let localDir = parts[0]
            let cloneURL = parts[1]
            guard MacSyncPaths.safeGitHubRepositoryRelativePath(localDir) else {
                warning("skip unsafe GitHub repository relative path: \(localDir)")
                continue
            }
            guard let normalized = MacSyncPaths.normalizeGitHubRemoteURL(cloneURL) else {
                warning("skip non-GitHub repository URL for \(localDir): \(cloneURL)")
                continue
            }
            let target = "\(config.githubRootDir)/\(localDir)"
            if pathExists(target) {
                if runner.run("git", ["-C", target, "rev-parse", "--is-inside-work-tree"]).status == 0 {
                    info("existing GitHub repo: \(target)")
                } else {
                    warning("skip clone over existing non-repo path: \(target)")
                }
                continue
            }
            if config.dryRun == "1" {
                info("would clone GitHub repo: \(normalized) -> \(target)")
                continue
            }
            info("clone GitHub repo: \(normalized) -> \(target)")
            try ensureDirectory((target as NSString).deletingLastPathComponent)
            if runner.run("git", ["clone", normalized, target]).status != 0 {
                warning("failed to clone GitHub repo: \(normalized)")
            }
        }
    }

    private func secretsArchive(for machine: String) -> String {
        "\(config.machinesRootDir)/\(machine)/secrets/secrets.tar.gz.age"
    }

    private func safeSecretRelPath(_ rel: String) -> Bool {
        !(rel.isEmpty || rel.hasPrefix("/") || rel == ".." || rel.hasPrefix("../") || rel.contains("/../") || rel.hasSuffix("/..") || rel == "." || rel.hasPrefix("-"))
    }

    private func secretManifestPaths() -> [String] {
        readConfigLines(config.secretPathsFile).filter { rel in
            if safeSecretRelPath(rel) { return true }
            warning("skip unsafe secret path: \(rel)")
            return false
        }
    }

    private func ageRecipients() -> [String] {
        readConfigLines(config.ageRecipientsFile)
    }

    private func ageRecipientsPresent() -> Bool {
        !ageRecipients().isEmpty
    }

    private func appendUniqueConfigLine(file: String, line: String) throws {
        try ensureDirectory((file as NSString).deletingLastPathComponent)
        if !fm.fileExists(atPath: file) {
            fm.createFile(atPath: file, contents: Data())
        }
        let existing = readText(file).splitLines()
        if !existing.contains(line) {
            let prefix = readText(file)
            try writeText(file, prefix + (prefix.hasSuffix("\n") || prefix.isEmpty ? "" : "\n") + line + "\n")
        }
    }

    private func ensureSecretPathsFile() throws {
        guard !fm.fileExists(atPath: config.secretPathsFile) else { return }
        try writeText(
            config.secretPathsFile,
            "# Paths are relative to $HOME and are encrypted before syncing.\n# Keep this list narrow; the decrypted archive restores into $HOME.\n.ssh\n.secrets\n"
        )
    }

    private func ensureAgeRecipientsFile() throws {
        guard !fm.fileExists(atPath: config.ageRecipientsFile) else { return }
        try writeText(
            config.ageRecipientsFile,
            "# Public age recipients that can decrypt encrypted secret snapshots.\n# Add one age1... recipient per trusted Mac or recovery key.\n"
        )
    }

    private func checkSecretsRuntime() throws {
        try need("age")
        try need("gzip")
        try need("gtar")
    }

    private func checkKeychainRuntime() throws {
        try checkSecretsRuntime()
        try need("age-keygen")
        try need("security")
    }

    private func keychainIdentityExists() -> Bool {
        runner.run("security", ["find-generic-password", "-a", config.keychainAccount, "-s", config.keychainService, "-w"]).status == 0
    }

    private func requireKeychainIdentity() throws {
        guard keychainIdentityExists() else {
            errorMessage("missing Keychain age identity: \(config.keychainService)")
            errorMessage("run: \(config.scriptName) secrets init")
            throw ExitError(code: 1)
        }
    }

    private func writeKeychainIdentityFile(_ target: String) throws {
        let result = runner.run("security", ["find-generic-password", "-a", config.keychainAccount, "-s", config.keychainService, "-w"])
        guard result.status == 0 else { throw ExitError(code: Int(result.status)) }
        try result.stdout.write(toFile: target, atomically: true, encoding: .utf8)
        _ = chmod(target, S_IRUSR | S_IWUSR)
    }

    private func storeKeychainIdentity(_ identity: String) throws {
        let result = runner.run("security", ["add-generic-password", "-a", config.keychainAccount, "-s", config.keychainService, "-w", identity, "-U"])
        if result.status != 0 { throw ExitError(code: Int(result.status)) }
    }

    private func recipientFromIdentityFile(_ identityFile: String) throws -> String {
        let result = runner.run("age-keygen", ["-y", identityFile])
        guard result.status == 0 else {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
        return result.stdout.trimmed
    }

    private func recipientConfigured(_ recipient: String) -> Bool {
        ageRecipients().contains(recipient)
    }

    private func cmdSecretsInit() throws {
        try checkRuntime()
        try pullRepoIfSafe()
        try checkKeychainRuntime()
        try ensureSecretPathsFile()
        try ensureAgeRecipientsFile()
        let tmpDir = try tempPath(prefix: "mac-sync-age-keygen", directory: true)
        defer { try? removePath(tmpDir) }
        let tmpIdentity = "\(tmpDir)/identity.txt"
        let tmpKeygen = "\(tmpDir)/keygen.txt"
        let recipient: String
        if keychainIdentityExists() {
            try writeKeychainIdentityFile(tmpIdentity)
            recipient = try recipientFromIdentityFile(tmpIdentity)
            info("Keychain age identity already exists: \(config.keychainService)")
        } else {
            let result = runner.run("age-keygen", ["-o", tmpKeygen])
            guard result.status == 0 else {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            let identity = readText(tmpKeygen).splitLines().first { $0.hasPrefix("AGE-SECRET-KEY-") } ?? ""
            guard !identity.isEmpty else { try fail("age-keygen did not create an age identity") }
            try writeText(tmpIdentity, identity + "\n")
            recipient = try recipientFromIdentityFile(tmpIdentity)
            try storeKeychainIdentity(identity)
            info("Stored new age identity in Apple Keychain: \(config.keychainService)")
        }
        try appendUniqueConfigLine(file: config.ageRecipientsFile, line: recipient)
        if recipientConfigured(recipient) {
            info("Configured public age recipient: \(recipient)")
        }
        try commitConfigAndPush(message: "chore: configure encrypted secrets", paths: ["config/secret-paths.txt", "config/age-recipients.txt"])
    }

    private func commitConfigAndPush(message: String, paths: [String]) throws {
        if config.dryRun == "1" {
            info("dry run enabled; skipping config commit and push")
            return
        }
        _ = runner.run("git", ["-C", config.repoDir, "add", "--"] + paths)
        if runner.run("git", ["-C", config.repoDir, "diff", "--cached", "--quiet", "--"] + paths).status == 0 {
            info("no secrets config changes to commit")
        } else {
            let result = runner.run("git", ["-C", config.repoDir, "commit", "-m", message, "--"] + paths)
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
        }
        guard repoHasOrigin(config.repoDir) else {
            warning("no origin remote configured; skipping git push")
            return
        }
        let branch = runner.run("git", ["-C", config.repoDir, "branch", "--show-current"]).stdout.trimmed
        guard !branch.isEmpty else {
            warning("detached HEAD; skipping git push")
            return
        }
        if branchAheadOfUpstream(config.repoDir) {
            info("pushing \(branch) to origin")
            _ = runner.run("git", ["-C", config.repoDir, "push", "-u", "origin", branch])
        } else {
            info("no local commits to push")
        }
    }

    private func writePlainSecretsArchive(includedFile: String, target: String) throws {
        let script = """
        gtar -C \(ShellQuoter.quote(config.homeDir)) --ignore-failed-read --warning=no-file-ignored --sort=name --exclude='.DS_Store' --exclude='*/.DS_Store' --exclude='*.sock' --exclude='*.socket' --exclude='.ssh/agent' --exclude='.ssh/agent/*' -cf - -T \(ShellQuoter.quote(includedFile)) | gzip -n > \(ShellQuoter.quote(target))
        """
        let result = runner.shell(script)
        if result.status != 0 {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
    }

    private func writeSecretsIncludedPathsManifest(_ includedFile: String) throws {
        try writeText(
            config.secretsIncludedPathsFile,
            "# Generated by mac-sync. Do not edit.\n# HOME-relative paths included in secrets.tar.gz.age.\n" + readText(includedFile)
        )
    }

    private func syncSecretsArchive(mode: String = "auto") throws {
        guard secretsSyncEnabled() else { return }
        guard ageRecipientsPresent() else {
            if mode == "required" { try fail("no age recipients configured; run: \(config.scriptName) secrets init") }
            return
        }
        if mode == "required" {
            try checkKeychainRuntime()
            try requireKeychainIdentity()
        } else if !runner.commandExists("security") || !keychainIdentityExists() {
            warning("missing local Keychain age identity; skipping encrypted secrets snapshot")
            return
        }
        if !runner.commandExists("age") || !runner.commandExists("gzip") || !runner.commandExists("gtar") {
            if mode == "required" { try checkSecretsRuntime() }
            warning("age, gzip, or gtar not found; skipping encrypted secrets snapshot")
            return
        }
        let tmpDir = try tempPath(prefix: "mac-sync-secrets", directory: true)
        defer { try? removePath(tmpDir) }
        let included = "\(tmpDir)/included-paths.txt"
        let archive = "\(tmpDir)/secrets.tar.gz.age"
        let existingArchive = "\(tmpDir)/existing-secrets.tar.gz"
        let identity = "\(tmpDir)/identity.txt"
        let plainArchive = "\(tmpDir)/secrets.tar.gz"
        let includedPaths = secretManifestPaths().filter { pathExists(sourcePath(for: $0)) }
        if mode == "required" {
            for rel in secretManifestPaths() where !pathExists(sourcePath(for: rel)) {
                info("skip missing secret source: \(sourcePath(for: rel))")
            }
        }
        guard !includedPaths.isEmpty else {
            if mode == "required" { warning("no configured secret paths exist; skipping encrypted secrets snapshot") }
            return
        }
        try writeText(included, includedPaths.joined(separator: "\n") + "\n")
        if config.dryRun == "1" {
            progressPending("would update encrypted secrets snapshot: \(config.secretsArchive)")
            return
        }
        progressPending("updating encrypted secrets snapshot")
        try ensureDirectory(config.secretsDir)
        try writePlainSecretsArchive(includedFile: included, target: plainArchive)
        if fm.fileExists(atPath: config.secretsArchive) {
            try writeKeychainIdentityFile(identity)
            let decrypt = runner.shell("age -d -i \(ShellQuoter.quote(identity)) \(ShellQuoter.quote(config.secretsArchive)) > \(ShellQuoter.quote(existingArchive))")
            if decrypt.status == 0,
               let plainData = try? Data(contentsOf: URL(fileURLWithPath: plainArchive)),
               let existingData = try? Data(contentsOf: URL(fileURLWithPath: existingArchive)),
               plainData == existingData {
                progressDone("encrypted secrets snapshot unchanged")
                return
            } else if decrypt.status != 0 {
                warning("could not decrypt existing encrypted secrets snapshot; rewriting it")
            }
        }
        let encrypt = runner.shell("age -R \(ShellQuoter.quote(config.ageRecipientsFile)) -o \(ShellQuoter.quote(archive)) < \(ShellQuoter.quote(plainArchive))")
        if encrypt.status != 0 {
            fputs(encrypt.combinedOutput, stderr)
            throw ExitError(code: Int(encrypt.status))
        }
        try? removePath(config.secretsArchive)
        try fm.moveItem(atPath: archive, toPath: config.secretsArchive)
        try writeSecretsIncludedPathsManifest(included)
        progressDone("updated encrypted secrets snapshot: \(config.secretsArchive)")
    }

    private func safeArchiveEntry(_ entry: String) -> Bool {
        !(entry.isEmpty || entry.hasPrefix("/") || entry == ".." || entry.hasPrefix("../") || entry.contains("/../") || entry.hasSuffix("/..") || entry == ".")
    }

    private func decryptedArchiveEntries(archive: String, identity: String) throws -> [String] {
        let result = runner.shell("age -d -i \(ShellQuoter.quote(identity)) \(ShellQuoter.quote(archive)) | gtar -tzf -")
        guard result.status == 0 else {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
        return result.stdout.splitLines().filter { !$0.isEmpty }
    }

    private func printSecretsRestoreHint(machine: String) {
        guard secretsSyncEnabled() else { return }
        let archive = secretsArchive(for: machine)
        guard fm.fileExists(atPath: archive) else { return }
        info()
        info("Encrypted secrets snapshot found:")
        info("  \(archive)")
        info("To inspect it:")
        info("  \(config.scriptName) secrets list --from \(ShellQuoter.quote(machine))")
        info("To restore it:")
        info("  \(config.scriptName) secrets restore --from \(ShellQuoter.quote(machine))")
    }

    private func cmdSecretsList(_ args: [String]) throws {
        var args = args
        var fromMachine = config.machineName
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--from":
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                fromMachine = value
                args.removeFirst()
            default:
                try fail("unknown secrets list option: \(arg)", code: 2)
            }
        }
        guard MacSyncPaths.safeMachineName(fromMachine) else { try fail("invalid machine name: \(fromMachine)", code: 2) }
        try checkRuntime()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try checkKeychainRuntime()
        try requireKeychainIdentity()
        let archive = secretsArchive(for: fromMachine)
        guard fm.fileExists(atPath: archive) else { try fail("missing encrypted secrets snapshot: \(archive)") }
        let identity = try tempPath(prefix: "mac-sync-age-identity")
        defer { try? removePath(identity) }
        try writeKeychainIdentityFile(identity)
        for entry in try decryptedArchiveEntries(archive: archive, identity: identity) {
            info(entry)
        }
    }

    private func cmdSecretsRestore(_ args: [String]) throws {
        var args = args
        var force = false
        var fromMachine = config.machineName
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--from":
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                fromMachine = value
                args.removeFirst()
            case "--force":
                force = true
            default:
                try fail("unknown secrets restore option: \(arg)", code: 2)
            }
        }
        guard MacSyncPaths.safeMachineName(fromMachine) else { try fail("invalid machine name: \(fromMachine)", code: 2) }
        try checkRuntime()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try checkKeychainRuntime()
        try requireKeychainIdentity()
        let archive = secretsArchive(for: fromMachine)
        guard fm.fileExists(atPath: archive) else { try fail("missing encrypted secrets snapshot: \(archive)") }
        let identity = try tempPath(prefix: "mac-sync-age-identity")
        defer { try? removePath(identity) }
        try writeKeychainIdentityFile(identity)
        let entries = try decryptedArchiveEntries(archive: archive, identity: identity)
        for entry in entries where !safeArchiveEntry(entry) {
            try fail("unsafe archive entry: \(entry)")
        }
        let conflicts = entries.filter { !$0.hasSuffix("/") && pathExists(sourcePath(for: $0)) }
        if !force && !conflicts.isEmpty {
            errorMessage("secret restore would overwrite existing files; re-run with --force")
            for conflict in conflicts { fputs("  \(conflict)\n", stderr) }
            throw ExitError(code: 1)
        }
        if config.dryRun == "1" {
            info("would restore encrypted secrets from: \(archive)")
            return
        }
        info("restoring encrypted secrets from: \(archive)")
        let result = runner.shell("age -d -i \(ShellQuoter.quote(identity)) \(ShellQuoter.quote(archive)) | gtar -xzf - -C \(ShellQuoter.quote(config.homeDir))")
        if result.status != 0 {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
    }

    private func cmdSecretsTest() throws {
        try checkRuntime()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try checkKeychainRuntime()
        try requireKeychainIdentity()
        let identity = try tempPath(prefix: "mac-sync-age-identity")
        defer { try? removePath(identity) }
        try writeKeychainIdentityFile(identity)
        let recipient = try recipientFromIdentityFile(identity)
        if recipientConfigured(recipient) {
            info("Keychain identity has a configured public recipient.")
        } else {
            warning("Keychain identity recipient is not in \(config.ageRecipientsFile)")
        }
        if fm.fileExists(atPath: config.secretsArchive) {
            _ = try decryptedArchiveEntries(archive: config.secretsArchive, identity: identity)
            info("Current machine encrypted secrets snapshot can be decrypted.")
        } else {
            info("No current machine encrypted secrets snapshot found yet.")
        }
    }

    private func cmdSecretsSync() throws {
        try checkRuntime()
        try acquireLock()
        defer { releaseLock() }
        try selfUpdateFromRemoteOrWarn()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncSecretsArchive(mode: "required")
        try commitAndPush()
    }

    private func cmdSecrets(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }
        switch command {
        case "init":
            guard args.isEmpty else { try fail("secrets init does not accept options", code: 2) }
            try cmdSecretsInit()
        case "sync":
            guard args.isEmpty else { try fail("secrets sync does not accept options", code: 2) }
            try cmdSecretsSync()
        case "list":
            try cmdSecretsList(args)
        case "restore":
            try cmdSecretsRestore(args)
        case "test":
            guard args.isEmpty else { try fail("secrets test does not accept options", code: 2) }
            try cmdSecretsTest()
        case "help", "-h", "--help":
            usageSecrets()
        default:
            try fail("unknown secrets command: \(command)", code: 2)
        }
    }

    private func cmdPackages(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }
        switch command {
        case "sync":
            guard args.isEmpty else { try fail("packages sync does not accept options", code: 2) }
            try cmdPackagesSync()
        case "diff":
            try cmdPackagesDiff(args)
        case "install":
            try cmdPackagesInstall(args)
        case "list":
            try cmdPackagesList(args)
        case "help", "-h", "--help":
            usagePackages()
        default:
            try fail("unknown packages command: \(command)", code: 2)
        }
    }

    private func cmdPackagesSync() throws {
        try checkRuntime()
        try acquireLock()
        defer { releaseLock() }
        try selfUpdateFromRemoteOrWarn()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncHomebrewPackages()
        if config.dryRun != "1" { try writeMachineMetadata() }
        try commitAndPush()
    }

    private func parseFromOption(_ args: [String], commandName: String) throws -> String {
        var args = args
        var machine = config.machineName
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--from":
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                machine = value
                args.removeFirst()
            default:
                try fail("unknown \(commandName) option: \(arg)", code: 2)
            }
        }
        return try resolveRequestedMachine(machine)
    }

    private func cmdPackagesDiff(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        printHomebrewRestoreCommands(machine: try parseFromOption(args, commandName: "packages diff"))
    }

    private func cmdPackagesInstall(_ arguments: [String]) throws {
        var args = arguments
        var machine = config.machineName
        var formulaeOnly = false
        var adminUser = ""
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--from":
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                machine = value
                args.removeFirst()
            case "--formulae-only":
                formulaeOnly = true
            case "--admin-user":
                guard let value = args.first else { try fail("missing user after --admin-user", code: 2) }
                adminUser = value
                args.removeFirst()
            default:
                try fail("unknown packages install option: \(arg)", code: 2)
            }
        }
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try installHomebrewSnapshot(machine: try resolveRequestedMachine(machine), formulaeOnly: formulaeOnly, adminUser: adminUser)
    }

    private func cmdPackagesList(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try listHomebrewSnapshot(machine: try parseFromOption(args, commandName: "packages list"))
    }

    private func cmdEditor(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }
        switch command {
        case "sync":
            guard args.isEmpty else { try fail("editor sync does not accept options", code: 2) }
            try cmdEditorSync()
        case "diff":
            try cmdEditorDiff(args)
        case "install":
            try cmdEditorInstall(args)
        case "list":
            try cmdEditorList(args)
        case "help", "-h", "--help":
            usageEditor()
        default:
            try fail("unknown editor command: \(command)", code: 2)
        }
    }

    private func cmdEditorSync() throws {
        try checkRuntime()
        try acquireLock()
        defer { releaseLock() }
        try selfUpdateFromRemoteOrWarn()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncVscodeExtensions()
        if config.dryRun != "1" { try writeMachineMetadata() }
        try commitAndPush()
    }

    private func cmdEditorDiff(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        printVscodeExtensionRestoreCommands(machine: try parseFromOption(args, commandName: "editor diff"))
    }

    private func cmdEditorInstall(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try installVscodeExtensionsSnapshot(machine: try parseFromOption(args, commandName: "editor install"))
    }

    private func cmdEditorList(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        let machine = try parseFromOption(args, commandName: "editor list")
        let file = vscodeExtensionsFile(for: machine)
        guard fm.fileExists(atPath: file) else { try fail("missing VS Code extension snapshot: \(file)") }
        info(file)
        for line in readText(file).splitLines() { info("  \(line)") }
    }

    private func cmdManifest(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "list"
        if !args.isEmpty { args.removeFirst() }
        switch command {
        case "list":
            guard args.isEmpty else { try fail("manifest list does not accept options", code: 2) }
            try checkRuntime()
            for path in try manifestPaths() { info(path) }
        case "configured":
            guard args.isEmpty else { try fail("manifest configured does not accept options", code: 2) }
            try checkRuntime()
            for path in try configuredManifestPaths() { info(path) }
        case "dynamic":
            guard args.isEmpty else { try fail("manifest dynamic does not accept options", code: 2) }
            try checkRuntime()
            for path in dynamicManifestPaths() { info(path) }
        case "source":
            guard args.isEmpty else { try fail("manifest source does not accept options", code: 2) }
            try checkRuntime()
            info(configuredManifestSourceLabel())
        case "help", "-h", "--help":
            usageManifest()
        default:
            try fail("unknown manifest command: \(command)", code: 2)
        }
    }

    private func printSyncedDirectoryChanges(srcRoot: String, destRoot: String, changes: String) {
        for line in changes.splitLines() where !line.isEmpty {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2 else { continue }
            let code = parts[0]
            let rel = parts[1]
            guard !rel.isEmpty, rel != ".", rel != "./" else { continue }
            if code == "*deleting" {
                progressDone("removed snapshot path: \(destRoot)/\(rel)")
            } else if code.dropFirst().first != "d" {
                progressDone("sync file: \(srcRoot)/\(rel) -> \(destRoot)/\(rel)")
            }
        }
    }

    private func syncOnePath(_ rel: String) throws {
        let src = sourcePath(for: rel)
        let dest = destPath(for: rel)
        let parent = (dest as NSString).deletingLastPathComponent
        if !pathExists(src) {
            if pathExists(dest) {
                if config.dryRun == "1" {
                    progressPending("would remove missing source snapshot: \(dest)")
                } else {
                    try removePath(dest)
                    progressDone("removed missing source snapshot: \(dest)")
                }
            }
            return
        }
        if config.dryRun == "1" {
            progressPending("\(isDirectory(src) ? "would sync directory" : "would sync file"): \(src) -> \(dest)")
            return
        }
        try ensureDirectory(parent)
        var args = isDirectory(src) ? ["-a", "--delete", "--itemize-changes", "--out-format=%i %n"] : ["-aL", "--itemize-changes", "--out-format=%i %n"]
        if fm.fileExists(atPath: config.excludesFile) { args.append("--exclude-from=\(config.excludesFile)") }
        if isDirectory(src) {
            try ensureDirectory(dest)
            let result = runner.run("rsync", args + ["\(src)/", "\(dest)/"])
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            printSyncedDirectoryChanges(srcRoot: src, destRoot: dest, changes: result.stdout)
        } else {
            let result = runner.run("rsync", args + [src, dest])
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            if !result.stdout.trimmed.isEmpty {
                progressDone("sync file: \(src) -> \(dest)")
            }
        }
    }

    private func restoreOnePath(machine: String, rel: String, force: Bool) throws {
        let src = snapshotPath(machine: machine, rel: rel)
        let dest = sourcePath(for: rel)
        let parent = (dest as NSString).deletingLastPathComponent
        guard pathExists(src) else {
            info("skip missing snapshot path: \(src)")
            return
        }
        if isDirectory(src) {
            if pathExists(dest), !isDirectory(dest) {
                if force {
                    if config.dryRun == "1" {
                        info("would replace non-directory with directory: \(dest)")
                    } else {
                        try removePath(dest)
                        info("removed non-directory before directory restore: \(dest)")
                    }
                } else {
                    warning("skip directory restore over non-directory: \(dest)")
                    return
                }
            }
            if config.dryRun == "1" {
                info("would restore directory: \(src) -> \(dest)")
                return
            }
            try ensureDirectory(dest)
            info("restore directory: \(src) -> \(dest)")
            var args = ["-a"]
            if !force { args.append("--update") }
            if fm.fileExists(atPath: config.excludesFile) { args.append("--exclude-from=\(config.excludesFile)") }
            let result = runner.run("rsync", args + ["\(src)/", "\(dest)/"])
            if result.status != 0 { throw ExitError(code: Int(result.status)) }
            return
        }
        if isDirectory(dest) {
            if force {
                if config.dryRun == "1" {
                    info("would replace directory with file: \(dest)")
                } else {
                    try removePath(dest)
                    info("removed directory before file restore: \(dest)")
                }
            } else {
                warning("skip file restore over directory: \(dest)")
                return
            }
        }
        if !force, pathExists(dest), modificationDate(dest) > modificationDate(src) {
            info("skip newer local file: \(dest)")
            return
        }
        if !force, pathExists(dest), filesEqual(src, dest) {
            info("unchanged local file: \(dest)")
            return
        }
        if config.dryRun == "1" {
            info("would restore file: \(src) -> \(dest)")
            return
        }
        try ensureDirectory(parent)
        info("restore file: \(src) -> \(dest)")
        var args = ["-a"]
        if fm.fileExists(atPath: config.excludesFile) { args.append("--exclude-from=\(config.excludesFile)") }
        let result = runner.run("rsync", args + [src, dest])
        if result.status != 0 { throw ExitError(code: Int(result.status)) }
    }

    private func modificationDate(_ path: String) -> Date {
        ((try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date.distantPast)
    }

    private func filesEqual(_ left: String, _ right: String) -> Bool {
        guard let leftData = try? Data(contentsOf: URL(fileURLWithPath: left)),
              let rightData = try? Data(contentsOf: URL(fileURLWithPath: right)) else { return false }
        return leftData == rightData
    }

    private func writeMachineMetadata() throws {
        let computerName = runner.commandExists("scutil") ? runner.run("scutil", ["--get", "ComputerName"]).stdout.trimmed : ""
        let localHostName = runner.commandExists("scutil") ? runner.run("scutil", ["--get", "LocalHostName"]).stdout.trimmed : ""
        let osName = runner.commandExists("sw_vers") ? runner.run("sw_vers", ["-productName"]).stdout.trimmed : ""
        let osVersion = runner.commandExists("sw_vers") ? runner.run("sw_vers", ["-productVersion"]).stdout.trimmed : ""
        let arch = runner.run("uname", ["-m"]).stdout.trimmed
        try writeText(
            "\(config.machineDir)/MACHINE.md",
            """
            # \(config.machineName)

            This directory contains the curated dotfile snapshot for `\(config.machineName)`.

            - ComputerName: `\(computerName.isEmpty ? "unknown" : computerName)`
            - LocalHostName: `\(localHostName.isEmpty ? "unknown" : localHostName)`
            - OS: `\(osName.isEmpty ? "unknown" : osName) \(osVersion.isEmpty ? "unknown" : osVersion)`
            - Architecture: `\(arch.isEmpty ? "unknown" : arch)`
            """
        )
    }

    private func pullGitRepoIfSafe(repo: String, label: String) throws {
        guard repoHasOrigin(repo) else {
            warning("no origin remote configured for \(label); skipping git pull")
            return
        }
        guard repoClean(repo) else {
            warning("\(label) has local changes; skipping pre-operation git pull")
            return
        }
        guard runWithProgressCommand("pulling latest \(label) changes", "git", ["-C", repo, "pull", "--ff-only"]) else {
            printProgressCommandOutput()
            throw ExitError(code: 1)
        }
        progressDone(lastCommandOutput.contains("Already up to date.") ? "\(label) already up to date" : "pulled latest \(label) changes")
    }

    private func pullRepoIfSafe() throws {
        try pullGitRepoIfSafe(repo: config.repoDir, label: "local repo")
    }

    private func pullMachinesRepoIfSafe() throws {
        guard repoHasOrigin(config.machinesRepoDir) else {
            warning("no origin remote configured for machines repo; skipping git pull")
            return
        }
        let machinePath = "machines/\(config.machineName)"
        guard repoPathClean(config.machinesRepoDir, machinePath) else {
            warning("current machine snapshot has local changes; skipping pre-operation git pull")
            return
        }
        let args = repoClean(config.machinesRepoDir)
            ? ["-C", config.machinesRepoDir, "pull", "--ff-only"]
            : ["-C", config.machinesRepoDir, "pull", "--ff-only", "--autostash"]
        let message = repoClean(config.machinesRepoDir)
            ? "pulling latest machines repo changes"
            : "pulling latest machines repo changes with unrelated local edits preserved"
        guard runWithProgressCommand(message, "git", args) else {
            printProgressCommandOutput()
            warning("could not pull machines repo before sync; continuing and retrying before push")
            return
        }
        progressDone(lastCommandOutput.contains("Already up to date.") ? "machines repo already up to date" : "pulled latest machines repo changes")
    }

    private func isMachOExecutable(_ path: String) -> Bool {
        guard fm.isExecutableFile(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magicValues: Set<[UInt8]> = [
            [0xCA, 0xFE, 0xBA, 0xBE],
            [0xBE, 0xBA, 0xFE, 0xCA],
            [0xFE, 0xED, 0xFA, 0xCF],
            [0xCF, 0xFA, 0xED, 0xFE],
        ]
        return magicValues.contains(Array(data))
    }

    private func preferredExecutablePath(name: String, fallback: String) -> String {
        let candidates = [
            "\(config.selfDir)/\(name)",
            "\(config.repoDir)/.build/release/\(name)",
            "\(config.repoDir)/.build/debug/\(name)",
        ]
        return candidates.first { isMachOExecutable($0) } ?? fallback
    }

    private func commandSourcePath() -> String {
        preferredExecutablePath(name: "mac-sync", fallback: config.selfPath)
    }

    private func spinnerSourcePath() -> String? {
        let source = preferredExecutablePath(name: "mac-spinner", fallback: config.repoSpinner)
        return fm.fileExists(atPath: source) ? source : nil
    }

    private func installSpinnerCommand() throws {
        guard let source = spinnerSourcePath() else {
            warning("spinner helper not found; skipping install: \(config.repoSpinner)")
            return
        }
        let result = runner.run("install", ["-m", "755", source, config.spinnerInstallPath])
        if result.status != 0 { throw ExitError(code: Int(result.status)) }
    }

    private func runningInstalledScript() -> Bool {
        guard fm.fileExists(atPath: config.installPath) else { return false }
        return Config.realpathExisting(config.selfPath) == Config.realpathExisting(config.installPath)
    }

    private func selfUpdateRemoteURL() -> String {
        if !config.selfUpdateRemote.isEmpty { return config.selfUpdateRemote }
        if isDirectory("\(config.repoDir)/.git") {
            let result = runner.run("git", ["-C", config.repoDir, "remote", "get-url", "origin"])
            if result.status == 0 { return result.stdout.trimmed }
        }
        return "https://github.com/stephenlclarke/mac-sync.git"
    }

    private func selfUpdateRemoteRefSHA(remote: String, ref: String) -> String? {
        let heads = runner.shell("git ls-remote --heads \(ShellQuoter.quote(remote)) \(ShellQuoter.quote(ref)) 2>/dev/null | awk 'NR == 1 { print $1 }'").stdout.trimmed
        if !heads.isEmpty { return heads }
        let any = runner.shell("git ls-remote \(ShellQuoter.quote(remote)) \(ShellQuoter.quote(ref)) 2>/dev/null | awk 'NR == 1 { print $1 }'").stdout.trimmed
        return any.isEmpty ? nil : any
    }

    private func selfUpdateCloneRef(_ ref: String) -> String {
        if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
        if ref.hasPrefix("refs/tags/") { return String(ref.dropFirst("refs/tags/".count)) }
        return ref
    }

    private func selfUpdateLocalSourceCurrent(remoteSHA: String) -> Bool {
        guard isDirectory("\(config.repoDir)/.git"), fm.fileExists(atPath: config.repoScript), repoClean(config.repoDir) else { return false }
        return runner.run("git", ["-C", config.repoDir, "rev-parse", "HEAD"]).stdout.trimmed == remoteSHA
    }

    private func fileChecksum(_ file: String) -> String {
        guard fm.fileExists(atPath: file) else { return "missing" }
        let result = runner.run("cksum", [file]).stdout.split(separator: " ")
        guard result.count >= 2 else { return "missing" }
        return "\(result[0]):\(result[1])"
    }

    private func selfUpdateStateValue(_ key: String) -> String {
        readText(config.selfUpdateStatusFile).splitLines().first { $0.hasPrefix("\(key)=") }?.dropFirst(key.count + 1).description ?? ""
    }

    private func selfUpdateStateCurrent(remote: String, ref: String, remoteSHA: String) -> Bool {
        guard fm.fileExists(atPath: config.selfUpdateStatusFile) else { return false }
        return selfUpdateStateValue("remote") == remote
            && selfUpdateStateValue("ref") == ref
            && selfUpdateStateValue("remote_sha") == remoteSHA
            && selfUpdateStateValue("script_checksum") == fileChecksum(config.installPath)
            && selfUpdateStateValue("spinner_checksum") == fileChecksum(config.spinnerInstallPath)
    }

    private func writeSelfUpdateState(remote: String, ref: String, remoteSHA: String) throws {
        try writeText(
            config.selfUpdateStatusFile,
            """
            remote=\(remote)
            ref=\(ref)
            remote_sha=\(remoteSHA)
            script_checksum=\(fileChecksum(config.installPath))
            spinner_checksum=\(fileChecksum(config.spinnerInstallPath))
            """
        )
    }

    private func cloneSelfUpdateSource(remote: String, ref: String, target: String) -> Bool {
        runner.run("git", ["clone", "--quiet", "--depth", "1", "--branch", selfUpdateCloneRef(ref), remote, target]).status == 0
    }

    private func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let line = "[\(stamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if fm.fileExists(atPath: config.logOut), let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: config.logOut)) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            } else {
                fm.createFile(atPath: config.logOut, contents: data)
            }
        }
    }

    private func applySelfUpdateSource(sourceDir: String, sourceLabel: String) throws -> Bool {
        selfUpdateScriptChanged = false
        let sourceScript = "\(sourceDir)/bin/mac-sync"
        let sourceSpinner = "\(sourceDir)/bin/mac-spinner"
        if fm.fileExists(atPath: sourceSpinner), !filesEqual(sourceSpinner, config.spinnerInstallPath) {
            try ensureDirectory(config.installDir)
            let result = runner.run("install", ["-m", "755", sourceSpinner, config.spinnerInstallPath])
            if result.status == 0 { log("updated installed spinner helper from \(sourceLabel)") }
        }
        guard fm.fileExists(atPath: sourceScript) else {
            warning("self-update source is missing bin/mac-sync: \(sourceLabel)")
            return false
        }
        if fm.fileExists(atPath: config.installPath), filesEqual(sourceScript, config.installPath) {
            return true
        }
        try ensureDirectory(config.installDir)
        let result = runner.run("install", ["-m", "755", sourceScript, config.installPath])
        if result.status != 0 { return false }
        selfUpdateScriptChanged = true
        log("updated installed mac-sync from \(sourceLabel)")
        return true
    }

    private func normalizedSelfUpdateMode() -> String {
        switch config.selfUpdateMode {
        case "restart", "reexec":
            return "restart"
        case "exit":
            return "exit"
        default:
            warning("unknown MAC_SYNC_SELF_UPDATE_MODE: \(config.selfUpdateMode); using restart")
            return "restart"
        }
    }

    private func finishSelfUpdate(sourceLabel: String) throws {
        guard selfUpdateScriptChanged else { return }
        if normalizedSelfUpdateMode() == "exit" {
            warning("mac-sync updated itself from \(sourceLabel)")
            warning("Please re-run the sync using the new script: \(config.installPath) sync")
            log("self-updated installed script and exited before continuing")
            throw ExitError(code: 75)
        }
        warning("mac-sync updated itself from \(sourceLabel); restarting with the new script")
        log("self-updated installed script and restarted")
        releaseLock()
        let result = runner.run(config.installPath, config.originalArgs, capture: true)
        if !result.stdout.isEmpty { print(result.stdout, terminator: "") }
        if !result.stderr.isEmpty { fputs(result.stderr, stderr) }
        throw ExitError(code: Int(result.status))
    }

    private func selfUpdateFromRemoteOrWarn() throws {
        guard selfUpdateEnabled(), config.dryRun != "1", runningInstalledScript() else { return }
        let remote = selfUpdateRemoteURL()
        guard let remoteSHA = selfUpdateRemoteRefSHA(remote: remote, ref: config.selfUpdateRef) else {
            warning("could not check mac-sync self-update remote: \(remote) \(config.selfUpdateRef)")
            return
        }
        let sourceDir: String
        let sourceLabel: String
        var tmpDir: String?
        if selfUpdateLocalSourceCurrent(remoteSHA: remoteSHA) {
            sourceDir = config.repoDir
            sourceLabel = "\(config.repoDir) (\(config.selfUpdateRef)@\(remoteSHA.prefix(7)))"
        } else if selfUpdateStateCurrent(remote: remote, ref: config.selfUpdateRef, remoteSHA: remoteSHA) {
            return
        } else {
            let dir = try tempPath(prefix: "mac-sync-self-update", directory: true)
            tmpDir = dir
            guard cloneSelfUpdateSource(remote: remote, ref: config.selfUpdateRef, target: "\(dir)/source") else {
                try? removePath(dir)
                warning("could not clone mac-sync self-update source: \(remote) \(config.selfUpdateRef)")
                return
            }
            sourceDir = "\(dir)/source"
            sourceLabel = "\(remote) (\(config.selfUpdateRef)@\(remoteSHA.prefix(7)))"
        }
        if try applySelfUpdateSource(sourceDir: sourceDir, sourceLabel: sourceLabel) {
            try writeSelfUpdateState(remote: remote, ref: config.selfUpdateRef, remoteSHA: remoteSHA)
            if let tmpDir { try? removePath(tmpDir) }
            try finishSelfUpdate(sourceLabel: sourceLabel)
        }
        if let tmpDir { try? removePath(tmpDir) }
    }

    private func rebaseMachinesRepoBeforePush() -> Bool {
        guard branchHasUpstream(config.machinesRepoDir) else {
            progressDone("no upstream branch yet; skipping pre-push pull")
            return true
        }
        guard runWithProgressCommand("fetching machines repo upstream", "git", ["-C", config.machinesRepoDir, "fetch", "--quiet"]) else {
            printProgressCommandOutput()
            return false
        }
        let counts = runner.run("git", ["-C", config.machinesRepoDir, "rev-list", "--left-right", "--count", "HEAD...@{u}"])
            .stdout
            .split { $0 == " " || $0 == "\t" || $0 == "\n" }
        let behind = counts.count > 1 ? String(counts[1]).trimmed : "0"
        if behind == "0" {
            progressDone("machines repo already includes upstream")
            return true
        }
        guard runWithProgressCommand("rebasing machines repo before push", "git", ["-C", config.machinesRepoDir, "pull", "--rebase", "--autostash"]) else {
            printProgressCommandOutput()
            return false
        }
        progressDone("rebased machines repo before push")
        return true
    }

    private func pushMachinesRepoWithRetries(branch: String) -> Bool {
        for attempt in 1...3 {
            guard rebaseMachinesRepoBeforePush() else { return false }
            if runWithProgressCommand("pushing \(branch) to origin", "git", ["-C", config.machinesRepoDir, "push", "-u", "origin", branch]) {
                progressDone("pushed \(branch) to origin")
                return true
            }
            printProgressCommandOutput()
            if attempt == 3 { return false }
            warning("machines repo push failed; rebasing and retrying (\(attempt)/3)")
        }
        return false
    }

    private func commitAndPush() throws {
        if config.dryRun == "1" {
            progressPending("dry run enabled; skipping git commit and push")
            return
        }
        guard runWithProgressCommand("checking machine snapshot changes", "git", ["-C", config.machinesRepoDir, "add", "machines/\(config.machineName)"]) else {
            printProgressCommandOutput()
            throw ExitError(code: 1)
        }
        var committed = false
        if runner.run("git", ["-C", config.machinesRepoDir, "diff", "--cached", "--quiet", "--", "machines/\(config.machineName)"]).status == 0 {
            progressDone("no machine snapshot changes to commit")
        } else {
            let message = "chore(\(config.machineName)): sync machine state"
            guard runWithProgressCommand("committing machine snapshot changes", "git", ["-C", config.machinesRepoDir, "commit", "-m", message, "--", "machines/\(config.machineName)"]) else {
                printProgressCommandOutput()
                throw ExitError(code: 1)
            }
            progressDone("committed machine snapshot changes")
            committed = true
        }
        guard repoHasOrigin(config.machinesRepoDir) else {
            warning("no origin remote configured for machines repo; skipping git push")
            return
        }
        let branch = runner.run("git", ["-C", config.machinesRepoDir, "branch", "--show-current"]).stdout.trimmed
        guard !branch.isEmpty else {
            warning("detached HEAD; skipping git push")
            return
        }
        if !committed && !branchAheadOfUpstream(config.machinesRepoDir) {
            progressDone("no local commits to push")
            return
        }
        guard pushMachinesRepoWithRetries(branch: branch) else { throw ExitError(code: 1) }
    }

    private func acquireLock() throws {
        let pidFile = "\(config.lockDir)/pid"
        do {
            try fm.createDirectory(atPath: config.lockDir, withIntermediateDirectories: false)
            try writeText(pidFile, "\(getpid())\n")
            return
        } catch {
            let lockPID = readText(pidFile).trimmed
            if !lockPID.isEmpty, runner.run("kill", ["-0", lockPID]).status == 0 {
                info("another mac-sync run is active; exiting: pid \(lockPID)")
                throw ExitError(code: 0)
            }
            warning("removing stale sync lock: \(config.lockDir)")
            try? removePath(config.lockDir)
            try fm.createDirectory(atPath: config.lockDir, withIntermediateDirectories: false)
            try writeText(pidFile, "\(getpid())\n")
        }
    }

    private func releaseLock() {
        let pidFile = "\(config.lockDir)/pid"
        if readText(pidFile).trimmed == "\(getpid())" {
            try? removePath(config.lockDir)
        }
    }

    private func statusTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        return formatter.string(from: Date())
    }

    private func treeFileCount(_ dir: String) -> Int {
        guard let enumerator = fm.enumerator(atPath: dir) else { return 0 }
        var count = 0
        for case let path as String in enumerator {
            if !isDirectory("\(dir)/\(path)") { count += 1 }
        }
        return count
    }

    private func treeByteCount(_ dir: String) -> Int {
        guard let enumerator = fm.enumerator(atPath: dir) else { return 0 }
        var total = 0
        for case let path as String in enumerator {
            let full = "\(dir)/\(path)"
            guard !isDirectory(full), let size = try? fm.attributesOfItem(atPath: full)[.size] as? NSNumber else { continue }
            total += size.intValue
        }
        return total
    }

    private func changedMachineMetrics() -> (count: Int, bytes: Int) {
        let result = runner.run("git", ["-C", config.machinesRepoDir, "ls-files", "--modified", "--deleted", "--others", "--exclude-standard", "-z", "--", "machines/\(config.machineName)"])
        let files = result.stdout.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
        let bytes = files.reduce(0) { total, rel -> Int in
            let path = "\(config.machinesRepoDir)/\(rel)"
            guard let size = try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber else { return total }
            return total + size.intValue
        }
        return (files.count, bytes)
    }

    private func startSyncStatus() throws {
        try ensureDirectory(config.statusDir)
        runActive = true
        runStartedAt = statusTimestamp()
        runStartedEpoch = Int(Date().timeIntervalSince1970)
        warningCount = 0
        errorCount = 0
        warningMessages = []
        errorMessages = []
        startedFileCount = 0
        startedByteCount = 0
        lastUpdatedFileCount = 0
        lastUpdatedByteCount = 0
        lastNetByteChange = 0
        lastStorageFileCount = 0
        lastStorageByteCount = 0
    }

    private func captureSyncStartMetrics() {
        startedFileCount = treeFileCount(config.machineDir)
        startedByteCount = treeByteCount(config.machineDir)
    }

    private func captureSyncFinishMetrics() {
        lastStorageFileCount = treeFileCount(config.machineDir)
        lastStorageByteCount = treeByteCount(config.machineDir)
        lastNetByteChange = lastStorageByteCount - startedByteCount
        let metrics = changedMachineMetrics()
        lastUpdatedFileCount = metrics.count
        lastUpdatedByteCount = metrics.bytes
    }

    private func finishSyncStatus(_ status: Int) {
        guard runActive else { return }
        let finishedAt = statusTimestamp()
        let duration = max(0, Int(Date().timeIntervalSince1970) - runStartedEpoch)
        try? writeText(config.syncWarningsFile, warningMessages.joined(separator: "\n") + (warningMessages.isEmpty ? "" : "\n"))
        try? writeText(config.syncErrorsFile, errorMessages.joined(separator: "\n") + (errorMessages.isEmpty ? "" : "\n"))
        let lastCommit = runner.run("git", ["-C", config.machinesRepoDir, "rev-parse", "--short", "HEAD"]).stdout.trimmed.ifEmpty("unknown")
        let remoteRepo = runner.run("git", ["-C", config.machinesRepoDir, "remote", "get-url", "origin"]).stdout.trimmed.ifEmpty("none")
        let result = status == 0 ? "success" : "failed"
        let text = """
        machine=\(config.machineName)
        result=\(result)
        exit_status=\(status)
        started_at=\(runStartedAt)
        finished_at=\(finishedAt)
        duration_seconds=\(duration)
        started_file_count=\(startedFileCount)
        started_byte_count=\(startedByteCount)
        updated_file_count=\(lastUpdatedFileCount)
        updated_byte_count=\(lastUpdatedByteCount)
        net_byte_change=\(lastNetByteChange)
        storage_file_count=\(lastStorageFileCount)
        storage_byte_count=\(lastStorageByteCount)
        warning_count=\(warningCount)
        error_count=\(errorCount)
        remote_repo=\(remoteRepo)
        last_commit=\(lastCommit)
        """
        try? writeText(config.syncStatusFile, text)
        runActive = false
    }

    private func cmdSync() throws {
        try checkRuntime()
        try acquireLock()
        defer { releaseLock() }
        try selfUpdateFromRemoteOrWarn()
        try startSyncStatus()
        do {
            try pullRepoIfSafe()
            try pullMachinesRepoIfSafe()
            captureSyncStartMetrics()
            progressPending("building sync manifest")
            let configured = try configuredManifestPaths()
            let dynamic = dynamicManifestPaths()
            let dynamicExtra = dynamicExtraPaths(dynamic: dynamic, configured: configured)
            var seen = Set<String>()
            let manifest = (configured + dynamicExtra).filter { !$0.trimmed.isEmpty && seen.insert($0).inserted }
            progressDone("built sync manifest")
            if config.dryRun != "1" {
                try ensureDirectory(config.machineHomeDir)
                try ensureDirectory(config.machineAbsoluteDir)
            }
            progressPending("syncing configured paths")
            for rel in manifest { try syncOnePath(rel) }
            progressDone("synced configured paths")
            try pruneStaleDynamicPaths(currentDynamic: dynamicExtra, configured: configured)
            try syncHomebrewPackages()
            try syncVscodeExtensions()
            try syncGitHubRepositories()
            try syncSecretsArchive(mode: "auto")
            if config.dryRun != "1" {
                if dynamicRefsEnabled() { try writeDynamicPathsManifest(dynamicExtra) }
                try writeMachineMetadata()
            }
            captureSyncFinishMetrics()
            try commitAndPush()
            finishSyncStatus(0)
        } catch let error as ExitError {
            finishSyncStatus(error.code)
            throw error
        } catch {
            finishSyncStatus(1)
            throw error
        }
    }

    private func cmdRestore(_ arguments: [String]) throws {
        var args = arguments
        var force = false
        var fromMachine = config.machineName
        var fromProvided = false
        var listMachines = false
        var selectMachine = false
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--from":
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                fromMachine = value
                fromProvided = true
                args.removeFirst()
            case "--select":
                selectMachine = true
            case "--list-machines":
                listMachines = true
            case "--force":
                force = true
            case "-h", "--help":
                usageRestore()
                return
            default:
                errorMessage("unknown restore option: \(arg)")
                usageRestore()
                throw ExitError(code: 2)
            }
        }
        if fromProvided && selectMachine { try fail("--from and --select cannot be used together", code: 2) }
        try checkRuntime()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        if listMachines {
            machineSnapshotSuggestionLines()
            return
        }
        if fromProvided {
            guard MacSyncPaths.safeMachineName(fromMachine) else { try fail("invalid machine name: \(fromMachine)", code: 2) }
            let requested = fromMachine
            guard let resolved = resolveMachineSnapshotName(requested) else {
                machineSnapshotSuggestionLines()
                try fail("missing machine snapshot: \(config.machinesRootDir)/\(requested)")
            }
            fromMachine = resolved
        } else if selectMachine || !isDirectory("\(config.machinesRootDir)/\(config.machineName)") {
            machineSnapshotSuggestionLines()
            try fail("current machine snapshot is missing; re-run with --from <machine>")
        }
        let machineDir = "\(config.machinesRootDir)/\(fromMachine)"
        guard isDirectory(machineDir) else { try fail("missing machine snapshot: \(machineDir)") }
        info("restoring from machine: \(fromMachine)")
        if force {
            warning("force enabled; newer local files may be overwritten")
        } else {
            info("newer local files will be kept; use --force to overwrite them")
        }
        for rel in try restoreManifestPaths(machine: fromMachine) {
            try restoreOnePath(machine: fromMachine, rel: rel, force: force)
        }
        printHomebrewRestoreCommands(machine: fromMachine)
        printVscodeExtensionRestoreCommands(machine: fromMachine)
        try restoreGitHubRepositories(machine: fromMachine)
        printSecretsRestoreHint(machine: fromMachine)
    }

    private func cmdList() throws {
        info("local repo: \(config.repoDir)")
        info("machines repo: \(config.machinesRepoDir)")
        info("machine: \(config.machineName)")
        info("paths file: \(config.pathsFile)")
        info("manifest source: \(configuredManifestSourceLabel())")
        info("dynamic paths file: \(config.dynamicPathsFile)")
        info("Homebrew snapshot dir: \(config.homebrewDir)")
        info("VS Code extension snapshot file: \(config.vscodeExtensionsFile)")
        info("GitHub repo root: \(config.githubRootDir)")
        info("GitHub repo snapshot file: \(config.githubReposFile)")
        info("secret paths file: \(config.secretPathsFile)")
        info("age recipients file: \(config.ageRecipientsFile)")
        info("encrypted secrets archive: \(config.secretsArchive)")
        info("dynamic refs: \(dynamicRefsEnabled() ? "enabled" : "disabled")")
        info("Homebrew sync: \(homebrewSyncEnabled() ? "enabled" : "disabled")")
        info("VS Code extension sync: \(vscodeExtensionsSyncEnabled() ? "enabled" : "disabled")")
        info("GitHub repo sync: \(githubReposSyncEnabled() ? "enabled" : "disabled")")
        info("encrypted secrets sync: \(secretsSyncEnabled() ? "enabled" : "disabled")")
        info()
        for rel in try manifestPaths() {
            let src = sourcePath(for: rel)
            let dest = destPath(for: rel)
            let state = pathExists(src) ? (isDirectory(src) ? "dir" : "file") : "missing"
            info("\(state.padding(toLength: 8, withPad: " ", startingAt: 0)) \(src) -> \(dest)")
        }
    }

    private func cmdInstall() throws {
        try need("install")
        try need("launchctl")
        try validateIntRange(name: "MAC_SYNC_HOURLY_MINUTE", value: config.hourlyMinute, min: 0, max: 59)
        try ensureDirectory(config.installDir)
        try ensureDirectory((config.launchAgentPlist as NSString).deletingLastPathComponent)
        var result = runner.run("install", ["-m", "755", commandSourcePath(), config.installPath])
        if result.status != 0 { throw ExitError(code: Int(result.status)) }
        try installSpinnerCommand()
        try writeLaunchAgent()
        _ = runner.run("launchctl", ["bootout", "gui/\(getuid())", config.launchAgentPlist])
        result = runner.run("launchctl", ["bootstrap", "gui/\(getuid())", config.launchAgentPlist])
        if result.status != 0 { throw ExitError(code: Int(result.status)) }
        info("installed \(config.installPath)")
        info("installed \(config.spinnerInstallPath)")
        info("loaded \(config.launchAgentPlist)")
    }

    private func cmdUninstall() {
        _ = runner.run("launchctl", ["bootout", "gui/\(getuid())", config.launchAgentPlist])
        try? removePath(config.launchAgentPlist)
        try? removePath(config.installPath)
        try? removePath(config.spinnerInstallPath)
        info("removed \(config.launchAgentPlist)")
        info("removed \(config.installPath)")
        info("removed \(config.spinnerInstallPath)")
    }

    private func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func writeLaunchAgent() throws {
        let optionalEnvironment = [
            "SCRIPT_COLOUR",
            "MAC_SYNC_SELF_UPDATE",
            "MAC_SYNC_SELF_UPDATE_MODE",
            "MAC_SYNC_SELF_UPDATE_REMOTE",
            "MAC_SYNC_SELF_UPDATE_REF",
        ].compactMap { key -> String? in
            guard let value = environment[key], !value.isEmpty else { return nil }
            return """
                  <key>\(key)</key>
                  <string>\(xmlEscape(value))</string>
            """
        }.joined(separator: "\n")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>\(config.launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
              <string>\(xmlEscape(config.installPath))</string>
              <string>run</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
              <key>MAC_SYNC_REPO</key>
              <string>\(xmlEscape(config.repoDir))</string>
              <key>MAC_SYNC_MACHINES_REPO</key>
              <string>\(xmlEscape(config.machinesRepoDir))</string>
              <key>MAC_SYNC_MACHINE</key>
              <string>\(xmlEscape(config.machineName))</string>
              <key>MAC_SYNC_GITHUB_ROOT</key>
              <string>\(xmlEscape(config.githubRootDir))</string>
              <key>PATH</key>
              <string>\(xmlEscape(config.launchAgentPathEnv))</string>
        \(optionalEnvironment)
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>StartCalendarInterval</key>
            <dict>
              <key>Minute</key>
              <integer>\(config.hourlyMinute)</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(config.logOut))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(config.logErr))</string>
          </dict>
        </plist>
        """
        try writeText(config.launchAgentPlist, plist)
    }

    private func syncStatusValue(_ key: String) -> String {
        readText(config.syncStatusFile).splitLines().first { $0.hasPrefix("\(key)=") }?.dropFirst(key.count + 1).description ?? ""
    }

    private func printStatusMessages(title: String, file: String) {
        let text = readText(file)
        if text.trimmed.isEmpty {
            info("\(title): none")
        } else {
            info("\(title):")
            for line in text.splitLines() where !line.isEmpty {
                info("  \(line)")
            }
        }
    }

    private func printRepoLocalChanges(repo: String, title: String) {
        let changes = runner.run("git", ["-C", repo, "status", "--short"]).stdout.trimmed
        guard !changes.isEmpty else { return }
        info("\(title) local changes:")
        for line in changes.splitLines() { info("  \(line)") }
    }

    private func launchagentLoaded() -> Bool {
        runner.run("launchctl", ["print", "gui/\(getuid())/\(config.launchAgentLabel)"]).status == 0
    }

    private func launchagentScheduledMinute() -> Int {
        let text = readText(config.launchAgentPlist)
        if let range = text.range(of: #"<key>Minute</key>\s*<integer>([0-9]+)</integer>"#, options: .regularExpression) {
            let snippet = String(text[range])
            let digits = snippet.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
            if let value = Int(digits), value >= 0, value <= 59 { return value }
        }
        return Int(config.hourlyMinute) ?? 0
    }

    private func nextScheduledRun() -> String {
        let now = Date()
        let calendar = Calendar.current
        let minute = launchagentScheduledMinute()
        let currentMinute = calendar.component(.minute, from: now)
        let currentSecond = calendar.component(.second, from: now)
        let elapsed = currentMinute * 60 + currentSecond
        let target = minute * 60
        let delta = elapsed < target ? target - elapsed : 3600 - elapsed + target
        let next = now.addingTimeInterval(TimeInterval(delta))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        return formatter.string(from: next)
    }

    private func cmdStatus() {
        info("mac-sync version: \(repoCommitVersion(config.repoDir))")
        info("local repo: \(config.repoDir)")
        info("machines repo: \(config.machinesRepoDir)")
        info("machine: \(config.machineName)")
        info("installed command: \(config.installPath)")
        info("spinner command: \(config.spinnerInstallPath)")
        info("paths file: \(config.pathsFile)")
        info("manifest source: \(configuredManifestSourceLabel())")
        info("Homebrew snapshot dir: \(config.homebrewDir)")
        info("VS Code extension snapshot file: \(config.vscodeExtensionsFile)")
        info("self-update remote: \(selfUpdateRemoteURL())")
        info("self-update ref: \(config.selfUpdateRef)")
        info("LaunchAgent: \(config.launchAgentPlist)")
        info("status file: \(config.syncStatusFile)")
        info("self-update state file: \(config.selfUpdateStatusFile)")
        info("stdout log: \(config.logOut)")
        info("stderr log: \(config.logErr)")
        info("install state: \(fm.isExecutableFile(atPath: config.installPath) ? "installed" : "not installed")")
        info("LaunchAgent state: \(launchagentLoaded() ? "loaded" : "not loaded")")
        info("next scheduled run: \(nextScheduledRun())")
        info("machine snapshot stored: \(treeByteCount(config.machineDir)) bytes across \(treeFileCount(config.machineDir)) files")
        if fm.fileExists(atPath: config.syncStatusFile) {
            let remoteRepo = syncStatusValue("remote_repo").ifEmpty(runner.run("git", ["-C", config.machinesRepoDir, "remote", "get-url", "origin"]).stdout.trimmed.ifEmpty("unknown"))
            info("last sync: \(syncStatusValue("result").ifEmpty("unknown"))")
            info("last sync finished: \(syncStatusValue("finished_at").ifEmpty("unknown"))")
            info("last sync duration: \(syncStatusValue("duration_seconds").ifEmpty("0"))s")
            info("last sync updated: \(syncStatusValue("updated_byte_count").ifEmpty("0")) bytes across \(syncStatusValue("updated_file_count").ifEmpty("0")) files")
            info("last sync net storage change: \(syncStatusValue("net_byte_change").ifEmpty("0")) bytes")
            info("last sync warnings: \(syncStatusValue("warning_count").ifEmpty("0"))")
            printStatusMessages(title: "last sync warning messages", file: config.syncWarningsFile)
            info("last sync errors: \(syncStatusValue("error_count").ifEmpty("0"))")
            printStatusMessages(title: "last sync error messages", file: config.syncErrorsFile)
            info("last sync remote repo: \(remoteRepo)")
            info("last sync commit: \(syncStatusValue("last_commit").ifEmpty("unknown"))")
        } else {
            info("last sync: unknown (no local status file yet)")
        }
        if isDirectory("\(config.repoDir)/.git") {
            info("local repo branch: \(runner.run("git", ["-C", config.repoDir, "branch", "--show-current"]).stdout.trimmed)")
            printRepoLocalChanges(repo: config.repoDir, title: "local repo")
        } else {
            warning("local repo is not initialized yet")
        }
        if isDirectory("\(config.machinesRepoDir)/.git") {
            info("machines repo branch: \(runner.run("git", ["-C", config.machinesRepoDir, "branch", "--show-current"]).stdout.trimmed)")
            printRepoLocalChanges(repo: config.machinesRepoDir, title: "machines repo")
        } else {
            warning("machines repo is not initialized yet")
        }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
