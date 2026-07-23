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

enum EncryptedSecretsInspectionError: LocalizedError {
    case invalidMachineName
    case missingExecutable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidMachineName:
            "This machine name is not safe to inspect."
        case .missingExecutable:
            "The mac-sync command is unavailable. Reinstall the app or set MAC_SYNC_EXECUTABLE."
        case .unavailable:
            "The encrypted archive could not be opened. Confirm this Mac's Keychain identity is a trusted recipient."
        }
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
            throw EncryptedSecretsInspectionError.unavailable
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
