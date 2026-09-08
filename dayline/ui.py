"""GTK editor window, event form and application wiring."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from .desktop import DesktopWidget
from .reminders import ReminderService
from .settings import AppSettings, get_settings_manager
from .settings_dialog import open_settings_dialog
from .storage import Event, EventStore
from .theme import apply_theme, generate_css
from .timeline import TimelineCanvas


CSS = generate_css(AppSettings()).encode("utf-8")
WEEKDAYS = "一二三四五六日"


def load_css() -> None:
    apply_theme(get_settings_manager().current)


class EventDialog(Gtk.Dialog):
    def __init__(
        self,
        parent: Gtk.Window,
        store: EventStore,
        event: Event | None,
        saved,
        selected_day: date | None = None,
        initial_start: datetime | None = None,
        initial_end: datetime | None = None,
    ):
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
        start = event.starts_at if event else initial_start or default_start
        end = event.ends_at if event else initial_end or start + timedelta(hours=1)
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
        super().__init__(application=app, title="DayLine")
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

        settings_btn = Gtk.Button(icon_name="preferences-system-symbolic", tooltip_text="设置（自定义颜色与字体大小）")
        settings_btn.add_css_class("flat")
        settings_btn.connect("clicked", lambda *_: self.get_application().open_settings())
        titlebar.pack_end(settings_btn)

        minimize = Gtk.Button(label="收起到桌面", tooltip_text="关闭编辑窗口，保留桌面日程与提醒")
        minimize.add_css_class("flat")
        minimize.connect("clicked", lambda *_: self._hide())
        titlebar.pack_end(minimize)
        shell.append(titlebar)

        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        outer.set_vexpand(True)
        shell.append(outer)

        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin_top=20, margin_bottom=18, margin_start=16, margin_end=16)
        sidebar.add_css_class("sidebar")
        sidebar.set_size_request(248, -1)
        outer.append(sidebar)

        brand_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, valign=Gtk.Align.CENTER)
        brand_icon = Gtk.Image(icon_name="x-office-calendar-symbolic")
        brand = Gtk.Label(label="时序 · Dayline", xalign=0)
        brand = Gtk.Label(label="DayLine", xalign=0)
        brand.add_css_class("brand")
        brand_box.append(brand_icon)
        brand_box.append(brand)
        sidebar.append(brand_box)

        today = Gtk.Button(label="返回今天")
        today.add_css_class("sidebar-today-btn")
        today.connect("clicked", lambda *_: self.goto_day(date.today()))
        sidebar.append(today)

        self.calendar = Gtk.Calendar()
        self.calendar.connect("day-selected", self._calendar_selected)
        sidebar.append(self.calendar)

        side_title = Gtk.Label(label="下一项安排", xalign=0, margin_top=8)
        side_title.add_css_class("section-title")
        sidebar.append(side_title)

        self.upcoming_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        sidebar.append(self.upcoming_box)

        spacer = Gtk.Box(vexpand=True)
        sidebar.append(spacer)

        desktop_note = Gtk.Label(label="关闭窗口后，日程仍会留在桌面。", wrap=True, xalign=0)
        desktop_note.add_css_class("muted")
        sidebar.append(desktop_note)

        quit_button = Gtk.Button(label="退出时序")
        quit_button = Gtk.Button(label="退出 DayLine")
        quit_button.add_css_class("flat")
        quit_button.connect("clicked", lambda *_: self.get_application().quit())
        sidebar.append(quit_button)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        outer.append(body)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10, margin_top=18, margin_start=20, margin_end=24, margin_bottom=6)
        nav_group = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        nav_group.add_css_class("linked")
        previous = Gtk.Button(icon_name="go-previous-symbolic", tooltip_text="前一天")
        previous.connect("clicked", lambda *_: self.goto_day(self.selected_day - timedelta(days=1)))
        next_button = Gtk.Button(icon_name="go-next-symbolic", tooltip_text="后一天")
        next_button.connect("clicked", lambda *_: self.goto_day(self.selected_day + timedelta(days=1)))
        now_button = Gtk.Button(label="回到现在", tooltip_text="定位到今日当前时刻")
        now_button.connect("clicked", lambda *_: self.goto_day(date.today(), scroll_to_now=True))
        nav_group.append(previous)
        nav_group.append(next_button)
        nav_group.append(now_button)
        header.append(nav_group)

        self.date_label = Gtk.Label(xalign=0, hexpand=True)
        self.date_label.add_css_class("date-title")
        self.stats_label = Gtk.Label(xalign=1)
        self.stats_label.add_css_class("stat")
        add = Gtk.Button(label="＋ 新建事件")
        add.add_css_class("suggested-action")
        add.connect("clicked", lambda *_: self.open_event_dialog())

        header.append(self.date_label)
        header.append(self.stats_label)
        header.append(add)
        body.append(header)

        self.timeline = TimelineCanvas(self._event_card, self._create_event_from_range)
        self.timeline.add_css_class("timeline")
        self.scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        self.scroll.set_child(self.timeline)
        body.append(self.scroll)

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

    def open_event_dialog(
        self,
        event: Event | None = None,
        initial_start: datetime | None = None,
        initial_end: datetime | None = None,
    ):
        dialog = EventDialog(
            self,
            self.store,
            event,
            self.refresh,
            self.selected_day,
            initial_start,
            initial_end,
        )
        dialog.present()

    def _create_event_from_range(self, start_minute: int, end_minute: int) -> None:
        day_start = datetime.combine(self.selected_day, time.min)
        self.open_event_dialog(
            initial_start=day_start + timedelta(minutes=start_minute),
            initial_end=day_start + timedelta(minutes=end_minute),
        )

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
            following = child.get_next_sibling()
            self.upcoming_box.remove(child)
            child = following
        upcoming = self.store.upcoming(3)
        if upcoming:
            for event in upcoming:
                card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                card.add_css_class("upcoming-mini-card")
                time_lbl = Gtk.Label(label=f"{event.starts_at:%m/%d %H:%M}", xalign=0)
                time_lbl.add_css_class("upcoming-mini-time")
                title_lbl = Gtk.Label(label=event.title, xalign=0, ellipsize=3)
                title_lbl.add_css_class("upcoming-mini-title")
                card.append(time_lbl)
                card.append(title_lbl)
                self.upcoming_box.append(card)
        else:
            empty_lbl = Gtk.Label(label="暂无近期待办", xalign=0)
            empty_lbl.add_css_class("muted")
            self.upcoming_box.append(empty_lbl)

    def _rebuild_timeline(self, events: list[Event]):
        self.timeline.set_events(events, self.selected_day)

    def _event_card(self, event: Event, duration: int | None = None) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        card.add_css_class("event-card")
        if event.completed:
            card.add_css_class("done")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
        title = Gtk.Label(label=event.title, xalign=0, ellipsize=3)
        title.add_css_class("event-name")
        start = f"昨日 {event.starts_at:%H:%M}" if event.starts_at.date() < self.selected_day else event.starts_at.strftime("%H:%M")
        end = f"次日 {event.ends_at:%H:%M}" if event.ends_at.date() > self.selected_day else event.ends_at.strftime("%H:%M")
        details = Gtk.Label(label=f"{start} — {end}" + (f"  ·  {event.notes}" if event.notes else ""), xalign=0, ellipsize=3)
        details.add_css_class("event-detail")
        text.append(title)
        text.append(details)
        card.append(text)
        if duration is not None and duration < 45:
            title.set_text(f"{event.title} · {start}")
            details.set_visible(False)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2, valign=Gtk.Align.CENTER)
        done = Gtk.Button(icon_name="object-select-symbolic", tooltip_text="标记完成")
        done.add_css_class("flat")
        done.connect("clicked", lambda *_: self._complete(event.id))
        actions.append(done)
        edit = Gtk.Button(icon_name="document-edit-symbolic", tooltip_text="编辑")
        edit.add_css_class("flat")
        edit.connect("clicked", lambda *_: self.open_event_dialog(event))
        actions.append(edit)
        delete = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="删除")
        delete.add_css_class("flat")
        delete.connect("clicked", lambda *_: self._delete(event.id))
        actions.append(delete)
        card.append(actions)
        return card

    def _complete(self, event_id):
        self.store.set_completed(event_id)
        self.refresh()

    def _delete(self, event_id):
        self.store.delete(event_id)
        self.refresh()


class DaylineApplication(Adw.Application):
    def __init__(self):
        super().__init__(application_id="io.github.dayline.Calendar", flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.store: EventStore | None = None
        self.desktop: DesktopWidget | None = None
        self.main_window: MainWindow | None = None
        self.reminders: ReminderService | None = None
        self.settings_manager = None
        self.hold()
        self.connect("shutdown", self._shutdown)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_LIGHT)
        self.settings_manager = get_settings_manager()
        self.settings_manager.add_listener(self._on_settings_changed)
        apply_theme(self.settings_manager.current)
        self.store = EventStore()
        self.desktop = DesktopWidget(
            self,
            self.store,
            self.show_editor,
            self.new_event,
            self.quit,
            open_settings=self.open_settings,
        )
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
            self.quit()
            return 0
        if "--desktop" in args:
            self.show_desktop()
            return 0
        self.activate()
        return 0

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

    def open_settings(self):
        parent = self.main_window if self.main_window and self.main_window.get_visible() else None
        open_settings_dialog(parent=parent)

    def _on_settings_changed(self, _settings):
        self.refresh_all()

    def refresh_all(self):
        if self.main_window:
            self.main_window.refresh()
        if self.desktop:
            self.desktop.refresh()

    def _shutdown(self, *_):
        if self.reminders:
            self.reminders.stop()
        if self.store:
            self.store.close()
