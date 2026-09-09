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
    private var isLightBg: Bool {
        if model.settings.bgType == "image" { return false }
        return Color(hex: model.settings.bgColor).isLightColor
    }
    var body: some View {
        ZStack {
            DayLineBackgroundView(settings: model.settings, cornerRadius: 0)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DayLine").font(.system(size: 23, weight: .bold)).foregroundStyle(Color(hex: model.settings.themeColor))
                    Button("返回今天") { model.selectedDay = Calendar.current.startOfDay(for: Date()); model.reload() }.buttonStyle(.borderedProminent).tint(Color(hex: model.settings.themeColor))
                    DatePicker("", selection: $model.selectedDay, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().onChange(of: model.selectedDay) { _ in model.reload() }
                    Text("下一项安排").font(.headline)
                    if model.upcoming.isEmpty {
                        Text("暂无近期待办").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.upcoming) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.startsAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(Color(hex: model.settings.themeColor))
                                Text(e.title).lineLimit(1).font(.system(size: 13, weight: .medium))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Spacer()
                    Button("收起到桌面") { showDesktop() }.buttonStyle(.bordered)
                    Button("退出 DayLine") { quit() }.foregroundStyle(.red).buttonStyle(.plain)
                }
                .padding(18)
                .frame(width: 262)
                .background(.ultraThinMaterial.opacity(0.85))

                Divider()

                VStack(spacing: 0) {
                    HStack {
                        Button("‹") { model.go(-1) }.buttonStyle(.bordered)
                        Button("›") { model.go(1) }.buttonStyle(.bordered)
                        Button("今天") { model.selectedDay = Calendar.current.startOfDay(for: Date()); model.reload() }.buttonStyle(.bordered)
                        Text(dayText).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(model.events.filter { !$0.completed }.count) 项待办 · \(model.events.count) 个事件").foregroundStyle(.secondary)
                        Button("偏好设置") { model.showSettings = true }.buttonStyle(.bordered)
                        Button("＋ 新建事件") { model.presentNewEvent() }.buttonStyle(.borderedProminent).tint(Color(hex: model.settings.themeColor))
                    }
                    .padding(12)
                    .background(.ultraThinMaterial.opacity(0.75))

                    Divider()

                    ScrollView([.vertical]) {
                        TimelineRepresentable(
                            day: model.selectedDay,
                            events: model.events,
                            color: model.settings.themeColor,
                            fontScale: model.settings.fontScale,
                            bgColor: model.settings.bgColor,
                            bgOpacity: model.settings.bgOpacity,
                            bgImagePath: model.settings.bgImagePath,
                            bgType: model.settings.bgType,
                            open: { event in model.editing = event; model.showingEditor = true },
                            newRange: { start, end in model.presentNewEvent((start, end)) },
                            complete: { model.complete($0) }
                        )
                        .frame(minWidth: 540, minHeight: 1440)
                    }
                }
            }
        }
        .frame(minWidth: 840, minHeight: 600)
        .font(.system(size: 13 * model.settings.fontScale))
        .sheet(isPresented: $model.showingEditor, onDismiss: { model.editing = nil; model.draftRange = nil }) {
            EventEditor(model: model).font(.system(size: 13 * model.settings.fontScale))
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .alert("DayLine", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }
}

struct EventEditor: View {
    @ObservedObject var model: DayLineModel; @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var notes = ""; @State private var start = Date(); @State private var end = Date().addingTimeInterval(3600)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.editing == nil ? "新建事件" : "编辑事件").font(.title2.bold())
            TextField("事件名称", text: $title)
            DatePicker("开始时间", selection: $start)
            DatePicker("结束时间", selection: $end)
            TextField("备注（可选）", text: $notes, axis: .vertical).lineLimit(3...6)
            HStack {
                if let event = model.editing {
                    Button(event.completed ? "恢复待办" : "标记完成") { model.complete(event, completed: !event.completed); dismiss() }
                    Button("删除", role: .destructive) { model.delete(event); dismiss() }
                    Spacer()
                } else {
                    Spacer()
                }
                Button("取消") { dismiss() }
                Button("保存事件") { if model.save(title: title, start: start, end: end, notes: notes) { dismiss() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: model.settings.themeColor))
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            let e = model.editing
            title = e?.title ?? ""
            notes = e?.notes ?? ""
            start = e?.startsAt ?? model.draftRange?.0 ?? defaultStart()
            end = e?.endsAt ?? model.draftRange?.1 ?? start.addingTimeInterval(3600)
        }
    }
    private func defaultStart() -> Date {
        let date = max(Date(), model.selectedDay)
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
    }
}

