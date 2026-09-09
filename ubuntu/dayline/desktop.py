"""The small desktop-background companion window."""

from __future__ import annotations

import ctypes
import ctypes.util
from datetime import datetime
import os
from pathlib import Path

import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("GdkX11", "4.0")
from gi.repository import Gdk, GdkX11, GLib, Gtk

from .storage import EventStore


class X11DesktopHints:
    """Set EWMH hints on a GTK surface without adding a PyPI dependency.

    Window managers may ignore these hints.  Under Wayland clients cannot place a
    normal GTK window beneath the desktop, which is why DesktopWidget displays an
    honest availability message there.
    """
    XA_ATOM = 4
    XA_CARDINAL = 6
    PROP_MODE_REPLACE = 0
    ALL_DESKTOPS = 0xFFFFFFFF
    CLIENT_MESSAGE = 33
    SUBSTRUCTURE_NOTIFY_MASK = 1 << 19
    SUBSTRUCTURE_REDIRECT_MASK = 1 << 20

    class ClientMessageEvent(ctypes.Structure):
        _fields_ = [
            ("type", ctypes.c_int),
            ("serial", ctypes.c_ulong),
            ("send_event", ctypes.c_int),
            ("display", ctypes.c_void_p),
            ("window", ctypes.c_ulong),
            ("message_type", ctypes.c_ulong),
            ("format", ctypes.c_int),
            ("data", ctypes.c_long * 5),
        ]

    def __init__(self):
        lib = ctypes.util.find_library("X11")
        self.lib = ctypes.CDLL(lib) if lib else None
        if self.lib:
            self.lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
            self.lib.XOpenDisplay.restype = ctypes.c_void_p
            self.lib.XInternAtom.restype = ctypes.c_ulong
            self.lib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
            self.lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
            self.lib.XDefaultRootWindow.restype = ctypes.c_ulong
            self.lib.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
            self.lib.XChangeProperty.restype = ctypes.c_int
            self.lib.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
            self.lib.XSendEvent.restype = ctypes.c_int
            self.lib.XFlush.argtypes = [ctypes.c_void_p]
            self.lib.XMoveWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int]
            self.lib.XResizeWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_uint, ctypes.c_uint]
            self.lib.XResizeWindow.restype = ctypes.c_int
            self.lib.XGetGeometry.argtypes = [
                ctypes.c_void_p, ctypes.c_ulong,
                ctypes.POINTER(ctypes.c_ulong),
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint),
                ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint),
            ]
            self.lib.XGetGeometry.restype = ctypes.c_int
            self.lib.XQueryPointer.argtypes = [
                ctypes.c_void_p, ctypes.c_ulong,
                ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_uint),
            ]
            self.lib.XQueryPointer.restype = ctypes.c_int
            self.lib.XTranslateCoordinates.argtypes = [
                ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
                ctypes.c_int, ctypes.c_int,
                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                ctypes.POINTER(ctypes.c_ulong),
            ]
            self.lib.XTranslateCoordinates.restype = ctypes.c_int
            self.lib.XCloseDisplay.argtypes = [ctypes.c_void_p]

    def position(self, xid: int) -> tuple[int, int] | None:
        if not self.lib or not xid:
            return None
        display = self.lib.XOpenDisplay(None)
        if not display:
            return None
        try:
            x = ctypes.c_int()
            y = ctypes.c_int()
            child = ctypes.c_ulong()
            ok = self.lib.XTranslateCoordinates(
                display, xid, self.lib.XDefaultRootWindow(display), 0, 0,
                ctypes.byref(x), ctypes.byref(y), ctypes.byref(child),
            )
            return (x.value, y.value) if ok else None
        finally:
            self.lib.XCloseDisplay(display)

    def pointer_position(self) -> tuple[int, int] | None:
        if not self.lib:
            return None
        display = self.lib.XOpenDisplay(None)
        if not display:
            return None
        try:
            root = self.lib.XDefaultRootWindow(display)
            root_return = ctypes.c_ulong()
            child_return = ctypes.c_ulong()
            root_x = ctypes.c_int()
            root_y = ctypes.c_int()
            window_x = ctypes.c_int()
            window_y = ctypes.c_int()
            mask = ctypes.c_uint()
            ok = self.lib.XQueryPointer(
                display, root,
                ctypes.byref(root_return), ctypes.byref(child_return),
                ctypes.byref(root_x), ctypes.byref(root_y),
                ctypes.byref(window_x), ctypes.byref(window_y), ctypes.byref(mask),
            )
            return (root_x.value, root_y.value) if ok else None
        finally:
            self.lib.XCloseDisplay(display)

    def move(self, xid: int, position: tuple[int, int]) -> None:
        display = self.lib.XOpenDisplay(None)
        if not display:
            return
        try:
            self.lib.XMoveWindow(display, xid, position[0], position[1])
            self.lib.XFlush(display)
        finally:
            self.lib.XCloseDisplay(display)

    def resize(self, xid: int, width: int, height: int) -> None:
        if not self.lib or not xid:
            return
        display = self.lib.XOpenDisplay(None)
        if not display:
            return
        try:
            self.lib.XResizeWindow(display, xid, max(300, width), max(200, height))
            self.lib.XFlush(display)
        finally:
            self.lib.XCloseDisplay(display)

    def geometry(self, xid: int) -> tuple[int, int, int, int] | None:
        if not self.lib or not xid:
            return None
        display = self.lib.XOpenDisplay(None)
        if not display:
            return None
        try:
            root = ctypes.c_ulong()
            x = ctypes.c_int()
            y = ctypes.c_int()
            w = ctypes.c_uint()
            h = ctypes.c_uint()
            bw = ctypes.c_uint()
            depth = ctypes.c_uint()
            ok = self.lib.XGetGeometry(
                display, xid, ctypes.byref(root),
                ctypes.byref(x), ctypes.byref(y),
                ctypes.byref(w), ctypes.byref(h),
                ctypes.byref(bw), ctypes.byref(depth),
            )
            return (x.value, y.value, int(w.value), int(h.value)) if ok else None
        finally:
            self.lib.XCloseDisplay(display)

    def apply(self, xid: int, position: tuple[int, int] | None = None, size: tuple[int, int] | None = None) -> bool:
        if not self.lib or not xid:
            return False
        display = self.lib.XOpenDisplay(None)
        if not display:
            return False
        try:
            atom = lambda name: self.lib.XInternAtom(display, name.encode(), False)

            def atoms_property(property_name, names):
                values = (ctypes.c_ulong * len(names))(*(atom(n) for n in names))
                self.lib.XChangeProperty(display, xid, atom(property_name), self.XA_ATOM, 32, self.PROP_MODE_REPLACE, ctypes.cast(values, ctypes.c_void_p), len(names))

            atoms_property("_NET_WM_WINDOW_TYPE", ["_NET_WM_WINDOW_TYPE_DESKTOP"])
            atoms_property("_NET_WM_STATE", ["_NET_WM_STATE_BELOW", "_NET_WM_STATE_STICKY", "_NET_WM_STATE_SKIP_TASKBAR", "_NET_WM_STATE_SKIP_PAGER"])
            desktop = ctypes.c_ulong(self.ALL_DESKTOPS)
            self.lib.XChangeProperty(display, xid, atom("_NET_WM_DESKTOP"), self.XA_CARDINAL, 32, self.PROP_MODE_REPLACE, ctypes.byref(desktop), 1)
            root = self.lib.XDefaultRootWindow(display)
            state_atom = atom("_NET_WM_STATE")
            state_mask = self.SUBSTRUCTURE_REDIRECT_MASK | self.SUBSTRUCTURE_NOTIFY_MASK

            def request_state(first: str, second: str):
                event = self.ClientMessageEvent(
                    self.CLIENT_MESSAGE,
                    0,
                    1,
                    display,
                    xid,
                    state_atom,
                    32,
                    (ctypes.c_long * 5)(1, atom(first), atom(second), 1, 0),
                )
                self.lib.XSendEvent(display, root, 0, state_mask, ctypes.cast(ctypes.byref(event), ctypes.c_void_p))

            request_state("_NET_WM_STATE_BELOW", "_NET_WM_STATE_STICKY")
            request_state("_NET_WM_STATE_SKIP_TASKBAR", "_NET_WM_STATE_SKIP_PAGER")
            desktop_event = self.ClientMessageEvent(
                self.CLIENT_MESSAGE,
                0,
                1,
                display,
                xid,
                atom("_NET_WM_DESKTOP"),
                32,
                (ctypes.c_long * 5)(self.ALL_DESKTOPS, 1, 0, 0, 0),
            )
            self.lib.XSendEvent(display, root, 0, state_mask, ctypes.cast(ctypes.byref(desktop_event), ctypes.c_void_p))
            if size:
                self.lib.XResizeWindow(display, xid, max(300, size[0]), max(200, size[1]))
            if position:
                self.lib.XMoveWindow(display, xid, position[0], position[1])
            # Reassert the properties after the WM has processed the mapped
            # window request.  This keeps xprop and the EWMH request aligned.
            atoms_property("_NET_WM_WINDOW_TYPE", ["_NET_WM_WINDOW_TYPE_DESKTOP"])
            atoms_property("_NET_WM_STATE", ["_NET_WM_STATE_BELOW", "_NET_WM_STATE_STICKY", "_NET_WM_STATE_SKIP_TASKBAR", "_NET_WM_STATE_SKIP_PAGER"])
            self.lib.XChangeProperty(display, xid, atom("_NET_WM_DESKTOP"), self.XA_CARDINAL, 32, self.PROP_MODE_REPLACE, ctypes.byref(desktop), 1)
            self.lib.XFlush(display)
            return True
        finally:
            self.lib.XCloseDisplay(display)


