import AppKit
import SwiftUI
import DayLineCore

final class ReminderPanel: NSPanel {
    var onClosed: (() -> Void)?
    init(event: CalendarEvent, model: DayLineModel) {
        super.init(contentRect:NSRect(x:0,y:0,width:390,height:205),styleMask:[.titled,.closable,.utilityWindow],backing:.buffered,defer:false); title = "DayLine 提醒"; isFloatingPanel = true; level = .floating; collectionBehavior = [.canJoinAllSpaces]; isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: ReminderView(event:event,model:model,close:{ [weak self] in self?.close() })); center()
    }
    func show() { makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    override func close() { super.close(); onClosed?() }
}
struct ReminderView: View {
    let event:CalendarEvent; @ObservedObject var model:DayLineModel; let close:()->Void
    var body:some View { VStack(alignment:.leading,spacing:14) { Text("该做这件事了").font(.caption).foregroundStyle(.secondary); Text(event.title).font(.title3.bold()); Text("原定时间  \(event.startsAt.formatted(.dateTime.year().month().day().hour().minute()))").foregroundStyle(.secondary); Spacer(); HStack { Spacer(); Button("10 分钟后") { do { try model.store.snooze(event.id); model.reload(); close() } catch { model.message = error.localizedDescription } }; Button("完成") { model.complete(event); close() }.buttonStyle(.borderedProminent) } }.padding(24) }
}
