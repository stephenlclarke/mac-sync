import Foundation
@testable import MacSyncCore
import XCTest

final class NewestDiskPageTests: XCTestCase {
    func testCanPageBeyondOneThousandWithoutDuplicatesOrHiddenOldRecords() throws {
        let records = (0 ..< 1205).map { (Date(timeIntervalSince1970: Double($0)), String(format: "%05d", $0)) }
        let page = try NewestDiskPage.read(limit: 50, offset: 1000, ordering: { $0 }) { emit in for record in records {
            emit(record)
        } }
        XCTAssertEqual(page.count, 50)
        XCTAssertEqual(page.first?.1, "00204")
        XCTAssertEqual(page.last?.1, "00155")
        let last = try NewestDiskPage.read(limit: 50, offset: 1200, ordering: { $0 }) { emit in for record in records.reversed() {
            emit(record)
        } }
        XCTAssertEqual(last.map(\.1), ["00004", "00003", "00002", "00001", "00000"])
        let empty = try NewestDiskPage.read(limit: 50, offset: 1300, ordering: { $0 }) { emit in for record in records {
            emit(record)
        } }
        XCTAssertTrue(empty.isEmpty)
    }
}
