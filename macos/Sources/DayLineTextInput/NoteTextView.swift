import AppKit

/// AppKit owns in-progress IME input. Model refreshes only replace text when
/// the user explicitly loads another draft, never on an autosave notification.
public final class NoteTextView: NSTextView {
    public var onCommittedChange: ((String) -> Void)?
    public var singleLine = false
    private var wantsFocus = false
    public var placeholder: String?
    private var revision: UInt64?
    private var applyingModel = false
    private var updatingMarkedText = false
    private var lastPublished = ""

    public func loadDraft(_ text: String, revision: UInt64) {
        guard self.revision != revision else { return }
        applyingModel = true
        if hasMarkedText() { super.unmarkText() }
        if string != text { string = text }
        setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        undoManager?.removeAllActions()
        self.revision = revision; lastPublished = text
        applyingModel = false
    }

    public override func didChangeText() {
        super.didChangeText()
        publishCommittedText()
    }

    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        updatingMarkedText = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updatingMarkedText = false
    }

    public override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let input: Any
        if singleLine {
            let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String) ?? ""
            input = text.components(separatedBy: .newlines).joined(separator: " ")
        } else { input = insertString }
        super.insertText(input, replacementRange: replacementRange)
        // Some input methods finish a composition after didChangeText fires.
        publishCommittedText()
    }

    public override func unmarkText() {
        super.unmarkText()
        publishCommittedText()
    }

    private func publishCommittedText() {
        guard !applyingModel, !updatingMarkedText, !hasMarkedText(), string != lastPublished else { return }
        lastPublished = string
        onCommittedChange?(string)
    }

    public func commitPendingInput() {
        if hasMarkedText() { unmarkText() }
        publishCommittedText()
    }

    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { commitPendingInput() }
        return resigned
    }

    public override func insertNewline(_ sender: Any?) {
        if singleLine { commitPendingInput(); window?.selectNextKeyView(self) }
        else { super.insertNewline(sender) }
    }

    public override func insertTab(_ sender: Any?) {
        if singleLine { commitPendingInput(); window?.selectNextKeyView(self) }
        else { super.insertTab(sender) }
    }

    public func requestFocus() {
        wantsFocus = true
        if let window { window.makeFirstResponder(self); wantsFocus = false }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus { requestFocus() }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
        }
    }

    public static func commitFocusedInput() {
        (NSApp.keyWindow?.firstResponder as? NoteTextView)?.commitPendingInput()
    }
}
