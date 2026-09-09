import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import DayLineCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private lazy var model = DayLineModel()
    private var mainWindow: NSWindow!
    private var desktop: DesktopPanel!
    private var reminderTimer: Timer?
    private var lock: SingleInstance?
    private var reminderPanels: [ReminderPanel] = []
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lock = SingleInstance(dataDirectory: DataPaths.shared.directory)
        let requested = CommandLine.arguments.contains("--quit") ? "quit" : (CommandLine.arguments.contains("--desktop") ? "desktop" : "activate")
        if lock?.isPrimary == false { lock?.send(requested); NSApp.terminate(nil); return }
        // `--quit` with no existing instance must be a no-op: do not open a
        // database, request notification permission, or create a window.
        if requested == "quit" { NSApp.terminate(nil); return }
        lock?.onCommand = { [weak self] command in DispatchQueue.main.async { self?.handle(command) } }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        createWindows(); setupMenu(); model.reload()
        checkReminders(); reminderTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkReminders() }
        if requested == "desktop" { hideToDesktop() } else { showMain() }
    }
    func applicationWillTerminate(_ notification: Notification) { reminderTimer?.invalidate(); lock = nil }
    private func createWindows() {
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        mainWindow.title = "DayLine"; mainWindow.center(); mainWindow.isReleasedWhenClosed = false; mainWindow.delegate = self
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model, showDesktop: { [weak self] in self?.hideToDesktop() }, quit: { NSApp.terminate(nil) }))
        desktop = DesktopPanel(model: model, openMain: { [weak self] in self?.showMain() }, newEvent: { [weak self] in self?.showMain(); self?.model.presentNewEvent() }, settings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })
    }
    private func setupMenu() {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app); let appMenu = NSMenu(); app.submenu = appMenu
        appMenu.addItem(withTitle: "显示 DayLine", action: #selector(showMainAction), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "显示桌面卡片", action: #selector(showDesktopAction), keyEquivalent: "d").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出 DayLine", action: #selector(quitAction), keyEquivalent: "q").target = self
        NSApp.mainMenu = menu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); statusItem = item; item.button?.title = "◷"; let status = NSMenu(); status.addItem(withTitle: "打开 DayLine", action: #selector(showMainAction), keyEquivalent: "").target = self; status.addItem(withTitle: "新建事件", action: #selector(newEventAction), keyEquivalent: "").target = self; status.addItem(.separator()); status.addItem(withTitle: "退出", action: #selector(quitAction), keyEquivalent: "").target = self; item.menu = status
    }
    @objc func showMainAction() { showMain() }; @objc func showDesktopAction() { hideToDesktop() }; @objc func newEventAction() { showMain(); model.presentNewEvent() }; @objc func quitAction() { NSApp.terminate(nil) }
    func showMain() { desktop.orderOut(nil); mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func hideToDesktop() { mainWindow.orderOut(nil); desktop.show() }
    func showSettings() { showMain(); model.showSettings = true }
    private func handle(_ command: String) { if command == "quit" { NSApp.terminate(nil) } else if command == "desktop" { hideToDesktop() } else { showMain() } }
    private func checkReminders() {
        do { _ = try model.store.expireStale(); for event in try model.store.due() { try model.store.markAlerted(event.id); model.reload(); postNotification(event); let panel = ReminderPanel(event: event, model: model); panel.onClosed = { [weak self, weak panel] in if let panel { self?.reminderPanels.removeAll { $0 === panel } } }; reminderPanels.append(panel); panel.show() } } catch { NSLog("DayLine reminder error: \(error)") }
    }
    private func postNotification(_ event: CalendarEvent) { let content = UNMutableNotificationContent(); content.title = "该做这件事了"; content.body = event.title; content.sound = .default; let request = UNNotificationRequest(identifier: "dayline.\(event.id).\(Date().timeIntervalSince1970)", content: content, trigger: nil); UNUserNotificationCenter.current().add(request) }
}
extension AppDelegate: NSWindowDelegate { func windowShouldClose(_ sender: NSWindow) -> Bool { hideToDesktop(); return false } }

