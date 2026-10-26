import AppKit
@testable import MacSyncApp
import SwiftUI
import XCTest

final class SyncIssuesLayoutTests: XCTestCase {
    @MainActor
    func testEmptyHealthPanesFillTheAvailableHeight() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SyncStore(environment: [
            "HOME": root.path,
            "MAC_SYNC_MACHINES_REPO": root.appendingPathComponent("data").path,
            "MAC_SYNC_MACHINE": "layout-test",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ])
        let host = NSHostingView(rootView: SyncIssuesView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for size in [NSSize(width: 1000, height: 600), NSSize(width: 1200, height: 800), NSSize(width: 1600, height: 1000)] {
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            let split = try XCTUnwrap(splitView(in: host))
            XCTAssertEqual(split.bounds.height, host.bounds.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(split.subviews.count, 2)
            for pane in split.subviews {
                XCTAssertEqual(pane.frame.height, host.bounds.height, accuracy: 1)
            }
        }
    }

    @MainActor
    private func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView {
            return split
        }
        return view.subviews.lazy.compactMap { self.splitView(in: $0) }.first
    }
}
