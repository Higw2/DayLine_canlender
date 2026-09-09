import AppKit
import SwiftUI
import DayLineCore

final class DesktopPanel: NSPanel {
    private let model: DayLineModel; private let geometryURL = DataPaths.shared.geometry
    init(model: DayLineModel, openMain:@escaping()->Void, newEvent:@escaping()->Void, settings:@escaping()->Void, quit:@escaping()->Void) {
        self.model=model; super.init(contentRect:NSRect(x:120,y:130,width:390,height:300),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
        title = "DayLine 桌面卡片"; isFloatingPanel = false
        // AppKit cannot place a normal app beneath the Finder desktop.  Keep the
        // card just below ordinary app windows, above the desktop background.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]; isReleasedWhenClosed = false; hidesOnDeactivate = false; contentView = NSHostingView(rootView: DesktopCard(model:model,openMain:openMain,newEvent:newEvent,settings:settings,quit:quit)); loadGeometry(); NotificationCenter.default.addObserver(self,selector:#selector(saveGeometry),name:NSWindow.didMoveNotification,object:self); NotificationCenter.default.addObserver(self,selector:#selector(saveGeometry),name:NSWindow.didResizeNotification,object:self)
    }
    func show() { clamp(); orderFrontRegardless() }
    @objc private func saveGeometry() { let f=frame; let values:[String:CGFloat]=["x":f.origin.x,"y":f.origin.y,"width":f.width,"height":f.height]; if let d=try? JSONEncoder().encode(values) { try? d.write(to:geometryURL,options:.atomic) } }
    private func loadGeometry() { guard let d=try? Data(contentsOf:geometryURL),let v=try? JSONDecoder().decode([String:CGFloat].self,from:d),let x=v["x"],let y=v["y"],let w=v["width"],let h=v["height"] else{return}; setFrame(NSRect(x:x,y:y,width:max(340,w),height:max(220,h)),display:false) }
    private func clamp() { let screen=NSScreen.screens.first(where:{$0.visibleFrame.intersects(frame)}) ?? NSScreen.main; guard let screen else{return}; var f=frame; let visible=screen.visibleFrame; f.size.width=min(f.width,visible.width); f.size.height=min(f.height,visible.height); f.origin.x=min(max(f.origin.x,visible.minX),visible.maxX-f.width); f.origin.y=min(max(f.origin.y,visible.minY),visible.maxY-f.height); setFrame(f,display:true) }
}

struct DesktopCard: View {
    @ObservedObject var model:DayLineModel; let openMain:()->Void; let newEvent:()->Void; let settings:()->Void; let quit:()->Void
    var body: some View { let dark=model.settings.desktopTheme != "light"; VStack(alignment:.leading,spacing:9) { HStack { Text("DayLine").font(.headline); Spacer(); ClockView() }; Text(Date(),format:.dateTime.year().month().day().weekday()).font(.caption).opacity(0.75); Divider(); if model.upcoming.isEmpty { Text("暂无近期待办").foregroundStyle(.secondary).frame(maxHeight:.infinity) } else { ForEach(model.upcoming.prefix(5)) { e in HStack(alignment:.top) { Circle().fill(Color(hex:model.settings.themeColor)).frame(width:7,height:7).padding(.top,4); VStack(alignment:.leading) { Text(e.title).lineLimit(1); Text(e.startsAt,format:.dateTime.month().day().hour().minute()).font(.caption).opacity(0.7) }; Spacer(); Button("✓") { model.complete(e) }.buttonStyle(.borderless) } } }; Spacer(); HStack { Button("新建",action:newEvent); Button("打开",action:openMain); Button("设置",action:settings); Spacer(); Button("退出",action:quit) } }.padding(16).font(.system(size:13*model.settings.fontScale)).foregroundStyle(dark ? .white:.primary).background(dark ? (model.settings.desktopTheme == "tinted" ? Color(hex:model.settings.themeColor).opacity(0.82):Color(red:0.09,green:0.13,blue:0.12)):.white).onReceive(model.$upcoming) { _ in } }
}
struct ClockView: View { @State private var now=Date(); var body:some View { Text(now,format:.dateTime.hour().minute().second()).monospacedDigit().onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()) { now=$0 } } }
