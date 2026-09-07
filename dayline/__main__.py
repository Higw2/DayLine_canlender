"""Command-line entry point for Dayline."""

import os
import sys
import locale
import gi
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib
from . import APP_ID, APP_NAME
from .ui import DaylineApplication


def main() -> int:
    args = sys.argv[1:]
    if "--help" in args or "-h" in args:
        print("用法: python3 -m dayline [--desktop | --quit]\n\n不带参数时打开日程编辑器；--desktop 仅显示桌面日程卡片；--quit 退出正在运行的时序。")
        return 0
    unknown = [arg for arg in args if arg not in {"--desktop", "--quit"}]
    if unknown:
        print(f"未知参数: {unknown[0]}（使用 --help 查看用法）", file=sys.stderr)
        return 2
    # GTK derives X11 WM_CLASS from the process program name.  Keep it aligned
    # with the desktop-file StartupWMClass and application notification identity.
    GLib.set_prgname(APP_ID)
    GLib.set_application_name(APP_NAME)
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        print("时序需要在 Ubuntu 图形桌面会话中运行（未检测到 DISPLAY 或 WAYLAND_DISPLAY）。", file=sys.stderr)
        return 1
    display_name = os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")
    if Gdk.Display.open(display_name) is None:
        print("无法连接到图形桌面会话，请从已登录的 Ubuntu 桌面中启动时序。", file=sys.stderr)
        return 1
    # Localize GTK's stock calendar labels without changing the user's system-wide locale.
    try:
        locale.setlocale(locale.LC_TIME, "zh_CN.UTF-8")
    except locale.Error:
        pass
    app = DaylineApplication()
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
