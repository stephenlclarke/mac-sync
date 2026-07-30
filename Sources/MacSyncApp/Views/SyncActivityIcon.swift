import SwiftUI

struct SyncActivityIcon: View {
    nonisolated static let rotationPeriod: TimeInterval = 1.2

    let systemName: String
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isAnimating || reduceMotion,
            ),
        ) { context in
            Image(systemName: systemName)
                .rotationEffect(
                    .degrees(
                        Self.rotationDegrees(
                            at: context.date,
                            isAnimating: isAnimating,
                            reduceMotion: reduceMotion,
                        ),
                    ),
                )
        }
    }

    nonisolated static func rotationDegrees(
        at date: Date,
        isAnimating: Bool,
        reduceMotion: Bool,
    ) -> Double {
        guard isAnimating, !reduceMotion else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: rotationPeriod)
        return elapsed / rotationPeriod * 360
    }
}
