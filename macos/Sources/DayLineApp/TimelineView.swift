import AppKit
import SwiftUI
import DayLineCore

struct TimelineRepresentable: NSViewRepresentable {
    let day: Date; let events: [CalendarEvent]; let color: String; let fontScale: Double
    let bgColor: String; let bgOpacity: Double; let bgImagePath: String; let bgType: String
    let open: (CalendarEvent) -> Void; let delete: (CalendarEvent) -> Void
    let newRange: (Date, Date) -> Void; let complete: (CalendarEvent) -> Void
    func makeNSView(context: Context) -> TimelineNSView { TimelineNSView() }
    func updateNSView(_ view: TimelineNSView, context: Context) {
        view.day = day; view.events = events; view.accent = NSColor(Color(hex:color)); view.fontScale = fontScale
        view.bgColor = bgColor; view.bgOpacity = bgOpacity; view.bgImagePath = bgImagePath; view.bgType = bgType
        view.open = open; view.delete = delete; view.newRange = newRange; view.complete = complete
        view.rebuildActionButtons(); view.needsDisplay = true
    }
}

private final class TimelineActionButton: NSButton {
    var eventID: Int64 = 0
}

final class TimelineNSView: NSView {
    var day = Date(); var events:[CalendarEvent]=[]; var accent = NSColor.systemGreen; var fontScale: Double = 1
    var bgColor: String = "#1e242b"; var bgOpacity: Double = 0.90; var bgImagePath: String = ""; var bgType: String = "color"
    var open: ((CalendarEvent)->Void)?; var delete: ((CalendarEvent)->Void)?
    var newRange: ((Date,Date)->Void)?; var complete: ((CalendarEvent)->Void)?
    private var dragStart: CGFloat?; private var cards: [(TimelineLayout.Placement, NSRect)] = []
    private var actionButtons: [(edit: TimelineActionButton, delete: TimelineActionButton)] = []
    private let buttonSize: CGFloat = 22
    private let buttonGap: CGFloat = 3
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    func rebuildActionButtons() {
        for pair in actionButtons { pair.edit.removeFromSuperview(); pair.delete.removeFromSuperview() }
        actionButtons = TimelineLayout.placements(events, on: day).map { placement in
            let edit = makeActionButton(for: placement.event, symbol: "pencil", label: "编辑", action: #selector(editEvent(_:)))
            let delete = makeActionButton(for: placement.event, symbol: "trash", label: "删除", action: #selector(deleteEvent(_:)))
            addSubview(edit)
            addSubview(delete)
            return (edit, delete)
        }
        positionActionButtons()
    }

    private func makeActionButton(for event: CalendarEvent, symbol: String, label: String, action: Selector) -> TimelineActionButton {
        let button = TimelineActionButton(frame: .zero)
        button.eventID = event.id
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        button.contentTintColor = .white
        button.toolTip = "\(label)事件：\(event.title)"
        button.setAccessibilityLabel("\(label)事件：\(event.title)")
        button.target = self
        button.action = action
        return button
    }

    @objc private func editEvent(_ sender: TimelineActionButton) {
        guard let event = events.first(where: { $0.id == sender.eventID }) else { return }
        open?(event)
    }

    @objc private func deleteEvent(_ sender: TimelineActionButton) {
        guard let event = events.first(where: { $0.id == sender.eventID }) else { return }
        delete?(event)
    }

    override func layout() {
        super.layout()
        positionActionButtons()
    }

    private func positionActionButtons() {
        cards = positionedCards()
        for (card, buttons) in zip(cards, actionButtons) {
            let rect = card.1
            buttons.delete.frame = NSRect(x: rect.maxX - 5 - buttonSize, y: rect.minY + 5, width: buttonSize, height: buttonSize)
            buttons.edit.frame = NSRect(x: buttons.delete.frame.minX - buttonGap - buttonSize, y: rect.minY + 5, width: buttonSize, height: buttonSize)
        }
    }

    private func positionedCards() -> [(TimelineLayout.Placement, NSRect)] {
        let gutter: CGFloat = 64
        let width = max(bounds.width, 260)
        return TimelineLayout.placements(events, on: day).map { placement in
            let start = TimelineLayout.minute(placement.start, on: day)
            let end = TimelineLayout.minute(placement.end, on: day)
            let columnWidth = (width - gutter - 10) / CGFloat(placement.columns)
            let rect = NSRect(
                x: gutter + 5 + CGFloat(placement.column) * columnWidth,
                y: CGFloat(start),
                width: columnWidth - 5,
                height: max(TimelineLayout.minimumCardHeight, CGFloat(end - start))
            )
            return (placement, rect)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { positionActionButtons(); needsDisplay = true }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let changed = newSize != bounds.size
        super.setBoundsSize(newSize)
        if changed { positionActionButtons(); needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect); let gutter:CGFloat=64; let width=max(bounds.width,260)

        let isLight = Color(hex: bgColor).isLightColor && (bgType != "image")
        let separatorCol = isLight ? NSColor.separatorColor : NSColor.white.withAlphaComponent(0.22)
        let labelCol = isLight ? NSColor.secondaryLabelColor : NSColor.white.withAlphaComponent(0.85)

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
        positionActionButtons()
        for (placement, rect) in cards { drawCard(placement, rect) }
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
        let buttonSpace = buttonSize * 2 + buttonGap + 10
        title.draw(in:NSRect(x:rect.minX+8,y:rect.minY+6,width:max(0,rect.width-buttonSpace-8),height:rect.height-12),withAttributes:[.font:NSFont.systemFont(ofSize:12 * fontScale,weight:.semibold),.foregroundColor:textColor])
        if rect.height >= 45 { ("\(start) — \(end)" + (p.event.notes.isEmpty ? "" : "  ·  \(p.event.notes)")).draw(in:NSRect(x:rect.minX+8,y:rect.minY+24,width:max(0,rect.width-buttonSpace-8),height:18),withAttributes:[.font:NSFont.systemFont(ofSize:10 * fontScale),.foregroundColor:textColor.withAlphaComponent(0.9)]) }
    }
    override func mouseDown(with event: NSEvent) { let point=convert(event.locationInWindow,from:nil); if let card=cards.first(where:{$0.1.contains(point)}) { if event.clickCount == 2 { open?(card.0.event) } else if event.modifierFlags.contains(.command) { complete?(card.0.event) }; return }; guard point.x > 64 else{return}; dragStart=point.y; needsDisplay=true }
    override func mouseDragged(with event: NSEvent) { if dragStart != nil { needsDisplay=true } }
    override func mouseUp(with event: NSEvent) { guard let start=dragStart else{return}; let end=convert(event.locationInWindow,from:nil).y; dragStart=nil; needsDisplay=true; let range=TimelineLayout.selection(from:start,to:end); newRange?(date(range.0),date(range.1)) }
    private func date(_ minute:Int)->Date { var c=Calendar.current.dateComponents([.year,.month,.day],from:day); c.hour=minute/60; c.minute=minute%60; c.second=0; return Calendar.current.date(from:c)! }
}
