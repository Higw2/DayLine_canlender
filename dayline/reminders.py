"""Polling reminder service and visible GTK reminder dialog."""

from __future__ import annotations

from datetime import datetime
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk

from .storage import Event, EventStore


class ReminderService:
    def __init__(self, app: Gtk.Application, store: EventStore, on_changed):
        self.app, self.store, self.on_changed = app, store, on_changed
        self.last_minute = None
        self.source_id = GLib.timeout_add_seconds(3, self.check)

    def check(self) -> bool:
        now = datetime.now()
        changed = bool(self.store.expire_stale_reminders())
        due = self.store.due_events()
        for event in due:
            self.store.mark_alerted(event.id)
            self._notify(event)
            ReminderWindow(self.app, event, self.store, self.on_changed).present()
        minute_key = now.strftime("%Y%m%d%H%M")
        minute_changed = minute_key != self.last_minute
        self.last_minute = minute_key
        if changed or due or minute_changed:
            self.on_changed()
        return True

    def _notify(self, event: Event) -> None:
        notification = Gio.Notification.new("时序提醒")
        notification = Gio.Notification.new("DayLine 提醒")
        notification.set_body(f"{event.title} · {event.starts_at:%H:%M}")
        notification.set_priority(Gio.NotificationPriority.URGENT)
        self.app.send_notification(f"event-{event.id}", notification)

    def stop(self) -> None:
        if self.source_id:
            GLib.source_remove(self.source_id)
            self.source_id = 0


class ReminderWindow(Gtk.Window):
    def __init__(self, app, event: Event, store: EventStore, on_changed):
        super().__init__(application=app, title="时序提醒", modal=False)
        super().__init__(application=app, title="DayLine 提醒", modal=False)
        self.event, self.store, self.on_changed = event, store, on_changed
        self.set_default_size(390, 205)
        self.set_resizable(False)
        self.add_css_class("reminder-window")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin_top=24, margin_bottom=20, margin_start=24, margin_end=24)
        label = Gtk.Label(label="该做这件事了", xalign=0)
        label.add_css_class("eyebrow")
        box.append(label)
        title = Gtk.Label(label=event.title, xalign=0, wrap=True)
        title.add_css_class("reminder-title")
        box.append(title)
        when = Gtk.Label(label=f"原定时间  {event.starts_at:%Y年%m月%d日  %H:%M}", xalign=0)
        when.add_css_class("muted")
        box.append(when)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, halign=Gtk.Align.END, margin_top=4)
        later = Gtk.Button(label="10 分钟后")
        later.connect("clicked", self._snooze)
        done = Gtk.Button(label="完成")
        done.add_css_class("suggested-action")
        done.connect("clicked", self._done)
        actions.append(later); actions.append(done); box.append(actions)
        self.set_child(box)

    def _snooze(self, *_):
        if self.store.get(self.event.id) is not None:
            self.store.snooze(self.event.id)
        self.on_changed(); self.close()

    def _done(self, *_):
        if self.store.get(self.event.id) is not None:
            self.store.set_completed(self.event.id)
        self.on_changed(); self.close()
