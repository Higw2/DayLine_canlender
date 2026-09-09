import AppKit
import SwiftUI
import DayLineCore

public struct DayLineBackgroundView: View {
    let settings: AppSettings
    var cornerRadius: CGFloat = 16

    public init(settings: AppSettings, cornerRadius: CGFloat = 16) {
        self.settings = settings
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            if settings.bgType == "image",
               !settings.bgImagePath.isEmpty,
               let nsImage = NSImage(contentsOfFile: settings.bgImagePath) {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(settings.bgOpacity)
                }
                Color(hex: settings.bgColor)
                    .opacity(max(0.08, 0.35 * (1.0 - settings.bgOpacity)))
                Color.black.opacity(0.12)
            } else {
                Color(hex: settings.bgColor)
                    .opacity(settings.bgOpacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

final class DesktopPanel: NSPanel {
    private let model: DayLineModel
    private let geometryURL = DataPaths.shared.geometry

    init(model: DayLineModel, openMain: @escaping () -> Void, newEvent: @escaping () -> Void, settings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.model = model
        super.init(contentRect: NSRect(x: 120, y: 130, width: 390, height: 300), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        title = "DayLine 桌面卡片"
        isFloatingPanel = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true

        contentView = NSHostingView(rootView: DesktopCard(model: model, openMain: openMain, newEvent: newEvent, settings: settings, quit: quit))
        loadGeometry()
        NotificationCenter.default.addObserver(self, selector: #selector(saveGeometry), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(saveGeometry), name: NSWindow.didResizeNotification, object: self)
    }

    func show() { clamp(); orderFrontRegardless() }

    @objc private func saveGeometry() {
        let f = frame
        let values: [String: CGFloat] = ["x": f.origin.x, "y": f.origin.y, "width": f.width, "height": f.height]
        if let d = try? JSONEncoder().encode(values) { try? d.write(to: geometryURL, options: .atomic) }
    }

    private func loadGeometry() {
        guard let d = try? Data(contentsOf: geometryURL),
              let v = try? JSONDecoder().decode([String: CGFloat].self, from: d),
              let x = v["x"], let y = v["y"], let w = v["width"], let h = v["height"] else { return }
        setFrame(NSRect(x: x, y: y, width: max(340, w), height: max(220, h)), display: false)
    }

    private func clamp() {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        guard let screen else { return }
        var f = frame
        let visible = screen.visibleFrame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
        setFrame(f, display: true)
    }
}

struct DesktopCard: View {
    @ObservedObject var model: DayLineModel
    let openMain: () -> Void
    let newEvent: () -> Void
    let settings: () -> Void
    let quit: () -> Void

    private var isLight: Bool {
        if model.settings.bgType == "image" { return false }
        if model.settings.desktopTheme == "light" { return true }
        if model.settings.desktopTheme == "tinted" { return false }
        return Color(hex: model.settings.bgColor).isLightColor
    }

    var body: some View {
        ZStack {
            DayLineBackgroundView(settings: model.settings, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: model.settings.themeColor))
                        Text("DayLine")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isLight ? Color.primary : Color.white)
                    }
                    Spacer()
                    ClockView(isLight: isLight)
                }

                // Date
                Text(Date(), format: .dateTime.year().month().day().weekday())
                    .font(.system(size: 11 * model.settings.fontScale))
                    .foregroundStyle(isLight ? Color.secondary : Color.white.opacity(0.8))

                Divider()
                    .overlay(isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18))

                // Upcoming items
                if model.upcoming.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: model.settings.themeColor).opacity(0.75))
                        Text("暂无近期待办，给自己留一点空白。")
                            .font(.system(size: 12 * model.settings.fontScale))
                            .foregroundStyle(isLight ? Color.secondary : Color.white.opacity(0.75))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.upcoming.prefix(5)) { e in
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(Color(hex: model.settings.themeColor))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title)
                                        .font(.system(size: 12.5 * model.settings.fontScale, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(isLight ? Color.primary : Color.white)
                                    Text(e.startsAt, format: .dateTime.month().day().hour().minute())
                                        .font(.system(size: 10 * model.settings.fontScale))
                                        .foregroundStyle(isLight ? Color.secondary : Color.white.opacity(0.7))
                                }
                                Spacer()
                                Button {
                                    model.complete(e)
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 20, height: 20)
                                        .background(Color(hex: model.settings.themeColor).opacity(0.25), in: Circle())
                                        .foregroundStyle(isLight ? Color(hex: model.settings.themeColor) : Color.white)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                            )
                        }
                    }
                }

                Spacer(minLength: 4)

                // Footer Buttons
                HStack(spacing: 8) {
                    Button(action: newEvent) {
                        Label("新建", systemImage: "plus")
                            .font(.system(size: 11 * model.settings.fontScale, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: model.settings.themeColor))

                    Button(action: openMain) {
                        Label("打开", systemImage: "calendar")
                            .font(.system(size: 11 * model.settings.fontScale))
                    }
                    .buttonStyle(.bordered)

                    Button(action: settings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11 * model.settings.fontScale))
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: quit) {
                        Image(systemName: "power")
                            .font(.system(size: 11 * model.settings.fontScale))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 340, minHeight: 220)
    }
}

struct ClockView: View {
    var isLight: Bool = false
    @State private var now = Date()
    var body: some View {
        Text(now, format: .dateTime.hour().minute().second())
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(isLight ? Color.primary : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
            )
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
