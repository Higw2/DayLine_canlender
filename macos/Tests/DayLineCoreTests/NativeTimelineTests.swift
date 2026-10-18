import AppKit
import XCTest
import DayLineCore
@testable import DayLineApp

final class NativeTimelineTests: XCTestCase {
    @MainActor private func fixture() -> (NSWindow, TimelineNSView, CalendarEvent) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 1440), styleMask: [], backing: .buffered, defer: false)
        let view = TimelineNSView(frame: NSRect(x: 0, y: 0, width: 600, height: 1440))
        window.contentView = view
        let day = Calendar.current.startOfDay(for: Date())
        let event = CalendarEvent(id: 1, title: "前一个", startsAt: TimelineLayout.date(atMinute: 60, on: day), endsAt: TimelineLayout.date(atMinute: 120, on: day))
        view.day = day; view.events = [event]; view.rebuildActionButtons()
        return (window, view, event)
    }

    @MainActor private func mouse(_ type: NSEvent.EventType, y: CGFloat, view: TimelineNSView, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: 300, y: y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    @MainActor func testNativeTopAndBottomDragSaveExactlyOnce() async throws {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        var changes: [DateInterval] = []
        var creates = 0
        view.resizeEvent = { event, range in XCTAssertEqual(event, original); changes.append(range) }
        view.newRange = { _, _ in creates += 1 }
        view.mouseDown(with: mouse(.leftMouseDown, y: 62, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 92, view: view))
        XCTAssertTrue(changes.isEmpty)
        view.mouseUp(with: mouse(.leftMouseUp, y: 92, view: view))
        XCTAssertEqual(changes, [DateInterval(start: original.startsAt.addingTimeInterval(1800), end: original.endsAt)])
        view.mouseDown(with: mouse(.leftMouseDown, y: 118, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 148, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 148, view: view))
        XCTAssertEqual(changes.count, 2); XCTAssertEqual(changes.last?.end, original.endsAt.addingTimeInterval(1800))
        XCTAssertEqual(creates, 0)
    }

    @MainActor func testClicksBodyDragsAndEscapeNeverResizeOrCreate() async {
        let (window, view, _) = fixture()
        defer { window.contentView = nil }
        var changes = 0
        view.resizeEvent = { _, _ in changes += 1 }; view.newRange = { _, _ in changes += 1 }
        view.mouseDown(with: mouse(.leftMouseDown, y: 62, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 62, view: view))
        view.mouseDown(with: mouse(.leftMouseDown, y: 90, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 150, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 150, view: view))
        view.mouseDown(with: mouse(.leftMouseDown, y: 62, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 92, view: view))
        view.cancelOperation(nil)
        view.mouseUp(with: mouse(.leftMouseUp, y: 92, view: view))
        XCTAssertEqual(changes, 0)
    }

    @MainActor func testReleaseUsesFinalPointerPositionAndShortCardDoesNotJump() async {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        var changed: DateInterval?
        view.resizeEvent = { _, range in changed = range }
        view.mouseDown(with: mouse(.leftMouseDown, y: 118, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 133, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 148, view: view))
        XCTAssertEqual(changed?.end, original.endsAt.addingTimeInterval(1800))
        var short = original; short.endsAt = short.startsAt.addingTimeInterval(300)
        view.events = [short]; view.rebuildActionButtons()
        view.mouseDown(with: mouse(.leftMouseDown, y: 90, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 105, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 105, view: view))
        XCTAssertEqual(changed?.end, short.startsAt.addingTimeInterval(900))
    }

    @MainActor func testExistingDoubleClickAndBlankDragStillWork() async {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        var opened: CalendarEvent?
        var created: DateInterval?
        view.open = { opened = $0 }; view.newRange = { created = DateInterval(start: $0, end: $1) }
        view.mouseDown(with: mouse(.leftMouseDown, y: 62, view: view, clicks: 2))
        view.mouseUp(with: mouse(.leftMouseUp, y: 62, view: view, clicks: 2))
        XCTAssertEqual(opened, original); XCTAssertNil(created)
        view.mouseDown(with: mouse(.leftMouseDown, y: 181, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 239, view: view))
        view.mouseUp(with: mouse(.leftMouseUp, y: 239, view: view))
        XCTAssertEqual(created, DateInterval(start: TimelineLayout.date(atMinute: 180, on: view.day), end: TimelineLayout.date(atMinute: 240, on: view.day)))
    }

    @MainActor func testChangedOrDeletedEventsAndDaySwitchCancelPendingResize() async {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        var changes = 0
        view.resizeEvent = { _, _ in changes += 1 }
        for scenario in 0..<3 {
            view.mouseDown(with: mouse(.leftMouseDown, y: 62, view: view))
            view.mouseDragged(with: mouse(.leftMouseDragged, y: 92, view: view))
            if scenario == 0 { view.cancelIfInvalidated(day: view.day, events: []) }
            else if scenario == 1 {
                var changed = original; changed.endsAt.addTimeInterval(3600)
                view.cancelIfInvalidated(day: view.day, events: [changed])
            } else {
                view.cancelIfInvalidated(day: Calendar.current.date(byAdding: .day, value: 1, to: view.day)!, events: [original])
            }
            view.mouseUp(with: mouse(.leftMouseUp, y: 92, view: view))
        }
        XCTAssertEqual(changes, 0)
    }

    @MainActor func testOverlapPreviewKeepsActionButtonsBoundToCorrectEvents() async throws {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        let other = CalendarEvent(id: 2, title: "后一个", startsAt: TimelineLayout.date(atMinute: 120, on: view.day), endsAt: TimelineLayout.date(atMinute: 180, on: view.day))
        view.events = [original, other]; view.rebuildActionButtons()
        view.mouseDown(with: mouse(.leftMouseDown, y: 122, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 32, view: view))
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        let otherEdit = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "编辑事件：后一个" })
        XCTAssertEqual(otherEdit.frame.minY, 35)
        let originalEdit = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == "编辑事件：前一个" })
        XCTAssertEqual(originalEdit.frame.minY, 65)
        var opened: CalendarEvent?
        view.open = { opened = $0 }
        otherEdit.performClick(nil)
        XCTAssertEqual(opened?.id, other.id)
        view.cancelOperation(nil)
    }

    @MainActor func testDraggingOvernightStartToMidnightHidesDetachedButtons() async {
        let (window, view, original) = fixture()
        defer { window.contentView = nil }
        var overnight = original
        overnight.startsAt = TimelineLayout.date(atMinute: 1380, on: view.day)
        overnight.endsAt = Calendar.current.date(byAdding: .hour, value: 2, to: TimelineLayout.date(atMinute: 1440, on: view.day))!
        view.events = [overnight]; view.rebuildActionButtons()
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        XCTAssertTrue(buttons.allSatisfy { !$0.isHidden })
        view.mouseDown(with: mouse(.leftMouseDown, y: 1382, view: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, y: 1442, view: view))
        XCTAssertTrue(buttons.allSatisfy(\.isHidden))
        view.cancelOperation(nil)
        XCTAssertTrue(buttons.allSatisfy { !$0.isHidden })
    }
}
