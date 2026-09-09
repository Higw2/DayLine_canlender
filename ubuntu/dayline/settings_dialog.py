"""Modern preferences window for Dayline using Libadwaita."""

from __future__ import annotations

import gi
from pathlib import Path

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk

from .settings import AppSettings, get_settings_manager
from .theme import BACKGROUND_PALETTE, FONT_SCALE_OPTIONS, PRESET_PALETTE, apply_theme


class SettingsDialog(Adw.PreferencesWindow):
    """Preferences window allowing users to customize colors and font sizes."""

    def __init__(self, parent: Gtk.Window | None = None):
        super().__init__(title="时序 · 偏好设置")
        super().__init__(title="DayLine · 偏好设置")
        if parent:
            self.set_transient_for(parent)
            self.set_modal(True)
        self.set_default_size(560, 480)
        self.manager = get_settings_manager()
        self._updating_ui = False
        self._swatch_buttons: list[tuple[str, Gtk.Button]] = []
        self._bg_swatch_buttons: list[tuple[str, Gtk.Button]] = []

        self._build_ui()
        self._sync_ui_from_settings(self.manager.current)

    def _build_ui(self) -> None:
        page = Adw.PreferencesPage(title="个性化", icon_name="preferences-desktop-theme-symbolic")
        self.add(page)

        # 1. Theme Color Group
        color_group = Adw.PreferencesGroup(
            title="主题与色彩",
            description="自定义应用的强调色调，修改后主窗口和桌面卡片将实时同步更新。",
        )
        page.add(color_group)

        # Accent color row
        color_row = Adw.ActionRow(
            title="主题强调色",
            subtitle="点击预设圆钮快速切换，或使用右侧调色盘拾取任意自定义色彩",
        )
        color_group.add(color_row)

        swatches_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, margin_top=8, margin_bottom=8)
        self._swatch_buttons.clear()
        for preset in PRESET_PALETTE:
            btn = Gtk.Button(tooltip_text=preset.name)
            btn.set_size_request(28, 28)
            btn.add_css_class("circular")
            btn.add_css_class("color-swatch-btn")

            # Inline style provider for the swatch color
            provider = Gtk.CssProvider()
            provider.load_from_data(
                f"button.color-swatch-btn {{ background: {preset.hex_code}; min-width: 28px; min-height: 28px; }}".encode()
            )
            btn.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10)

            hex_code = preset.hex_code
            btn.connect("clicked", lambda _b, c=hex_code: self._on_preset_clicked(c))
            swatches_box.append(btn)
            self._swatch_buttons.append((hex_code, btn))

        # Custom color picker button
        color_dialog = Gtk.ColorDialog(title="选择自定义主题色", with_alpha=False)
        self.color_dialog_btn = Gtk.ColorDialogButton(dialog=color_dialog, tooltip_text="自定义调色盘")
        self.color_dialog_btn.connect("notify::rgba", self._on_custom_color_chosen)
        swatches_box.append(self.color_dialog_btn)

        color_row.add_suffix(swatches_box)

        # Desktop Widget Theme Row
        self.desktop_theme_row = Adw.ComboRow(
            title="桌面挂件背景风格",
            subtitle="设定桌面常驻日程卡片的底色与视觉质感",
        )
        self._desktop_theme_keys = ["dark", "tinted", "light"]
        desktop_model = Gtk.StringList.new(["深邃墨夜 (默认)", "跟随主题色调", "清爽素雅明亮"])
        self.desktop_theme_row.set_model(desktop_model)
        self.desktop_theme_row.connect("notify::selected", self._on_desktop_theme_changed)
        color_group.add(self.desktop_theme_row)

        background_group = Adw.PreferencesGroup(
            title="背景与毛玻璃",
            description="主窗口和桌面日程卡片共用背景。图片会自动裁切填充并使用柔和的毛玻璃模糊。",
        )
        page.add(background_group)

        self.bg_type_row = Adw.ComboRow(title="背景样式", subtitle="纯色背景或图片背景")
        self._bg_type_keys = ["color", "image"]
        self.bg_type_row.set_model(Gtk.StringList.new(["纯色背景", "图片背景"]))
        self.bg_type_row.connect("notify::selected", self._on_bg_type_changed)
        background_group.add(self.bg_type_row)

        bg_color_row = Adw.ActionRow(title="背景颜色", subtitle="选择 7 种预设颜色或自定义颜色")
        bg_swatches = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for preset in BACKGROUND_PALETTE:
            btn = Gtk.Button(tooltip_text=preset.name)
            btn.set_size_request(28, 28)
            btn.add_css_class("circular")
            btn.add_css_class("color-swatch-btn")
            provider = Gtk.CssProvider()
            provider.load_from_data(
                f"button.color-swatch-btn {{ background: {preset.hex_code}; min-width: 28px; min-height: 28px; }}".encode()
            )
            btn.get_style_context().add_provider(provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10)
            btn.connect("clicked", lambda _b, c=preset.hex_code: self._on_bg_preset_clicked(c))
            bg_swatches.append(btn)
            self._bg_swatch_buttons.append((preset.hex_code, btn))
        bg_dialog = Gtk.ColorDialog(title="选择自定义背景颜色", with_alpha=False)
        self.bg_color_dialog_btn = Gtk.ColorDialogButton(dialog=bg_dialog, tooltip_text="自定义背景颜色")
        self.bg_color_dialog_btn.connect("notify::rgba", self._on_bg_custom_color_chosen)
        bg_swatches.append(self.bg_color_dialog_btn)
        bg_color_row.add_suffix(bg_swatches)
        background_group.add(bg_color_row)

        image_row = Adw.ActionRow(title="背景图片", subtitle="界面只显示文件名，不展示本地路径")
        image_actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.bg_image_label = Gtk.Label(xalign=1, ellipsize=3)
        self.bg_image_label.set_max_width_chars(18)
        image_actions.append(self.bg_image_label)
        self.bg_image_button = Gtk.Button(label="选择图片…")
        self.bg_image_button.add_css_class("suggested-action")
        self.bg_image_button.connect("clicked", self._choose_background_image)
        image_actions.append(self.bg_image_button)
        self.bg_clear_button = Gtk.Button(label="清除")
        self.bg_clear_button.add_css_class("flat")
        self.bg_clear_button.connect("clicked", self._clear_background_image)
        image_actions.append(self.bg_clear_button)
        image_row.add_suffix(image_actions)
        background_group.add(image_row)

        opacity_row = Adw.ActionRow(title="背景透明度", subtitle="20% 通透 · 100% 饱满")
        self.bg_opacity_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.2, 1.0, 0.05)
        self.bg_opacity_scale.set_digits(0)
        self.bg_opacity_scale.set_hexpand(True)
        self.bg_opacity_scale.set_size_request(180, -1)
        self.bg_opacity_scale.connect("value-changed", self._on_bg_opacity_changed)
        opacity_row.add_suffix(self.bg_opacity_scale)
        background_group.add(opacity_row)

        # 2. Typography Group
        font_group = Adw.PreferencesGroup(
            title="文字与排版",
            description="缩放全局字体大小，以适配合适的阅读距离与显示器分辨率。",
        )
        page.add(font_group)

        self.font_scale_row = Adw.ComboRow(
            title="界面字体大小",
            subtitle="按比例缩放主窗口、时间线日程及桌面卡片的所有文字",
        )
        self._font_scales = [scale for _, scale in FONT_SCALE_OPTIONS]
        font_labels = [label for label, _ in FONT_SCALE_OPTIONS]
        font_model = Gtk.StringList.new(font_labels)
        self.font_scale_row.set_model(font_model)
        self.font_scale_row.connect("notify::selected", self._on_font_scale_changed)
        font_group.add(self.font_scale_row)

        # 3. Defaults & Reset Group
        reset_group = Adw.PreferencesGroup()
        page.add(reset_group)

        reset_row = Adw.ActionRow(
            title="恢复默认配置",
            subtitle="还原为经典翡翠墨绿主题与标准字号",
        )
        reset_btn = Gtk.Button(label="恢复默认", valign=Gtk.Align.CENTER)
        reset_btn.add_css_class("flat")
        reset_btn.connect("clicked", lambda *_: self._on_reset_defaults())
        reset_row.add_suffix(reset_btn)
        reset_group.add(reset_row)

    def _sync_ui_from_settings(self, settings: AppSettings) -> None:
        self._updating_ui = True
        try:
            # Sync swatch selection indicator
            current_hex = settings.theme_color.lower()
            for hex_code, btn in self._swatch_buttons:
                if hex_code.lower() == current_hex:
                    btn.set_icon_name("object-select-symbolic")
                else:
                    btn.set_icon_name("")

            # Sync color dialog button
            rgba = Gdk.RGBA()
            if rgba.parse(settings.theme_color):
                self.color_dialog_btn.set_rgba(rgba)

            # Sync desktop theme combo
            if settings.desktop_theme in self._desktop_theme_keys:
                idx = self._desktop_theme_keys.index(settings.desktop_theme)
                self.desktop_theme_row.set_selected(idx)

            current_bg = settings.bg_color.lower()
            for hex_code, btn in self._bg_swatch_buttons:
                btn.set_icon_name("object-select-symbolic" if hex_code.lower() == current_bg else "")
            bg_rgba = Gdk.RGBA()
            if bg_rgba.parse(settings.bg_color):
                self.bg_color_dialog_btn.set_rgba(bg_rgba)
            self.bg_type_row.set_selected(self._bg_type_keys.index(settings.bg_type))
            self.bg_opacity_scale.set_value(settings.bg_opacity)
            self.bg_image_label.set_text(Path(settings.bg_image_path).name if settings.bg_image_path else "未选择")
            self.bg_image_button.set_label("更换图片…" if settings.bg_image_path else "选择图片…")
            self.bg_clear_button.set_sensitive(bool(settings.bg_image_path))

            # Sync font scale combo
            closest_idx = min(
                range(len(self._font_scales)),
                key=lambda i: abs(self._font_scales[i] - settings.font_scale),
            )
            self.font_scale_row.set_selected(closest_idx)
        finally:
            self._updating_ui = False

    def _on_preset_clicked(self, hex_code: str) -> None:
        if self._updating_ui:
            return
        self.manager.update(theme_color=hex_code)
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _on_custom_color_chosen(self, btn, _pspec) -> None:
        if self._updating_ui:
            return
        rgba = btn.get_rgba()
        r = int(round(rgba.red * 255))
        g = int(round(rgba.green * 255))
        b = int(round(rgba.blue * 255))
        hex_code = f"#{r:02x}{g:02x}{b:02x}"
        self.manager.update(theme_color=hex_code)
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _on_desktop_theme_changed(self, row, _pspec) -> None:
        if self._updating_ui:
            return
        idx = row.get_selected()
        if 0 <= idx < len(self._desktop_theme_keys):
            theme_key = self._desktop_theme_keys[idx]
            self.manager.update(desktop_theme=theme_key)
            apply_theme(self.manager.current)

    def _on_bg_type_changed(self, row, _pspec) -> None:
        if self._updating_ui:
            return
        self.manager.update(bg_type=self._bg_type_keys[row.get_selected()])
        apply_theme(self.manager.current)

    def _on_bg_preset_clicked(self, hex_code: str) -> None:
        if self._updating_ui:
            return
        self.manager.update(bg_color=hex_code, bg_type="color")
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _on_bg_custom_color_chosen(self, btn, _pspec) -> None:
        if self._updating_ui:
            return
        rgba = btn.get_rgba()
        hex_code = f"#{round(rgba.red * 255):02x}{round(rgba.green * 255):02x}{round(rgba.blue * 255):02x}"
        self.manager.update(bg_color=hex_code, bg_type="color")
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _on_bg_opacity_changed(self, scale) -> None:
        if self._updating_ui:
            return
        self.manager.update(bg_opacity=round(scale.get_value(), 2))
        apply_theme(self.manager.current)

    def _choose_background_image(self, _button) -> None:
        dialog = Gtk.FileDialog(title="选择日历背景图片")
        image_filter = Gtk.FileFilter()
        image_filter.set_name("图片文件")
        image_filter.add_mime_type("image/png")
        image_filter.add_mime_type("image/jpeg")
        image_filter.add_mime_type("image/webp")
        image_filter.add_mime_type("image/gif")
        dialog.set_default_filter(image_filter)
        dialog.open(self, None, self._background_image_chosen, None)

    def _background_image_chosen(self, dialog, result, _data) -> None:
        try:
            selected = dialog.open_finish(result)
        except GLib.Error:
            return
        self.manager.update(bg_image_path=selected.get_path(), bg_type="image")
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _clear_background_image(self, _button) -> None:
        self.manager.update(bg_image_path="", bg_type="color")
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)

    def _on_font_scale_changed(self, row, _pspec) -> None:
        if self._updating_ui:
            return
        idx = row.get_selected()
        if 0 <= idx < len(self._font_scales):
            scale = self._font_scales[idx]
            self.manager.update(font_scale=scale)
            apply_theme(self.manager.current)

    def _on_reset_defaults(self) -> None:
        self.manager.reset_to_defaults()
        apply_theme(self.manager.current)
        self._sync_ui_from_settings(self.manager.current)


def open_settings_dialog(parent: Gtk.Window | None = None) -> SettingsDialog:
    dlg = SettingsDialog(parent=parent)
    dlg.present()
    return dlg