struct SettingsView: View {
    @ObservedObject var model: DayLineModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("偏好设置").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent).tint(Color(hex: model.settings.themeColor))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. 强调色
                    GroupBox("强调色彩") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(Accent.allCases) { accent in
                                    Button {
                                        model.settings.themeColor = accent.rawValue
                                        model.persistSettings()
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: accent.rawValue))
                                            .frame(width: 25, height: 25)
                                            .overlay(Circle().stroke(.primary, lineWidth: model.settings.themeColor == accent.rawValue ? 2.5 : 0))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                                ColorPicker("自定义强调色", selection: Binding(get: { Color(hex: model.settings.themeColor) }, set: {
                                    model.settings.themeColor = $0.hexString
                                    model.persistSettings()
                                }))
                            }
                        }
                        .padding(6)
                    }

                    // 2. 背景与个性化（用户可调透明度、背景颜色、自定义图片）
                    GroupBox("背景外观与个性化") {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("背景样式", selection: Binding(get: { model.settings.bgType }, set: {
                                model.settings.bgType = $0
                                model.persistSettings()
                            })) {
                                Text("纯色背景").tag("color")
                                Text("自定义背景图").tag("image")
                            }
                            .pickerStyle(.segmented)

                            if model.settings.bgType == "color" {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("预设背景色").font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        ForEach(BackgroundPreset.allCases) { preset in
                                            Button {
                                                model.settings.bgColor = preset.rawValue
                                                model.settings.bgType = "color"
                                                model.persistSettings()
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Circle()
                                                        .fill(Color(hex: preset.rawValue))
                                                        .frame(width: 24, height: 24)
                                                        .overlay(Circle().stroke(Color.primary, lineWidth: model.settings.bgColor == preset.rawValue && model.settings.bgType == "color" ? 2.5 : 0.5))
                                                    Text(preset.name)
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    HStack {
                                        ColorPicker("自定义背景颜色", selection: Binding(get: { Color(hex: model.settings.bgColor) }, set: {
                                            model.settings.bgColor = $0.hexString
                                            model.settings.bgType = "color"
                                            model.persistSettings()
                                        }))
                                        Spacer()
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    if !model.settings.bgImagePath.isEmpty, let img = NSImage(contentsOfFile: model.settings.bgImagePath) {
                                        HStack(spacing: 12) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 72, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(URL(fileURLWithPath: model.settings.bgImagePath).lastPathComponent)
                                                    .font(.system(size: 12, weight: .semibold))
                                                Text(model.settings.bgImagePath)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button("更换图片...") { selectCustomImage() }
                                            Button("清除", role: .destructive) {
                                                model.settings.bgImagePath = ""
                                                model.settings.bgType = "color"
                                                model.persistSettings()
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        HStack {
                                            Text("尚未选择自定义背景图片").font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            Button("从电脑选择图片...") { selectCustomImage() }
                                                .buttonStyle(.borderedProminent)
                                                .tint(Color(hex: model.settings.themeColor))
                                        }
                                    }

                                    // Quick test button for science_gate.png in Downloads
                                    let samplePath = ("/Users/holixxx/Downloads/science_gate.png" as NSString).expandingTildeInPath
                                    if FileManager.default.fileExists(atPath: samplePath) {
                                        HStack {
                                            Label("发现测试图片：science_gate.png", systemImage: "sparkles")
                                                .font(.caption)
                                                .foregroundStyle(Color(hex: model.settings.themeColor))
                                            Spacer()
                                            Button("一键测试该图片") {
                                                model.settings.bgImagePath = samplePath
                                                model.settings.bgType = "image"
                                                model.persistSettings()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        .padding(8)
                                        .background(Color(hex: model.settings.themeColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }

                            Divider()

                            // 背景透明度滑动条
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("背景不透明度 (毛玻璃与色彩融合)")
                                    Spacer()
                                    Text("\(Int(model.settings.bgOpacity * 100))%")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(hex: model.settings.themeColor))
                                }
                                Slider(value: Binding(get: { model.settings.bgOpacity }, set: {
                                    model.settings.bgOpacity = (round($0 * 100) / 100)
                                    model.persistSettings()
                                }), in: 0.2...1.0, step: 0.05)
                                HStack {
                                    Text("20% 通透毛玻璃").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("100% 饱满不透明").font(.caption2).foregroundStyle(.secondary)
                                }
                            }

                            Divider()

                            // 桌面卡片主题色调
                            Picker("桌面卡片基调", selection: $model.settings.desktopTheme) {
                                Text("深邃墨夜").tag("dark")
                                Text("跟随主题色调").tag("tinted")
                                Text("清爽明亮").tag("light")
                            }
                            .onChange(of: model.settings.desktopTheme) { _ in model.persistSettings() }
                        }
                        .padding(6)
                    }

                    // 3. 文字与排版
                    GroupBox("文字与排版") {
                        Picker("字体大小缩放", selection: $model.settings.fontScale) {
                            Text("小 (90%)").tag(0.9)
                            Text("标准 (100%)").tag(1.0)
                            Text("大 (115%)").tag(1.15)
                            Text("特大 (130%)").tag(1.3)
                        }
                        .onChange(of: model.settings.fontScale) { _ in model.persistSettings() }
                        .padding(6)
                    }

                    // 4. 登录启动
                    GroupBox("开机自启") {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("登录系统时自动启动 DayLine", isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            Text("macOS 可能会在「系统设置 -> 登录项」中提示授权。").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }
                }
            }

            HStack {
                Button("恢复默认设置") { model.resetSettings() }
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent).tint(Color(hex: model.settings.themeColor))
            }
        }
        .padding(24)
        .frame(width: 530, height: 600)
        .font(.system(size: 13 * model.settings.fontScale))
    }

    private func selectCustomImage() {
        let panel = NSOpenPanel()
        panel.title = "选择日历背景图片"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .webP]
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.bgImagePath = url.path
            model.settings.bgType = "image"
            model.persistSettings()
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x28735f
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: 1)
    }
    var hexString: String {
        let n = NSColor(self).usingColorSpace(.sRGB) ?? .systemGreen
        return String(format: "#%02x%02x%02x", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
    }
    var isLightColor: Bool {
        let n = NSColor(self).usingColorSpace(.sRGB) ?? .systemGray
        let luminance = 0.299 * n.redComponent + 0.587 * n.greenComponent + 0.114 * n.blueComponent
        return luminance > 0.62
    }
}
