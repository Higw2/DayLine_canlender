import AppKit
import SwiftUI

public struct NoteTextInput: NSViewRepresentable {
    @Binding private var text: String
    private let revision: UInt64
    private let fontSize: CGFloat
    private let singleLine: Bool
    private let label: String
    private let focusRequest: UInt64

    public init(text: Binding<String>, revision: UInt64, fontSize: CGFloat, singleLine: Bool = false, label: String, focusRequest: UInt64 = 0) {
        _text = text; self.revision = revision; self.fontSize = fontSize
        self.singleLine = singleLine; self.label = label; self.focusRequest = focusRequest
    }

    public final class Coordinator {
        var focusRequest: UInt64 = 0
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = !singleLine
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let view = NoteTextView(frame: scroll.bounds)
        view.singleLine = singleLine
        if singleLine { view.placeholder = "标题（可选）" }
        view.isRichText = false; view.importsGraphics = false; view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 6, height: singleLine ? 4 : 8)
        view.isVerticallyResizable = !singleLine; view.isHorizontallyResizable = singleLine
        view.autoresizingMask = singleLine ? [.width, .height] : [.width]
        view.textContainer?.widthTracksTextView = !singleLine
        view.textContainer?.containerSize = NSSize(width: singleLine ? CGFloat.greatestFiniteMagnitude : scroll.bounds.width, height: .greatestFiniteMagnitude)
        view.setAccessibilityLabel(label)
        scroll.documentView = view
        updateNSView(scroll, context: context)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NoteTextView else { return }
        view.onCommittedChange = { text = $0 }
        let font = NSFont.systemFont(ofSize: fontSize)
        if view.font != font { view.font = font }
        view.loadDraft(text, revision: revision)
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            view.requestFocus()
        }
    }
}
