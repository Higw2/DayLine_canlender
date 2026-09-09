import AppKit
import SwiftUI
import DayLineCore

struct TimelineRepresentable: NSViewRepresentable {
    let day: Date; let events: [CalendarEvent]; let color: String; let fontScale: Double
    let bgColor: String; let bgOpacity: Double; let bgImagePath: String; let bgType: String
    let open: (CalendarEvent) -> Void; let newRange: (Date, Date) -> Void; let complete: (CalendarEvent) -> Void
    func makeNSView(context: Context) -> TimelineNSView { TimelineNSView() }
    func updateNSView(_ view: TimelineNSView, context: Context) {
        view.day = day; view.events = events; view.accent = NSColor(Color(hex:color)); view.fontScale = fontScale
        view.bgColor = bgColor; view.bgOpacity = bgOpacity; view.bgImagePath = bgImagePath; view.bgType = bgType
        view.open = open; view.newRange = newRange; view.complete = complete; view.needsDisplay = true
    }
}

final class TimelineNSView: NSView {
    var day = Date(); var events:[CalendarEvent]=[]; var accent = NSColor.systemGreen; var fontScale: Double = 1
    var bgColor: String = "#1e242b"; var bgOpacity: Double = 0.90; var bgImagePath: String = ""; var bgType: String = "color"
    var open: ((CalendarEvent)->Void)?; var newRange: ((Date,Date)->Void)?; var complete: ((CalendarEvent)->Void)?
    private var dragStart: CGFloat?; private var cards: [(TimelineLayout.Placement, NSRect)] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect); let gutter:CGFloat=64; let width=max(bounds.width,540)
        // Background: Color or Image
        if bgType == "image", !bgImagePath.isEmpty, let img = NSImage(contentsOfFile: bgImagePath) {
            let imgSize = img.size
            if imgSize.width > 0 && imgSize.height > 0 {
                let scale = max(bounds.width / imgSize.width, bounds.height / imgSize.height)
                let drawW = imgSize.width * scale; let drawH = imgSize.height * scale
                let drawRect = NSRect(x: (bounds.width - drawW) / 2, y: (bounds.height - drawH) / 2, width: drawW, height: drawH)
                img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: CGFloat(bgOpacity))
            }
            NSColor(Color(hex: bgColor)).withAlphaComponent(CGFloat(max(0.08, 0.35 * (1.0 - bgOpacity)))).setFill()
            bounds.fill()
        } else {
            let bgNSColor = NSColor(Color(hex: bgColor)).withAlphaComponent(CGFloat(bgOpacity))
            bgNSColor.setFill()
            bounds.fill()
        }

        let isLight = Color(hex: bgColor).isLightColor && (bgType != "image")
        let separatorCol = isLight ? NSColor.separatorColor : NSColor.white.withAlphaComponent(0.18)
        let labelCol = isLight ? NSColor.secondaryLabelColor : NSColor.white.withAlphaComponent(0.72)

        for minute in stride(from:0, through:1440, by:30) {
            let y=CGFloat(minute)
            (minute % 60 == 0 ? separatorCol : separatorCol.withAlphaComponent(0.4)).setStroke()
            let line=NSBezierPath(); line.move(to:NSPoint(x:gutter,y:y)); line.line(to:NSPoint(x:width,y:y)); line.lineWidth=minute % 60 == 0 ? 1:0.5; line.stroke()
            if minute < 1440 && minute % 60 == 0 {
                let text=String(format:"%02d:00",minute/60)
                text.draw(at:NSPoint(x:9,y:y+7),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11 * fontScale,weight:.regular),.foregroundColor:labelCol])
            }
        }
        separatorCol.setStroke(); let v=NSBezierPath(); v.move(to:NSPoint(x:gutter,y:0)); v.line(to:NSPoint(x:gutter,y:1440)); v.stroke()
        cards=[]; let placements=TimelineLayout.placements(events,on:day)
        for p in placements {
            let start=TimelineLayout.minute(p.start,on:day); let end=TimelineLayout.minute(p.end,on:day)
            let x=gutter+5+CGFloat(p.column)*(width-gutter-10)/CGFloat(p.columns); let cardWidth=(width-gutter-10)/CGFloat(p.columns)-5
            let rect=NSRect(x:x,y:CGFloat(start),width:cardWidth,height:max(TimelineLayout.minimumCardHeight,CGFloat(end-start)))
            cards.append((p,rect)); drawCard(p,rect)
        }
        if Calendar.current.isDateInToday(day) {
            let comps=Calendar.current.dateComponents([.hour,.minute],from:Date())
            let y=CGFloat((comps.hour ?? 0)*60+(comps.minute ?? 0))
            accent.setStroke(); let line=NSBezierPath(); line.move(to:NSPoint(x:gutter,y:y)); line.line(to:NSPoint(x:width,y:y)); line.lineWidth=2; line.stroke()
        }
        if let start=dragStart {
            let selection=TimelineLayout.selection(from:start,to:currentMouseY)
            let rect=NSRect(x:gutter+5,y:CGFloat(selection.0),width:width-gutter-10,height:CGFloat(selection.1-selection.0))
            accent.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4).fill()
            accent.withAlphaComponent(0.6).setStroke(); let border=NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4); border.lineWidth=1; border.stroke()
            TimelineLayout.timeText(selection.0).appending(" – ").appending(TimelineLayout.timeText(selection.1)).draw(at:NSPoint(x:rect.minX+8,y:rect.minY+5),withAttributes:[.font:NSFont.systemFont(ofSize:11 * fontScale,weight:.semibold),.foregroundColor:accent])
        }
    }
    private var currentMouseY: CGFloat { convert(window?.mouseLocationOutsideOfEventStream ?? .zero,from:nil).y }
    private func drawCard(_ p: TimelineLayout.Placement,_ rect:NSRect) {
        let done=p.event.completed; let cardColor = done ? NSColor.systemGray : accent
        cardColor.withAlphaComponent(done ? 0.28:0.88).setFill(); NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6).fill()
        cardColor.withAlphaComponent(done ? 0.4:1.0).setStroke(); let outline=NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6); outline.lineWidth=1; outline.stroke()
        let textColor=done ? NSColor.secondaryLabelColor : .white
        let start=TimelineLayout.timeText(TimelineLayout.minute(p.start,on:day)); let end=TimelineLayout.timeText(TimelineLayout.minute(p.end,on:day))
        let title=p.event.title + (rect.height < 45 ? " · \(start)" : "")
        title.draw(in:rect.insetBy(dx:8,dy:6),withAttributes:[.font:NSFont.systemFont(ofSize:12 * fontScale,weight:.semibold),.foregroundColor:textColor])
        if rect.height >= 45 { ("\(start) — \(end)" + (p.event.notes.isEmpty ? "" : "  ·  \(p.event.notes)")).draw(in:NSRect(x:rect.minX+8,y:rect.minY+24,width:rect.width-16,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:10 * fontScale),.foregroundColor:textColor.withAlphaComponent(0.9)]) }
    }
    override func mouseDown(with event: NSEvent) { let point=convert(event.locationInWindow,from:nil); if let card=cards.first(where:{$0.1.contains(point)}) { if event.clickCount == 2 { open?(card.0.event) } else if event.modifierFlags.contains(.command) { complete?(card.0.event) }; return }; guard point.x > 64 else{return}; dragStart=point.y; needsDisplay=true }
    override func mouseDragged(with event: NSEvent) { if dragStart != nil { needsDisplay=true } }
    override func mouseUp(with event: NSEvent) { guard let start=dragStart else{return}; let end=convert(event.locationInWindow,from:nil).y; dragStart=nil; needsDisplay=true; let range=TimelineLayout.selection(from:start,to:end); newRange?(date(range.0),date(range.1)) }
    private func date(_ minute:Int)->Date { var c=Calendar.current.dateComponents([.year,.month,.day],from:day); c.hour=minute/60; c.minute=minute%60; c.second=0; return Calendar.current.date(from:c)! }
}
