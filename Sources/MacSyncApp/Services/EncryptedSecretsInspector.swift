import Foundation
import MacSyncCore

protocol EncryptedSecretsCommandRunning {
    func run(executablePath: String, arguments: [String], environment: [String: String]) -> CommandResult
}

struct SystemEncryptedSecretsCommandRunner: EncryptedSecretsCommandRunning {
    func run(executablePath: String, arguments: [String], environment: [String: String]) -> CommandResult {
        ProcessRunner(environment: environment).run(executablePath, arguments)
    }
}

enum EncryptedSecretsInspectionError: LocalizedError, Equatable {
    case invalidMachineName
    case missingExecutable
    case missingArchive
    case missingKeychainIdentity
    case missingRuntimeDependency
    case accessNotGranted
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidMachineName:
            "This machine name is not safe to inspect."
        case .missingExecutable:
            "The mac-sync command is unavailable. Reinstall the app or set MAC_SYNC_EXECUTABLE."
        case .missingArchive:
            "This machine does not have an encrypted secrets archive."
        case .missingKeychainIdentity:
            "No Keychain encryption identity is available on this Mac."
        case .missingRuntimeDependency:
            "A required encryption command is unavailable on this Mac."
        case .accessNotGranted:
            "This Mac's Keychain identity cannot decrypt this archive."
        case .unavailable:
            "Mac Sync could not inspect this encrypted archive."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingKeychainIdentity:
            "Set up this Mac's access to create a Keychain identity and publish its public recipient."
        case .accessNotGranted:
            "Set up this Mac's access, then sync on a Mac that can already open this archive. That Mac will re-encrypt the archive for every trusted recipient."
        case .missingRuntimeDependency:
            "Reinstall Mac Sync with Homebrew so age, age-keygen, and GNU tar are available."
        case .missingArchive:
            "Run Sync Now on this machine after configuring at least one encrypted secret path."
        case .invalidMachineName, .missingExecutable, .unavailable:
            nil
        }
    }

    var supportsAccessSetup: Bool {
        self == .missingKeychainIdentity || self == .accessNotGranted
    }

    static func classify(commandOutput: String) -> EncryptedSecretsInspectionError {
        let output = commandOutput.lowercased()
        if output.contains("missing encrypted secrets snapshot") {
            return .missingArchive
        }
        if output.contains("missing keychain age identity") {
            return .missingKeychainIdentity
        }
        if output.contains("missing required command:") {
            return .missingRuntimeDependency
        }
        if output.contains("no identity matched any of the recipients") {
            return .accessNotGranted
        }
        return .unavailable
    }
}

struct EncryptedSecretsInspector {
    private let environment: [String: String]
    private let executablePath: String?
    private let runner: any EncryptedSecretsCommandRunning

    init(
        environment: [String: String],
        executablePath: String? = nil,
        runner: (any EncryptedSecretsCommandRunning)? = nil
    ) {
        self.environment = environment
        self.executablePath = executablePath ?? MacSyncCommandLocator.executableURL(environment: environment)?.path
        self.runner = runner ?? SystemEncryptedSecretsCommandRunner()
    }

    func entries(from machine: String) throws -> [String] {
        guard MacSyncPaths.safeMachineName(machine) else {
            throw EncryptedSecretsInspectionError.invalidMachineName
        }
        guard let executablePath else {
            throw EncryptedSecretsInspectionError.missingExecutable
        }

        let result = runner.run(
            executablePath: executablePath,
            arguments: ["secrets", "list", "--from", machine],
            environment: environment
        )
        guard result.status == 0 else {
            throw EncryptedSecretsInspectionError.classify(commandOutput: result.combinedOutput)
        }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter(Self.isSafeArchiveEntry)
    }

    static func isSafeArchiveEntry(_ entry: String) -> Bool {
        !entry.isEmpty
            && !entry.hasPrefix("/")
            && entry != "."
            && entry != ".."
            && !entry.hasPrefix("../")
            && !entry.contains("/../")
            && !entry.hasSuffix("/..")
            && !entry.contains("\0")
    }
}
