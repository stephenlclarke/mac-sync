import Darwin
import Foundation

private struct ExitError: Error {
    let code: Int
}

private struct Config {
    let originalArgs: [String]
    let scriptName: String
    let homeDir: String
    let repoDir: String
    let machinesRepoDir: String
    let dryRun: String
    let dynamicRefs: String
    let homebrewSync: String
    let vscodeExtensionsSync: String
    let githubRootDir: String
    let githubReposSync: String
    let secretsSync: String
    let manifestSource: String
    let brewBundleInstallFlags: String
    let pathsFile: String
    let excludesFile: String
    let secretPathsFile: String
    let ageRecipientsFile: String
    let keychainService: String
    let keychainAccount: String
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
    let secretsRecipientsFile: String
    let lockDir: String
    let serviceLockFile: String
    let statusDir: String
    let syncStatusFile: String
    let syncWarningsFile: String
    let syncErrorsFile: String
    let syncLocalChangesFile: String
    let syncConditionsFile: String
    let syncCommandsFile: String
    let syncHistoryDir: String

    init(environment originalEnvironment: [String: String], originalArgs: [String], runner: ProcessRunner) {
        let env = MacSyncUserConfiguration.resolvedEnvironment(originalEnvironment)
        let selfPath = Config.realpathExisting(originalArgs.first ?? "mac-sync")
        let home = env["HOME"] ?? NSHomeDirectory()
        let machinesRepo = env["MAC_SYNC_MACHINES_REPO"] ?? "\(home)/github/mac-sync-data"
        let repo = env["MAC_SYNC_REPO"] ?? machinesRepo
        let machine = Config.computeMachineName(environment: env, runner: runner)
        let machinesRoot = "\(machinesRepo)/machines"
        let machineDir = "\(machinesRoot)/\(machine)"
        let machineConfigDir = "\(machineDir)/config"
        let statusDir = env["MAC_SYNC_STATUS_DIR"] ?? "\(home)/Library/Application Support/mac-sync/status"
        let tmpDir = env["TMPDIR"] ?? "/tmp"

        self.originalArgs = Array(originalArgs.dropFirst())
        scriptName = (selfPath as NSString).lastPathComponent
        homeDir = home
        repoDir = repo
        machinesRepoDir = machinesRepo
        dryRun = env["MAC_SYNC_DRY_RUN"] ?? "0"
        dynamicRefs = env["MAC_SYNC_DYNAMIC_REFS"] ?? "1"
        homebrewSync = env["MAC_SYNC_HOMEBREW"] ?? "1"
        vscodeExtensionsSync = env["MAC_SYNC_VSCODE_EXTENSIONS"] ?? "1"
        githubRootDir = env["MAC_SYNC_GITHUB_ROOT"] ?? "\(home)/github"
        githubReposSync = env["MAC_SYNC_GITHUB_REPOS"] ?? "1"
        secretsSync = env["MAC_SYNC_SECRETS"] ?? "1"
        manifestSource = env["MAC_SYNC_MANIFEST_SOURCE"] ?? "config"
        brewBundleInstallFlags = env["MAC_SYNC_BREW_BUNDLE_INSTALL_FLAGS"] ?? env["BREW_BUNDLE_INSTALL_FLAGS"] ?? ""
        let configurationRoot = env["MAC_SYNC_REPO"] == nil ? machineConfigDir : "\(repo)/config"
        pathsFile = env["MAC_SYNC_PATHS_FILE"] ?? "\(configurationRoot)/sync-paths.txt"
        excludesFile = env["MAC_SYNC_EXCLUDES_FILE"] ?? "\(configurationRoot)/excludes.txt"
        secretPathsFile = env["MAC_SYNC_SECRET_PATHS_FILE"] ?? "\(configurationRoot)/secret-paths.txt"
        ageRecipientsFile = env["MAC_SYNC_AGE_RECIPIENTS_FILE"]
            ?? (env["MAC_SYNC_REPO"] == nil
                ? "\(machinesRoot)/_shared/config/age-recipients.txt"
                : "\(configurationRoot)/age-recipients.txt")
        keychainService = env["MAC_SYNC_KEYCHAIN_SERVICE"] ?? "mac-sync age identity"
        keychainAccount = env["MAC_SYNC_KEYCHAIN_ACCOUNT"] ?? env["USER"] ?? runner.shell("id -un").stdout.trimmed
        machineName = machine
        machinesRootDir = machinesRoot
        self.machineDir = machineDir
        machineHomeDir = "\(machineDir)/home"
        machineAbsoluteDir = "\(machineDir)/absolute"
        dynamicPathsFile = "\(machineDir)/dynamic-sync-paths.txt"
        homebrewDir = "\(machineDir)/homebrew"
        editorDir = "\(machineDir)/editor"
        vscodeExtensionsFile = "\(machineDir)/editor/vscode-extensions.txt"
        githubReposDir = "\(machineDir)/github-repositories"
        githubReposFile = "\(machineDir)/github-repositories/repositories.txt"
        secretsDir = "\(machineDir)/secrets"
        secretsArchive = "\(machineDir)/secrets/secrets.tar.gz.age"
        secretsIncludedPathsFile = "\(machineDir)/secrets/included-paths.txt"
        secretsRecipientsFile = "\(machineDir)/secrets/recipients.txt"
        lockDir = "\(tmpDir)/mac-sync-\(machine).lock"
        serviceLockFile = MacSyncProcessLock.syncServiceLockURL(environment: env).path
        self.statusDir = statusDir
        syncStatusFile = "\(statusDir)/\(machine).env"
        syncWarningsFile = "\(statusDir)/\(machine).warnings.log"
        syncErrorsFile = "\(statusDir)/\(machine).errors.log"
        syncLocalChangesFile = "\(statusDir)/\(machine).local-changes.log"
        syncConditionsFile = "\(statusDir)/\(machine).conditions.json"
        syncCommandsFile = "\(statusDir)/\(machine).commands.json"
        syncHistoryDir = "\(statusDir)/history/\(machine)"
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

private enum GitNetworkFailureKind {
    case authentication
    case unavailable
    case other
}

public final class MacSyncApp {
    private let environment: [String: String]
    private let invocationArguments: [String]
    private let userInterfaceLauncher: ([String: String]) throws -> Void
    private var runner: ProcessRunner
    private let config: Config
    private let fm = FileManager.default
    private var warningMessages: [String] = []
    private var errorMessages: [String] = []
    private var healthConditions: [SyncHealthCondition] = []
    private var commandDiagnostics: [SyncCommandDiagnostic] = []
    private var currentMachineLocalChanges: [String] = []
    private var lastCommandOutput = ""
    private var lastCommandStatus: Int32 = 0
    private var useSSHForGitHub = false
    private var isServiceInvocation = false
    private var cachedKeychainIdentity: String?
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
    private var historyActive = false
    private var historyAction: SyncHistoryAction?
    private var historySourceMachine: String?
    private var historyStartedAt = ""
    private var historyStartedEpoch = 0
    private var historyJournal: HistoryJournal?
    private var historyWriteFailed = false
    private var operationLock: MacSyncProcessLock?
    private var serviceLock: MacSyncProcessLock?
    private var backgroundResources: BackgroundResources?
    private var backgroundCheckpoint = BackgroundCheckpoint()
    private var backgroundDeferralReason: String?
    private var backgroundConnectivityDeferred = false
    private var gitHubSSHTransport = "git@github.com:"
    private var checkpointPath: String {
        "\(config.statusDir)/\(config.machineName).background.json"
    }

    private var networkAttempts: ClosedRange<Int> {
        1 ... (isServiceInvocation ? 1 : 3)
    }

    public convenience init() {
        self.init(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    }

    public init(
        arguments: [String],
        environment: [String: String],
        userInterfaceLauncher: @escaping ([String: String]) throws -> Void = MacSyncUserInterface.open,
    ) {
        self.environment = environment
        invocationArguments = arguments
        self.userInterfaceLauncher = userInterfaceLauncher
        runner = ProcessRunner(environment: environment)
        config = Config(environment: environment, originalArgs: arguments, runner: runner)
    }

    public func run() -> Int {
        do {
            let arguments = Array(invocationArguments.dropFirst())
            if !["ui", "version", "--version", "-V"].contains(arguments.first),
               !MacSyncPaths.safeMachineName(config.machineName)
            {
                try fail("invalid machine name: \(config.machineName)", code: 2)
            }
            try main(arguments)
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
        case "sync":
            try cmdSync()
        case "run":
            try cmdRun()
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
        case "ui":
            try cmdUI(args)
        case "version", "--version", "-V":
            try cmdVersion(args)
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
              sync        Sync configured paths, commit machine changes, and push
              run         Service mode; exits if the service is already running
              restore     Restore this machine snapshot back into $HOME
              restore [--from <machine>|--select] [--path <path>]... [--force]
                          Restore another machine snapshot back into $HOME
              secrets     Manage encrypted secret snapshots with age and Keychain
              packages    Manage Homebrew package snapshots and restore commands
              editor      Manage VS Code extension snapshots and restore commands
              manifest    Show configured and discovered backup paths
              list        Show configured source paths and repo destinations
              paths       Alias for list
              status      Show repo, git, local status, and last-sync state
              ui          Open the installed Mac Sync desktop app
              version     Show the Mac Sync app version and build number
              help [topic]
                          Show this help text or command-specific help
              -h, --help  Show this help text

            ENVIRONMENT:
              MAC_SYNC_MACHINES_REPO mac-sync data repo. Default: $HOME/github/mac-sync-data
              MAC_SYNC_REPO          Legacy command/config repo override
              MAC_SYNC_APP_CONFIG    App/service data repository location file
              MAC_SYNC_MACHINE       Machine directory name. Default: macOS host name
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
              MAC_SYNC_KEYCHAIN_SERVICE
                                     Keychain service for the age identity
              MAC_SYNC_KEYCHAIN_ACCOUNT
                                     Keychain account. Default: $USER or id -un
              SCRIPT_COLOUR          Set to off, false, or 0 to disable colour

            EXAMPLES:
              mac-sync list
              mac-sync sync
              mac-sync restore --from old-mbp
              mac-sync secrets init
              mac-sync packages diff --from old-mbp
              mac-sync editor install --from old-mbp
              mac-sync secrets list --from old-mbp
              mac-sync ui
              mac-sync version
              mac-sync help restore
              mac-sync help secrets
              MAC_SYNC_MACHINE=work-mbp mac-sync status
            """,
        )
    }

    private func usageRestore() {
        print(
            """
            USAGE:
              \(config.scriptName) restore [--from <machine>|--select|--list-machines] [--path <path>]... [--force]

            OPTIONS:
              --from <machine>   Restore from another machine snapshot.
              --select           Prompt for a machine snapshot even when the current machine exists.
              --list-machines    List available machine snapshots and exit.
              --path <path>      Restore only this selected snapshot path. May be repeated.
              --force            Replace existing local files and resolve file/directory conflicts.
              -h, --help         Show this help text.

            BEHAVIOR:
              Restore pulls the mac-sync-data repository when its worktree is clean.
              When --from is omitted, restore defaults to the current machine snapshot when
              it exists. Otherwise it offers machine snapshots from mac-sync-data.
              Existing local files are kept by default so this Mac remains the source of truth.
              Use --force only after choosing to replace those local files with the snapshot.
              It restores configured paths plus that machine's persisted dynamic paths. When
              --path is supplied, only the selected paths are restored and package, editor,
              repository, and secrets restore hints are skipped.
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
            """,
        )
    }

    private func usageUI() {
        print(
            """
            USAGE:
              \(config.scriptName) ui

            BEHAVIOR:
              Opens the installed Mac Sync desktop app. macOS reuses its existing
              app instance when it is already running. The Current Homebrew build
              is preferred when both Current and stable app bundles are present.
            """,
        )
    }

    private func usageVersion() {
        print(
            """
            USAGE:
              \(config.scriptName) version
              \(config.scriptName) --version

            BEHAVIOR:
              Prints the installed Mac Sync app version and build number.
            """,
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
              Public recipients are stored in machines/_shared/config/age-recipients.txt.
              Secret paths are configured in machines/<machine>/config/secret-paths.txt.
              Normal restore never decrypts secrets automatically.

            EXAMPLES:
              \(config.scriptName) secrets init
              \(config.scriptName) secrets sync
              \(config.scriptName) secrets list --from old-mbp
              \(config.scriptName) secrets restore --from old-mbp
              \(config.scriptName) secrets restore --from old-mbp --force
              \(config.scriptName) secrets test
            """,
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
            """,
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
            """,
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
            """,
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
        case "ui":
            usageUI()
        case "version":
            usageVersion()
        case "help", "-h", "--help":
            usage()
        default:
            try fail("unknown help topic: \(args.first!)", code: 2, usage: true)
        }
    }

    private func cmdUI(_ arguments: [String]) throws {
        switch arguments {
        case []:
            break
        case ["-h"], ["--help"]:
            usageUI()
            return
        default:
            try fail("ui does not accept options", code: 2)
        }

        do {
            try userInterfaceLauncher(environment)
            info("Opened Mac Sync UI.")
        } catch MacSyncUserInterfaceError.notInstalled {
            try fail(
                "Mac Sync UI is not installed. Install mac-sync-current with Homebrew, then run mac-sync ui.",
                code: 2,
            )
        } catch {
            try fail("Mac Sync UI could not be opened: \(error.localizedDescription)", code: 1)
        }
    }

    private func cmdVersion(_ arguments: [String]) throws {
        switch arguments {
        case []:
            info(MacSyncUserInterface.versionDescription(environment: environment))
        case ["-h"], ["--help"]:
            usageVersion()
        default:
            try fail("version does not accept options", code: 2)
        }
    }

    private func errorMessage(_ message: String) {
        errorCount += 1
        let line = "ERROR: \(message)"
        if runActive || historyActive, errorMessages.count < 100 {
            errorMessages.append(String(line.prefix(2000)))
        }
        fputs("\(line)\n", stderr)
    }

    private func warning(_ message: String) {
        warningCount += 1
        let line = "WARN: \(message)"
        if runActive || historyActive, warningMessages.count < 100 {
            warningMessages.append(String(line.prefix(2000)))
        }
        fputs("\(line)\n", stderr)
    }

    private func recordHealthCondition(_ condition: SyncHealthCondition) {
        let condition = SyncHealthCondition(id: condition.id, code: condition.code, component: condition.component,
                                            severity: condition.severity, title: String(condition.title.prefix(512)),
                                            detail: String(condition.detail.prefix(2000)), recovery: String(condition.recovery.prefix(2000)))
        if let index = healthConditions.firstIndex(where: { $0.code == condition.code }) {
            healthConditions[index] = condition
        } else {
            healthConditions.append(condition)
        }
    }

    private func recordCommandDiagnostic(
        step: String,
        command: String,
        attempt: Int,
        result: CommandResult,
    ) {
        if commandDiagnostics.count >= 32 {
            commandDiagnostics.removeFirst()
        }
        commandDiagnostics.append(SyncCommandDiagnostic(
            step: step,
            command: command,
            attempt: attempt,
            exitStatus: result.status,
            output: safeDiagnosticOutput(result.combinedOutput),
        ))
    }

    private func safeDiagnosticOutput(_ rawOutput: String) -> String {
        let embeddedUserInfoPattern = #"https://[^/@\s]+@"#
        let redacted = rawOutput.replacingOccurrences(
            of: embeddedUserInfoPattern,
            with: "https://<redacted>@",
            options: .regularExpression,
        )
        let trimmed = redacted.trimmed
        guard trimmed.count > 2000 else { return trimmed }
        return String(trimmed.prefix(2000)) + "\n[output truncated]"
    }

    private func fail(_ message: String, code: Int = 1, usage: Bool = false) throws -> Never {
        errorMessage(message)
        if usage {
            self.usage()
        }
        throw ExitError(code: code)
    }

    private func info(_ message: String = "") {
        if isServiceInvocation || environment["MAC_SYNC_QUIET"] == "1" {
            if message.contains(" -> ") || message.contains("skip missing") || message.contains("unchanged local file") {
                return
            }
        }
        print(message)
    }

    private var pendingMark: String {
        "\u{2813}"
    }

    private var doneMark: String {
        "\u{2714}\u{FE0E}"
    }

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
        workingDirectory: String? = nil,
    ) -> Bool {
        progressPending(message)
        let result = runner.run(executable, arguments, workingDirectory: workingDirectory)
        lastCommandOutput = result.combinedOutput
        lastCommandStatus = result.status
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

    private func dynamicRefsEnabled() -> Bool {
        enabled(config.dynamicRefs)
    }

    private func homebrewSyncEnabled() -> Bool {
        enabled(config.homebrewSync)
    }

    private func vscodeExtensionsSyncEnabled() -> Bool {
        enabled(config.vscodeExtensionsSync)
    }

    private func githubReposSyncEnabled() -> Bool {
        enabled(config.githubReposSync)
    }

    private func secretsSyncEnabled() -> Bool {
        enabled(config.secretsSync) && !isServiceInvocation
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
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else {
            fm.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o600])
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
            errorMessage("clone or create the repository there, or set MAC_SYNC_REPO")
            throw ExitError(code: 1)
        }
        guard config.repoDir == config.machinesRepoDir || isDirectory("\(config.machinesRepoDir)/.git") else {
            errorMessage("not a git repository: \(config.machinesRepoDir)")
            errorMessage("clone https://github.com/stephenlclarke/mac-sync-data there, or set MAC_SYNC_MACHINES_REPO")
            throw ExitError(code: 1)
        }
    }

    private func repoHasOrigin(_ repo: String? = nil) -> Bool {
        runner.run("git", ["-C", repo ?? config.repoDir, "remote", "get-url", "origin"]).status == 0
    }

    private func repoClean(_ repo: String? = nil) -> Bool {
        runner.run("git", ["-C", repo ?? config.repoDir, "status", "--porcelain"]).stdout.trimmed.isEmpty
    }

    private func repoPathsClean(_ repo: String, _ pathspecs: [String]) -> Bool {
        runner.run("git", ["-C", repo, "status", "--porcelain", "--"] + pathspecs).stdout.trimmed.isEmpty
    }

    private func managedSnapshotPaths() -> [String] {
        let machinePath = "machines/\(config.machineName)"
        let sharedPath = "machines/_shared"
        let sharedFiles = runner.run(
            "git",
            [
                "-C", config.machinesRepoDir,
                "ls-files", "--cached", "--others", "--exclude-standard",
                "--", sharedPath,
            ],
        )
        return sharedFiles.stdout.trimmed.isEmpty
            ? [machinePath]
            : [machinePath, sharedPath]
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
        return try validatedSyncPaths(readConfigLines(config.pathsFile), source: config.pathsFile)
    }

    private func dotFilesManifestAvailable() -> Bool {
        fm.fileExists(atPath: "\(config.machinesRepoDir)/Makefile") && runner.commandExists("make")
    }

    private func configuredManifestPathsFromDotFiles() throws -> [String]? {
        guard dotFilesManifestAvailable() else {
            return nil
        }
        let result = runner.run(
            "make",
            ["--no-print-directory", "-s", "-C", config.machinesRepoDir, "print-mac-sync-paths"],
            extraEnvironment: ["BASH_ENV": "", "ENV": ""],
        )
        guard result.status == 0 else { return nil }
        let lines = result.stdout.splitLines().filter { !$0.trimmed.isEmpty }
        guard !lines.isEmpty else { return nil }
        var seen = Set<String>()
        let paths = lines.filter { seen.insert($0).inserted }
        return try validatedSyncPaths(paths, source: "dot-files manifest")
    }

    private func validatedSyncPaths(_ paths: [String], source: String) throws -> [String] {
        for path in paths where !MacSyncPaths.safeSyncPath(path) {
            try fail("unsafe sync path in \(source): \(path)", code: 2)
        }
        return paths
    }

    private func configuredManifestPaths() throws -> [String] {
        switch config.manifestSource {
        case "auto":
            if let paths = try configuredManifestPathsFromDotFiles() {
                return paths
            }
            return try configuredManifestPathsFromFile()
        case "dot-files":
            guard let paths = try configuredManifestPathsFromDotFiles() else {
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
            dotFilesManifestAvailable() ? "dot-files" : "config"
        case "dot-files", "config":
            config.manifestSource
        default:
            "invalid"
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
        if rel.hasPrefix("./") {
            rel.removeFirst(2)
        }
        while rel.hasSuffix("/") {
            rel.removeLast()
        }
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
            if rel == String(prefix.dropLast()) || rel.hasPrefix(prefix) {
                return false
            }
        }
        if rel.hasPrefix(".gnupg/"), rel != ".gnupg/common.conf" {
            return false
        }
        if rel.hasPrefix(".ssh/") {
            if rel == ".ssh/config" || rel.hasSuffix(".pub") {
                return true
            }
            return false
        }
        for suffix in [".pem", ".ppk", ".p12", ".pfx", ".key"] where rel.hasSuffix(suffix) {
            return false
        }
        return true
    }

    private func dynamicSyncRoot(for rel: String) -> String {
        let parts = rel.split(separator: "/").map(String.init)
        if parts.count >= 3, rel.hasPrefix(".config/") || rel.hasPrefix(".zsh/") {
            return "\(parts[0])/\(parts[1])"
        }
        if parts.count >= 4, rel.hasPrefix(".tmux/plugins/") {
            return "\(parts[0])/\(parts[1])/\(parts[2])"
        }
        return rel
    }

    private func isTextFile(_ file: String) -> Bool {
        guard fm.fileExists(atPath: file), !isDirectory(file) else { return false }
        guard let size = try? fm.attributesOfItem(atPath: file)[.size] as? NSNumber,
              size.intValue <= 1024 * 1024,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file)) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024) else { return false }
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
               match.numberOfRanges > 1
            {
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
            "# Generated by mac-sync. Do not edit.\n# HOME-relative dynamic paths discovered from dotfile references.\n" + paths.joined(separator: "\n") + (paths.isEmpty ? "" : "\n"),
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
            if currentDynamic.contains(where: { pathsOverlap(rel, $0) }) {
                continue
            }
            if configured.contains(where: { pathsOverlap(rel, $0) }) {
                continue
            }
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
        return try (configuredManifestPaths() + dynamicManifestPaths()).filter { !$0.trimmed.isEmpty && seen.insert($0).inserted }
    }

    private func restoreManifestPaths(machine: String, selectedPaths: [String]) throws -> [String] {
        if !selectedPaths.isEmpty {
            return try validatedSyncPaths(uniqueSorted(selectedPaths), source: "restore --path")
        }
        var seen = Set<String>()
        let dynamicFile = "\(config.machinesRootDir)/\(machine)/dynamic-sync-paths.txt"
        let dynamic = storedDynamicManifestPaths(dynamicFile)
        for path in dynamic where !safeDynamicRelPath(path) {
            try fail("unsafe dynamic sync path in \(dynamicFile): \(path)", code: 2)
        }
        return try (configuredManifestPaths() + dynamic).filter { !$0.trimmed.isEmpty && seen.insert($0).inserted }
    }

    private func machineSnapshotNames() -> [String] {
        guard let entries = try? fm.contentsOfDirectory(atPath: config.machinesRootDir) else { return [] }
        return entries.filter { isDirectory("\(config.machinesRootDir)/\($0)") }.sorted()
    }

    private func resolveMachineSnapshotName(_ requested: String) -> String? {
        if isDirectory("\(config.machinesRootDir)/\(requested)") {
            return requested
        }
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

    private func selectMachineSnapshot() throws -> String {
        let names = machineSnapshotNames()
        guard !names.isEmpty else {
            machineSnapshotSuggestionLines()
            try fail("no machine snapshots are available")
        }
        info("Available machine snapshots in \(config.machinesRootDir):")
        for (index, name) in names.enumerated() {
            info("  \(index + 1). \(name)\(name == config.machineName ? " (current default)" : "")")
        }
        print("Select a machine by number or name: ", terminator: "")
        guard let input = readLine(), let selected = MacSyncPaths.selectedMachineName(input: input, available: names) else {
            try fail("invalid machine selection", code: 2)
        }
        return selected
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

    private func currentHomebrewList(_ kind: String) throws -> [String] {
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
        guard result.status == 0 else {
            fputs(result.combinedOutput, stderr)
            try fail("Homebrew inventory command failed: \(kind)")
        }
        return uniqueSorted(result.stdout.splitLines().filter { !$0.trimmed.isEmpty })
    }

    private func brewfileQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func writeHomebrewSnapshot() throws {
        try ensureDirectory(config.homebrewDir)
        let lists: [(String, String, [String])] = try [
            ("taps.txt", "Installed Homebrew taps.", currentHomebrewList("taps")),
            ("formulae.txt", "Installed Homebrew formulae.", currentHomebrewList("formulae")),
            ("casks.txt", "Installed Homebrew casks.", currentHomebrewList("casks")),
        ]
        for (file, description, values) in lists {
            try writeText(
                "\(config.homebrewDir)/\(file)",
                "# Generated by mac-sync. Do not edit.\n# \(description)\n" + values.joined(separator: "\n") + (values.isEmpty ? "" : "\n"),
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

    private func printHomebrewRestoreCommands(machine: String) throws {
        guard homebrewSyncEnabled() else { return }
        let dir = homebrewDir(for: machine)
        guard fm.fileExists(atPath: "\(dir)/taps.txt") || fm.fileExists(atPath: "\(dir)/formulae.txt") || fm.fileExists(atPath: "\(dir)/casks.txt") else {
            return
        }
        let desiredTaps = uniqueSorted(homebrewListFileLines("\(dir)/taps.txt"))
        let desiredFormulae = uniqueSorted(homebrewListFileLines("\(dir)/formulae.txt"))
        let desiredCasks = uniqueSorted(homebrewListFileLines("\(dir)/casks.txt"))
        let currentTaps = try Set(currentHomebrewList("taps"))
        let currentFormulae = try Set(currentHomebrewList("formulae"))
        let currentCasks = try Set(currentHomebrewList("casks"))
        let outdatedFormulae = try Set(currentHomebrewList("outdated-formulae"))
        let outdatedCasks = try Set(currentHomebrewList("outdated-casks"))

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
            if result.status != 0 {
                throw ExitError(code: Int(result.status))
            }
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

    private func currentVscodeExtensions() throws -> [String] {
        guard runner.commandExists("code") else { return [] }
        let result = runner.run("code", ["--list-extensions", "--show-versions"])
        guard result.status == 0 else {
            fputs(result.combinedOutput, stderr)
            try fail("VS Code extension inventory command failed")
        }
        return uniqueSorted(result.stdout.splitLines().filter { !$0.trimmed.isEmpty })
    }

    private func writeVscodeExtensionsSnapshot() throws {
        try writeText(
            config.vscodeExtensionsFile,
            "# Generated by mac-sync. Do not edit.\n# Installed VS Code extensions with versions.\n" + currentVscodeExtensions().joined(separator: "\n") + "\n",
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

    private func vscodeExtensionDiff(snapshotFile: String) throws -> (install: [String], remove: [String]) {
        let desired = Set(vscodeExtensionLines(snapshotFile))
        let current = try Set(currentVscodeExtensions())
        return (Array(desired.subtracting(current)).sorted(), Array(current.subtracting(desired)).sorted())
    }

    private func printVscodeExtensionRestoreCommands(machine: String) throws {
        guard vscodeExtensionsSyncEnabled() else { return }
        let file = vscodeExtensionsFile(for: machine)
        guard fm.fileExists(atPath: file) else { return }
        let diff = try vscodeExtensionDiff(snapshotFile: file)
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
        let diff = try vscodeExtensionDiff(snapshotFile: file)
        for ext in diff.remove {
            let extID = String(ext.split(separator: "@").first ?? "")
            info("remove VS Code extension \(extID)")
            if config.dryRun != "1" {
                let result = runner.run("code", ["--uninstall-extension", extID])
                if result.status != 0 {
                    throw ExitError(code: Int(result.status))
                }
            }
        }
        for ext in diff.install {
            info("install VS Code extension \(ext)")
            if config.dryRun != "1" {
                let result = runner.run("code", ["--install-extension", ext])
                if result.status != 0 {
                    throw ExitError(code: Int(result.status))
                }
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
        while parent != rootReal, parent != "/", !parent.isEmpty {
            let top = runner.run("git", ["-C", parent, "rev-parse", "--show-toplevel"]).stdout.trimmed
            if !top.isEmpty {
                let ancestor = Config.realpathExisting(top)
                if ancestor != repoReal, repoReal.hasPrefix("\(ancestor)/") {
                    return true
                }
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
            "# Generated by mac-sync. Do not edit.\n# Format: relative-path<TAB>github-clone-url\n" + localGitHubRepositoryLines().joined(separator: "\n") + "\n",
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
        if config.dryRun != "1" {
            try ensureDirectory(config.githubRootDir)
        }
        for rawLine in readText(file).splitLines() {
            if rawLine.isEmpty || rawLine.hasPrefix("#") {
                continue
            }
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
            if safeSecretRelPath(rel) {
                return true
            }
            warning("skip unsafe secret path: \(rel)")
            return false
        }
    }

    private func ageRecipients() -> [String] {
        readConfigLines(config.ageRecipientsFile)
    }

    private func normalizedRecipients(_ recipients: [String]) -> [String] {
        Array(Set(recipients.map(\.trimmed).filter { !$0.isEmpty })).sorted()
    }

    private func configuredAgeRecipients() -> [String] {
        normalizedRecipients(ageRecipients())
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
            "# Paths are relative to $HOME and are encrypted before syncing.\n# Keep this list narrow; the decrypted archive restores into $HOME.\n.ssh\n.secrets\n",
        )
    }

    private func ensureAgeRecipientsFile() throws {
        guard !fm.fileExists(atPath: config.ageRecipientsFile) else { return }
        try writeText(
            config.ageRecipientsFile,
            "# Shared public age recipients for every encrypted mac-sync snapshot.\n# Add one age1... recipient per trusted Mac or recovery key.\n",
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
    }

    private func keychainIdentity(
        allowInteraction: Bool,
    ) -> MacSyncKeychainIdentityLookup {
        if let cachedKeychainIdentity {
            return MacSyncKeychainIdentityLookup(
                availability: .available,
                identity: cachedKeychainIdentity,
            )
        }

        let lookup: MacSyncKeychainIdentityLookup
        if environment["KEYCHAIN_FAKE_DIR"] != nil {
            let result = runner.run(
                "security",
                ["find-generic-password", "-a", config.keychainAccount, "-s", config.keychainService, "-w"],
            )
            if result.status == 0 {
                lookup = MacSyncKeychainIdentityLookup(
                    availability: .available,
                    identity: result.stdout,
                )
            } else if result.status == 44 {
                lookup = MacSyncKeychainIdentityLookup(availability: .missing)
            } else {
                lookup = MacSyncKeychainIdentityLookup(availability: .interactionRequired)
            }
        } else {
            lookup = MacSyncKeychain.identity(
                service: config.keychainService,
                account: config.keychainAccount,
                allowInteraction: allowInteraction,
            )
        }
        if let identity = lookup.identity {
            cachedKeychainIdentity = identity
        }
        return lookup
    }

    private func keychainIdentityExists(allowInteraction: Bool = true) -> Bool {
        keychainIdentity(allowInteraction: allowInteraction).availability == .available
    }

    private func requireKeychainIdentity() throws {
        guard keychainIdentityExists(allowInteraction: !isServiceInvocation) else {
            errorMessage("missing Keychain age identity: \(config.keychainService)")
            errorMessage("run: \(config.scriptName) secrets init")
            throw ExitError(code: 1)
        }
    }

    private func writeKeychainIdentityFile(_ target: String) throws {
        let lookup = keychainIdentity(allowInteraction: !isServiceInvocation)
        guard lookup.availability == .available, let identity = lookup.identity else {
            throw ExitError(code: 1)
        }
        guard fm.createFile(
            atPath: target,
            contents: Data(identity.utf8),
            attributes: [.posixPermissions: NSNumber(value: 0o600)],
        ) else {
            try fail("could not create temporary Keychain identity file")
        }
    }

    private func storeKeychainIdentity(_ identity: String) throws {
        if environment["KEYCHAIN_FAKE_DIR"] != nil {
            let result = runner.run(
                "security",
                ["add-generic-password", "-a", config.keychainAccount, "-s", config.keychainService, "-w", identity, "-U"],
            )
            guard result.status == 0 else {
                throw ExitError(code: Int(result.status))
            }
        } else {
            let status = MacSyncKeychain.storeIdentity(
                identity,
                service: config.keychainService,
                account: config.keychainAccount,
            )
            guard status == 0 else {
                throw ExitError(code: Int(status))
            }
        }
        cachedKeychainIdentity = identity
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
        configuredAgeRecipients().contains(recipient)
    }

    private func cmdSecretsInit() throws {
        try checkRuntime()
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try checkKeychainRuntime()
        try ensureSecretPathsFile()
        try ensureAgeRecipientsFile()
        let tmpDir = try tempPath(prefix: "mac-sync-age-keygen", directory: true)
        defer { try? removePath(tmpDir) }
        let tmpIdentity = "\(tmpDir)/identity.txt"
        let tmpKeygen = "\(tmpDir)/keygen.txt"
        let recipient: String
        if keychainIdentityExists(allowInteraction: true) {
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
        try commitConfigAndPush(message: "chore: configure encrypted secrets", paths: secretConfigurationGitPaths())
    }

    private func secretConfigurationGitPaths() -> [String] {
        guard config.repoDir == config.machinesRepoDir else {
            return ["config/secret-paths.txt", "config/age-recipients.txt"]
        }
        return [
            "machines/\(config.machineName)/config/secret-paths.txt",
            "machines/_shared/config/age-recipients.txt",
        ]
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
            let result = runner.run("git", ["-C", config.repoDir, "push", "-u", "origin", branch])
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
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
            "# Generated by mac-sync. Do not edit.\n# HOME-relative paths included in secrets.tar.gz.age.\n" + readText(includedFile),
        )
    }

    private func writeSecretsRecipientsManifest(_ recipients: [String]) throws {
        try writeText(
            config.secretsRecipientsFile,
            "# Generated by mac-sync. Public recipients for this encrypted snapshot.\n" + recipients.joined(separator: "\n") + "\n",
        )
    }

    private func validateConfiguredKeychainRecipient(identity: String, recipients: [String]) throws {
        let recipient = try recipientFromIdentityFile(identity)
        guard recipients.contains(recipient) else {
            recordHealthCondition(SyncHealthCondition(
                code: .encryptedSecretsIdentityUntrusted,
                component: .encryptedSecrets,
                severity: .error,
                title: "This Mac's age identity is not trusted",
                detail: "The local Keychain identity does not match any recipient in the shared age recipient configuration.",
                recovery: "Run encrypted-secrets setup to add this Mac's public recipient, then retry the sync.",
            ))
            try fail("local Keychain age identity is not a shared recipient; run: \(config.scriptName) secrets init")
        }
    }

    /// Verifies encrypted snapshot access before the sync changes any managed
    /// files. This prevents an encryption configuration failure from leaving a
    /// partially updated data repository that blocks the next safe pull.
    private func preflightSecretsArchive() throws {
        guard secretsSyncEnabled() else { return }
        let recipients = configuredAgeRecipients()
        guard !recipients.isEmpty else { return }
        guard keychainIdentityExists(allowInteraction: !isServiceInvocation) else { return }
        guard runner.commandExists("age"), runner.commandExists("age-keygen") else { return }

        let tmpDir = try tempPath(prefix: "mac-sync-secrets-preflight", directory: true)
        defer { try? removePath(tmpDir) }
        let identity = "\(tmpDir)/identity.txt"
        try writeKeychainIdentityFile(identity)
        try validateConfiguredKeychainRecipient(identity: identity, recipients: recipients)

        guard fm.fileExists(atPath: config.secretsArchive) else { return }
        let decrypt = runner.shell(
            "age -d -i \(ShellQuoter.quote(identity)) \(ShellQuoter.quote(config.secretsArchive)) > /dev/null",
        )
        if decrypt.status != 0 {
            recordHealthCondition(SyncHealthCondition(
                code: .encryptedSecretsSnapshotSkipped,
                component: .encryptedSecrets,
                severity: .error,
                title: "Encrypted secrets could not be verified",
                detail: "Mac Sync could not decrypt the existing encrypted snapshot and left it unchanged.",
                recovery: "Test encrypted-secrets access, repair the identity or recipients if needed, then retry the sync.",
            ))
            try fail("existing encrypted secrets snapshot cannot be decrypted; refusing to replace it")
        }
    }

    private func syncSecretsArchive(mode: String = "auto") throws {
        guard secretsSyncEnabled() else { return }
        let recipients = configuredAgeRecipients()
        guard !recipients.isEmpty else {
            if mode == "required" {
                try fail("no age recipients configured; run: \(config.scriptName) secrets init")
            }
            return
        }
        if mode == "required" {
            try checkKeychainRuntime()
            try requireKeychainIdentity()
        } else {
            let lookup = keychainIdentity(allowInteraction: !isServiceInvocation)
            switch lookup.availability {
            case .available:
                break
            case .missing:
                recordHealthCondition(SyncHealthCondition(
                    code: .encryptedSecretsIdentityMissing,
                    component: .encryptedSecrets,
                    severity: .warning,
                    title: "Encrypted secrets were not updated",
                    detail: "No age identity was found in this Mac's Keychain.",
                    recovery: "Set up encrypted-secrets access, then retry the sync.",
                ))
                warning("no local Keychain age identity; encrypted secrets were not updated")
                return
            case .interactionRequired:
                recordHealthCondition(SyncHealthCondition(
                    code: .encryptedSecretsIdentityUnavailable,
                    component: .encryptedSecrets,
                    severity: .warning,
                    title: "Encrypted secrets need an unlocked Keychain",
                    detail: "The age identity exists but the unattended sync could not access it without user interaction.",
                    recovery: "Unlock this Mac, test encrypted-secrets access, then retry the sync.",
                ))
                warning("Keychain age identity requires user interaction; encrypted secrets were not updated")
                return
            case let .unavailable(status):
                recordHealthCondition(SyncHealthCondition(
                    code: .encryptedSecretsIdentityUnavailable,
                    component: .encryptedSecrets,
                    severity: .warning,
                    title: "Encrypted-secrets Keychain access failed",
                    detail: "The Keychain returned status \(status); no secret material was read or logged.",
                    recovery: "Test encrypted-secrets access from the app, repair Keychain access if needed, then retry.",
                ))
                warning("Keychain age identity is unavailable; encrypted secrets were not updated")
                return
            }
        }
        let missingCommands = ["age", "age-keygen", "gzip", "gtar"].filter {
            !runner.commandExists($0)
        }
        if !missingCommands.isEmpty {
            if mode == "required" {
                try checkSecretsRuntime()
            }
            recordHealthCondition(SyncHealthCondition(
                code: .encryptedSecretsRuntimeUnavailable,
                component: .encryptedSecrets,
                severity: .warning,
                title: "Encrypted-secrets tools are unavailable",
                detail: "Missing commands: \(missingCommands.joined(separator: ", ")).",
                recovery: "Install the missing commands, test encrypted-secrets access, then retry the sync.",
            ))
            warning("encrypted-secrets tools are unavailable; encrypted secrets were not updated")
            return
        }
        let tmpDir = try tempPath(prefix: "mac-sync-secrets", directory: true)
        defer { try? removePath(tmpDir) }
        let included = "\(tmpDir)/included-paths.txt"
        let existingArchive = "\(tmpDir)/existing-secrets.tar.gz"
        let identity = "\(tmpDir)/identity.txt"
        let plainArchive = "\(tmpDir)/secrets.tar.gz"
        let stagedArchive = "\(config.secretsDir)/.secrets.tar.gz.age.\(UUID().uuidString).tmp"
        defer { try? removePath(stagedArchive) }
        let includedPaths = secretManifestPaths().filter { pathExists(sourcePath(for: $0)) }
        if mode == "required" {
            for rel in secretManifestPaths() where !pathExists(sourcePath(for: rel)) {
                info("skip missing secret source: \(sourcePath(for: rel))")
            }
        }
        guard !includedPaths.isEmpty else {
            if mode == "required" {
                warning("no configured secret paths exist; skipping encrypted secrets snapshot")
            }
            return
        }
        try writeText(included, includedPaths.joined(separator: "\n") + "\n")
        if config.dryRun == "1" {
            progressPending("would update encrypted secrets snapshot")
            return
        }
        progressPending("updating encrypted secrets snapshot")
        try ensureDirectory(config.secretsDir)
        try writeKeychainIdentityFile(identity)
        try validateConfiguredKeychainRecipient(identity: identity, recipients: recipients)
        try writePlainSecretsArchive(includedFile: included, target: plainArchive)
        if fm.fileExists(atPath: config.secretsArchive) {
            let decrypt = runner.shell("age -d -i \(ShellQuoter.quote(identity)) \(ShellQuoter.quote(config.secretsArchive)) > \(ShellQuoter.quote(existingArchive))")
            if decrypt.status == 0,
               StreamingFileComparison.equal(plainArchive, existingArchive),
               normalizedRecipients(readConfigLines(config.secretsRecipientsFile)) == recipients
            {
                progressDone("encrypted secrets snapshot unchanged")
                return
            } else if decrypt.status != 0 {
                recordHealthCondition(SyncHealthCondition(
                    code: .encryptedSecretsSnapshotSkipped,
                    component: .encryptedSecrets,
                    severity: .error,
                    title: "Encrypted secrets could not be verified",
                    detail: "Mac Sync could not decrypt the existing encrypted snapshot and left it unchanged.",
                    recovery: "Test encrypted-secrets access, repair the identity or recipients if needed, then retry the sync.",
                ))
                try fail("existing encrypted secrets snapshot cannot be decrypted; refusing to replace it")
            }
        }
        let encrypt = runner.shell("age -R \(ShellQuoter.quote(config.ageRecipientsFile)) -o \(ShellQuoter.quote(stagedArchive)) < \(ShellQuoter.quote(plainArchive))")
        if encrypt.status != 0 {
            fputs(encrypt.combinedOutput, stderr)
            throw ExitError(code: Int(encrypt.status))
        }
        guard rename(stagedArchive, config.secretsArchive) == 0 else {
            try fail("could not replace encrypted secrets snapshot: \(String(cString: strerror(errno)))")
        }
        try writeSecretsIncludedPathsManifest(included)
        try writeSecretsRecipientsManifest(recipients)
        progressDone("updated encrypted secrets snapshot")
    }

    /// Encryption needs public recipients only. A changed recipient set must
    /// be verified interactively before replacing an existing trusted archive.
    private func syncBackgroundSecretsArchive() throws {
        guard enabled(config.secretsSync), !configuredAgeRecipients().isEmpty else { return }
        let recipients = configuredAgeRecipients()
        if fm.fileExists(atPath: config.secretsArchive), normalizedRecipients(readConfigLines(config.secretsRecipientsFile)) != recipients {
            recordHealthCondition(SyncHealthCondition(code: .encryptedSecretsIdentityUntrusted, component: .encryptedSecrets,
                                                      severity: .warning, title: "Encrypted backup recipients need review",
                                                      detail: "The public recipient set changed; the previous archive was preserved.",
                                                      recovery: "Review recipients and run an interactive encrypted-secrets sync once."))
            return
        }
        let missing = ["age", "gtar", "gzip"].filter { !runner.commandExists($0) }
        guard missing.isEmpty else {
            recordHealthCondition(SyncHealthCondition(code: .encryptedSecretsRuntimeUnavailable, component: .encryptedSecrets,
                                                      severity: .warning, title: "Encrypted backup tools are unavailable", detail: missing.joined(separator: ", "),
                                                      recovery: "Reinstall the Homebrew formula and retry."))
            return
        }
        let includedPaths = secretManifestPaths().filter { pathExists(sourcePath(for: $0)) }
        guard !includedPaths.isEmpty else { return }
        let temporary = try tempPath(prefix: "mac-sync-background-secrets", directory: true)
        defer { try? removePath(temporary) }
        let included = "\(temporary)/included.txt"
        let plain = "\(temporary)/archive.tar.gz"
        try writeText(included, includedPaths.joined(separator: "\n") + "\n")
        try writePlainSecretsArchive(includedFile: included, target: plain)
        let digest = try StreamingFileFingerprint.sha256(plain)
        let digestPath = "\(config.statusDir)/\(config.machineName).secrets.sha256"
        if readText(digestPath).trimmed == digest, fm.fileExists(atPath: config.secretsArchive) {
            backgroundCheckpoint.lastSecrets = Date()
            return
        }
        try ensureDirectory(config.secretsDir)
        let staged = "\(config.secretsDir)/.secrets-\(UUID().uuidString).tmp"
        defer { try? removePath(staged) }
        let encrypted = runner.shell("age -R \(ShellQuoter.quote(config.ageRecipientsFile)) -o \(ShellQuoter.quote(staged)) < \(ShellQuoter.quote(plain))")
        guard encrypted.status == 0 else { try fail("background encrypted backup failed; the previous archive was preserved") }
        guard rename(staged, config.secretsArchive) == 0 else { try fail("could not publish encrypted backup") }
        try writeSecretsIncludedPathsManifest(included)
        try writeSecretsRecipientsManifest(recipients)
        try writeText(digestPath, digest + "\n")
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: digestPath)
        backgroundCheckpoint.lastSecrets = Date()
        progressDone("updated encrypted backup using public recipients")
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
            if arg == "--from" {
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                fromMachine = value
                args.removeFirst()
            } else {
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
        guard fm.fileExists(atPath: archive) else {
            try fail("missing encrypted secrets snapshot for machine: \(fromMachine)")
        }
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
        guard fm.fileExists(atPath: archive) else {
            try fail("missing encrypted secrets snapshot for machine: \(fromMachine)")
        }
        let identity = try tempPath(prefix: "mac-sync-age-identity")
        defer { try? removePath(identity) }
        try writeKeychainIdentityFile(identity)
        let entries = try decryptedArchiveEntries(archive: archive, identity: identity)
        for entry in entries where !safeArchiveEntry(entry) {
            try fail("unsafe archive entry: \(entry)")
        }
        let conflicts = entries.filter { !$0.hasSuffix("/") && pathExists(sourcePath(for: $0)) }
        if !force, !conflicts.isEmpty {
            errorMessage("secret restore would overwrite existing files; re-run with --force")
            for conflict in conflicts {
                fputs("  \(conflict)\n", stderr)
            }
            throw ExitError(code: 1)
        }
        if config.dryRun == "1" {
            info("would restore encrypted secrets snapshot from machine: \(fromMachine)")
            return
        }
        info("restoring encrypted secrets snapshot from machine: \(fromMachine)")
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
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncSecretsArchive(mode: "required")
        try commitAndPush()
    }

    private func cmdSecrets(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty {
            args.removeFirst()
        }
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
        if !args.isEmpty {
            args.removeFirst()
        }
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
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncHomebrewPackages()
        if config.dryRun != "1" {
            try writeMachineMetadata()
        }
        try commitAndPush()
    }

    private func parseFromOption(_ args: [String], commandName: String) throws -> String {
        var args = args
        var machine = config.machineName
        while !args.isEmpty {
            let arg = args.removeFirst()
            if arg == "--from" {
                guard let value = args.first else { try fail("missing machine name after --from", code: 2) }
                machine = value
                args.removeFirst()
            } else {
                try fail("unknown \(commandName) option: \(arg)", code: 2)
            }
        }
        return try resolveRequestedMachine(machine)
    }

    private func cmdPackagesDiff(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try printHomebrewRestoreCommands(machine: parseFromOption(args, commandName: "packages diff"))
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
        try installHomebrewSnapshot(machine: resolveRequestedMachine(machine), formulaeOnly: formulaeOnly, adminUser: adminUser)
    }

    private func cmdPackagesList(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try listHomebrewSnapshot(machine: parseFromOption(args, commandName: "packages list"))
    }

    private func cmdEditor(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "help"
        if !args.isEmpty {
            args.removeFirst()
        }
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
        try pullRepoIfSafe()
        try pullMachinesRepoIfSafe()
        try syncVscodeExtensions()
        if config.dryRun != "1" {
            try writeMachineMetadata()
        }
        try commitAndPush()
    }

    private func cmdEditorDiff(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try printVscodeExtensionRestoreCommands(machine: parseFromOption(args, commandName: "editor diff"))
    }

    private func cmdEditorInstall(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        try installVscodeExtensionsSnapshot(machine: parseFromOption(args, commandName: "editor install"))
    }

    private func cmdEditorList(_ args: [String]) throws {
        try checkRuntime()
        try pullMachinesRepoIfSafe()
        let machine = try parseFromOption(args, commandName: "editor list")
        let file = vscodeExtensionsFile(for: machine)
        guard fm.fileExists(atPath: file) else { try fail("missing VS Code extension snapshot: \(file)") }
        info(file)
        for line in readText(file).splitLines() {
            info("  \(line)")
        }
    }

    private func cmdManifest(_ arguments: [String]) throws {
        var args = arguments
        let command = args.first ?? "list"
        if !args.isEmpty {
            args.removeFirst()
        }
        switch command {
        case "list":
            guard args.isEmpty else { try fail("manifest list does not accept options", code: 2) }
            try checkRuntime()
            for path in try manifestPaths() {
                info(path)
            }
        case "configured":
            guard args.isEmpty else { try fail("manifest configured does not accept options", code: 2) }
            try checkRuntime()
            for path in try configuredManifestPaths() {
                info(path)
            }
        case "dynamic":
            guard args.isEmpty else { try fail("manifest dynamic does not accept options", code: 2) }
            try checkRuntime()
            for path in dynamicManifestPaths() {
                info(path)
            }
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

    private func isItemizedRsyncChangeCode(_ code: String) -> Bool {
        if code == "*deleting" {
            return true
        }
        let characters = Array(code)
        guard characters.count >= 2 else { return false }
        return "<>ch.".contains(characters[0]) && "fdLDS".contains(characters[1])
    }

    private func printSyncedDirectoryChanges(
        srcRoot: String,
        destRoot: String,
        changes: String,
        destinationWasNew: Bool = false,
    ) {
        for line in changes.splitLines() where !line.isEmpty {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2 else { continue }
            let code = parts[0]
            guard isItemizedRsyncChangeCode(code) else { continue }
            let rel = parts[1]
            guard !rel.isEmpty, rel != ".", rel != "./" else { continue }
            if code == "*deleting" {
                progressDone("removed snapshot path: \(destRoot)/\(rel)")
            } else if code.dropFirst().first != "d" {
                let action = destinationWasNew || code.contains("+++++++++") ? "new snapshot file" : "updated snapshot file"
                progressDone("\(action): \(srcRoot)/\(rel) -> \(destRoot)/\(rel)")
            }
        }
    }

    @discardableResult
    private func recordItemizedTransfers(
        _ changes: String,
        selectionPath: String,
        sourceRoot: String,
        destinationRoot: String,
        direction: SyncHistoryTransferDirection,
        destinationWasNew: Bool = false,
    ) -> Int {
        var transferCount = 0
        for line in changes.splitLines() where !line.isEmpty {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2 else { continue }
            let code = parts[0]
            guard isItemizedRsyncChangeCode(code) else { continue }
            let relativePath = parts[1]
            guard !relativePath.isEmpty, relativePath != ".", relativePath != "./" else { continue }

            if code == "*deleting" {
                recordHistoryTransfer(
                    direction: direction,
                    outcome: .removed,
                    path: selectionPath,
                    source: "\(sourceRoot)/\(relativePath)",
                    destination: "\(destinationRoot)/\(relativePath)",
                    detail: "Removed from the destination",
                )
                transferCount += 1
                continue
            }

            // rsync itemises directories with a d in its second column. The
            // individual file entries are the useful history detail.
            guard code.dropFirst().first != "d" else { continue }
            let outcome: SyncHistoryTransferOutcome = destinationWasNew || code.contains("+++++++++") ? .new : .updated
            recordHistoryTransfer(
                direction: direction,
                outcome: outcome,
                path: selectionPath,
                source: "\(sourceRoot)/\(relativePath)",
                destination: "\(destinationRoot)/\(relativePath)",
            )
            transferCount += 1
        }
        return transferCount
    }

    private func recordHistoryTransfer(
        direction: SyncHistoryTransferDirection,
        outcome: SyncHistoryTransferOutcome,
        path: String,
        source: String,
        destination: String,
        detail: String? = nil,
    ) {
        guard historyActive else { return }
        do {
            try historyJournal?.append(SyncHistoryEntry(
                direction: direction,
                outcome: outcome,
                path: path,
                source: source,
                destination: destination,
                detail: detail,
            ))
        } catch { historyWriteFailed = true }
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
                    recordHistoryTransfer(
                        direction: .upload,
                        outcome: .removed,
                        path: rel,
                        source: src,
                        destination: dest,
                        detail: "The selected source path no longer exists",
                    )
                }
            } else if config.dryRun != "1" {
                recordHistoryTransfer(
                    direction: .upload,
                    outcome: .skipped,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: "The selected source path does not exist",
                )
            }
            return
        }
        if config.dryRun == "1" {
            progressPending("\(isDirectory(src) ? "would sync directory" : "would sync file"): \(src) -> \(dest)")
            return
        }
        try ensureDirectory(parent)
        var args = isDirectory(src) ? ["-a", "--delete", "--itemize-changes", "--out-format=%i %n"] : ["-aL", "--itemize-changes", "--out-format=%i %n"]
        if fm.fileExists(atPath: config.excludesFile) {
            args.append("--exclude-from=\(config.excludesFile)")
        }
        if isDirectory(src) {
            let destinationExisted = pathExists(dest)
            try ensureDirectory(dest)
            var transferCount = 0
            let result = runner.run("rsync", args + ["\(src)/", "\(dest)/"], onStdoutLine: { line in
                self.printSyncedDirectoryChanges(srcRoot: src, destRoot: dest, changes: line, destinationWasNew: !destinationExisted)
                transferCount += self.recordItemizedTransfers(line, selectionPath: rel, sourceRoot: src, destinationRoot: dest,
                                                              direction: .upload, destinationWasNew: !destinationExisted)
            })
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            if transferCount == 0, !destinationExisted, treeFileCount(dest) > 0 {
                // Some older macOS rsync builds complete the copy without
                // emitting file-level itemisation. Preserve a useful activity
                // and history record for that successful first snapshot.
                progressDone("new snapshot file: \(src) -> \(dest)")
                recordHistoryTransfer(
                    direction: .upload,
                    outcome: .new,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: "Copied a new directory snapshot",
                )
            } else if transferCount == 0 {
                recordHistoryTransfer(
                    direction: .upload,
                    outcome: .skipped,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: "No file changes were needed",
                )
            }
        } else {
            let destinationExisted = pathExists(dest)
            let result = runner.run("rsync", args + [src, dest])
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            if !result.stdout.trimmed.isEmpty {
                let action = destinationExisted ? "updated snapshot file" : "new snapshot file"
                progressDone("\(action): \(src) -> \(dest)")
                recordHistoryTransfer(
                    direction: .upload,
                    outcome: destinationExisted ? .updated : .new,
                    path: rel,
                    source: src,
                    destination: dest,
                )
            } else {
                recordHistoryTransfer(
                    direction: .upload,
                    outcome: .skipped,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: "The destination already matched",
                )
            }
        }
    }

    private func restoreOnePath(machine: String, rel: String, force: Bool) throws {
        let src = snapshotPath(machine: machine, rel: rel)
        let dest = sourcePath(for: rel)
        let parent = (dest as NSString).deletingLastPathComponent
        let destinationExisted = pathExists(dest)
        guard pathExists(src) else {
            info("skip missing snapshot path: \(src)")
            recordHistoryTransfer(
                direction: .download,
                outcome: .skipped,
                path: rel,
                source: src,
                destination: dest,
                detail: "The requested snapshot path does not exist",
            )
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
                    recordHistoryTransfer(
                        direction: .download,
                        outcome: .skipped,
                        path: rel,
                        source: src,
                        destination: dest,
                        detail: "A local non-directory is already present",
                    )
                    return
                }
            }
            if config.dryRun == "1" {
                info("would restore directory: \(src) -> \(dest)")
                return
            }
            try ensureDirectory(dest)
            info("restore directory: \(src) -> \(dest)")
            var args = ["-a", "--itemize-changes", "--out-format=%i %n"]
            if !force {
                // A restore is an explicit import into this Mac. Its existing
                // files remain authoritative unless the caller chose --force.
                args.append("--ignore-existing")
            }
            if fm.fileExists(atPath: config.excludesFile) {
                args.append("--exclude-from=\(config.excludesFile)")
            }
            var transferCount = 0
            let result = runner.run("rsync", args + ["\(src)/", "\(dest)/"], onStdoutLine: { line in
                transferCount += self.recordItemizedTransfers(line, selectionPath: rel, sourceRoot: src, destinationRoot: dest, direction: .download)
            })
            if result.status != 0 {
                fputs(result.combinedOutput, stderr)
                throw ExitError(code: Int(result.status))
            }
            if transferCount == 0 {
                recordHistoryTransfer(
                    direction: .download,
                    outcome: .skipped,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: force ? "No file changes were needed" : "No files were copied; local files already existed or already matched",
                )
            }
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
                recordHistoryTransfer(
                    direction: .download,
                    outcome: .skipped,
                    path: rel,
                    source: src,
                    destination: dest,
                    detail: "A local directory is already present",
                )
                return
            }
        }
        if !force, pathExists(dest) {
            let matchesSnapshot = filesEqual(src, dest)
            info(matchesSnapshot ? "unchanged local file: \(dest)" : "skip existing local file: \(dest)")
            recordHistoryTransfer(
                direction: .download,
                outcome: .skipped,
                path: rel,
                source: src,
                destination: dest,
                detail: matchesSnapshot ? "The local file already matches" : "The local file remains the source of truth",
            )
            return
        }
        if config.dryRun == "1" {
            info("would restore file: \(src) -> \(dest)")
            return
        }
        try ensureDirectory(parent)
        progressPending("restoring file: \(src) -> \(dest)")
        var args = ["-a"]
        if fm.fileExists(atPath: config.excludesFile) {
            args.append("--exclude-from=\(config.excludesFile)")
        }
        let result = runner.run("rsync", args + [src, dest])
        if result.status != 0 {
            fputs(result.combinedOutput, stderr)
            throw ExitError(code: Int(result.status))
        }
        let action = destinationExisted ? "updated local file" : "new local file"
        progressDone("\(action): \(src) -> \(dest)")
        recordHistoryTransfer(
            direction: .download,
            outcome: destinationExisted ? .updated : .new,
            path: rel,
            source: src,
            destination: dest,
        )
    }

    private func filesEqual(_ left: String, _ right: String) -> Bool {
        StreamingFileComparison.equal(left, right)
    }

    private func writeMachineMetadata() throws {
        let computerName = runner.commandExists("scutil") ? runner.run("scutil", ["--get", "ComputerName"]).stdout.trimmed : ""
        let localHostName = runner.commandExists("scutil") ? runner.run("scutil", ["--get", "LocalHostName"]).stdout.trimmed : ""
        let osName = runner.commandExists("sw_vers") ? runner.run("sw_vers", ["-productName"]).stdout.trimmed : ""
        let osVersion = runner.commandExists("sw_vers") ? runner.run("sw_vers", ["-productVersion"]).stdout.trimmed : ""
        let arch = runner.run("uname", ["-m"]).stdout.trimmed
        let homeMetrics = treeMetrics(config.machineHomeDir)
        let absoluteMetrics = treeMetrics(config.machineAbsoluteDir)
        try writeText(
            "\(config.machineDir)/MACHINE.md",
            """
            # \(config.machineName)

            This directory contains the curated dotfile snapshot for `\(config.machineName)`.

            - ComputerName: `\(computerName.isEmpty ? "unknown" : computerName)`
            - LocalHostName: `\(localHostName.isEmpty ? "unknown" : localHostName)`
            - OS: `\(osName.isEmpty ? "unknown" : osName) \(osVersion.isEmpty ? "unknown" : osVersion)`
            - Architecture: `\(arch.isEmpty ? "unknown" : arch)`
            - SnapshotFiles: `\(homeMetrics.count + absoluteMetrics.count)`
            - SnapshotBytes: `\(homeMetrics.bytes + absoluteMetrics.bytes)`
            """,
        )
    }

    private func gitNetworkFailureKind(_ output: String) -> GitNetworkFailureKind {
        let message = output.lowercased()
        let authenticationPatterns = [
            "authentication failed",
            "could not read username",
            "permission denied (publickey)",
            "terminal prompts disabled",
            "repository not found",
            "requested url returned error: 401",
            "requested url returned error: 403",
        ]
        if authenticationPatterns.contains(where: message.contains) {
            return .authentication
        }
        let unavailablePatterns = [
            "could not resolve host",
            "network is unreachable",
            "connection timed out",
            "connection refused",
            "operation timed out",
            "command timed out",
            "no route to host",
            "could not resolve proxy",
            "connection reset",
            "requested url returned error: 408",
            "requested url returned error: 429",
            "requested url returned error: 500",
            "requested url returned error: 502",
            "requested url returned error: 503",
            "requested url returned error: 504",
        ]
        if unavailablePatterns.contains(where: message.contains) {
            return .unavailable
        }
        return .other
    }

    private func gitNetworkArguments(_ arguments: [String]) -> [String] {
        guard useSSHForGitHub else { return arguments }
        return [
            "-c",
            "url.\(gitHubSSHTransport).insteadOf=https://github.com/",
        ] + arguments
    }

    private var gitNetworkEnvironment: [String: String] {
        [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "/usr/bin/false",
            "GCM_INTERACTIVE": "never",
            "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10",
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "http.lowSpeedLimit",
            "GIT_CONFIG_VALUE_0": "1024",
            "GIT_CONFIG_KEY_1": "http.lowSpeedTime",
            "GIT_CONFIG_VALUE_1": "30",
        ]
    }

    private func enableSSHGitHubFallback(repo: String, attempt: Int) -> Bool {
        let remote = runner.run("git", ["-C", repo, "remote", "get-url", "origin"])
        guard remote.status == 0,
              let sshRemote = MacSyncPaths.githubSSHRemoteURL(remote.stdout.trimmed)
        else {
            return false
        }
        var probe = runner.run(
            "git",
            ["ls-remote", sshRemote, "HEAD"],
            extraEnvironment: gitNetworkEnvironment,
            timeout: 30,
        )
        if probe.status != 0, sshRemote.hasPrefix("git@github.com:") {
            let path = String(sshRemote.dropFirst("git@github.com:".count))
            probe = runner.run("git", ["ls-remote", "ssh://git@ssh.github.com:443/\(path)", "HEAD"],
                               extraEnvironment: gitNetworkEnvironment, timeout: 30)
            if probe.status == 0 {
                gitHubSSHTransport = "ssh://git@ssh.github.com:443/"
            }
        }
        recordCommandDiagnostic(
            step: "Testing SSH access to the data repository",
            command: "git ls-remote <ssh-origin> HEAD",
            attempt: attempt,
            result: probe,
        )
        guard probe.status == 0 else { return false }
        useSSHForGitHub = true
        progressDone("using verified SSH access for this GitHub sync")
        return true
    }

    private func runGitNetworkOperation(
        step: String,
        message: String,
        repo: String,
        arguments: [String],
        attempt: Int,
    ) -> Bool {
        progressPending(message)
        var commandArguments = gitNetworkArguments(arguments)
        var result = runner.run(
            "git",
            commandArguments,
            extraEnvironment: gitNetworkEnvironment,
            timeout: 120,
        )
        recordCommandDiagnostic(
            step: step,
            command: "git \(arguments.dropFirst(2).joined(separator: " "))",
            attempt: attempt,
            result: result,
        )

        if result.status != 0,
           !useSSHForGitHub,
           gitNetworkFailureKind(result.combinedOutput) != .other,
           enableSSHGitHubFallback(repo: repo, attempt: attempt)
        {
            commandArguments = gitNetworkArguments(arguments)
            result = runner.run(
                "git",
                commandArguments,
                extraEnvironment: gitNetworkEnvironment,
                timeout: 120,
            )
            recordCommandDiagnostic(
                step: "\(step) using SSH",
                command: "git \(arguments.dropFirst(2).joined(separator: " "))",
                attempt: attempt,
                result: result,
            )
        }

        lastCommandOutput = result.combinedOutput
        lastCommandStatus = result.status
        return result.status == 0
    }

    private func recordRemoteFailure(
        output: String,
        title: String,
        recovery: String,
    ) {
        backgroundConnectivityDeferred = isServiceInvocation && gitNetworkFailureKind(output) == .unavailable
        let code: SyncHealthConditionCode = switch gitNetworkFailureKind(output) {
        case .authentication:
            .remoteAuthenticationFailed
        case .unavailable:
            .remoteUnavailable
        case .other:
            .remoteRefreshFailed
        }
        recordHealthCondition(SyncHealthCondition(
            code: code,
            component: .remoteRepository,
            severity: .error,
            title: title,
            detail: safeDiagnosticOutput(output).ifEmpty("Git exited with status \(lastCommandStatus)."),
            recovery: recovery,
        ))
    }

    private func pullGitRepoIfSafe(repo: String, label: String) throws {
        guard repoHasOrigin(repo) else {
            recordHealthCondition(SyncHealthCondition(
                code: .remoteConfigurationMissing,
                component: .remoteRepository,
                severity: .warning,
                title: "The \(label) has no remote",
                detail: "Mac Sync could not refresh or publish this repository because origin is not configured.",
                recovery: "Configure an origin remote, test repository access, then retry.",
            ))
            warning("no origin remote configured for \(label); skipping git pull")
            return
        }
        guard repoClean(repo) else {
            recordHealthCondition(SyncHealthCondition(
                code: .remoteRefreshBlockedByLocalChanges,
                component: .remoteRepository,
                severity: .warning,
                title: "The \(label) has local changes",
                detail: "Mac Sync preserved the local edits and did not refresh the repository.",
                recovery: "Commit or revert the local changes, then retry.",
            ))
            warning("\(label) has local changes; skipping pre-operation git pull")
            return
        }
        for attempt in networkAttempts {
            if runGitNetworkOperation(
                step: "Refreshing \(label)",
                message: attempt == 1
                    ? "pulling latest \(label) changes"
                    : "retrying \(label) refresh (\(attempt)/3)",
                repo: repo,
                arguments: ["-C", repo, "pull", "--ff-only"],
                attempt: attempt,
            ) {
                progressDone(lastCommandOutput.contains("Already up to date.")
                    ? "\(label) already up to date"
                    : "pulled latest \(label) changes")
                return
            }
            if attempt < networkAttempts.upperBound {
                usleep(useconds_t(attempt * 1_000_000))
            }
        }
        recordRemoteFailure(
            output: lastCommandOutput,
            title: "The \(label) could not be refreshed",
            recovery: "Test repository access, use SSH if offered, then retry.",
        )
        let diagnostic = safeDiagnosticOutput(lastCommandOutput)
        if !diagnostic.isEmpty {
            fputs("\(diagnostic)\n", stderr)
        }
        try fail("the \(label) could not be refreshed; sync stopped before changing snapshots")
    }

    private func pullRepoIfSafe() throws {
        guard config.repoDir != config.machinesRepoDir else { return }
        try pullGitRepoIfSafe(repo: config.repoDir, label: "local repo")
    }

    private func pullMachinesRepoIfSafe() throws {
        guard repoHasOrigin(config.machinesRepoDir) else {
            recordHealthCondition(SyncHealthCondition(
                code: .remoteConfigurationMissing,
                component: .remoteRepository,
                severity: .warning,
                title: "The data repository has no remote",
                detail: "Snapshots can be written locally but cannot be refreshed or published.",
                recovery: "Configure an origin remote, test repository access, then retry.",
            ))
            warning("no origin remote configured for machines repo; skipping git pull")
            return
        }
        let snapshotPaths = managedSnapshotPaths()
        guard repoPathsClean(config.machinesRepoDir, snapshotPaths) else {
            currentMachineLocalChanges = repoLocalChanges(
                repo: config.machinesRepoDir,
                restrictingTo: snapshotPaths,
            )
            recordHealthCondition(SyncHealthCondition(
                code: .remoteRefreshBlockedByLocalChanges,
                component: .remoteRepository,
                severity: .warning,
                title: "Snapshot changes are blocking the remote refresh",
                detail: currentMachineLocalChanges.joined(separator: "\n"),
                recovery: "Review and commit or revert these snapshot changes, then retry.",
            ))
            warning("current machine snapshot has local changes; skipping pre-operation git pull")
            return
        }
        // An offline publish can leave a local commit while a peer advances
        // upstream. Reconcile it before copying another generation of files.
        if branchAheadOfUpstream(config.machinesRepoDir) {
            guard rebaseMachinesRepoBeforePush() else {
                try fail("pending snapshots could not be reconciled; local commits were preserved")
            }
            return
        }
        let args = repoClean(config.machinesRepoDir)
            ? ["-C", config.machinesRepoDir, "pull", "--ff-only"]
            : ["-C", config.machinesRepoDir, "pull", "--ff-only", "--autostash"]
        let message = repoClean(config.machinesRepoDir)
            ? "pulling latest machines repo changes"
            : "pulling latest machines repo changes with unrelated local edits preserved"
        for attempt in networkAttempts {
            if runGitNetworkOperation(
                step: "Refreshing the data repository",
                message: attempt == 1 ? message : "retrying data repository refresh (\(attempt)/3)",
                repo: config.machinesRepoDir,
                arguments: args,
                attempt: attempt,
            ) {
                progressDone(lastCommandOutput.contains("Already up to date.")
                    ? "machines repo already up to date"
                    : "pulled latest machines repo changes")
                return
            }
            if attempt < networkAttempts.upperBound {
                usleep(useconds_t(attempt * 1_000_000))
            }
        }
        recordRemoteFailure(
            output: lastCommandOutput,
            title: "The data repository could not be refreshed",
            recovery: "Test GitHub access, use SSH if offered, then retry the sync.",
        )
        let diagnostic = safeDiagnosticOutput(lastCommandOutput)
        if !diagnostic.isEmpty {
            fputs("\(diagnostic)\n", stderr)
        }
        try fail("the data repository could not be refreshed; sync stopped before changing snapshots")
    }

    private func rebaseMachinesRepoBeforePush() -> Bool {
        guard branchHasUpstream(config.machinesRepoDir) else {
            progressDone("no upstream branch yet; skipping pre-push pull")
            return true
        }
        guard runGitNetworkOperation(
            step: "Fetching the data repository before publish",
            message: "fetching machines repo upstream",
            repo: config.machinesRepoDir,
            arguments: ["-C", config.machinesRepoDir, "fetch", "--quiet"],
            attempt: 1,
        ) else {
            recordRemoteFailure(
                output: lastCommandOutput,
                title: "The data repository could not be refreshed before publish",
                recovery: "Test GitHub access, use SSH if offered, then retry the sync.",
            )
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
        guard !machinesRebaseInProgress() else {
            lastCommandOutput = "A Git rebase is already in progress. Finish or abort it before syncing."
            return false
        }
        guard runGitNetworkOperation(
            step: "Rebasing the data repository before publish",
            message: "rebasing machines repo before push",
            repo: config.machinesRepoDir,
            arguments: ["-C", config.machinesRepoDir, "pull", "--rebase", "--autostash"],
            attempt: 1,
        ) else {
            if machinesRebaseInProgress() {
                _ = runner.run("git", ["-C", config.machinesRepoDir, "rebase", "--abort"])
            }
            recordRemoteFailure(
                output: lastCommandOutput,
                title: "The data repository could not be rebased before publish",
                recovery: "Review the Git state, test repository access, then retry the sync.",
            )
            return false
        }
        progressDone("rebased machines repo before push")
        return true
    }

    private func machinesRebaseInProgress() -> Bool {
        ["rebase-merge", "rebase-apply"].contains { name in
            let result = runner.run("git", ["-C", config.machinesRepoDir, "rev-parse", "--path-format=absolute", "--git-path", name])
            return result.status == 0 && fm.fileExists(atPath: result.stdout.trimmed)
        }
    }

    private func pushMachinesRepoWithRetries(branch: String) -> Bool {
        for attempt in networkAttempts {
            guard rebaseMachinesRepoBeforePush() else { return false }
            if runGitNetworkOperation(
                step: "Publishing the data repository",
                message: "pushing \(branch) to origin",
                repo: config.machinesRepoDir,
                arguments: ["-C", config.machinesRepoDir, "push", "-u", "origin", branch],
                attempt: attempt,
            ) {
                progressDone("pushed \(branch) to origin")
                return true
            }
            if attempt == networkAttempts.upperBound {
                recordRemoteFailure(
                    output: lastCommandOutput,
                    title: "The data repository could not be published",
                    recovery: "Test GitHub access, use SSH if offered, then retry the sync.",
                )
                return false
            }
            warning("machines repo push failed; rebasing and retrying (\(attempt)/3)")
        }
        return false
    }

    private func commitAndPush() throws {
        if config.dryRun == "1" {
            progressPending("dry run enabled; skipping git commit and push")
            return
        }
        let snapshotPaths = managedSnapshotPaths()
        guard runWithProgressCommand(
            "checking machine snapshot changes",
            "git",
            ["-C", config.machinesRepoDir, "add", "--all", "--"] + snapshotPaths,
        ) else {
            printProgressCommandOutput()
            throw ExitError(code: 1)
        }
        var committed = false
        if runner.run(
            "git",
            ["-C", config.machinesRepoDir, "diff", "--cached", "--quiet", "--"] + snapshotPaths,
        ).status == 0 {
            progressDone("no machine snapshot changes to commit")
        } else {
            let message = "chore(\(config.machineName)): sync machine state"
            guard runWithProgressCommand(
                "committing machine snapshot changes",
                "git",
                ["-C", config.machinesRepoDir, "commit", "-m", message, "--"] + snapshotPaths,
            ) else {
                printProgressCommandOutput()
                throw ExitError(code: 1)
            }
            progressDone("committed machine snapshot changes")
            committed = true
        }
        guard repoHasOrigin(config.machinesRepoDir) else {
            recordHealthCondition(SyncHealthCondition(
                code: .remoteConfigurationMissing,
                component: .remoteRepository,
                severity: .warning,
                title: "The data repository has no remote",
                detail: "The snapshot was updated locally but could not be published.",
                recovery: "Configure an origin remote, test repository access, then retry.",
            ))
            warning("no origin remote configured for machines repo; skipping git push")
            return
        }
        let branch = runner.run("git", ["-C", config.machinesRepoDir, "branch", "--show-current"]).stdout.trimmed
        guard !branch.isEmpty else {
            recordHealthCondition(SyncHealthCondition(
                code: .remoteConfigurationMissing,
                component: .remoteRepository,
                severity: .warning,
                title: "The data repository is on a detached commit",
                detail: "Mac Sync cannot publish a detached HEAD.",
                recovery: "Switch the data repository to its normal branch, then retry.",
            ))
            warning("detached HEAD; skipping git push")
            return
        }
        if !committed, !branchAheadOfUpstream(config.machinesRepoDir) {
            progressDone("no local commits to push")
            return
        }
        guard pushMachinesRepoWithRetries(branch: branch) else { throw ExitError(code: 1) }
    }

    private func acquireLock() throws {
        let pidFile = "\(config.lockDir)/pid"
        guard let lock = try MacSyncProcessLock.acquire(
            at: URL(fileURLWithPath: pidFile),
        ) else {
            let lockPID = readText(pidFile).trimmed
            let processDescription = lockPID.isEmpty ? "" : ": pid \(lockPID)"
            info("another mac-sync run is active; exiting\(processDescription)")
            throw ExitError(code: 0)
        }
        operationLock = lock
    }

    private func releaseLock() {
        operationLock = nil
    }

    private func statusTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        return formatter.string(from: Date())
    }

    private func treeFileCount(_ dir: String) -> Int {
        treeMetrics(dir).count
    }

    private func treeByteCount(_ dir: String) -> Int {
        treeMetrics(dir).bytes
    }

    private func treeMetrics(_ dir: String) -> (count: Int, bytes: Int) {
        guard let enumerator = fm.enumerator(atPath: dir) else { return (0, 0) }
        var count = 0
        var bytes = 0
        while autoreleasepool(invoking: {
            guard let path = enumerator.nextObject() as? String else { return false }
            let full = "\(dir)/\(path)"
            guard !isDirectory(full) else { return true }
            count += 1
            bytes += (try? fm.attributesOfItem(atPath: full)[.size] as? NSNumber)?.intValue ?? 0
            return true
        }) {}
        return (count, bytes)
    }

    private func changedMachineMetrics() -> (count: Int, bytes: Int) {
        let result = runner.run("git", ["-C", config.machinesRepoDir, "ls-files", "--modified", "--deleted", "--others", "--exclude-standard", "-z", "--", "machines/\(config.machineName)"])
        let files = result.stdout.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
        let bytes = files.reduce(0) { total, rel -> Int in
            autoreleasepool {
                let path = "\(config.machinesRepoDir)/\(rel)"
                guard let size = try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber else { return total }
                return total + size.intValue
            }
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
        healthConditions = []
        commandDiagnostics = []
        currentMachineLocalChanges = []
        cachedKeychainIdentity = nil
        useSSHForGitHub = false
        startedFileCount = 0
        startedByteCount = 0
        lastUpdatedFileCount = 0
        lastUpdatedByteCount = 0
        lastNetByteChange = 0
        lastStorageFileCount = 0
        lastStorageByteCount = 0
        startHistory(action: .sync, startedAt: runStartedAt, startedEpoch: runStartedEpoch)
    }

    private func startHistory(
        action: SyncHistoryAction,
        sourceMachine: String? = nil,
        startedAt: String? = nil,
        startedEpoch: Int? = nil,
    ) {
        guard config.dryRun != "1" else { return }
        guard (try? ensureDirectory(config.syncHistoryDir)) != nil else { return }
        historyActive = true
        historyAction = action
        historySourceMachine = sourceMachine
        historyStartedAt = startedAt ?? statusTimestamp()
        historyStartedEpoch = startedEpoch ?? Int(Date().timeIntervalSince1970)
        historyJournal = try? HistoryJournal(directory: config.syncHistoryDir)
        historyWriteFailed = historyJournal == nil
    }

    private func finishHistory(_ result: SyncHistoryResult, finishedAt: String? = nil) {
        guard historyActive, let action = historyAction else { return }
        let completedAt = finishedAt ?? statusTimestamp()
        let duration = max(0, Int(Date().timeIntervalSince1970) - historyStartedEpoch)
        let record = SyncHistoryRecord(
            id: historyJournal?.id ?? UUID().uuidString,
            action: action,
            sourceMachine: historySourceMachine,
            result: result,
            timing: SyncHistoryTiming(
                startedAt: historyStartedAt,
                finishedAt: completedAt,
                durationSeconds: duration,
            ),
            entries: [],
            diagnostics: SyncHistoryDiagnostics(
                warningCount: warningCount,
                errorCount: errorCount,
                warnings: warningMessages,
                errors: errorMessages,
                conditions: healthConditions,
                commands: commandDiagnostics,
            ),
        )

        defer {
            historyActive = false
            historyAction = nil
            historySourceMachine = nil
            historyJournal = nil
        }

        do {
            if historyWriteFailed {
                throw NSError(domain: "MacSyncHistory", code: 3)
            }
            try historyJournal?.finish(record)
        } catch {
            fputs("WARN: the local history journal could not be completed; snapshot data was preserved.\n", stderr)
        }
    }

    private func captureSyncStartMetrics() {
        let metrics = treeMetrics(config.machineDir)
        startedFileCount = metrics.count
        startedByteCount = metrics.bytes
    }

    private func captureSyncFinishMetrics() {
        let footprint = treeMetrics(config.machineDir)
        lastStorageFileCount = footprint.count
        lastStorageByteCount = footprint.bytes
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let conditions = try? encoder.encode(healthConditions) {
            try? conditions.write(to: URL(fileURLWithPath: config.syncConditionsFile), options: .atomic)
        }
        if let commands = try? encoder.encode(commandDiagnostics) {
            try? commands.write(to: URL(fileURLWithPath: config.syncCommandsFile), options: .atomic)
        }
        try? writeText(
            config.syncLocalChangesFile,
            currentMachineLocalChanges.joined(separator: "\n") + (currentMachineLocalChanges.isEmpty ? "" : "\n"),
        )
        let lastCommit = runner.run("git", ["-C", config.machinesRepoDir, "rev-parse", "--short", "HEAD"]).stdout.trimmed.ifEmpty("unknown")
        let rawRemoteRepo = runner.run(
            "git",
            ["-C", config.machinesRepoDir, "remote", "get-url", "origin"],
        ).stdout.trimmed
        let remoteRepo = MacSyncPaths.normalizeGitHubRemoteURL(rawRemoteRepo)
            ?? safeDiagnosticOutput(rawRemoteRepo).ifEmpty("none")
        let historyResult: SyncHistoryResult = if backgroundDeferralReason != nil || backgroundConnectivityDeferred {
            .deferred
        } else if status != 0 {
            .failed
        } else if healthConditions.isEmpty {
            .success
        } else {
            .partial
        }
        let text = """
        machine=\(config.machineName)
        result=\(historyResult.rawValue)
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
        finishHistory(historyResult, finishedAt: finishedAt)
        try? writeText(config.syncStatusFile, text)
        runActive = false
    }

    private func cmdSync() throws {
        try checkRuntime()
        try acquireLock()
        defer { releaseLock() }
        try startSyncStatus()
        let runningPath = "\(config.statusDir)/\(config.machineName).running"
        try writeText(runningPath, "\(getpid())\n")
        defer { try? fm.removeItem(atPath: runningPath) }
        do {
            try pullRepoIfSafe()
            try pullMachinesRepoIfSafe()
            try preflightSecretsArchive()
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
            for rel in manifest {
                try backgroundBoundary()
                try autoreleasepool { try syncOnePath(rel) }
            }
            progressDone("synced configured paths")
            try pruneStaleDynamicPaths(currentDynamic: dynamicExtra, configured: configured)
            try backgroundBoundary()
            if !isServiceInvocation || backgroundCheckpoint.lastInventory.map({ Date().timeIntervalSince($0) >= 86400 }) ?? true {
                try syncHomebrewPackages()
                try backgroundBoundary()
                try syncVscodeExtensions()
                try syncGitHubRepositories()
                if isServiceInvocation {
                    backgroundCheckpoint.lastInventory = Date()
                }
            }
            if isServiceInvocation {
                if !fm.fileExists(atPath: config.secretsArchive) || backgroundCheckpoint.lastSecrets.map({ Date().timeIntervalSince($0) >= 86400 }) ?? true {
                    try syncBackgroundSecretsArchive()
                }
            } else {
                try syncSecretsArchive(mode: "auto")
            }
            if config.dryRun != "1" {
                if dynamicRefsEnabled() {
                    try writeDynamicPathsManifest(dynamicExtra)
                }
                try writeMachineMetadata()
            }
            captureSyncFinishMetrics()
            try commitAndPush()
            if !isServiceInvocation {
                var checkpoint = BackgroundCheckpoint.load(from: checkpointPath, repository: config.machinesRepoDir)
                checkpoint.consecutiveFailures = 0
                checkpoint.nextAttempt = nil
                checkpoint.lastSuccess = Date()
                checkpoint.lastInventory = Date()
                if enabled(config.secretsSync), fm.fileExists(atPath: config.secretsArchive) {
                    checkpoint.lastSecrets = Date()
                }
                checkpoint.detail = "Synced; waiting for the next scheduled run"
                try? checkpoint.save(to: checkpointPath)
            }
            finishSyncStatus(0)
        } catch let error as ExitError {
            finishSyncStatus(error.code)
            throw error
        } catch {
            finishSyncStatus(1)
            throw error
        }
    }

    private func cmdRun() throws {
        guard let lock = try MacSyncProcessLock.acquire(
            at: URL(fileURLWithPath: config.serviceLockFile),
        ) else {
            let lockPID = readText(config.serviceLockFile).trimmed
            let processDescription = lockPID.isEmpty ? "" : ": pid \(lockPID)"
            info("another mac-sync service is already running; exiting\(processDescription)")
            throw ExitError(code: 0)
        }
        serviceLock = lock
        isServiceInvocation = true
        // Background priority also applies when invoked by Homebrew services.
        _ = setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)
        backgroundResources = BackgroundResources()
        backgroundCheckpoint = BackgroundCheckpoint.load(from: checkpointPath, repository: config.machinesRepoDir)
        defer {
            isServiceInvocation = false
            serviceLock = nil
            backgroundResources = nil
        }
        try BackgroundAgentMigration.migrate(homeDirectory: config.homeDir,
                                             executable: Config.realpathExisting(invocationArguments.first ?? "mac-sync"), runner: runner)
        if let reason = backgroundResources?.deferralReason {
            backgroundCheckpoint.detail = reason
            try backgroundCheckpoint.save(to: checkpointPath)
            info(reason)
            return
        }
        if let next = backgroundCheckpoint.nextAttempt, next > Date() {
            info(backgroundCheckpoint.detail)
            return
        }
        do {
            try cmdSync()
            backgroundCheckpoint.consecutiveFailures = 0
            backgroundCheckpoint.nextAttempt = nil
            backgroundCheckpoint.lastSuccess = Date()
            backgroundCheckpoint.detail = "Synced; waiting for the next scheduled run"
            try backgroundCheckpoint.save(to: checkpointPath)
        } catch {
            if let reason = backgroundDeferralReason {
                backgroundCheckpoint.detail = reason
                backgroundCheckpoint.nextAttempt = Date().addingTimeInterval(900)
            } else {
                backgroundCheckpoint.failed(authentication: gitNetworkFailureKind(lastCommandOutput) == .authentication)
            }
            try? backgroundCheckpoint.save(to: checkpointPath)
            throw error
        }
    }

    private func backgroundBoundary() throws {
        guard isServiceInvocation else { return }
        let budgetExpired = Date().timeIntervalSince1970 - Double(runStartedEpoch) >= 900
        if let reason = backgroundResources?.deferralReason ?? (budgetExpired ? "Background work paused after its 15-minute budget" : nil) {
            backgroundDeferralReason = reason
            info(reason)
            throw ExitError(code: 75)
        }
    }

    private func cmdRestore(_ arguments: [String]) throws {
        var args = arguments
        var force = false
        var fromMachine = config.machineName
        var fromProvided = false
        var listMachines = false
        var selectMachine = false
        var selectedPaths: [String] = []
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
            case "--path":
                guard let value = args.first else { try fail("missing path after --path", code: 2) }
                selectedPaths.append(value)
                args.removeFirst()
            case "-h", "--help":
                usageRestore()
                return
            default:
                errorMessage("unknown restore option: \(arg)")
                usageRestore()
                throw ExitError(code: 2)
            }
        }
        if fromProvided && selectMachine {
            try fail("--from and --select cannot be used together", code: 2)
        }
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
            fromMachine = try selectMachineSnapshot()
        }
        let machineDir = "\(config.machinesRootDir)/\(fromMachine)"
        guard isDirectory(machineDir) else { try fail("missing machine snapshot: \(machineDir)") }
        warningCount = 0
        errorCount = 0
        warningMessages = []
        errorMessages = []
        startHistory(action: .restore, sourceMachine: fromMachine)
        do {
            info("restoring from machine: \(fromMachine)")
            if force {
                warning("force enabled; existing local files may be replaced")
            } else {
                info("existing local files will be kept; use --force to replace them")
            }
            for rel in try restoreManifestPaths(machine: fromMachine, selectedPaths: selectedPaths) {
                try restoreOnePath(machine: fromMachine, rel: rel, force: force)
            }
            if !selectedPaths.isEmpty {
                info("selected restore complete; skipped package, editor, repository, and secrets restore steps")
                finishHistory(.success)
                return
            }
            try printHomebrewRestoreCommands(machine: fromMachine)
            try printVscodeExtensionRestoreCommands(machine: fromMachine)
            try restoreGitHubRepositories(machine: fromMachine)
            printSecretsRestoreHint(machine: fromMachine)
            finishHistory(.success)
        } catch let error as ExitError {
            finishHistory(.failed)
            throw error
        } catch {
            finishHistory(.failed)
            throw error
        }
    }

