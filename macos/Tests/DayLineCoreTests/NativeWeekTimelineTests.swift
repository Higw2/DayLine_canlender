import AppKit
import XCTest
import SwiftUI
import DayLineCore
@testable import DayLineApp

final class NativeWeekTimelineTests: XCTestCase {
    @MainActor func testHostedWeekCreatesSevenAlignedColumnsAndOneTimeAxis() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EventStore(path: directory.appendingPathComponent("events.db"))
        let model = DayLineModel(store: store, settingsStore: SettingsStore(path: directory.appendingPathComponent("settings.json")))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600), styleMask: [], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: WeekTimelineView(model: model, delete: { _ in }))
        window.contentView = host
        defer { window.contentView = nil }
        func timelines(_ view: NSView) -> [TimelineNSView] {
            (view as? TimelineNSView).map { [$0] } ?? view.subviews.flatMap(timelines)
        }
        var columns: [TimelineNSView] = []
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            columns = timelines(host).sorted { $0.day < $1.day }
            if columns.count == 7 { break }
        }
        XCTAssertEqual(columns.count, 7)
        XCTAssertEqual(columns.map(\.day), WeekTimelineLayout.days(containing: model.selectedDay))
        XCTAssertEqual(columns.filter(\.showsTimeAxis).count, 1)
        guard columns.count == 7 else { return }
        XCTAssertTrue(columns[0].showsTimeAxis)
        XCTAssertTrue(columns.allSatisfy(\.compactMode))
        // A flexible spacer in the date header must not consume half the page.
        var ancestor = columns[0].superview
        var verticalScroll: NSScrollView?
        while let current = ancestor {
            if let scroll = current as? NSScrollView { verticalScroll = scroll; break }
            ancestor = current.superview
        }
        let scroll = try XCTUnwrap(verticalScroll)
        XCTAssertGreaterThan(scroll.frame.height, host.bounds.height - 80)
        XCTAssertLessThanOrEqual(columns[6].convert(columns[6].bounds, to: host).maxX, host.bounds.maxX - 15)
        for index in 1..<7 {
            let previousRight = columns[index - 1].convert(columns[index - 1].bounds, to: host).maxX
            let left = columns[index].convert(columns[index].bounds, to: host).minX
            XCTAssertEqual(left, previousRight, accuracy: 1)
            XCTAssertEqual(columns[index].bounds.height, 1440, accuracy: 1)
        }
    }
    @MainActor private func fixture(day: Date, first: Bool = false, events: [CalendarEvent] = []) -> (NSWindow, TimelineNSView) {
        _ = NSApplication.shared
        let width: CGFloat = 120 + (first ? 64 : 0)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1440), styleMask: [], backing: .buffered, defer: false)
        let view = TimelineNSView(frame: NSRect(x: 0, y: 0, width: width, height: 1440))
        window.contentView = view
        view.day = day; view.compactMode = true; view.showsTimeAxis = first
        view.events = events; view.rebuildActionButtons()
        return (window, view)
    }
    @MainActor private func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, view: TimelineNSView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor func testBlankDragInAllSevenColumnsCreatesOnCorrectDate() async throws {
        let days = WeekTimelineLayout.days(containing: Date())
        for (index, day) in days.enumerated() {
            let (window, view) = fixture(day: day, first: index == 0)
            defer { window.contentView = nil }
            let x: CGFloat = index == 0 ? 94 : 30
            var created: DateInterval?
            view.newRange = { created = DateInterval(start: $0, end: $1) }
            view.mouseDown(with: mouse(.leftMouseDown, x: x, y: 541, view: view))
            view.mouseDragged(with: mouse(.leftMouseDragged, x: x, y: 599, view: view))
            view.mouseUp(with: mouse(.leftMouseUp, x: x, y: 599, view: view))
            let range = try XCTUnwrap(created)
            XCTAssertEqual(range.start, TimelineLayout.date(atMinute: 540, on: day))
            XCTAssertEqual(range.end, TimelineLayout.date(atMinute: 600, on: day))
        }
    }

    @MainActor func testTimeAxisCannotCreateAndHorizontalDriftKeepsOriginalDay() async throws {
        let day = WeekTimelineLayout.days(containing: Date())[3]
        let (window, view) = fixture(day: day, first: true)
        defer { window.contentView = nil }
        var created: DateInterval?
        view.newRange = { created = DateInterval(start: $0, end: $1) }
        view.mouseDown(with: mouse(.leftMouseDown, x: 20, y: 120, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, x: 20, y: 180, view: view))
        XCTAssertNil(created)
        view.mouseDown(with: mouse(.leftMouseDown, x: 94, y: 120, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 260, y: 180, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, x: 260, y: 180, view: view))
        XCTAssertEqual(try XCTUnwrap(created).start, TimelineLayout.date(atMinute: 120, on: day))
    }

    @MainActor func testCompactColumnResizeSaveAndCancellation() async throws {
        let day = WeekTimelineLayout.days(containing: Date())[5]
        let event = CalendarEvent(id: 8, title: "周六", startsAt: TimelineLayout.date(atMinute: 60, on: day), endsAt: TimelineLayout.date(atMinute: 120, on: day))
        let (window, view) = fixture(day: day, events: [event])
        defer { window.contentView = nil }
        var resized: DateInterval?
        view.resizeEvent = { original, range in XCTAssertEqual(original.id, event.id); resized = range }
        view.mouseDown(with: mouse(.leftMouseDown, x: 30, y: 118, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 30, y: 148, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, x: 30, y: 148, view: view))
        XCTAssertEqual(try XCTUnwrap(resized).end, TimelineLayout.date(atMinute: 150, on: day))
        resized = nil
        view.mouseDown(with: mouse(.leftMouseDown, x: 30, y: 62, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 30, y: 92, view: view))
        view.cancelOperation(nil)
        view.mouseUp(with: mouse(.leftMouseUp, x: 30, y: 92, view: view))
        XCTAssertNil(resized)
    }

    @MainActor func testCrossDayEventActionsAndVisibleEndpointsInEachColumn() async throws {
        let days = WeekTimelineLayout.days(containing: Date())
        let event = CalendarEvent(id: 9, title: "跨午夜", startsAt: TimelineLayout.date(atMinute: 1380, on: days[1]), endsAt: TimelineLayout.date(atMinute: 60, on: days[2]))
        let (firstWindow, first) = fixture(day: days[1], events: [event])
        let (secondWindow, second) = fixture(day: days[2], events: [event])
        defer { firstWindow.contentView = nil; secondWindow.contentView = nil }
        var firstChanged: DateInterval?, secondChanged: DateInterval?
        first.resizeEvent = { _, range in firstChanged = range }
        second.resizeEvent = { _, range in secondChanged = range }
        // The artificial midnight edge is not the event's real end.
        first.mouseDown(with: mouse(.leftMouseDown, x: 30, y: 1438, view: first))
        first.mouseDragged(with: mouse(.leftMouseDragged, x: 30, y: 1408, view: first))
        first.mouseUp(with: mouse(.leftMouseUp, x: 30, y: 1408, view: first))
        XCTAssertNil(firstChanged)
        second.mouseDown(with: mouse(.leftMouseDown, x: 30, y: 58, view: second))
        second.mouseDragged(with: mouse(.leftMouseDragged, x: 30, y: 88, view: second))
        second.mouseUp(with: mouse(.leftMouseUp, x: 30, y: 88, view: second))
        XCTAssertEqual(try XCTUnwrap(secondChanged).start, event.startsAt)
        XCTAssertEqual(secondChanged?.end, TimelineLayout.date(atMinute: 90, on: days[2]))
        for view in [first, second] {
            let edit = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "编辑事件：跨午夜" })
            XCTAssertLessThanOrEqual(edit.frame.maxX, view.bounds.maxX)
            var opened: CalendarEvent?
            view.open = { opened = $0 }; edit.performClick(nil)
            XCTAssertEqual(opened?.id, event.id)
        }
    }
}
