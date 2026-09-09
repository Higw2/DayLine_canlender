import json
import tempfile
import unittest
from pathlib import Path

from dayline.settings import AppSettings, SettingsManager
from dayline.theme import (
    BACKGROUND_PALETTE,
    FONT_SCALE_OPTIONS,
    PRESET_PALETTE,
    adjust_color_brightness,
    generate_css,
    hex_to_rgba_css,
    parse_hex_color,
)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp.name) / "settings.json"

    def tearDown(self):
        self.temp.cleanup()

    def test_default_settings(self):
        settings = AppSettings()
        self.assertEqual(settings.theme_color, "#28735f")
        self.assertEqual(settings.font_scale, 1.0)
        self.assertEqual(settings.desktop_theme, "dark")
        self.assertEqual(settings.bg_color, "#1e242b")
        self.assertEqual(settings.bg_opacity, 0.90)
        self.assertEqual(settings.bg_image_path, "")
        self.assertEqual(settings.bg_type, "color")

    def test_load_and_save_settings(self):
        manager = SettingsManager(self.config_path)
        self.assertEqual(manager.current.theme_color, "#28735f")

        manager.update(theme_color="#2563eb", font_scale=1.15, desktop_theme="tinted", bg_color="#2d3748", bg_opacity=0.75, bg_image_path="/tmp/background.png", bg_type="image")
        self.assertTrue(self.config_path.is_file())

        # Load fresh in another manager instance
        manager2 = SettingsManager(self.config_path)
        self.assertEqual(manager2.current.theme_color, "#2563eb")
        self.assertEqual(manager2.current.font_scale, 1.15)
        self.assertEqual(manager2.current.desktop_theme, "tinted")
        self.assertEqual(manager2.current.bg_color, "#2d3748")
        self.assertEqual(manager2.current.bg_opacity, 0.75)
        self.assertEqual(manager2.current.bg_image_path, "/tmp/background.png")
        self.assertEqual(manager2.current.bg_type, "image")

    def test_listener_notification(self):
        manager = SettingsManager(self.config_path)
        notified = []

        def on_change(settings):
            notified.append(settings.theme_color)

        manager.add_listener(on_change)
        manager.update(theme_color="#7c3aed")
        self.assertEqual(notified, ["#7c3aed"])

        manager.remove_listener(on_change)
        manager.update(theme_color="#ea580c")
        self.assertEqual(len(notified), 1)

    def test_invalid_settings_fallback(self):
        self.config_path.write_text("invalid json content!", encoding="utf-8")
        manager = SettingsManager(self.config_path)
        self.assertEqual(manager.current.theme_color, "#28735f")

        # Invalid field types in json
        self.config_path.write_text(json.dumps({"theme_color": "not-a-color", "font_scale": 99.0, "desktop_theme": "xyz"}), encoding="utf-8")
        manager2 = SettingsManager(self.config_path)
        self.assertEqual(manager2.current.theme_color, "#28735f")
        self.assertIn(manager2.current.font_scale, {0.9, 1.0, 1.15, 1.3})
        self.assertEqual(manager2.current.desktop_theme, "dark")

    def test_reset_to_defaults(self):
        manager = SettingsManager(self.config_path)
        manager.update(theme_color="#db2777", font_scale=1.3, desktop_theme="light")
        manager.reset_to_defaults()
        self.assertEqual(manager.current.theme_color, "#28735f")
        self.assertEqual(manager.current.font_scale, 1.0)
        self.assertEqual(manager.current.desktop_theme, "dark")
        self.assertEqual(manager.current.bg_type, "color")

    def test_background_settings_are_clamped_and_share_mac_keys(self):
        settings = AppSettings.from_dict({"bg_color": "#abc", "bg_opacity": 2, "bg_image_path": "/tmp/wallpaper.jpg", "bg_type": "image"})
        self.assertEqual(settings.bg_color, "#abc")
        self.assertEqual(settings.bg_opacity, 1.0)
        self.assertEqual(settings.bg_image_path, "/tmp/wallpaper.jpg")
        self.assertEqual(settings.bg_type, "image")
        self.assertEqual(AppSettings.from_dict({"theme_color": "#ggg"}).theme_color, "#28735f")
        self.assertEqual(AppSettings.from_dict({"bg_color": "#12x456"}).bg_color, "#1e242b")
        self.assertEqual(AppSettings.from_dict({"bg_opacity": 0.05}).bg_opacity, 0.1)


class ThemeTests(unittest.TestCase):
    def test_palette_and_font_scales(self):
        self.assertGreaterEqual(len(PRESET_PALETTE), 6)
        self.assertIn("#28735f", [p.hex_code for p in PRESET_PALETTE])
        scales = [s for _, s in FONT_SCALE_OPTIONS]
        self.assertIn(1.0, scales)
        self.assertIn(0.9, scales)
        self.assertEqual(len(BACKGROUND_PALETTE), 7)

    def test_color_math(self):
        r, g, b = parse_hex_color("#28735f")
        self.assertEqual((r, g, b), (40, 115, 95))
        rgba = hex_to_rgba_css("#28735f", 0.5)
        self.assertIn("rgba(40, 115, 95, 0.50)", rgba)

        brighter = adjust_color_brightness("#28735f", 1.2)
        self.assertTrue(brighter.startswith("#"))
        self.assertEqual(len(brighter), 7)

    def test_css_generation_with_custom_color_and_scale(self):
        settings = AppSettings(theme_color="#2563eb", font_scale=1.15, desktop_theme="tinted")
        css = generate_css(settings)
        self.assertIn("#2563eb", css)
        self.assertIn("desktop-drag-area", css)
        self.assertIn("desktop-drag-grip", css)
        self.assertIn("desktop-drag-time", css)
        self.assertIn("upcoming-mini-card", css)

    def test_css_generation_light_desktop_theme(self):
        settings = AppSettings(desktop_theme="light")
        css = generate_css(settings)
        self.assertIn("#ffffff", css)
        self.assertIn("desktop-widget", css)
        self.assertIn("desktop-drag-time", css)
        self.assertIn("desktop-resize-handle", css)
        self.assertIn("desktop-events-scroll", css)
        # Verify light theme uses dark text for event title
        self.assertIn(".desktop-event {\n    color: #111827;", css)


if __name__ == "__main__":
    unittest.main()
