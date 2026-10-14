import AppKit
import SwiftUI
import DayLineCore

final class ReminderPanel: NSPanel {
    var onClosed: (() -> Void)?
    private let delivery: ReminderDelivery

    init(delivery: ReminderDelivery, model: DayLineModel) {
        self.delivery = delivery
        super.init(contentRect: NSRect(x: 0, y: 0, width: 430, height: 255), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = delivery.stage == .advance ? "DayLine 预提醒" : "DayLine 到点提醒"
        isFloatingPanel = true; level = .floating
        collectionBehavior = [.canJoinAllSpaces]; isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: ReminderView(delivery: delivery, model: model, close: { [weak self] in self?.close() }))
        center()
    }

    func isCurrent(in store: EventStore, now: Date) throws -> Bool {
        guard let current = try store.get(delivery.event.id), !current.completed,
              current.startsAt == delivery.event.startsAt else { return false }
        if delivery.stage == .advance {
            return current.startsAt > now && current.alertedAt == nil && current.reminderAt == nil && current.preAlertedAt != nil
        }
        return current.alertedAt != nil && current.reminderAt == nil
    }

    func show() { makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    override func close() { super.close(); onClosed?() }
}

struct ReminderView: View {
    let delivery: ReminderDelivery
    @ObservedObject var model: DayLineModel
    let close: () -> Void
    @State private var errorMessage: String?

    private var event: CalendarEvent { delivery.event }
    private var heading: String {
        delivery.stage == .due && event.reminderAt != nil ? "推迟的提醒已到" : delivery.stage.heading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.caption).foregroundStyle(.secondary)
            Text(event.title).font(.title3.bold()).lineLimit(3)
            Text("原定时间  \(event.startsAt.formatted(.dateTime.year().month().day().hour().minute()))")
                .foregroundStyle(.secondary)
            if delivery.stage == .advance {
                Text("请提前准备；到设定时间会再次提醒。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack {
                Spacer()
                if delivery.stage == .advance {
                    Button("知道了", action: close).buttonStyle(.borderedProminent)
                } else {
                    Button("推迟 10 分钟") { respond(snooze: true) }
                    Button("已完成") { respond(snooze: false) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .alert("提醒操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func respond(snooze: Bool) {
        do {
            // Recheck after clicking so an old window cannot change an event
            // that was deleted, completed, rescheduled or already snoozed.
            guard let current = try model.store.get(event.id), !current.completed,
                  current.startsAt == event.startsAt, current.alertedAt != nil,
                  current.reminderAt == nil else { close(); return }
            if snooze { try model.store.snooze(event.id) }
            else { try model.store.complete(event.id) }
            model.reload(); close()
        } catch { errorMessage = error.localizedDescription }
    }
}
