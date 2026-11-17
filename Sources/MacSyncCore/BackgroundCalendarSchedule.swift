import Foundation

public struct BackgroundCalendarEntry: Codable, Equatable, Sendable {
    public let weekday: Int
    public let hour: Int
    public let minute: Int

    public init(weekday: Int, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    public var isValid: Bool {
        (0 ... 6).contains(weekday) && (0 ... 23).contains(hour) && (0 ... 59).contains(minute)
    }

    public static func nextDate(entries: [Self], after now: Date, calendar: Calendar = .current) -> Date? {
        guard !entries.isEmpty, entries.count <= 256, entries.allSatisfy(\.isValid) else { return nil }
        return entries.compactMap { entry in
            calendar.nextDate(after: now, matching: DateComponents(hour: entry.hour, minute: entry.minute, second: 0, weekday: entry.weekday + 1), matchingPolicy: .nextTime)
        }.min()
    }
}
