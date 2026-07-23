@testable import MacSyncApp
import XCTest

final class CommandActivityPresentationTests: XCTestCase {
    func testClassifiesTransferAndDiagnosticLinesForTheLiveActivityView() {
        let lines = CommandActivityPresentation.lines(for: """
        ✔ new snapshot file: /source/.zshrc -> /snapshot/.zshrc
        ✔ updated local file: /snapshot/.zshrc -> /source/.zshrc
        skip newer local file: /source/.zshrc
        WARN: no origin remote configured
        ERROR: sync failed
        ⠓ building sync manifest
        """)

        XCTAssertEqual(lines.map(\.tone), [.new, .updated, .skipped, .warning, .error, .pending])
    }

    func testTreatsExistingNoChangeMessagesAsSkipped() {
        XCTAssertEqual(
            CommandActivityPresentation.tone(for: "✔ no machine snapshot changes to commit"),
            .skipped
        )
        XCTAssertEqual(
            CommandActivityPresentation.tone(for: "✔ machines repo already up to date"),
            .skipped
        )
    }
}
