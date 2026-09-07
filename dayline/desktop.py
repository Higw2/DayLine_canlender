"""The small desktop-background companion window."""

from __future__ import annotations

import ctypes
import ctypes.util
from datetime import datetime

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
            self.lib.XCloseDisplay.argtypes = [ctypes.c_void_p]

    def apply(self, xid: int, position: tuple[int, int] | None = None) -> bool:
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
    def __init__(self, app, store: EventStore, open_editor, create_event, quit_app):
        super().__init__(application=app, title="时序 · 桌面日程")
        self.store, self.open_editor, self.create_event, self.quit_app = store, open_editor, create_event, quit_app
        self.hints_applied = False
        self._x11_hints: X11DesktopHints | None = None
        self._x11_xid = 0
        self._x11_position: tuple[int, int] | None = None
        self._x11_map_reapply_scheduled = False
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(390, 286)
        self.add_css_class("desktop-widget")
        self.connect("realize", self._on_realize)
        self.connect("map", self._on_map)
        self._root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(self._root)
        self.refresh()

    def _on_realize(self, *_):
        surface = self.get_surface()
        display = self.get_display()
        if not surface or not isinstance(display, GdkX11.X11Display):
            return
        monitor = display.get_monitors().get_item(0)
        geometry = monitor.get_geometry()
        # Keep it clear of the upper-left desktop icon area by default.
        self._x11_position = (geometry.x + geometry.width - 420, geometry.y + 84)
        self._x11_xid = GdkX11.X11Surface.get_xid(surface)
        self._x11_hints = X11DesktopHints()
        self.hints_applied = self._x11_hints.apply(self._x11_xid, self._x11_position)

    def _on_map(self, *_):
        if self._x11_hints and self._x11_xid and not self._x11_map_reapply_scheduled:
            self._x11_map_reapply_scheduled = True
            GLib.timeout_add(120, self._reapply_x11_hints)

    def _reapply_x11_hints(self):
        self.hints_applied = self._x11_hints.apply(self._x11_xid, self._x11_position)
        return False

    def refresh(self):
        child = self._root.get_first_child()
        while child:
            next_child = child.get_next_sibling()
            self._root.remove(child)
            child = next_child
        now = datetime.now()
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, margin_top=22, margin_start=24, margin_end=20)
        mark = Gtk.Label(label="时序", xalign=0, hexpand=True)
        mark.add_css_class("desktop-brand")
        weekday = "一二三四五六日"[now.weekday()]
        date = Gtk.Label(label=f"{now:%m月%d日}  星期{weekday}", xalign=1)
        date.add_css_class("desktop-date")
        header.append(mark); header.append(date); self._root.append(header)
        intro = Gtk.Label(label="接下来的安排", xalign=0, margin_start=24, margin_top=8)
        intro.add_css_class("desktop-subtitle"); self._root.append(intro)
        events = self.store.upcoming(2, now=now)
        if events:
            for event in events:
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10, margin_top=13, margin_start=24, margin_end=20)
                time = Gtk.Label(label=event.starts_at.strftime("%H:%M"), valign=Gtk.Align.START)
                time.add_css_class("desktop-time")
                text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
                name = Gtk.Label(label=event.title, xalign=0, ellipsize=3)
                name.add_css_class("desktop-event")
                day_prefix = "" if event.starts_at.date() == now.date() else f"{event.starts_at:%m/%d} · "
                subtitle = Gtk.Label(label=f"{day_prefix}至 {event.ends_at:%H:%M}", xalign=0)
                subtitle.add_css_class("desktop-event-detail")
                text.append(name); text.append(subtitle); row.append(time); row.append(text); self._root.append(row)
        else:
            empty = Gtk.Label(label="今天还没有待办，给自己留一点空白。", xalign=0, margin_top=18, margin_start=24)
            empty.add_css_class("desktop-event-detail"); self._root.append(empty)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, margin_top=18, margin_bottom=18, margin_start=24, margin_end=20)
        new = Gtk.Button(label="＋ 新建")
        new.add_css_class("desktop-new")
        new.connect("clicked", lambda *_: self.create_event())
        open_button = Gtk.Button(label="打开日程")
        open_button.connect("clicked", lambda *_: self.open_editor())
        quit_button = Gtk.Button(icon_name="application-exit-symbolic", tooltip_text="退出时序")
        quit_button.connect("clicked", lambda *_: self.quit_app())
        actions.append(new); actions.append(open_button); actions.append(quit_button); self._root.append(actions)
        if self.get_display().__class__.__module__.endswith("GdkWayland"):
            warning = Gtk.Label(label="Wayland 下桌面背景模式受系统限制，会以普通窗口显示。", wrap=True, xalign=0, margin_start=24, margin_end=20, margin_bottom=12)
            warning.add_css_class("desktop-event-detail")
            self._root.append(warning)
