import AppKit
import SwiftUI
import DayLineCore

struct TimelineRepresentable: NSViewRepresentable {
    let day: Date; let events: [CalendarEvent]; let color: String; let fontScale: Double
    let bgColor: String; let bgOpacity: Double; let bgImagePath: String; let bgType: String
    let open: (CalendarEvent) -> Void; let delete: (CalendarEvent) -> Void
    let newRange: (Date, Date) -> Void
    let resize: (CalendarEvent, DateInterval) -> Void
    let complete: (CalendarEvent) -> Void
    func makeNSView(context: Context) -> TimelineNSView { TimelineNSView() }
    func updateNSView(_ view: TimelineNSView, context: Context) {
        view.cancelIfInvalidated(day: day, events: events)
        view.day = day; view.events = events; view.accent = NSColor(Color(hex:color)); view.fontScale = fontScale
        view.bgColor = bgColor; view.bgOpacity = bgOpacity; view.bgImagePath = bgImagePath; view.bgType = bgType
        view.open = open; view.delete = delete; view.newRange = newRange; view.complete = complete
        view.resizeEvent = resize
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
    var resizeEvent: ((CalendarEvent, DateInterval) -> Void)?
    private var dragStart: CGFloat?; private var cards: [(TimelineLayout.Placement, NSRect)] = []
    private var creationCurrentY: CGFloat = 0
    private struct ResizeDrag {
        let original: CalendarEvent
        let edge: TimelineLayout.ResizeEdge
        let originY: CGFloat
        var range: DateInterval?
        var moved = false
    }
    private var resizeDrag: ResizeDrag?
    private var actionButtons: [(edit: TimelineActionButton, delete: TimelineActionButton)] = []
    private let buttonSize: CGFloat = 22
    private let buttonGap: CGFloat = 3
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func cancelIfInvalidated(day: Date, events: [CalendarEvent]) {
        if !Calendar.current.isDate(self.day, inSameDayAs: day) { cancelOperation(nil); return }
        if let drag = resizeDrag {
            guard let current = events.first(where: { $0.id == drag.original.id }),
                  current.startsAt == drag.original.startsAt, current.endsAt == drag.original.endsAt else {
                cancelOperation(nil); return
            }
        }
    }

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
        window?.invalidateCursorRects(for: self)
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
        let visibleIDs = Set(cards.map { $0.0.event.id })
        for buttons in actionButtons {
            buttons.edit.isHidden = !visibleIDs.contains(buttons.edit.eventID)
            buttons.delete.isHidden = buttons.edit.isHidden
        }
        let buttonsByID = Dictionary(uniqueKeysWithValues: actionButtons.map { ($0.edit.eventID, $0) })
        for card in cards {
            guard let buttons = buttonsByID[card.0.event.id] else { continue }
            let rect = card.1
            buttons.delete.frame = NSRect(x: rect.maxX - 5 - buttonSize, y: rect.minY + 5, width: buttonSize, height: buttonSize)
            buttons.edit.frame = NSRect(x: buttons.delete.frame.minX - buttonGap - buttonSize, y: rect.minY + 5, width: buttonSize, height: buttonSize)
        }
    }

