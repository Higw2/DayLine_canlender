"""Shared GTK background surface for the editor and desktop card."""

from __future__ import annotations

from pathlib import Path

import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Graphene, Gsk, Gtk

from .settings import AppSettings


class BackgroundSurface(Gtk.Widget):
    """Paint a color or an aspect-filled, softly blurred local image."""

    def __init__(self, settings: AppSettings):
        super().__init__()
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.add_css_class("background-surface")
        self._texture: Gdk.Texture | None = None
        self._texture_path: str | None = None
        self._settings = settings
        self.set_settings(settings)

    def set_settings(self, settings: AppSettings) -> None:
        self._settings = settings
        image_path = settings.bg_image_path if settings.bg_type == "image" else None
        if image_path != self._texture_path:
            self._texture_path = image_path
            self._texture = None
            if image_path and Path(image_path).is_file():
                try:
                    self._texture = Gdk.Texture.new_from_filename(image_path)
                except GLib.Error:
                    self._texture = None
        self.queue_draw()

    def do_snapshot(self, snapshot: Gtk.Snapshot) -> None:
        width = self.get_width()
        height = self.get_height()
        if width <= 0 or height <= 0:
            return
        bounds = Graphene.Rect().init(0, 0, width, height)
        opacity = self._settings.bg_opacity
        if self._texture is None or self._settings.bg_type != "image":
            rgba = Gdk.RGBA()
            rgba.parse(self._settings.bg_color)
            rgba.alpha = opacity
            snapshot.append_color(rgba, bounds)
            return

        texture_width = self._texture.get_width()
        texture_height = self._texture.get_height()
        scale = max(width / texture_width, height / texture_height)
        draw_width = texture_width * scale
        draw_height = texture_height * scale
        image_bounds = Graphene.Rect().init(
            (width - draw_width) / 2,
            (height - draw_height) / 2,
            draw_width,
            draw_height,
        )
        snapshot.push_opacity(opacity)
        snapshot.push_blur(24.0)
        snapshot.append_scaled_texture(self._texture, Gsk.ScalingFilter.LINEAR, image_bounds)
        snapshot.pop()
        snapshot.pop()