final class DayLineModel: ObservableObject {
    let store: EventStore
    let settingsStore = SettingsStore()
    @Published var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published var events: [CalendarEvent] = []
    @Published var upcoming: [CalendarEvent] = []
    @Published var settings: AppSettings
    @Published var editing: CalendarEvent?
    @Published var draftRange: (Date, Date)?
    @Published var showingEditor = false
    @Published var showSettings = false
    @Published var message: String?
    init() { do { store = try EventStore() } catch { fatalError("DayLine database: \(error)") }; settings = settingsStore.current }
    func reload() { do { events = try store.events(on: selectedDay); upcoming = try store.upcoming(); } catch { message = error.localizedDescription } }
    func go(_ days: Int) { selectedDay = Calendar.current.date(byAdding: .day, value: days, to: selectedDay)!; reload() }
    func presentNewEvent(_ range: (Date, Date)? = nil) { editing = nil; draftRange = range; showingEditor = true }
    @discardableResult func save(title: String, start: Date, end: Date, notes: String) -> Bool { do { if let event = editing { _ = try store.update(id: event.id, title: title, startsAt: start, endsAt: end, notes: notes) } else { _ = try store.add(title: title, startsAt: start, endsAt: end, notes: notes) }; editing = nil; draftRange = nil; showingEditor = false; reload(); return true } catch { message = error.localizedDescription; return false } }
    func complete(_ event: CalendarEvent, completed: Bool = true) { do { try store.complete(event.id, completed: completed); reload() } catch { message = error.localizedDescription } }
    func delete(_ event: CalendarEvent) { do { try store.delete(event.id); reload() } catch { message = error.localizedDescription } }
    func persistSettings() { do { try settingsStore.save(settings) } catch { message = error.localizedDescription }; reload() }
    func setLaunchAtLogin(_ enabled: Bool) {
        do { if #available(macOS 13.0, *) { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }; settings.launchAtLogin = enabled; try settingsStore.save(settings) }
        catch { message = "登录启动设置失败：\(error.localizedDescription)" }
    }
    func resetSettings() { if settings.launchAtLogin { setLaunchAtLogin(false) }; settings = AppSettings(); persistSettings() }
    func dateForMinute(_ minute: Int) -> Date { var c = Calendar.current.dateComponents([.year,.month,.day], from: selectedDay); c.hour = minute / 60; c.minute = minute % 60; c.second = 0; return Calendar.current.date(from: c)! }
}

struct MainView: View {
    @ObservedObject var model: DayLineModel
    let showDesktop: () -> Void; let quit: () -> Void
    private var dayText: String { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年MM月dd日 EEEE"; return f.string(from: model.selectedDay) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("DayLine").font(.system(size: 23, weight: .bold)).foregroundStyle(Color(hex: model.settings.themeColor)); Button("返回今天") { model.selectedDay = Calendar.current.startOfDay(for: Date()); model.reload() }.buttonStyle(.borderedProminent)
                DatePicker("", selection: $model.selectedDay, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().onChange(of: model.selectedDay) { _ in model.reload() }
                Text("下一项安排").font(.headline); if model.upcoming.isEmpty { Text("暂无近期待办").foregroundStyle(.secondary) } else { ForEach(model.upcoming) { e in VStack(alignment:.leading) { Text(e.startsAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(Color(hex:model.settings.themeColor)); Text(e.title).lineLimit(1) }.padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 7)) } }
                Spacer(); Button("收起到桌面") { showDesktop() }; Button("退出 DayLine") { quit() }.foregroundStyle(.red)
            }.padding(18).frame(width: 262).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                HStack { Button("‹") { model.go(-1) }; Button("›") { model.go(1) }; Button("今天") { model.selectedDay = Calendar.current.startOfDay(for: Date()); model.reload() }; Text(dayText).font(.title3.bold()).frame(maxWidth:.infinity, alignment:.leading); Text("\(model.events.filter { !$0.completed }.count) 项待办 · \(model.events.count) 个事件").foregroundStyle(.secondary); Button("设置") { model.showSettings = true }; Button("＋ 新建事件") { model.presentNewEvent() }.buttonStyle(.borderedProminent) }.padding()
                ScrollView([.vertical]) { TimelineRepresentable(day: model.selectedDay, events: model.events, color: model.settings.themeColor, fontScale: model.settings.fontScale, open: { event in model.editing = event; model.showingEditor = true }, newRange: { start, end in model.presentNewEvent((start, end)) }, complete: { model.complete($0) }).frame(minWidth: 540, minHeight: 1440) }
            }
        }.frame(minWidth: 800, minHeight: 580).font(.system(size: 13 * model.settings.fontScale))
        .sheet(isPresented: $model.showingEditor, onDismiss: { model.editing=nil; model.draftRange=nil }) { EventEditor(model: model).font(.system(size: 13 * model.settings.fontScale)) }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .alert("DayLine", isPresented: Binding(get:{model.message != nil}, set:{if !$0 {model.message=nil}})) { Button("好", role:.cancel){} } message: { Text(model.message ?? "") }
    }
}