class DesktopWidget(Gtk.Window):
    def __init__(self, app, store: EventStore, open_editor, create_event, quit_app, open_settings=None):
        super().__init__(application=app, title="DayLine · 桌面日程")
        self.store, self.open_editor, self.create_event, self.quit_app = store, open_editor, create_event, quit_app
        self.open_settings = open_settings
        self.hints_applied = False
        self._x11_hints: X11DesktopHints | None = None
        self._x11_xid = 0
        self._x11_position: tuple[int, int] | None = None
        self._desktop_size: tuple[int, int] = (390, 286)
        self._x11_map_reapply_scheduled = False
        self._drag_origin: tuple[int, int] | None = None
        self._drag_pointer_origin: tuple[int, int] | None = None
        self._position_file = self._default_position_file()
        self._drag_header: Gtk.Widget | None = None
        self._resize_grip: Gtk.Widget | None = None
        self._resize_start_size: tuple[int, int] | None = None
        self._resize_pointer_origin: tuple[int, int] | None = None
        self._clock_timer: int = 0
        self.set_decorated(False)
        self.set_resizable(True)
        self.set_size_request(340, 220)
        self.set_default_size(390, 286)
        self.add_css_class("desktop-widget")
        self.connect("realize", self._on_realize)
        self.connect("map", self._on_map)
        self.connect("unmap", self._on_unmap)
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(self._root)
        self.refresh()

    @staticmethod
    def _default_position_file() -> Path:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        return config_home / "dayline" / "desktop-position"

    def _load_geometry(self) -> tuple[int, int, int, int] | None:
        try:
            parts = self._position_file.read_text(encoding="utf-8").strip().split(",")
            if len(parts) >= 4:
                return int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
            elif len(parts) >= 2:
                return int(parts[0]), int(parts[1]), 390, 286
            return None
        except (OSError, ValueError):
            return None

    def _save_position(self):
        if not self._x11_hints or not self._x11_xid:
            return False
        position = self._x11_hints.position(self._x11_xid)
        if position is not None:
            self._x11_position = position
            geom = self._x11_hints.geometry(self._x11_xid)
            w = geom[2] if geom else self.get_width()
            h = geom[3] if geom else self.get_height()
            self._desktop_size = (w, h)
            self._position_file.parent.mkdir(parents=True, exist_ok=True)
            self._position_file.write_text(f"{position[0]},{position[1]},{w},{h}\n", encoding="utf-8")
        return False

    def _on_realize(self, *_):
        surface = self.get_surface()
        display = self.get_display()
        if not surface or not isinstance(display, GdkX11.X11Display):
            return
        monitor = display.get_monitors().get_item(0)
        geometry = monitor.get_geometry()
        geom = self._load_geometry()
        if geom:
            self._x11_position = (geom[0], geom[1])
            self._desktop_size = (max(340, geom[2]), max(220, geom[3]))
        else:
            self._x11_position = (geometry.x + geometry.width - 420, geometry.y + 84)
            self._desktop_size = (390, 286)
        self._x11_xid = GdkX11.X11Surface.get_xid(surface)
        self._x11_hints = X11DesktopHints()
        self.set_default_size(self._desktop_size[0], self._desktop_size[1])
        self.hints_applied = self._x11_hints.apply(self._x11_xid, self._x11_position, self._desktop_size)

    def _on_map(self, *_):
        if self._x11_hints and self._x11_xid and not self._x11_map_reapply_scheduled:
            self._x11_map_reapply_scheduled = True
            GLib.timeout_add(120, self._reapply_x11_hints)
        if not self._clock_timer:
            self._clock_timer = GLib.timeout_add_seconds(30, self._tick_clock)

    def _on_unmap(self, *_):
        if self._clock_timer:
            GLib.source_remove(self._clock_timer)
            self._clock_timer = 0

    def _tick_clock(self):
        self.refresh()
        return True

    def _reapply_x11_hints(self):
        self.hints_applied = self._x11_hints.apply(self._x11_xid, self._x11_position, self._desktop_size)
        return False

    def refresh(self):
        child = self._root.get_first_child()
        while child:
            next_child = child.get_next_sibling()
            self._root.remove(child)
            child = next_child
        now = datetime.now()

        # Differentiated, explicit drag handle area using CenterBox for perfect balance
        header = Gtk.CenterBox()
        header.add_css_class("desktop-drag-area")
        header.set_cursor_from_name("grab")
        header.set_tooltip_text("按住此处拖动桌面卡片")
        self._drag_header = header

        drag = Gtk.GestureDrag(button=1)
        drag.connect("drag-begin", self._begin_drag)
        drag.connect("drag-update", self._update_drag)
        drag.connect("drag-end", self._end_drag)
        header.add_controller(drag)

        brand_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, valign=Gtk.Align.CENTER)
        brand_pill = Gtk.Label(label="DayLine")
        brand_pill.add_css_class("desktop-brand-pill")
        brand_box.append(brand_pill)
        header.set_start_widget(brand_box)

        # Center: Current time (strictly centered, 3 horizontal lines removed)
        current_time = Gtk.Label(
            label=now.strftime("%H:%M"),
            halign=Gtk.Align.CENTER,
            valign=Gtk.Align.CENTER,
        )
        current_time.add_css_class("desktop-drag-time")
        current_time.set_tooltip_text("当前时间 · 按住此处拖动卡片")
        header.set_center_widget(current_time)

        weekday = "一二三四五六日"[now.weekday()]
        date = Gtk.Label(label=f"{now:%m月%d日} 周{weekday}", halign=Gtk.Align.END, valign=Gtk.Align.CENTER)
        date.add_css_class("desktop-date")
        header.set_end_widget(date)

        self._root.append(header)

        intro = Gtk.Label(label="接下来的安排", xalign=0, margin_start=18, margin_top=8, margin_bottom=2)
        intro.add_css_class("desktop-subtitle")
        self._root.append(intro)

        # Scrollable events area so when resized larger or when many events exist, they all display!
        scroll = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
        scroll.add_css_class("desktop-events-scroll")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_propagate_natural_height(True)
        scroll.set_margin_bottom(6)
        events_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        scroll.set_child(events_container)

        events = self.store.upcoming(15, now=now)
        if events:
            for event in events:
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                row.add_css_class("desktop-event-row")
                time_badge = Gtk.Label(label=event.starts_at.strftime("%H:%M"), valign=Gtk.Align.CENTER)
                time_badge.add_css_class("desktop-time-pill")
                text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
                name = Gtk.Label(label=event.title, xalign=0, ellipsize=3)
                name.add_css_class("desktop-event")
                day_prefix = "" if event.starts_at.date() == now.date() else f"{event.starts_at:%m/%d} · "
                subtitle = Gtk.Label(label=f"{day_prefix}至 {event.ends_at:%H:%M}" + (f"  ·  {event.notes}" if event.notes else ""), xalign=0, ellipsize=3)
                subtitle.add_css_class("desktop-event-detail")
                text.append(name)
                text.append(subtitle)
                row.append(time_badge)
                row.append(text)
                events_container.append(row)
        else:
            empty_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, margin_start=18, margin_top=14, margin_bottom=8)
            empty_label = Gtk.Label(label="今天还没有待办，给自己留一点空白。", xalign=0)
            empty_label.add_css_class("desktop-event-detail")
            empty_box.append(empty_label)
            events_container.append(empty_box)

        self._root.append(scroll)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, margin_top=6, margin_bottom=10, margin_start=14, margin_end=12)
        new = Gtk.Button(label="＋ 新建")
        new.add_css_class("desktop-new")
        new.connect("clicked", lambda *_: self.create_event())

        open_button = Gtk.Button(label="打开日程")
        open_button.add_css_class("desktop-action-btn")
        open_button.connect("clicked", lambda *_: self.open_editor())

        spacer = Gtk.Box(hexpand=True)

        settings_button = Gtk.Button(icon_name="emblem-system-symbolic", tooltip_text="偏好设置")
        settings_button.add_css_class("desktop-action-btn")
        settings_button.connect("clicked", lambda *_: self.open_settings() if self.open_settings else None)

        quit_button = Gtk.Button(icon_name="application-exit-symbolic", tooltip_text="退出 DayLine")
        quit_button.add_css_class("desktop-action-btn")
        quit_button.connect("clicked", lambda *_: self.quit_app())

        # Resize grip in bottom-right corner
        resize_grip = Gtk.Box(valign=Gtk.Align.CENTER, halign=Gtk.Align.END)
        resize_grip.add_css_class("desktop-resize-handle")
        resize_grip.set_cursor_from_name("se-resize")
        resize_grip.set_tooltip_text("拖拽调整大小")
        resize_icon = Gtk.Label(label="⋰")
        resize_icon.add_css_class("desktop-resize-icon")
        resize_grip.append(resize_icon)
        self._resize_grip = resize_grip

        resize_drag = Gtk.GestureDrag(button=1)
        resize_drag.connect("drag-begin", self._begin_resize)
        resize_drag.connect("drag-update", self._update_resize)
        resize_drag.connect("drag-end", self._end_resize)
        resize_grip.add_controller(resize_drag)

        actions.append(new)
        actions.append(open_button)
        actions.append(spacer)
        actions.append(settings_button)
        actions.append(quit_button)
        actions.append(resize_grip)
        self._root.append(actions)

        if self.get_display().__class__.__module__.endswith("GdkWayland"):
            warning = Gtk.Label(label="Wayland 下桌面背景模式受系统限制，会以普通窗口显示。", wrap=True, xalign=0, margin_start=18, margin_end=18, margin_bottom=10)
            warning.add_css_class("desktop-event-detail")
            self._root.append(warning)

    def _begin_drag(self, gesture, x, y):
        if self._drag_header:
            self._drag_header.set_cursor_from_name("grabbing")
            self._drag_header.add_css_class("dragging")
        if self._x11_hints and self._x11_xid:
            self._drag_origin = self._x11_hints.position(self._x11_xid)
            self._drag_pointer_origin = self._x11_hints.pointer_position()
            return
        surface = self.get_surface()
        device = gesture.get_current_event_device()
        if isinstance(surface, Gdk.Toplevel) and device is not None:
            surface.begin_move(
                device,
                gesture.get_current_button(),
                x,
                y,
                gesture.get_current_event_time(),
            )

    def _update_drag(self, _gesture, _offset_x, _offset_y):
        if not self._x11_hints or not self._drag_origin or not self._drag_pointer_origin:
            return
        pointer = self._x11_hints.pointer_position()
        if pointer is None:
            return
        position = (
            self._drag_origin[0] + pointer[0] - self._drag_pointer_origin[0],
            self._drag_origin[1] + pointer[1] - self._drag_pointer_origin[1],
        )
        self._x11_hints.move(self._x11_xid, position)

    def _end_drag(self, *_):
        if self._drag_header:
            self._drag_header.set_cursor_from_name("grab")
            self._drag_header.remove_css_class("dragging")
        GLib.timeout_add(150, self._save_position)
        self._drag_origin = None
        self._drag_pointer_origin = None

    def _begin_resize(self, gesture, x, y):
        if self._resize_grip:
            self._resize_grip.add_css_class("resizing")
        if self._x11_hints and self._x11_xid:
            geom = self._x11_hints.geometry(self._x11_xid)
            if geom:
                self._resize_start_size = (geom[2], geom[3])
            else:
                self._resize_start_size = (self.get_width(), self.get_height())
            self._resize_pointer_origin = self._x11_hints.pointer_position()
            return
        surface = self.get_surface()
        device = gesture.get_current_event_device()
        if isinstance(surface, Gdk.Toplevel) and device is not None:
            surface.begin_resize(
                Gdk.SurfaceEdge.SOUTH_EAST,
                device,
                gesture.get_current_button(),
                x,
                y,
                gesture.get_current_event_time(),
            )

    def _update_resize(self, _gesture, _offset_x, _offset_y):
        if not self._x11_hints or not self._x11_xid or not self._resize_start_size or not self._resize_pointer_origin:
            return
        pointer = self._x11_hints.pointer_position()
        if pointer is None:
            return
        dx = pointer[0] - self._resize_pointer_origin[0]
        dy = pointer[1] - self._resize_pointer_origin[1]
        new_w = max(340, min(800, self._resize_start_size[0] + dx))
        new_h = max(220, min(1000, self._resize_start_size[1] + dy))
        self._desktop_size = (new_w, new_h)
        self._x11_hints.resize(self._x11_xid, new_w, new_h)
        self.set_default_size(new_w, new_h)

    def _end_resize(self, *_):
        if self._resize_grip:
            self._resize_grip.remove_css_class("resizing")
        self._resize_start_size = None
        self._resize_pointer_origin = None
        GLib.timeout_add(150, self._save_position)
