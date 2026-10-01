import AppKit
import XCTest
import DayLineCore
import DayLineTextInput

final class NoteInputTests: XCTestCase {
    @MainActor private func textView(_ text: String = "", revision: UInt64 = 0) -> NoteTextView {
        _ = NSApplication.shared
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isRichText = false; view.allowsUndo = true
        view.loadDraft(text, revision: revision)
        return view
    }

    @MainActor func testModelRefreshCannotOverwriteChineseCompositionOrSelection() async {
        let view = textView("已有文字")
        var updates: [String] = []
        view.onCommittedChange = { updates.append($0) }
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(view.string, "已有文字ni")
        let selection = view.selectedRange(), marked = view.markedRange()
        for _ in 0..<5 { view.loadDraft("已有文字", revision: 0) }
        XCTAssertEqual(view.string, "已有文字ni"); XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.markedRange(), marked); XCTAssertTrue(updates.isEmpty)
        view.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText()); XCTAssertEqual(view.string, "已有文字你好")
        XCTAssertEqual(updates, ["已有文字你好"])
        let committedSelection = view.selectedRange()
        view.loadDraft("旧模型值", revision: 0)
        XCTAssertEqual(view.string, "已有文字你好"); XCTAssertEqual(view.selectedRange(), committedSelection)
    }

    @MainActor func testAutosaveDuringIMEWaitPreservesCandidatesThenSavesCommittedText() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EventStore(path: directory.appendingPathComponent("events.db"))
        let model = NotebookModel(store: store)
        let view = textView()
        view.onCommittedChange = { model.body = $0 }
        model.prepareToSave = { view.commitPendingInput() }
        defer { model.prepareToSave = nil; view.onCommittedChange = nil }
        view.insertText("前缀", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 800_000_000)
        // Simulate the SwiftUI update caused by automatic note creation/list refresh.
        view.loadDraft(model.body, revision: model.draftRevision)
        XCTAssertEqual(model.body, "前缀"); XCTAssertEqual(try store.listNotes().first?.body, "前缀")
        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(view.string, "前缀zhongwen")
        view.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 800_000_000)
        view.loadDraft(model.body, revision: model.draftRevision)
        XCTAssertEqual(model.body, "前缀中文"); XCTAssertEqual(view.string, "前缀中文")
        XCTAssertEqual(try store.listNotes().first?.body, "前缀中文")
    }

    @MainActor func testExplicitSaveCommitsPendingInputBeforePersistence() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EventStore(path: directory.appendingPathComponent("events.db"))
        let model = NotebookModel(store: store)
        let view = textView()
        view.onCommittedChange = { model.body = $0 }
        model.prepareToSave = { view.commitPendingInput() }
        defer { model.prepareToSave = nil; view.onCommittedChange = nil }
        view.setMarkedText("尚未确认", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(model.body, "")
        XCTAssertTrue(model.flush())
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(try store.listNotes().first?.body, "尚未确认")
    }

    @MainActor func testTitleCompositionAndDraftSwitchOnlyResetOnNewRevision() async {
        let view = textView("标题")
        view.singleLine = true
        var updates: [String] = []
        view.onCommittedChange = { updates.append($0) }
        view.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.loadDraft("标题", revision: 0)
        XCTAssertTrue(view.hasMarkedText()); XCTAssertEqual(view.string, "标题ceshi")
        view.insertText("测试", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(updates, ["标题测试"])
        view.loadDraft("另一条便笺", revision: 1)
        XCTAssertEqual(view.string, "另一条便笺"); XCTAssertEqual(updates, ["标题测试"])
        view.insertText("\n换行", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.string, "另一条便笺 换行")
    }
}
