import Foundation
@testable import MacSyncCore
import XCTest

final class BackgroundCalendarScheduleTests: XCTestCase {
    func testChoosesNextWeekdayAndSkipsPassedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z"))
        let entries = [BackgroundCalendarEntry(weekday: 2, hour: 11, minute: 0), BackgroundCalendarEntry(weekday: 3, hour: 9, minute: 30)]
        let next = try XCTUnwrap(BackgroundCalendarEntry.nextDate(entries: entries, after: now, calendar: calendar))
        XCTAssertEqual(ISO8601DateFormatter().string(from: next), "2026-11-18T09:30:00Z")
    }

    func testRejectsInvalidAndUnboundedCalendars() {
        XCTAssertNil(BackgroundCalendarEntry.nextDate(entries: [], after: Date()))
        XCTAssertNil(BackgroundCalendarEntry.nextDate(entries: [.init(weekday: 7, hour: 0, minute: 0)], after: Date()))
        XCTAssertNil(BackgroundCalendarEntry.nextDate(entries: [.init(weekday: 0, hour: 24, minute: 0)], after: Date()))
        XCTAssertNil(BackgroundCalendarEntry.nextDate(entries: Array(repeating: .init(weekday: 0, hour: 9, minute: 0), count: 257), after: Date()))
    }
}
