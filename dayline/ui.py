"""GTK editor window, event form and application wiring."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from .desktop import DesktopWidget
from .reminders import ReminderService
from .storage import Event, EventStore
from .timeline import TimelineCanvas


CSS = b"""
window { background: #f8f8f2; color: #202b27; }
.main-window .titlebar { background: #fbfbfe; }
.sidebar { background: #edf1e9; border-right: 1px solid #d8dfd4; }
.brand { font-size: 21px; font-weight: 800; color: #1d5145; }
.section-title { font-size: 13px; font-weight: 700; color: #62677b; }
.date-title { font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
.stat { font-size: 13px; color: #656a7c; }
.timeline { background: #ffffff; border-radius: 16px; margin: 12px 22px 24px 8px; }
.timeline-grid { background: #ffffff; }
.timeline-hour-label { color: #9297a6; font-size: 12px; }
.timeline-hour-line { background: #e1e5e6; min-height: 1px; }
.timeline-half-line { background: #f0f1f3; min-height: 1px; }
.timeline-gutter-line { background: #e1e5e6; min-width: 1px; }
.timeline-now-line { background: #e55672; min-height: 2px; }
.timeline-now-dot { color: #e55672; font-size: 12px; }
.event-card { background: #e4f1ec; border-left: 4px solid #28735f; border-radius: 9px; padding: 3px 6px; margin: 0 8px 0 0; }
.event-card button { min-width: 24px; min-height: 24px; padding: 0; }
.event-card.done { opacity: .55; background: #eff1f3; border-left-color: #8e98a5; }
.event-name { font-weight: 700; font-size: 13px; }
.event-detail, .muted { color: #707587; font-size: 11px; }
.now-line { color: #e55672; font-size: 12px; font-weight: 700; }
.eyebrow { font-size: 12px; font-weight: 800; color: #28735f; text-transform: uppercase; }
.reminder-title { font-size: 23px; font-weight: 800; }
.desktop-widget { background: #183d35; color: #f8f8f2; border-radius: 20px; box-shadow: 0 12px 30px rgba(15,35,30,.35); }
.desktop-brand { font-size: 20px; font-weight: 800; color: #ffffff; }
.desktop-date { color: #bfc2d3; font-size: 12px; }
.desktop-subtitle { color: #aeb2ca; font-size: 12px; }
.desktop-time { color: #9bdfc6; font-weight: 800; min-width: 42px; }
.desktop-event { color: #ffffff; font-weight: 700; }
.desktop-event-detail { color: #b8bbca; font-size: 12px; }
.desktop-new { background: #28735f; color: white; }
.notice { background: #fff7db; color: #6d5716; border-radius: 8px; padding: 8px; }
button.suggested-action, button.suggested-action:hover { background: #28735f; color: #ffffff; }
calendar { background: #f9faf5; color: #26352f; border-radius: 10px; padding: 6px; }
calendar:selected { background: #28735f; color: #ffffff; border-radius: 999px; }
calendar.highlight { color: #28735f; font-weight: 800; }
"""

WEEKDAYS = "一二三四五六日"


def load_css() -> None:
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_display(Gtk.Widget.get_display(Gtk.Window()), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


class EventDialog(Gtk.Dialog):
    def __init__(self, parent: Gtk.Window, store: EventStore, event: Event | None, saved, selected_day: date | None = None):
        super().__init__(title="编辑事件" if event else "新建事件", transient_for=parent, modal=True)
        self.store, self.event, self.saved = store, event, saved
        self.set_default_size(480, -1)
        self.add_button("取消", Gtk.ResponseType.CANCEL)
        self.add_button("保存事件", Gtk.ResponseType.OK).add_css_class("suggested-action")
        content = self.get_content_area()
        content.set_spacing(10); content.set_margin_top(16); content.set_margin_bottom(16); content.set_margin_start(20); content.set_margin_end(20)
        form = Gtk.Grid(column_spacing=12, row_spacing=11)
        content.append(form)
        now = datetime.now().replace(second=0, microsecond=0)
        if selected_day and selected_day != now.date():
            default_start = datetime.combine(selected_day, time(9, 0))
        else:
            default_start = (now + timedelta(minutes=30)).replace(minute=(now.minute // 30) * 30)
            if default_start <= now: default_start += timedelta(minutes=30)
        start = event.starts_at if event else default_start
        end = event.ends_at if event else start + timedelta(hours=1)
        self.title_entry = Gtk.Entry(text=event.title if event else "", hexpand=True)
        self.start_entry = Gtk.Entry(text=start.strftime("%Y-%m-%d %H:%M"), hexpand=True)
        self.end_entry = Gtk.Entry(text=end.strftime("%Y-%m-%d %H:%M"), hexpand=True)
        self.notes_entry = Gtk.Entry(text=event.notes if event else "", hexpand=True)
        fields = [("事件名称", self.title_entry), ("开始时间", self.start_entry), ("结束时间", self.end_entry), ("备注（可选）", self.notes_entry)]
        for row, (label, widget) in enumerate(fields):
            form.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1); form.attach(widget, 1, row, 1, 1)
        helper = Gtk.Label(label="时间格式：2026-09-07 14:30。新建过去事件会保留在日程中，但不会补发提醒。", wrap=True, xalign=0)
        helper.add_css_class("muted"); form.attach(helper, 0, 4, 2, 1)
        self.error = Gtk.Label(xalign=0, wrap=True)
        self.error.add_css_class("notice"); self.error.set_visible(False); content.append(self.error)
        self.connect("response", self._respond)
        self.title_entry.grab_focus()

    def _respond(self, _dialog, response):
        if response != Gtk.ResponseType.OK:
            self.close(); return
        try:
            start = datetime.strptime(self.start_entry.get_text().strip(), "%Y-%m-%d %H:%M")
            end = datetime.strptime(self.end_entry.get_text().strip(), "%Y-%m-%d %H:%M")
        except ValueError:
            self.error.set_text("时间格式不正确，请使用 YYYY-MM-DD HH:MM，例如 2026-09-07 14:30。")
            self.error.set_visible(True)
            return
        try:
            if self.event:
                self.store.update_event(self.event.id, self.title_entry.get_text(), start, end, self.notes_entry.get_text())
            else:
                self.store.add_event(self.title_entry.get_text(), start, end, self.notes_entry.get_text())
        except ValueError as error:
            self.error.set_text(str(error) if str(error) else "请检查事件内容。")
            self.error.set_visible(True)
            return
        self.saved(); self.close()


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, app, store: EventStore, desktop: DesktopWidget):
        super().__init__(application=app, title="时序 · Dayline")
        self.store, self.desktop, self.selected_day = store, desktop, date.today()
        self.set_default_size(1060, 720)
        self.set_size_request(780, 560)
        self.add_css_class("main-window")
        self.connect("close-request", self._hide)
        self._build()
        self.refresh()

    def _build(self):
        shell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(shell)
        titlebar = Adw.HeaderBar()
        titlebar.set_show_end_title_buttons(True)
        minimize = Gtk.Button(label="收起到桌面", tooltip_text="关闭编辑窗口，保留桌面日程与提醒")
        minimize.connect("clicked", lambda *_: self._hide())
        titlebar.pack_end(minimize)
        shell.append(titlebar)
        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        outer.set_vexpand(True)
        shell.append(outer)
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin_top=24, margin_bottom=18, margin_start=18, margin_end=18)
        sidebar.add_css_class("sidebar"); sidebar.set_size_request(244, -1); outer.append(sidebar)
        brand = Gtk.Label(label="时序 · Dayline", xalign=0)
        brand.add_css_class("brand"); sidebar.append(brand)
        today = Gtk.Button(label="今天")
        today.connect("clicked", lambda *_: self.goto_day(date.today()))
        sidebar.append(today)
        self.calendar = Gtk.Calendar()
        self.calendar.connect("day-selected", self._calendar_selected)
        sidebar.append(self.calendar)
        side_title = Gtk.Label(label="下一项安排", xalign=0, margin_top=10)
        side_title.add_css_class("section-title"); sidebar.append(side_title)
        self.upcoming_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
        sidebar.append(self.upcoming_box)
        spacer = Gtk.Box(vexpand=True); sidebar.append(spacer)
        desktop_note = Gtk.Label(label="关闭窗口后，日程仍会留在桌面。", wrap=True, xalign=0)
        desktop_note.add_css_class("muted"); sidebar.append(desktop_note)
        quit_button = Gtk.Button(label="退出时序")
        quit_button.connect("clicked", lambda *_: self.get_application().quit())
        sidebar.append(quit_button)
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True); outer.append(body)
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, margin_top=22, margin_start=20, margin_end=26, margin_bottom=6)
        previous = Gtk.Button(icon_name="go-previous-symbolic"); previous.connect("clicked", lambda *_: self.goto_day(self.selected_day - timedelta(days=1)))
        next_button = Gtk.Button(icon_name="go-next-symbolic"); next_button.connect("clicked", lambda *_: self.goto_day(self.selected_day + timedelta(days=1)))
        now_button = Gtk.Button(label="现在"); now_button.connect("clicked", lambda *_: self.goto_day(date.today(), scroll_to_now=True))
        self.date_label = Gtk.Label(xalign=0, hexpand=True); self.date_label.add_css_class("date-title")
        self.stats_label = Gtk.Label(xalign=1); self.stats_label.add_css_class("stat")
        add = Gtk.Button(label="＋ 新建事件"); add.add_css_class("suggested-action"); add.connect("clicked", lambda *_: self.open_event_dialog())
        header.append(previous); header.append(next_button); header.append(now_button); header.append(self.date_label); header.append(self.stats_label); header.append(add); body.append(header)
        self.timeline = TimelineCanvas(self._event_card)
        self.timeline.add_css_class("timeline")
        self.scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.scroll.set_child(self.timeline); body.append(self.scroll)

    def _hide(self, *_):
        self.set_visible(False)
        self.desktop.present()
        return True

    def _calendar_selected(self, calendar):
        if getattr(self, "_syncing_calendar", False):
            return
        try:
            selected = calendar.get_date()
            self.goto_day(date(selected.get_year(), selected.get_month(), selected.get_day_of_month()))
        except Exception:
            pass

    def goto_day(self, day: date, scroll_to_now: bool = False):
        self.selected_day = day
        self._syncing_calendar = True
        try:
            self.calendar.select_day(GLib.DateTime.new_local(day.year, day.month, day.day, 0, 0, 0))
        finally:
            self._syncing_calendar = False
        self.refresh()
        if scroll_to_now:
            GLib.idle_add(self._scroll_to_now)

    def _scroll_to_now(self):
        adjustment = self.scroll.get_vadjustment()
        viewport_height = adjustment.get_page_size()
        now_minutes = datetime.now().hour * 60 + datetime.now().minute
        target = now_minutes - viewport_height / 3
        maximum = max(0, adjustment.get_upper() - viewport_height)
        adjustment.set_value(min(maximum, max(0, target)))
        return False

    def open_event_dialog(self, event: Event | None = None):
        dialog = EventDialog(self, self.store, event, self.refresh, self.selected_day)
        dialog.present()

    def refresh(self, *_):
        self.date_label.set_text(f"{self.selected_day:%Y年%m月%d日}  星期{WEEKDAYS[self.selected_day.weekday()]}")
        events = self.store.events_for_day(self.selected_day)
        active = sum(not event.completed for event in events)
        self.stats_label.set_text(f"{active} 项待办 · {len(events)} 个事件")
        self._rebuild_sidebar()
        self._rebuild_timeline(events)
        self.desktop.refresh()

    def _rebuild_sidebar(self):
        child = self.upcoming_box.get_first_child()
        while child:
            following = child.get_next_sibling(); self.upcoming_box.remove(child); child = following
        for event in self.store.upcoming(3):
            row = Gtk.Label(label=f"{event.starts_at:%m/%d %H:%M}  {event.title}", xalign=0, ellipsize=3)
            row.add_css_class("muted"); self.upcoming_box.append(row)

    def _rebuild_timeline(self, events: list[Event]):
        self.timeline.set_events(events, self.selected_day)

    def _event_card(self, event: Event, duration: int | None = None) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        card.add_css_class("event-card")
        if event.completed: card.add_css_class("done")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
        title = Gtk.Label(label=event.title, xalign=0, ellipsize=3); title.add_css_class("event-name")
        start = f"昨日 {event.starts_at:%H:%M}" if event.starts_at.date() < self.selected_day else event.starts_at.strftime("%H:%M")
        end = f"次日 {event.ends_at:%H:%M}" if event.ends_at.date() > self.selected_day else event.ends_at.strftime("%H:%M")
        details = Gtk.Label(label=f"{start} — {end}" + (f"  ·  {event.notes}" if event.notes else ""), xalign=0, ellipsize=3)
        details.add_css_class("event-detail"); text.append(title); text.append(details); card.append(text)
        if duration is not None and duration < 45:
            title.set_text(f"{event.title} · {start}")
            details.set_visible(False)
        done = Gtk.Button(icon_name="object-select-symbolic", tooltip_text="标记完成")
        done.connect("clicked", lambda *_: self._complete(event.id)); card.append(done)
        edit = Gtk.Button(icon_name="document-edit-symbolic", tooltip_text="编辑")
        edit.connect("clicked", lambda *_: self.open_event_dialog(event)); card.append(edit)
        delete = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="删除")
        delete.connect("clicked", lambda *_: self._delete(event.id)); card.append(delete)
        return card

    def _complete(self, event_id):
        self.store.set_completed(event_id); self.refresh()

    def _delete(self, event_id):
        self.store.delete(event_id); self.refresh()


class DaylineApplication(Adw.Application):
    def __init__(self):
        super().__init__(application_id="io.github.dayline.Calendar", flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.store: EventStore | None = None
        self.desktop: DesktopWidget | None = None
        self.main_window: MainWindow | None = None
        self.reminders: ReminderService | None = None
        self.hold()
        self.connect("shutdown", self._shutdown)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        css = Gtk.CssProvider(); css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.store = EventStore()
        self.desktop = DesktopWidget(self, self.store, self.show_editor, self.new_event, self.quit)
        self.main_window = MainWindow(self, self.store, self.desktop)
        self.reminders = ReminderService(self, self.store, self.refresh_all)
        GLib.idle_add(self._initial_reminder_check)

    def _initial_reminder_check(self):
        self.reminders.check()
        return False

    def do_activate(self):
        self.show_editor()

    def do_command_line(self, command_line):
        args = command_line.get_arguments()[1:]
        if "--quit" in args:
            self.quit(); return 0
        if "--desktop" in args:
            self.show_desktop(); return 0
        self.activate(); return 0

    def show_editor(self):
        self.main_window.present()
        self.main_window.refresh()
        if not getattr(self, "_initial_editor_positioned", False):
            self._initial_editor_positioned = True
            GLib.idle_add(self.main_window._scroll_to_now)

    def show_desktop(self):
        self.desktop.present()
        self.desktop.refresh()

    def new_event(self):
        self.show_editor()
        self.main_window.open_event_dialog()

    def refresh_all(self):
        if self.main_window: self.main_window.refresh()
        elif self.desktop: self.desktop.refresh()

    def _shutdown(self, *_):
        if self.reminders: self.reminders.stop()
        if self.store: self.store.close()
