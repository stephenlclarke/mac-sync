import Foundation

/// An explicit, same-Mac channel handoff. Never infer identity from peer data.
public enum InstallationIdentity {
    public static func importIdentity(from source: URL, statusDirectory: URL) throws {
        guard source.lastPathComponent == "device-id",
              let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 128,
              let value = try String(data: Data(contentsOf: source), encoding: .utf8), UUID(uuidString: value) != nil
        else {
            throw BackupStorageError.unavailable("Choose the previous installation's device-id file on this Mac, not a snapshot from another Mac.")
        }
        let destination = statusDirectory.appendingPathComponent("device-id")
        if FileManager.default.fileExists(atPath: destination.path) {
            guard let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 128,
                  try Data(contentsOf: destination) == Data(value.utf8)
            else {
                throw BackupStorageError.unavailable("This installation already has a different sync identity. Keep its unique This Mac identifier; identity replacement is not safe.")
            }
            return
        }
        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(value.utf8).write(to: destination, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
