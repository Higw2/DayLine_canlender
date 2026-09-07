#!/usr/bin/env python3
"""Offline, per-user installation. Never removes the user's calendar database."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess

APP_ID = "io.github.dayline.Calendar"
SOURCE = Path(__file__).resolve().parent


def desktop_quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'


def install(prefix, config, autostart=False):
    target = prefix / 'lib/dayline'
    package = SOURCE / 'dayline'
    if not (package / '__main__.py').is_file():
        raise SystemExit('找不到 dayline 应用包，请在完整项目中运行安装器。')
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(package, target / 'dayline', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    launcher = prefix / 'bin/dayline'
    launcher.parent.mkdir(parents=True, exist_ok=True)
    launcher.write_text('#!/bin/sh\ncd ' + shlex.quote(str(target)) + '\nexec /usr/bin/python3 -m dayline "$@"\n')
    launcher.chmod(0o755)
    icon = prefix / f'share/icons/hicolor/scalable/apps/{APP_ID}.svg'
    icon.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE / f'packaging/{APP_ID}.svg', icon)
    desktop = prefix / f'share/applications/{APP_ID}.desktop'
    desktop.parent.mkdir(parents=True, exist_ok=True)
    entry = ('[Desktop Entry]\nType=Application\nVersion=1.0\n'
             'Name=时序 · Dayline\nName[zh_CN]=时序日程\n'
             'Name=DayLine\nName[zh_CN]=DayLine 日程\n'
             'Comment=Your day, beautifully in view\nComment[zh_CN]=桌面时间线与日程提醒\n'
             f'Exec={desktop_quote(launcher)}\nIcon={APP_ID}\n'
             'Terminal=false\nCategories=Office;Calendar;\n'
             'Keywords=Calendar;Schedule;Timeline;Dayline;时序日程;日程;日历;\nStartupNotify=true\n'
             'Keywords=Calendar;Schedule;Timeline;DayLine;日程;日历;\nStartupNotify=true\n'
             f'StartupWMClass={APP_ID}\n')
    desktop.write_text(entry)
    if autostart:
        startup = config / f'autostart/{APP_ID}.desktop'
        startup.parent.mkdir(parents=True, exist_ok=True)
        startup.write_text(entry.replace(f'Exec={desktop_quote(launcher)}',
                                         f'Exec={desktop_quote(launcher)} --desktop') +
                           'X-GNOME-Autostart-enabled=true\n')
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', str(desktop.parent)], check=False)
    print(f'已安装：{launcher}\n可从应用列表打开「时序日程」。')
    print(f'已安装：{launcher}\n可从应用列表打开「DayLine」。')
    if autostart:
        print('已启用登录后显示桌面日程。')


def uninstall(prefix, config):
    target = prefix / 'lib/dayline'
    for file in [prefix / 'bin/dayline', prefix / f'share/applications/{APP_ID}.desktop',
                 prefix / f'share/icons/hicolor/scalable/apps/{APP_ID}.svg',
                 config / f'autostart/{APP_ID}.desktop']:
        file.unlink(missing_ok=True)
    if target.exists():
        shutil.rmtree(target)
    print('已卸载应用和自启动入口；日程数据库保留。')


def main():
    parser = argparse.ArgumentParser(description='时序日程：无需 sudo 的用户级安装器')
    parser = argparse.ArgumentParser(description='DayLine：无需 sudo 的用户级安装器')
    parser.add_argument('--prefix', type=Path, default=Path.home() / '.local')
    parser.add_argument('--config-dir', type=Path,
                        default=Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')))
    parser.add_argument('--autostart', action='store_true', help='登录后打开桌面日程')
    parser.add_argument('--uninstall', action='store_true', help='卸载应用，保留日程数据')
    args = parser.parse_args()
    prefix, config = args.prefix.expanduser().resolve(), args.config_dir.expanduser().resolve()
    if args.uninstall:
        uninstall(prefix, config)
    else:
        install(prefix, config, args.autostart)


if __name__ == '__main__':
    main()
