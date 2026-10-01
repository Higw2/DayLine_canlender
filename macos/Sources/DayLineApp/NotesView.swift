import SwiftUI
import DayLineCore
import DayLineTextInput

struct NotesView: View {
    @ObservedObject var notebook: NotebookModel
    let settings: AppSettings
    @State private var confirmingDelete = false
    @State private var bodyFocusRequest: UInt64 = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("随手记", systemImage: "note.text").font(.title3.bold())
                Spacer()
                Text("\(notebook.notes.count) 条便笺").foregroundStyle(.secondary)
                Button {
                    if notebook.newNote() { bodyFocusRequest &+= 1 }
                } label: { Label("新建便笺", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            GeometryReader { geometry in
                if geometry.size.width >= 620 {
                    HSplitView {
                        noteList.frame(minWidth: 170, idealWidth: 235, maxWidth: 350)
                        editor.frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VSplitView {
                        noteList.frame(minHeight: 80, idealHeight: 145, maxHeight: 220)
                        editor.frame(minHeight: 180, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .tint(Color(hex: settings.themeColor))
        .font(.system(size: 13 * settings.fontScale))
        .confirmationDialog("删除这条便笺？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除便笺", role: .destructive) { notebook.deleteSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除“\(notebook.notes.first { $0.id == notebook.selectedID }?.title ?? "便笺")”吗？删除后无法恢复。")
        }
        .alert("便笺保存", isPresented: Binding(get: { notebook.errorMessage != nil }, set: { if !$0 { notebook.errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(notebook.errorMessage ?? "") }
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的便笺").font(.headline).padding(.horizontal, 12).padding(.top, 12)
            if notebook.notes.isEmpty {
                Spacer()
                Text("还没有便笺\n点击“新建便笺”或直接在编辑器输入")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(notebook.notes) { note in
                            Button { notebook.select(note.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title).font(.headline).lineLimit(1)
                                    Text(note.body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").isEmpty ? "空白便笺" : note.body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
                                        .lineLimit(2).foregroundStyle(.secondary)
                                    Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(notebook.selectedID == note.id ? Color(hex: settings.themeColor).opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("打开便笺：\(note.title)")
                        }
                    }.padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(spacing: 10) {
            NoteTextInput(text: $notebook.title, revision: notebook.draftRevision, fontSize: 13 * settings.fontScale, singleLine: true, label: "便笺标题（可选）")
                .frame(height: 28 * settings.fontScale)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            NoteTextInput(text: $notebook.body, revision: notebook.draftRevision, fontSize: 14 * settings.fontScale, label: "便笺正文", focusRequest: bodyFocusRequest)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
            ViewThatFits(in: .horizontal) {
                HStack { Text(notebook.status).foregroundStyle(.secondary); Spacer(); editorActions }
                VStack(alignment: .leading, spacing: 6) {
                    Text(notebook.status).foregroundStyle(.secondary)
                    HStack { Spacer(); editorActions }
                }
            }
        }.padding(12)
    }

    private var editorActions: some View {
        HStack {
            Button("删除便笺", role: .destructive) { confirmingDelete = true }
                .disabled(notebook.selectedID == nil)
            Button("保存") { notebook.flush() }.keyboardShortcut("s", modifiers: .command)
        }
    }
}
