import Foundation

/// Counts only recorded review metadata. File contents, paths, peer names and
/// arbitrary warning text are deliberately absent from AI diagnostic inputs.
public struct IncomingReviewInventory: Codable, Equatable, Sendable {
    public private(set) var conflicts: Int
    public private(set) var deletions: Int
    public private(set) var pathOrLink: Int
    public private(set) var reviewPolicy: Int
    public private(set) var other: Int

    public var total: Int {
        conflicts + deletions + pathOrLink + reviewPolicy + other
    }

    public init(conflicts: Int = 0, deletions: Int = 0, pathOrLink: Int = 0, reviewPolicy: Int = 0, other: Int = 0) {
        self.conflicts = conflicts
        self.deletions = deletions
        self.pathOrLink = pathOrLink
        self.reviewPolicy = reviewPolicy
        self.other = other
    }

    struct Entry: Decodable {
        let reason: String
        let deletion: Bool
    }

    private static let pathOrLinkReason =
        "The local path changed, is linked, or needs a file/folder replacement. Review it before applying."

    mutating func record(_ entry: Entry) {
        // The typed flag wins even if a reason contains misleading wording.
        if entry.deletion {
            deletions += 1
        } else {
            switch entry.reason {
            case "Both Macs changed this file": conflicts += 1
            case Self.pathOrLinkReason: pathOrLink += 1
            case "Incoming changes are set to review first": reviewPolicy += 1
            default: other += 1
            }
        }
    }
}
