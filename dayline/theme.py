"""Dynamic theme styling and CSS generation for Dayline."""

from __future__ import annotations

import colorsys
from typing import NamedTuple

import gi
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, Gtk

from .settings import AppSettings


class PaletteColor(NamedTuple):
    name: str
    hex_code: str


PRESET_PALETTE: list[PaletteColor] = [
    PaletteColor("经典翡翠", "#28735f"),
    PaletteColor("曜石深蓝", "#2563eb"),
    PaletteColor("极光青碧", "#0d9488"),
    PaletteColor("典雅紫罗兰", "#7c3aed"),
    PaletteColor("活力珊瑚橙", "#ea580c"),
    PaletteColor("蔷薇洋红", "#e11d48"),
    PaletteColor("暖阳金棕", "#d97706"),
    PaletteColor("极简石板灰", "#475569"),
]

FONT_SCALE_OPTIONS: list[tuple[str, float]] = [
    ("小 (90%)", 0.9),
    ("标准 (100%)", 1.0),
    ("大 (115%)", 1.15),
    ("特大 (130%)", 1.3),
]


def parse_hex_color(hex_str: str) -> tuple[int, int, int]:
    clean = hex_str.strip().lstrip("#")
    if len(clean) == 3:
        clean = "".join(c * 2 for c in clean)
    elif len(clean) > 6:
        clean = clean[:6]
    try:
        val = int(clean, 16)
        return (val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF
    except ValueError:
        return 40, 115, 95  # Fallback to #28735f


def hex_to_rgba_css(hex_str: str, alpha: float) -> str:
    r, g, b = parse_hex_color(hex_str)
    return f"rgba({r}, {g}, {b}, {alpha:.2f})"


def adjust_color_brightness(hex_str: str, factor: float) -> str:
    r, g, b = parse_hex_color(hex_str)
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    new_l = max(0.0, min(1.0, l * factor))
    nr, ng, nb = colorsys.hls_to_rgb(h, new_l, s)
    return f"#{int(nr * 255):02x}{int(ng * 255):02x}{int(nb * 255):02x}"


def get_contrast_text(hex_str: str) -> str:
    r, g, b = parse_hex_color(hex_str)
    # W3C relative luminance approximation
    luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    return "#111827" if luminance > 0.6 else "#ffffff"


def generate_css(settings: AppSettings) -> str:
    scale = settings.font_scale
    theme = settings.theme_color
    hover_theme = adjust_color_brightness(theme, 0.88)
    active_theme = adjust_color_brightness(theme, 0.76)
    lighter_theme = adjust_color_brightness(theme, 1.25)
    card_tint_bg = hex_to_rgba_css(theme, 0.08)
    card_tint_hover = hex_to_rgba_css(theme, 0.14)
    btn_text = get_contrast_text(theme)

    # Scaled font sizes (px)
    def fs(base: int) -> int:
        return max(9, int(round(base * scale)))

    # Desktop widget background by style
    # Desktop widget styling by theme
    if settings.desktop_theme == "tinted":
        r, g, b = parse_hex_color(theme)
        desktop_bg = f"rgba({max(12, int(r * 0.18))}, {max(16, int(g * 0.18))}, {max(18, int(b * 0.18))}, 0.94)"
        desktop_fg = "#f8f8f2"
        desktop_time_fg = lighter_theme
        desktop_shadow = "0 16px 36px rgba(0, 0, 0, 0.36)"
        desktop_drag_bg = "rgba(255, 255, 255, 0.10)"
        desktop_drag_hover = "rgba(255, 255, 255, 0.18)"
        desktop_drag_active = "rgba(255, 255, 255, 0.26)"
        desktop_drag_time_fg = lighter_theme
        desktop_drag_time_hover_fg = "#ffffff"
        desktop_border = "rgba(255, 255, 255, 0.14)"
        desktop_brand_fg = "#ffffff"
        desktop_date_fg = "rgba(255, 255, 255, 0.75)"
        desktop_subtitle_fg = "rgba(255, 255, 255, 0.65)"
        desktop_event_row_bg = "rgba(255, 255, 255, 0.06)"
        desktop_event_row_border = "rgba(255, 255, 255, 0.05)"
        desktop_event_row_hover_bg = "rgba(255, 255, 255, 0.12)"
        desktop_event_row_hover_border = "rgba(255, 255, 255, 0.15)"
        desktop_event_fg = "#ffffff"
        desktop_event_detail_fg = "rgba(255, 255, 255, 0.60)"
        desktop_action_btn_bg = "rgba(255, 255, 255, 0.10)"
        desktop_action_btn_border = "rgba(255, 255, 255, 0.10)"
        desktop_action_btn_fg = "#ffffff"
        desktop_action_btn_hover_bg = "rgba(255, 255, 255, 0.18)"
        desktop_action_btn_hover_border = "rgba(255, 255, 255, 0.25)"
        desktop_time_pill_bg = hex_to_rgba_css(theme, 0.28)
        desktop_time_pill_fg = lighter_theme
    elif settings.desktop_theme == "light":
        desktop_bg = "#ffffff"
        desktop_fg = "#1f2937"
        desktop_time_fg = theme
        desktop_fg = "#111827"
        desktop_shadow = "0 12px 30px rgba(0, 0, 0, 0.12)"
        desktop_drag_bg = "rgba(0, 0, 0, 0.04)"
        desktop_drag_hover = "rgba(0, 0, 0, 0.08)"
        desktop_drag_active = "rgba(0, 0, 0, 0.14)"
        desktop_drag_time_fg = theme
        desktop_drag_time_hover_fg = hover_theme
        desktop_border = "rgba(0, 0, 0, 0.10)"
        desktop_brand_fg = "#111827"
        desktop_date_fg = "#4b5563"
        desktop_subtitle_fg = "#4b5563"
        desktop_event_row_bg = "rgba(0, 0, 0, 0.03)"
        desktop_event_row_border = "rgba(0, 0, 0, 0.06)"
        desktop_event_row_hover_bg = "rgba(0, 0, 0, 0.07)"
        desktop_event_row_hover_border = "rgba(0, 0, 0, 0.12)"
        desktop_event_fg = "#111827"
        desktop_event_detail_fg = "#6b7280"
        desktop_action_btn_bg = "rgba(0, 0, 0, 0.05)"
        desktop_action_btn_border = "rgba(0, 0, 0, 0.09)"
        desktop_action_btn_fg = "#374151"
        desktop_action_btn_hover_bg = "rgba(0, 0, 0, 0.10)"
        desktop_action_btn_hover_border = "rgba(0, 0, 0, 0.18)"
        desktop_time_pill_bg = hex_to_rgba_css(theme, 0.12)
        desktop_time_pill_fg = theme
    else:  # dark (default)
        desktop_bg = "#182220"
        desktop_fg = "#f8f8f2"
        desktop_time_fg = lighter_theme
        desktop_shadow = "0 16px 36px rgba(0, 0, 0, 0.36)"
        desktop_drag_bg = "rgba(255, 255, 255, 0.09)"
        desktop_drag_hover = "rgba(255, 255, 255, 0.16)"
        desktop_drag_active = "rgba(255, 255, 255, 0.24)"
        desktop_drag_time_fg = lighter_theme
        desktop_drag_time_hover_fg = "#ffffff"
        desktop_border = "rgba(255, 255, 255, 0.12)"
        desktop_brand_fg = "#ffffff"
        desktop_date_fg = "rgba(255, 255, 255, 0.75)"
        desktop_subtitle_fg = "rgba(255, 255, 255, 0.65)"
        desktop_event_row_bg = "rgba(255, 255, 255, 0.06)"
        desktop_event_row_border = "rgba(255, 255, 255, 0.05)"
        desktop_event_row_hover_bg = "rgba(255, 255, 255, 0.12)"
        desktop_event_row_hover_border = "rgba(255, 255, 255, 0.15)"
        desktop_event_fg = "#ffffff"
        desktop_event_detail_fg = "rgba(255, 255, 255, 0.60)"
        desktop_action_btn_bg = "rgba(255, 255, 255, 0.10)"
        desktop_action_btn_border = "rgba(255, 255, 255, 0.10)"
        desktop_action_btn_fg = "#ffffff"
        desktop_action_btn_hover_bg = "rgba(255, 255, 255, 0.18)"
        desktop_action_btn_hover_border = "rgba(255, 255, 255, 0.25)"
        desktop_time_pill_bg = hex_to_rgba_css(theme, 0.28)
        desktop_time_pill_fg = lighter_theme

    css = f"""
/* Root & Window */
window {{
    background: #f8faf9;
    color: #1f2937;
    font-size: {fs(13)}px;
}}
.main-window .titlebar {{
    background: #fbfbfe;
    border-bottom: 1px solid #e5e7eb;
}}

/* Sidebar */
.sidebar {{
    background: #edf1e9;
    border-right: 1px solid #d8dfd4;
    padding: 14px;
}}
.brand {{
    font-size: {fs(20)}px;
    font-weight: 800;
    color: {theme};
    letter-spacing: -0.3px;
}}
.section-title {{
    font-size: {fs(12)}px;
    font-weight: 700;
    color: #4b5563;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}}
.sidebar-today-btn {{
    border-radius: 8px;
    font-weight: 600;
    font-size: {fs(13)}px;
}}
.sidebar-today-btn:hover {{
    background: {card_tint_hover};
    color: {theme};
}}
.upcoming-mini-card {{
    background: rgba(255, 255, 255, 0.70);
    border-radius: 8px;
    padding: 6px 9px;
    border: 1px solid rgba(0, 0, 0, 0.05);
}}
.upcoming-mini-card:hover {{
    background: #ffffff;
    border-color: {theme};
}}
.upcoming-mini-time {{
    font-size: {fs(11)}px;
    font-weight: 700;
    color: {theme};
}}
.upcoming-mini-title {{
    font-size: {fs(12)}px;
    color: #1f2937;
}}

/* Main Header & Date Bar */
.date-title {{
    font-size: {fs(23)}px;
    font-weight: 800;
    letter-spacing: -0.4px;
    color: #111827;
}}
.stat {{
    font-size: {fs(12)}px;
    color: {theme};
    background: {card_tint_bg};
    border: 1px solid {hex_to_rgba_css(theme, 0.20)};
    border-radius: 999px;
    padding: 3px 10px;
    font-weight: 600;
}}
.eyebrow {{
    font-size: {fs(12)}px;
    font-weight: 800;
    color: {theme};
    text-transform: uppercase;
    letter-spacing: 0.5px;
}}

/* Primary Buttons & Actions */
button.suggested-action,
button.suggested-action:hover,
button.suggested-action:active {{
    background: {theme};
    color: {btn_text};
    border-radius: 8px;
    font-weight: 700;
    font-size: {fs(13)}px;
    padding: 6px 14px;
    border: none;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}}
button.suggested-action:hover {{
    background: {hover_theme};
    box-shadow: 0 3px 8px rgba(0, 0, 0, 0.16);
}}
button.suggested-action:active {{
    background: {active_theme};
}}

.nav-btn {{
    border-radius: 8px;
    padding: 5px 9px;
}}

/* Calendar */
calendar {{
    background: #ffffff;
    color: #1f2937;
    border-radius: 12px;
    padding: 8px;
    border: 1px solid #e5e7eb;
    font-size: {fs(13)}px;
}}
calendar:selected {{
    background: {theme};
    color: {btn_text};
    border-radius: 999px;
    font-weight: bold;
}}
calendar.highlight {{
    color: {theme};
    font-weight: 800;
}}
calendar header button {{
    border-radius: 6px;
    padding: 2px 6px;
}}

/* Timeline Grid */
.timeline {{
    background: #ffffff;
    border-radius: 16px;
    margin: 10px 20px 22px 8px;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.04);
    border: 1px solid #e5e7eb;
}}
.timeline-grid {{
    background: #ffffff;
}}
.timeline-hour-label {{
    color: #9ca3af;
    font-size: {fs(11)}px;
    font-weight: 600;
    font-feature-settings: "tnum";
}}
.timeline-hour-line {{
    background: #e5e7eb;
    min-height: 1px;
}}
.timeline-half-line {{
    background: #f3f4f6;
    min-height: 1px;
}}
.timeline-gutter-line {{
    background: #e5e7eb;
    min-width: 1px;
}}
.timeline-now-line {{
    background: #ef4444;
    min-height: 2px;
}}
.timeline-now-dot {{
    color: #ef4444;
    font-size: {fs(12)}px;
}}

/* Event Cards */
.event-card {{
    background: {card_tint_bg};
    border-left: 4px solid {theme};
    border-radius: 10px;
    padding: 4px 8px;
    margin: 0 6px 0 0;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
    border-top: 1px solid rgba(0, 0, 0, 0.04);
    border-right: 1px solid rgba(0, 0, 0, 0.04);
    border-bottom: 1px solid rgba(0, 0, 0, 0.04);
    transition: background 150ms ease, box-shadow 150ms ease;
}}
.event-card:hover {{
    background: {card_tint_hover};
    box-shadow: 0 3px 8px rgba(0, 0, 0, 0.08);
}}
.event-card button {{
    min-width: 26px;
    min-height: 26px;
    padding: 2px;
    border-radius: 6px;
    background: transparent;
    border: none;
    color: #6b7280;
}}
.event-card button:hover {{
    background: rgba(0, 0, 0, 0.08);
    color: #111827;
}}
.event-card.done {{
    opacity: 0.55;
    background: #f3f4f6;
    border-left-color: #9ca3af;
}}
.event-card.done .event-name {{
    text-decoration: line-through;
    color: #6b7280;
}}
.event-name {{
    font-weight: 700;
    font-size: {fs(13)}px;
    color: #111827;
}}
.event-detail, .muted {{
    color: #6b7280;
    font-size: {fs(11)}px;
}}
.notice {{
    background: #fef3c7;
    color: #92400e;
    border-radius: 8px;
    padding: 8px 12px;
    font-size: {fs(12)}px;
    border: 1px solid #fde68a;
}}

/* Desktop Widget */
.desktop-widget {{
    background: {desktop_bg};
    color: {desktop_fg};
    border-radius: 22px;
    border: 1px solid {desktop_border};
    box-shadow: 0 16px 36px rgba(0, 0, 0, 0.36);
    box-shadow: {desktop_shadow};
}}

/* Desktop Drag Area (Distinct visual indicator for dragging) */
.desktop-drag-area {{
    background: {desktop_drag_bg};
    border: 1px solid {desktop_border};
    border-radius: 14px;
    margin: 12px 14px 4px 14px;
    padding: 6px 12px;
    transition: background 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
}}
.desktop-drag-area:hover {{
    background: {desktop_drag_hover};
    border-color: {hex_to_rgba_css(theme, 0.45)};
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}}
.desktop-drag-area.dragging {{
    background: {desktop_drag_active};
    border-color: {theme};
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.25);
}}
.desktop-drag-grip {{
    color: {desktop_drag_time_fg};
    font-size: {fs(14)}px;
    margin: 0 6px;
}}
.desktop-drag-time {{
    color: {desktop_drag_time_fg};
    font-size: {fs(13)}px;
    font-weight: 700;
    font-feature-settings: "tnum";
    letter-spacing: 0.5px;
}}
.desktop-drag-area:hover .desktop-drag-time {{
    color: {desktop_drag_time_hover_fg};
}}
.desktop-drag-area:hover .desktop-drag-grip {{
    color: {lighter_theme};
}}
.desktop-brand {{
    font-size: {fs(16)}px;
    font-weight: 800;
    color: {desktop_brand_fg};
    letter-spacing: -0.2px;
}}
.desktop-brand-pill {{
    background: {theme};
    color: {btn_text};
    border-radius: 6px;
    padding: 2px 6px;
    font-size: {fs(11)}px;
    font-weight: 800;
}}
.desktop-date {{
    color: {desktop_date_fg};
    font-size: {fs(11)}px;
    font-weight: 500;
}}
.desktop-subtitle {{
    color: {desktop_subtitle_fg};
    font-size: {fs(12)}px;
    font-weight: 600;
}}
.desktop-event-row {{
    background: {desktop_event_row_bg};
    border-radius: 10px;
    padding: 8px 12px;
    margin: 4px 14px;
    border: 1px solid {desktop_event_row_border};
    transition: background 150ms ease;
}}
.desktop-event-row:hover {{
    background: {desktop_event_row_hover_bg};
    border-color: {desktop_event_row_hover_border};
}}
.desktop-time-pill {{
    background: {desktop_time_pill_bg};
    color: {desktop_time_pill_fg};
    font-weight: 800;
    font-size: {fs(12)}px;
    border-radius: 6px;
    padding: 2px 6px;
    min-width: 44px;
}}
.desktop-event {{
    color: {desktop_event_fg};
    font-weight: 700;
    font-size: {fs(13)}px;
}}
.desktop-event-detail {{
    color: {desktop_event_detail_fg};
    font-size: {fs(11)}px;
}}
.desktop-new {{
    background: {theme};
    color: {btn_text};
    border-radius: 8px;
    font-weight: 700;
    padding: 5px 12px;
    border: none;
}}
.desktop-new:hover {{
    background: {hover_theme};
}}
.desktop-action-btn {{
    background: {desktop_action_btn_bg};
    color: {desktop_action_btn_fg};
    border-radius: 8px;
    border: 1px solid {desktop_action_btn_border};
    padding: 5px 10px;
}}
.desktop-action-btn:hover {{
    background: {desktop_action_btn_hover_bg};
    border-color: {desktop_action_btn_hover_border};
}}

/* Reminder Window */
.reminder-window {{
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 16px 36px rgba(0, 0, 0, 0.20);
}}
.reminder-title {{
    font-size: {fs(22)}px;
    font-weight: 800;
    color: #111827;
    letter-spacing: -0.3px;
}}

/* Color Swatch in Settings */
.color-swatch-btn {{
    min-width: 32px;
    min-height: 32px;
    border-radius: 999px;
    padding: 0;
    border: 2px solid transparent;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
}}
.color-swatch-btn:hover {{
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.30);
}}
.color-swatch-btn.selected {{
    border-color: #ffffff;
    outline: 2px solid {theme};
}}
"""
    return css


_global_css_provider: Gtk.CssProvider | None = None


def apply_theme(settings: AppSettings, display: Gdk.Display | None = None) -> Gtk.CssProvider:
    global _global_css_provider
    if _global_css_provider is None:
        _global_css_provider = Gtk.CssProvider()
        disp = display or Gdk.Display.get_default()
        if disp:
            Gtk.StyleContext.add_provider_for_display(
                disp, _global_css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    css_data = generate_css(settings)
    _global_css_provider.load_from_data(css_data.encode("utf-8"))
    return _global_css_provider
