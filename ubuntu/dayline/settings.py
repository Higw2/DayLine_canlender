"""User settings and configuration persistence for Dayline."""

from __future__ import annotations

import json
import os
import string
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable


def default_config_dir() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "dayline"


def default_settings_file() -> Path:
    return default_config_dir() / "settings.json"


@dataclass
class AppSettings:
    """User preferences for appearance and behavior."""

    theme_color: str = "#28735f"
    font_scale: float = 1.0
    desktop_theme: str = "dark"  # "dark", "tinted", "light"
    # Shared with the macOS build so settings.json can move between builds.
    bg_color: str = "#1e242b"
    bg_opacity: float = 0.90
    bg_image_path: str = ""
    bg_type: str = "color"  # "color" or "image"

    @classmethod
    def from_dict(cls, data: dict) -> AppSettings:
        valid_font_scales = {0.9, 1.0, 1.15, 1.3}
        font_scale = float(data.get("font_scale", 1.0))
        if font_scale not in valid_font_scales:
            font_scale = min(valid_font_scales, key=lambda s: abs(s - font_scale))

        theme_color = str(data.get("theme_color", "#28735f")).strip()
        if not theme_color.startswith("#") or len(theme_color) not in (4, 7, 9) or any(c not in string.hexdigits for c in theme_color[1:]):
            theme_color = "#28735f"

        desktop_theme = str(data.get("desktop_theme", "dark")).strip()
        if desktop_theme not in {"dark", "tinted", "light"}:
            desktop_theme = "dark"

        bg_color = str(data.get("bg_color", "#1e242b")).strip()
        if not bg_color.startswith("#") or len(bg_color) not in (4, 7, 9) or any(c not in string.hexdigits for c in bg_color[1:]):
            bg_color = "#1e242b"
        bg_opacity = max(0.1, min(1.0, float(data.get("bg_opacity", 0.90))))
        bg_image_path = str(data.get("bg_image_path", "")).strip()
        bg_type = str(data.get("bg_type", "color")).strip()
        if bg_type not in {"color", "image"}:
            bg_type = "color"

        return cls(
            theme_color=theme_color,
            font_scale=font_scale,
            desktop_theme=desktop_theme,
            bg_color=bg_color,
            bg_opacity=bg_opacity,
            bg_image_path=bg_image_path,
            bg_type=bg_type,
        )


class SettingsManager:
    """Manages reading, updating, and saving user settings with listeners."""

    def __init__(self, file_path: Path | None = None):
        self.file_path = file_path or default_settings_file()
        self._listeners: list[Callable[[AppSettings], None]] = []
        self._settings: AppSettings = self._load()

    @property
    def current(self) -> AppSettings:
        return self._settings

    def add_listener(self, callback: Callable[[AppSettings], None]) -> None:
        if callback not in self._listeners:
            self._listeners.append(callback)

    def remove_listener(self, callback: Callable[[AppSettings], None]) -> None:
        if callback in self._listeners:
            self._listeners.remove(callback)

    def _load(self) -> AppSettings:
        try:
            if self.file_path.is_file():
                raw = json.loads(self.file_path.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    return AppSettings.from_dict(raw)
        except (OSError, json.JSONDecodeError, ValueError):
            pass
        return AppSettings()

    def save(self) -> None:
        try:
            self.file_path.parent.mkdir(parents=True, exist_ok=True)
            temp_file = self.file_path.with_suffix(".tmp")
            temp_file.write_text(
                json.dumps(asdict(self._settings), indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            temp_file.replace(self.file_path)
        except OSError:
            pass

    def update(
        self,
        *,
        theme_color: str | None = None,
        font_scale: float | None = None,
        desktop_theme: str | None = None,
        bg_color: str | None = None,
        bg_opacity: float | None = None,
        bg_image_path: str | None = None,
        bg_type: str | None = None,
    ) -> None:
        changed = False
        if theme_color is not None and theme_color != self._settings.theme_color:
            self._settings.theme_color = theme_color
            changed = True
        if font_scale is not None and abs(font_scale - self._settings.font_scale) > 0.001:
            self._settings.font_scale = font_scale
            changed = True
        if desktop_theme is not None and desktop_theme != self._settings.desktop_theme:
            self._settings.desktop_theme = desktop_theme
            changed = True
        if bg_color is not None and bg_color != self._settings.bg_color:
            self._settings.bg_color = bg_color
            changed = True
        if bg_opacity is not None and abs(bg_opacity - self._settings.bg_opacity) > 0.001:
            self._settings.bg_opacity = bg_opacity
            changed = True
        if bg_image_path is not None and bg_image_path != self._settings.bg_image_path:
            self._settings.bg_image_path = bg_image_path
            changed = True
        if bg_type is not None and bg_type != self._settings.bg_type:
            self._settings.bg_type = bg_type
            changed = True

        if changed:
            self.save()
            for listener in list(self._listeners):
                try:
                    listener(self._settings)
                except Exception:
                    pass

    def reset_to_defaults(self) -> None:
        defaults = AppSettings()
        self.update(
            theme_color=defaults.theme_color,
            font_scale=defaults.font_scale,
            desktop_theme=defaults.desktop_theme,
            bg_color=defaults.bg_color,
            bg_opacity=defaults.bg_opacity,
            bg_image_path=defaults.bg_image_path,
            bg_type=defaults.bg_type,
        )


_global_settings: SettingsManager | None = None


def get_settings_manager() -> SettingsManager:
    global _global_settings
    if _global_settings is None:
        _global_settings = SettingsManager()
    return _global_settings
