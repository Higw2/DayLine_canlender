"""Plain-text notes page for quick thoughts outside the calendar."""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk

from .storage import EventStore


class NotesPage(Gtk.Box):
    def __init__(self, store: EventStore):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.store = store
        self.selected_note_id: int | None = None
        self._save_source_id = 0
        self._loading = False
        self._updating_rows = False
        self._saved_contents = ("", "")
        self._last_width = -1
        self.add_css_class("notes-page")

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        title = Gtk.Label(label="随手记", xalign=0, hexpand=True)
        title.add_css_class("date-title")
        self.count_label = Gtk.Label(xalign=1)
        self.count_label.add_css_class("muted")
        new_button = Gtk.Button(label="＋ 新建便笺")
        new_button.add_css_class("suggested-action")
        new_button.connect("clicked", lambda *_: self.new_note())
        header.append(title)
        header.append(self.count_label)
        header.append(new_button)
        self.append(header)
        self.header = header
        self.new_button = new_button

        self.paned = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL, hexpand=True, vexpand=True)
        self.paned.set_position(145)
        self.append(self.paned)
        self.add_tick_callback(self._layout_tick)

        list_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        list_panel.add_css_class("notes-list-panel")
        list_panel.set_size_request(170, 80)
        list_heading = Gtk.Label(label="我的便笺", xalign=0)
        list_heading.add_css_class("section-title")
        list_panel.append(list_heading)
        self.note_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.note_list.add_css_class("notes-list")
        self.note_list.connect("row-selected", self._row_selected)
        empty = Gtk.Label(label="还没有便笺\n点击“新建便笺”写下第一条", wrap=True, justify=Gtk.Justification.CENTER)
        empty.add_css_class("muted")
        empty.set_margin_top(28)
        self.note_list.set_placeholder(empty)
        list_scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        list_scroll.set_child(self.note_list)
        list_panel.append(list_scroll)
        self.paned.set_start_child(list_panel)

        editor = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        editor.add_css_class("notes-editor")
        editor.set_size_request(190, 120)
        self.title_entry = Gtk.Entry(hexpand=True, placeholder_text="标题（可选）")
        self.title_entry.set_max_length(120)
        self.title_entry.connect("changed", self._changed)
        editor.append(self.title_entry)

        body_scroll = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
        body_scroll.add_css_class("notes-body")
        self.body_view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR)
        self.body_view.set_top_margin(14)
        self.body_view.set_bottom_margin(14)
        self.body_view.set_left_margin(16)
        self.body_view.set_right_margin(16)
        self.body_view.get_buffer().connect("changed", self._changed)
        body_scroll.set_child(self.body_view)
        editor.append(body_scroll)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.status_label = Gtk.Label(label="开始输入，内容会自动保存", xalign=0, hexpand=True)
        self.status_label.add_css_class("muted")
        self.delete_button = Gtk.Button(label="删除便笺")
        self.delete_button.add_css_class("flat")
        self.delete_button.set_sensitive(False)
        self.delete_button.connect("clicked", self._confirm_delete)
        save_button = Gtk.Button(label="保存")
        save_button.connect("clicked", lambda *_: self.flush())
        actions.append(self.status_label)
        actions.append(self.delete_button)
        actions.append(save_button)
        editor.append(actions)
        self.paned.set_end_child(editor)

        self.refresh_list()

    def _layout_tick(self, _widget, _frame_clock) -> bool:
        width = self.get_width()
        if width > 0 and width != self._last_width:
            self._last_width = width
            self._adapt_layout()
        return True

    def _adapt_layout(self) -> None:
        vertical = self.get_width() < 620
        orientation = Gtk.Orientation.VERTICAL if vertical else Gtk.Orientation.HORIZONTAL
        self.header.set_orientation(Gtk.Orientation.VERTICAL if self.get_width() < 420 else Gtk.Orientation.HORIZONTAL)
        self.new_button.set_halign(Gtk.Align.START if self.get_width() < 420 else Gtk.Align.FILL)
        if self.paned.get_orientation() != orientation:
            self.paned.set_orientation(orientation)
            self.paned.set_position(145 if vertical else 235)

    def _contents(self) -> tuple[str, str]:
        buffer = self.body_view.get_buffer()
        return self.title_entry.get_text(), buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), True)

    def _changed(self, *_args) -> None:
        if self._loading:
            return
        self.status_label.set_text("正在输入…")
        if self._save_source_id:
            GLib.source_remove(self._save_source_id)
        self._save_source_id = GLib.timeout_add(600, self._save_later)

    def _save_later(self) -> bool:
        self._save_source_id = 0
        self.flush()
        return False

    def flush(self) -> None:
        if self._save_source_id:
            GLib.source_remove(self._save_source_id)
            self._save_source_id = 0
        title, body = self._contents()
        if (title, body) == self._saved_contents:
            return
        if self.selected_note_id is None and not title.strip() and not body.strip():
            self.status_label.set_text("开始输入，内容会自动保存")
            return
        if self.selected_note_id is None:
            note = self.store.add_note(body, title)
            self.selected_note_id = note.id
            self.delete_button.set_sensitive(True)
        else:
            self.store.update_note(self.selected_note_id, body, title)
        self._saved_contents = (title, body)
        self.status_label.set_text("已自动保存")
        self.refresh_list()

    def refresh_list(self) -> None:
        notes = self.store.list_notes()
        self.count_label.set_text(f"{len(notes)} 条便笺")
        self._updating_rows = True
        child = self.note_list.get_first_child()
        while child:
            following = child.get_next_sibling()
            self.note_list.remove(child)
            child = following
        selected_row = None
        for note in notes:
            row = Gtk.ListBoxRow()
            row.note_id = note.id
            row.add_css_class("notes-row")
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            heading = Gtk.Label(label=note.title, xalign=0, ellipsize=3)
            heading.add_css_class("notes-row-title")
            preview = " ".join(note.body.split()) or "空白便笺"
            snippet = Gtk.Label(label=preview, xalign=0, ellipsize=3)
            snippet.add_css_class("notes-row-preview")
            modified = Gtk.Label(label=note.updated_at.strftime("%m/%d %H:%M"), xalign=0)
            modified.add_css_class("notes-row-date")
            content.append(heading)
            content.append(snippet)
            content.append(modified)
            row.set_child(content)
            self.note_list.append(row)
            if note.id == self.selected_note_id:
                selected_row = row
        if selected_row:
            self.note_list.select_row(selected_row)
        self._updating_rows = False

    def _row_selected(self, _list, row) -> None:
        if self._updating_rows or row is None or row.note_id == self.selected_note_id:
            return
        target_id = row.note_id
        self.flush()
        note = self.store.get_note(target_id)
        self.selected_note_id = note.id
        self._loading = True
        self.title_entry.set_text("" if note.auto_title else note.title)
        self.body_view.get_buffer().set_text(note.body)
        self._loading = False
        self._saved_contents = self._contents()
        self.delete_button.set_sensitive(True)
        self.status_label.set_text(f"已保存 · {note.updated_at:%m/%d %H:%M}")
        self.refresh_list()

    def new_note(self) -> None:
        self.flush()
        self.selected_note_id = None
        self._loading = True
        self.title_entry.set_text("")
        self.body_view.get_buffer().set_text("")
        self._loading = False
        self._saved_contents = ("", "")
        self._updating_rows = True
        self.note_list.unselect_all()
        self._updating_rows = False
        self.delete_button.set_sensitive(False)
        self.status_label.set_text("开始输入，内容会自动保存")
        self.body_view.grab_focus()

    def _confirm_delete(self, *_args) -> None:
        dialog = Adw.MessageDialog.new(self.get_root(), "删除这条便笺？", "删除后无法恢复。")
        dialog.add_response("cancel", "取消")
        dialog.add_response("delete", "删除")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.connect("response", self._delete_response)
        dialog.present()

    def _delete_response(self, _dialog, response: str) -> None:
        if response != "delete" or self.selected_note_id is None:
            return
        self.store.delete_note(self.selected_note_id)
        self.selected_note_id = None
        self._loading = True
        self.title_entry.set_text("")
        self.body_view.get_buffer().set_text("")
        self._loading = False
        self._saved_contents = ("", "")
        self.delete_button.set_sensitive(False)
        self.status_label.set_text("便笺已删除")
        self.refresh_list()
