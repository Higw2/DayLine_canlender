"""GitHub Release checks and in-app updates for the installed Ubuntu build."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from dataclasses import dataclass
from urllib.request import Request, urlopen

from gi.repository import GLib

from .settings import UPDATE_CHECK_INTERVALS, default_config_dir, get_settings_manager
from .version import VERSION


RELEASES_URL = "https://api.github.com/repos/Higw2/ubuntu24-calendar/releases?per_page=20"
ASSET_NAME = "DayLine-Ubuntu-24.04.tar.gz"
ARCHIVE_ROOT = "DayLine-Ubuntu-24.04"
MAX_ASSET_SIZE = 100 * 1024 * 1024


def parse_version(value: str) -> tuple[int, int, int] | None:
    match = re.search(r"(?:^|[^0-9])(\d+)\.(\d+)\.(\d+)(?:[^0-9]|$)", value)
    return tuple(map(int, match.groups())) if match else None


@dataclass(frozen=True)
class AvailableUpdate:
    version: str
    tag: str
    name: str
    notes: str
    page_url: str
    download_url: str
    size: int
    digest: str


def select_update(releases: list[dict], installed_version: str = VERSION) -> AvailableUpdate | None:
    current = parse_version(installed_version)
    candidates = []
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        version = parse_version(release.get("tag_name", "")) or parse_version(release.get("name") or "")
        if not version or current is None or version <= current:
            continue
        asset = next((item for item in release.get("assets", []) if item.get("name") == ASSET_NAME), None)
        if not asset or not 0 < asset.get("size", 0) <= MAX_ASSET_SIZE:
            continue
        digest = asset.get("digest") or ""
        if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
            raise ValueError(f"Release {release['tag_name']} 的 Ubuntu 安装包缺少 SHA-256 摘要")
        candidates.append((version, AvailableUpdate(
            version=".".join(map(str, version)),
            tag=release["tag_name"],
            name=release.get("name") or release["tag_name"],
            notes=release.get("body") or "",
            page_url=release["html_url"],
            download_url=asset["browser_download_url"],
            size=asset["size"],
            digest=digest[7:].lower(),
        )))
    return max(candidates, key=lambda item: item[0])[1] if candidates else None


def fetch_update() -> AvailableUpdate | None:
    request = Request(RELEASES_URL, headers={
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": f"DayLine-Ubuntu/{VERSION}",
    })
    with urlopen(request, timeout=20) as response:
        releases = json.load(response)
    return select_update(releases)


def installed_prefix() -> Path | None:
    package_dir = Path(__file__).resolve().parent
    install_dir = package_dir.parent
    prefix = install_dir.parent.parent
    if install_dir.name == "dayline" and install_dir.parent.name == "lib" and (prefix / "bin/dayline").is_file():
        return prefix
    return None


def download_and_stage(update: AvailableUpdate) -> Path:
    stage = Path(tempfile.mkdtemp(prefix="dayline-update-"))
    try:
        archive = stage / ASSET_NAME
        request = Request(update.download_url, headers={"User-Agent": f"DayLine-Ubuntu/{VERSION}"})
        hasher = hashlib.sha256()
        downloaded = 0
        with urlopen(request, timeout=60) as response, archive.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                downloaded += len(chunk)
                if downloaded > MAX_ASSET_SIZE:
                    raise ValueError("安装包超过大小限制")
                output.write(chunk)
                hasher.update(chunk)
        if downloaded != update.size or hasher.hexdigest() != update.digest:
            raise ValueError("安装包的 SHA-256 或大小与 Release 信息不符")
        with tarfile.open(archive, "r:gz") as bundle:
            bundle.extractall(stage, filter="data")
        package = stage / ARCHIVE_ROOT
        if (package / "VERSION").read_text(encoding="utf-8").strip() != update.version:
            raise ValueError("安装包版本与 Release 标签不一致")
        if not (package / "install.py").is_file() or not (package / "update_helper.py").is_file():
            raise ValueError("Release 中的 Ubuntu 安装包不完整")
        archive.unlink()
        return package
    except Exception:
        shutil.rmtree(stage)
        raise


class UpdateController:
    def __init__(self):
        self.available: AvailableUpdate | None = None
        self.status = "尚未检查更新"
        self.checking = False
        self.installing = False
        self.last_checked_at: float | None = None
        self._listeners = []
        self._state_file = default_config_dir() / "update-state.json"
        if self._state_file.is_file():
            try:
                self.last_checked_at = json.loads(self._state_file.read_text(encoding="utf-8")).get("last_checked_at")
            except (OSError, ValueError):
                pass
        GLib.timeout_add_seconds(3600, self._timer_tick)
        GLib.idle_add(self._check_if_due)

    def add_listener(self, callback) -> None:
        self._listeners.append(callback)

    def remove_listener(self, callback) -> None:
        self._listeners.remove(callback)

    def _notify(self) -> None:
        for callback in self._listeners:
            callback(self)

    def _timer_tick(self) -> bool:
        self._check_if_due()
        return True

    def _check_if_due(self) -> bool:
        settings = get_settings_manager().current
        interval = UPDATE_CHECK_INTERVALS[settings.update_check_interval]
        if settings.automatic_updates_enabled and time.time() - (self.last_checked_at or 0) >= interval:
            self.check()
        return False

    def settings_changed(self) -> None:
        self._check_if_due()

    def check(self) -> None:
        if self.checking or self.installing:
            return
        self.checking = True
        self.status = "正在检查更新…"
        self._notify()

        def work():
            try:
                update = fetch_update()
                GLib.idle_add(self._checked, update, None)
            except Exception as error:
                GLib.idle_add(self._checked, None, str(error))

        threading.Thread(target=work, daemon=True).start()

    def _checked(self, update: AvailableUpdate | None, error: str | None) -> bool:
        self.checking = False
        if error:
            self.status = f"检查失败：{error}"
        else:
            self.available = update
            self.last_checked_at = time.time()
            self._state_file.parent.mkdir(parents=True, exist_ok=True)
            self._state_file.write_text(json.dumps({"last_checked_at": self.last_checked_at}), encoding="utf-8")
            self.status = f"发现新版本 {update.version}" if update else f"已是最新版本（{VERSION}）"
        self._notify()
        return False

    def install(self) -> None:
        if not self.available or self.installing:
            return
        prefix = installed_prefix()
        if prefix is None:
            self.status = "请先安装 DayLine，再使用应用内更新"
            self._notify()
            return
        self.installing = True
        self.status = f"正在下载 DayLine {self.available.version}…"
        self._notify()

        update = self.available

        def work():
            try:
                package = download_and_stage(update)
                GLib.idle_add(self._launch_installer, package, prefix)
            except Exception as error:
                GLib.idle_add(self._install_failed, str(error))

        threading.Thread(target=work, daemon=True).start()

    def _launch_installer(self, package: Path, prefix: Path) -> bool:
        try:
            subprocess.Popen(
                [sys.executable, str(package / "update_helper.py"), str(os.getpid()), str(package), str(prefix)],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as error:
            return self._install_failed(str(error))
        self.status = "下载校验完成，正在安装并重新启动…"
        self._notify()
        self.on_quit()
        return False

    def _install_failed(self, error: str) -> bool:
        self.installing = False
        self.status = f"更新失败：{error}"
        self._notify()
        return False

    def on_quit(self) -> None:
        """Set by the application so installation starts after its process exits."""