    private func cmdList() throws {
        if config.repoDir == config.machinesRepoDir {
            info("data repo: \(config.machinesRepoDir)")
        } else {
            info("local repo: \(config.repoDir)")
            info("machines repo: \(config.machinesRepoDir)")
        }
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
        info("encrypted secrets archive: configured")
        info("dynamic refs: \(dynamicRefsEnabled() ? "enabled" : "disabled")")
        info("Homebrew sync: \(homebrewSyncEnabled() ? "enabled" : "disabled")")
        info("VS Code extension sync: \(vscodeExtensionsSyncEnabled() ? "enabled" : "disabled")")
        info("GitHub repo sync: \(githubReposSyncEnabled() ? "enabled" : "disabled")")
        info("encrypted secrets sync: \(secretsSyncEnabled() ? "enabled" : "disabled")")
        info()
        for rel in try manifestPaths() {
            let src = sourcePath(for: rel)
            let dest = destPath(for: rel)
            let state = if !pathExists(src) {
                "missing"
            } else if isDirectory(src) {
                "dir"
            } else {
                "file"
            }
            info("\(state.padding(toLength: 8, withPad: " ", startingAt: 0)) \(src) -> \(dest)")
        }
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

    private func repoLocalChanges(repo: String, restrictingTo paths: [String]? = nil) -> [String] {
        var arguments = ["-C", repo, "status", "--short", "--untracked-files=all"]
        if let paths {
            arguments += ["--"] + paths
        }
        return runner.run("git", arguments).stdout.splitLines().filter { !$0.isEmpty }
    }

    private func printRepoLocalChanges(repo: String, title: String) {
        let changes = repoLocalChanges(repo: repo)
        guard !changes.isEmpty else { return }
        info("\(title) local changes:")
        for line in changes {
            info("  \(line)")
        }
    }

    private func cmdStatus() {
        info("mac-sync version: \(repoCommitVersion(config.repoDir))")
        if config.repoDir == config.machinesRepoDir {
            info("data repo: \(config.machinesRepoDir)")
        } else {
            info("local repo: \(config.repoDir)")
            info("machines repo: \(config.machinesRepoDir)")
        }
        info("machine: \(config.machineName)")
        info("paths file: \(config.pathsFile)")
        info("manifest source: \(configuredManifestSourceLabel())")
        info("Homebrew snapshot dir: \(config.homebrewDir)")
        info("VS Code extension snapshot file: \(config.vscodeExtensionsFile)")
        info("status file: \(config.syncStatusFile)")
        info("Homebrew service: use `brew services info mac-sync`")
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
        if config.repoDir == config.machinesRepoDir, isDirectory("\(config.machinesRepoDir)/.git") {
            info("data repo branch: \(runner.run("git", ["-C", config.machinesRepoDir, "branch", "--show-current"]).stdout.trimmed)")
            printRepoLocalChanges(repo: config.machinesRepoDir, title: "data repo")
        } else if isDirectory("\(config.repoDir)/.git") {
            info("local repo branch: \(runner.run("git", ["-C", config.repoDir, "branch", "--show-current"]).stdout.trimmed)")
            printRepoLocalChanges(repo: config.repoDir, title: "local repo")
        } else {
            warning("local repo is not initialized yet")
        }
        if config.repoDir != config.machinesRepoDir, isDirectory("\(config.machinesRepoDir)/.git") {
            info("machines repo branch: \(runner.run("git", ["-C", config.machinesRepoDir, "branch", "--show-current"]).stdout.trimmed)")
            printRepoLocalChanges(repo: config.machinesRepoDir, title: "machines repo")
        } else if config.repoDir != config.machinesRepoDir {
            warning("machines repo is not initialized yet")
        }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
