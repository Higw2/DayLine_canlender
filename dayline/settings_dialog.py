"""Modern preferences window for Dayline using Libadwaita."""

from __future__ import annotations

import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gtk

from .settings import AppSettings, get_settings_manager
from .theme import FONT_SCALE_OPTIONS, PRESET_PALETTE, apply_theme


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
