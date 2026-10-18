import AppKit
import SwiftUI
import DayLineCore

final class AdvanceReminderPanel: NSPanel {
    var onClosed: (() -> Void)?
    private let event: CalendarEvent

    init(event: CalendarEvent) {
        self.event = event
        super.init(contentRect: NSRect(x: 0, y: 0, width: 430, height: 255), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = "DayLine 预提醒"
        isFloatingPanel = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces]; isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: AdvanceReminderView(event: event, close: { [weak self] in self?.close() }))
        center()
    }

    func isCurrent(in store: EventStore, now: Date) throws -> Bool {
        guard let current = try store.get(event.id), !current.completed,
              current.startsAt == event.startsAt else { return false }
        return current.startsAt > now && current.alertedAt == nil && current.reminderAt == nil && current.preAlertedAt != nil
    }

    func show() { makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    override func close() { super.close(); onClosed?() }
}

struct AdvanceReminderView: View {
    let event: CalendarEvent
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事件即将开始").font(.caption).foregroundStyle(.secondary)
            Text(event.title).font(.title3.bold()).lineLimit(3)
            Text("原定时间  \(event.startsAt.formatted(.dateTime.year().month().day().hour().minute()))")
                .foregroundStyle(.secondary)
            Text("请提前准备；到设定时间会通过系统通知再次提醒。")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            HStack {
                Spacer()
                Button("知道了", action: close).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