struct EventEditor: View {
    @ObservedObject var model: DayLineModel; @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var notes = ""; @State private var start = Date(); @State private var end = Date().addingTimeInterval(3600)
    var body: some View { VStack(alignment:.leading, spacing:14) { Text(model.editing == nil ? "新建事件" : "编辑事件").font(.title2.bold()); TextField("事件名称", text:$title); DatePicker("开始", selection:$start); DatePicker("结束", selection:$end); TextField("备注（可选）", text:$notes, axis:.vertical).lineLimit(3...6); HStack { if let event=model.editing { Button(event.completed ? "恢复待办" : "标记完成") { model.complete(event,completed:!event.completed); dismiss() }; Button("删除",role:.destructive) { model.delete(event); dismiss() }; Spacer() } else { Spacer() }; Button("取消") { dismiss() }; Button("保存事件") { if model.save(title:title,start:start,end:end,notes:notes) { dismiss() } }.buttonStyle(.borderedProminent) } }.padding(24).frame(width:460).onAppear { let e=model.editing; title=e?.title ?? ""; notes=e?.notes ?? ""; start=e?.startsAt ?? model.draftRange?.0 ?? defaultStart(); end=e?.endsAt ?? model.draftRange?.1 ?? start.addingTimeInterval(3600) } }
    private func defaultStart() -> Date { let date = max(Date(), model.selectedDay); return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)! }
}

struct SettingsView: View {
    @ObservedObject var model: DayLineModel; @Environment(\.dismiss) var dismiss
    var body: some View { VStack(alignment:.leading, spacing:18) { Text("偏好设置").font(.title2.bold()); GroupBox("主题与色彩") { VStack(alignment:.leading) { HStack { ForEach(Accent.allCases) { accent in Button { model.settings.themeColor=accent.rawValue; model.persistSettings() } label: { Circle().fill(Color(hex:accent.rawValue)).frame(width:25,height:25).overlay(Circle().stroke(.primary, lineWidth:model.settings.themeColor == accent.rawValue ? 2:0)) }.buttonStyle(.plain) }; ColorPicker("自定义强调色", selection: Binding(get:{Color(hex:model.settings.themeColor)}, set:{ model.settings.themeColor=$0.hexString; model.persistSettings() })) }; Picker("桌面卡片", selection:$model.settings.desktopTheme) { Text("深邃墨夜").tag("dark"); Text("跟随主题色调").tag("tinted"); Text("清爽明亮").tag("light") }.onChange(of:model.settings.desktopTheme) { _ in model.persistSettings() } } }
        GroupBox("文字与排版") { Picker("字体大小", selection:$model.settings.fontScale) { Text("小 (90%)").tag(0.9); Text("标准 (100%)").tag(1.0); Text("大 (115%)").tag(1.15); Text("特大 (130%)").tag(1.3) }.onChange(of:model.settings.fontScale) { _ in model.persistSettings() } }
        GroupBox("登录启动") { VStack(alignment:.leading) { Toggle("登录时启动 DayLine", isOn: Binding(get:{model.settings.launchAtLogin}, set:{ model.setLaunchAtLogin($0) })).help("macOS 可能会要求在系统设置中确认"); if #available(macOS 13.0, *), SMAppService.mainApp.status == .requiresApproval { Text("已请求登录启动，请在系统设置中批准。").font(.caption).foregroundStyle(.secondary) } } }
        HStack { Button("恢复默认") { model.resetSettings() }; Spacer(); Button("完成") { dismiss() }.buttonStyle(.borderedProminent) } }.padding(24).frame(width:500).font(.system(size:13 * model.settings.fontScale)) }
}

extension Color { init(hex: String) { let s=hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")); let v=UInt64(s,radix:16) ?? 0x28735f; self.init(.sRGB,red:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255,opacity:1) }; var hexString:String { let n=NSColor(self).usingColorSpace(.sRGB) ?? .systemGreen; return String(format:"#%02x%02x%02x",Int(n.redComponent*255),Int(n.greenComponent*255),Int(n.blueComponent*255)) } }
