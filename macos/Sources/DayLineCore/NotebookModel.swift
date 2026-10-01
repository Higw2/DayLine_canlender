import Foundation
import Combine

/// Keeps the draft alive across page switches and saves before changing selection.
@MainActor
public final class NotebookModel: ObservableObject {
    private let store: EventStore
    private var pendingSave: Task<Void, Never>?
    private var loading = false
    private var savedTitle = ""
    private var savedBody = ""
    /// UI adapter commits marked text for explicit save/navigation/quit only.
    /// Autosave must never interrupt an active input-method composition.
    public var prepareToSave: (() -> Void)?
    @Published public private(set) var draftRevision: UInt64 = 0
    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var selectedID: Int64?
    @Published public var title = "" { didSet { changed() } }
    @Published public var body = "" { didSet { changed() } }
    @Published public private(set) var status = "开始输入，内容会自动保存"
    @Published public var errorMessage: String?

    public init(store: EventStore) { self.store = store; refresh() }

    private func refresh() {
        do { notes = try store.listNotes() }
        catch { errorMessage = error.localizedDescription }
    }

    private func changed() {
        guard !loading else { return }
        pendingSave?.cancel()
        status = "正在输入…"
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush(commitInput: false)
        }
    }

    @discardableResult public func flush(now: Date = Date(), commitInput: Bool = true) -> Bool {
        if commitInput { prepareToSave?() }
        pendingSave?.cancel(); pendingSave = nil
        guard title != savedTitle || body != savedBody else { return true }
        if selectedID == nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = "开始输入，内容会自动保存"
            return true
        }
        do {
            let note: Note
            if let id = selectedID { note = try store.updateNote(id, body: body, title: title, now: now) }
            else { note = try store.addNote(body: body, title: title, now: now) }
            selectedID = note.id; savedTitle = title; savedBody = body
            status = "已保存"; errorMessage = nil; refresh()
            return true
        } catch {
            status = "保存失败，内容仍保留在编辑器中"
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult public func newNote() -> Bool {
        guard flush() else { return false }
        load(nil); return true
    }

    public func select(_ id: Int64) {
        guard selectedID != id, flush() else { return }
        do {
            guard let note = try store.getNote(id) else { throw DayLineError.sqlite("便笺不存在") }
            load(note)
        } catch { errorMessage = error.localizedDescription }
    }

    private func load(_ note: Note?) {
        loading = true
        selectedID = note?.id; title = note.map { $0.autoTitle ? "" : $0.title } ?? ""; body = note?.body ?? ""
        savedTitle = title; savedBody = body; loading = false
        draftRevision &+= 1
        status = note == nil ? "开始输入，内容会自动保存" : "已保存"
    }

    public func deleteSelected() {
        guard let id = selectedID else { return }
        pendingSave?.cancel(); pendingSave = nil
        do { try store.deleteNote(id); load(nil); status = "便笺已删除"; refresh() }
        catch { status = "删除失败"; errorMessage = error.localizedDescription }
    }
}