    private func positionedCards() -> [(TimelineLayout.Placement, NSRect)] {
        let gutter: CGFloat = 64
        let width = max(bounds.width, 260)
        let previewEvents = events.map { event -> CalendarEvent in
            guard let drag = resizeDrag, let range = drag.range, event.id == drag.original.id else { return event }
            var preview = event; preview.startsAt = range.start; preview.endsAt = range.end
            return preview
        }
        return TimelineLayout.placements(previewEvents, on: day).map { placement in
            let start = TimelineLayout.minute(placement.start, on: day)
            let end = TimelineLayout.minute(placement.end, on: day)
            let columnWidth = (width - gutter - 10) / CGFloat(placement.columns)
            let rect = NSRect(
                x: gutter + 5 + CGFloat(placement.column) * columnWidth,
                y: CGFloat(start),
                width: columnWidth - 5,
                height: min(CGFloat(TimelineLayout.dayMinutes - start), max(TimelineLayout.minimumCardHeight, CGFloat(end - start)))
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
            let selection=TimelineLayout.selection(from:start,to:creationCurrentY)
            let rect=NSRect(x:gutter+5,y:CGFloat(selection.0),width:width-gutter-10,height:CGFloat(selection.1-selection.0))
            accent.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4).fill()
            accent.withAlphaComponent(0.6).setStroke(); let border=NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4); border.lineWidth=1; border.stroke()
            TimelineLayout.timeText(selection.0).appending(" – ").appending(TimelineLayout.timeText(selection.1)).draw(at:NSPoint(x:rect.minX+8,y:rect.minY+5),withAttributes:[.font:NSFont.systemFont(ofSize:11 * fontScale,weight:.semibold),.foregroundColor:accent])
        }
        if let drag = resizeDrag, let range = drag.range {
            let label = "\(range.start.formatted(.dateTime.month().day().hour().minute())) — \(range.end.formatted(.dateTime.month().day().hour().minute()))"
            let edgeY = cards.first(where: { $0.0.event.id == drag.original.id }).map { drag.edge == .start ? $0.1.minY : $0.1.maxY } ?? visibleRect.minY
            let y = max(visibleRect.minY + 2, min(edgeY - 27, visibleRect.maxY - 26))
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
            let size = label.size(withAttributes: attributes)
            let bubble = NSRect(x: gutter + 5, y: y, width: min(size.width + 16, width - gutter - 10), height: 24)
            NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: bubble, xRadius: 4, yRadius: 4).fill()
            label.draw(in: bubble.insetBy(dx: 8, dy: 4), withAttributes: attributes)
        }
    }
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
        NSColor.white.withAlphaComponent(0.8).setStroke()
        for edge in [TimelineLayout.ResizeEdge.start, .end] where TimelineLayout.canResize(p.event, edge: edge, on: day) {
            let y = edge == .start ? rect.minY + 2.5 : rect.maxY - 2.5
            let halfWidth = min(16, rect.width / 4)
            let handle = NSBezierPath(); handle.move(to: NSPoint(x: rect.midX - halfWidth, y: y)); handle.line(to: NSPoint(x: rect.midX + halfWidth, y: y)); handle.lineWidth = 2; handle.stroke()
        }
    }

    private func edgeRect(_ edge: TimelineLayout.ResizeEdge, in rect: NSRect) -> NSRect {
        let height = min(7, rect.height / 3)
        return NSRect(x: rect.minX, y: edge == .start ? rect.minY : rect.maxY - height, width: rect.width, height: height)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for (placement, rect) in positionedCards() {
            for edge in [TimelineLayout.ResizeEdge.start, .end] where TimelineLayout.canResize(placement.event, edge: edge, on: day) {
                addCursorRect(edgeRect(edge, in: rect), cursor: .resizeUpDown)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelOperation(nil)
        window?.makeFirstResponder(self)
        positionActionButtons()
        let point = convert(event.locationInWindow, from: nil)
        if let card = cards.reversed().first(where: { $0.1.contains(point) }) {
            if event.clickCount == 2 { open?(card.0.event); return }
            if event.modifierFlags.contains(.command) { complete?(card.0.event); return }
            for edge in [TimelineLayout.ResizeEdge.start, .end] where TimelineLayout.canResize(card.0.event, edge: edge, on: day) {
                if edgeRect(edge, in: card.1).contains(point) {
                    resizeDrag = ResizeDrag(original: card.0.event, edge: edge, originY: point.y)
                    break
                }
            }
            return
        }
        guard point.x > 64 else { return }
        dragStart = point.y; creationCurrentY = point.y; needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        _ = autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if var drag = resizeDrag {
            if abs(point.y - drag.originY) >= 3 { drag.moved = true }
            if drag.moved {
                drag.range = TimelineLayout.resizedInterval(drag.original, edge: drag.edge, on: day, deltaY: point.y - drag.originY)
                resizeDrag = drag
                positionActionButtons()
                needsDisplay = true
            }
        } else if dragStart != nil { creationCurrentY = point.y; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        if var drag = resizeDrag {
            let delta = convert(event.locationInWindow, from: nil).y - drag.originY
            if drag.moved || abs(delta) >= 3 {
                drag.moved = true
                drag.range = TimelineLayout.resizedInterval(drag.original, edge: drag.edge, on: day, deltaY: delta)
            }
            resizeDrag = nil; positionActionButtons(); needsDisplay = true
            window?.invalidateCursorRects(for: self)
            if drag.moved, let range = drag.range, range.start != drag.original.startsAt || range.end != drag.original.endsAt {
                resizeEvent?(drag.original, range)
            }
            return
        }
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil).y
        dragStart = nil; needsDisplay = true
        let range = TimelineLayout.selection(from: start, to: end)
        newRange?(TimelineLayout.date(atMinute: range.0, on: day), TimelineLayout.date(atMinute: range.1, on: day))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        dragStart = nil; resizeDrag = nil; needsDisplay = true
        positionActionButtons()
    }
}
