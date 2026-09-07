import unittest
from datetime import date, datetime, timedelta

from dayline.storage import Event
import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GObject, Gtk

from dayline.desktop import DesktopWidget, X11DesktopHints
from dayline.timeline import CLOCK_REFRESH_SECONDS, TimelineCanvas, assign_overlap_columns, clip_event_to_day


DAY = date(2026, 9, 7)


def event(number: int, start: str, end: str) -> Event:
    return Event(number, f"事件 {number}", datetime.fromisoformat(start), datetime.fromisoformat(end))


class TimelineLayoutTests(unittest.TestCase):
    def test_clock_refresh_is_one_minute(self):
        self.assertEqual(CLOCK_REFRESH_SECONDS, 60)

    def test_timeline_uses_gtk_map_lifecycle_signals(self):
        self.assertNotEqual(GObject.signal_lookup("map", TimelineCanvas.__gtype__), 0)
        self.assertNotEqual(GObject.signal_lookup("unmap", TimelineCanvas.__gtype__), 0)

    def test_ewmh_client_message_mask_and_all_desktops_value(self):
        self.assertEqual(X11DesktopHints.SUBSTRUCTURE_NOTIFY_MASK | X11DesktopHints.SUBSTRUCTURE_REDIRECT_MASK, 0x180000)
        self.assertEqual(X11DesktopHints.ALL_DESKTOPS, 0xFFFFFFFF)
        self.assertEqual(X11DesktopHints.ClientMessageEvent._fields_[-1][0], "data")

    def test_clip_keeps_exact_minutes_and_duration(self):
        item = clip_event_to_day(event(1, "2026-09-07 09:17", "2026-09-07 10:43"), DAY)
        self.assertIsNotNone(item)
        self.assertEqual(item.start_minute, 9 * 60 + 17)
        self.assertEqual(item.end_minute - item.start_minute, 86)

    def test_clip_cross_day_event_to_each_half_open_boundary(self):
        item = event(1, "2026-09-06 23:30", "2026-09-08 01:15")
        first = clip_event_to_day(item, date(2026, 9, 6))
        middle = clip_event_to_day(item, DAY)
        last = clip_event_to_day(item, date(2026, 9, 8))
        self.assertEqual((first.start_minute, first.end_minute), (23 * 60 + 30, 24 * 60))
        self.assertEqual((middle.start_minute, middle.end_minute), (0, 24 * 60))
        self.assertEqual((last.start_minute, last.end_minute), (0, 75))
        ends_at_midnight = event(2, "2026-09-06 23:00", "2026-09-07 00:00")
        self.assertIsNone(clip_event_to_day(ends_at_midnight, date(2026, 9, 7)))

    def test_endpoint_touching_events_share_one_column(self):
        items = [
            clip_event_to_day(event(1, "2026-09-07 10:00", "2026-09-07 11:00"), DAY),
            clip_event_to_day(event(2, "2026-09-07 11:00", "2026-09-07 12:00"), DAY),
        ]
        placements = assign_overlap_columns(items)
        self.assertEqual([(item.column, item.columns) for item in placements], [(0, 1), (0, 1)])

    def test_two_overlapping_events_get_two_columns(self):
        items = [
            clip_event_to_day(event(1, "2026-09-07 10:00", "2026-09-07 12:00"), DAY),
            clip_event_to_day(event(2, "2026-09-07 11:00", "2026-09-07 13:00"), DAY),
        ]
        placements = assign_overlap_columns(items)
        self.assertEqual([item.column for item in placements], [0, 1])
        self.assertTrue(all(item.columns == 2 for item in placements))

    def test_three_way_overlap_gets_three_columns(self):
        items = [
            clip_event_to_day(event(1, "2026-09-07 10:00", "2026-09-07 13:00"), DAY),
            clip_event_to_day(event(2, "2026-09-07 11:00", "2026-09-07 12:00"), DAY),
            clip_event_to_day(event(3, "2026-09-07 11:30", "2026-09-07 14:00"), DAY),
        ]
        placements = assign_overlap_columns(items)
        self.assertEqual([item.column for item in placements], [0, 1, 2])
        self.assertTrue(all(item.columns == 3 for item in placements))

    def test_transitive_overlap_uses_one_component_column_count(self):
        items = [
            clip_event_to_day(event(1, "2026-09-07 09:00", "2026-09-07 10:00"), DAY),
            clip_event_to_day(event(2, "2026-09-07 09:30", "2026-09-07 11:00"), DAY),
            clip_event_to_day(event(3, "2026-09-07 10:30", "2026-09-07 12:00"), DAY),
        ]
        placements = assign_overlap_columns(items)
        self.assertEqual([item.columns for item in placements], [2, 2, 2])
        self.assertEqual([item.column for item in placements], [0, 1, 0])

    def test_short_visual_events_do_not_cover_the_next_card(self):
        items = [
            clip_event_to_day(event(1, "2026-09-07 15:00", "2026-09-07 15:05"), DAY),
            clip_event_to_day(event(2, "2026-09-07 15:20", "2026-09-07 15:25"), DAY),
        ]
        placements = assign_overlap_columns(items)
        self.assertEqual([item.columns for item in placements], [2, 2])

    def test_desktop_geometry_load_and_resizability(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as td:
            pos_file = Path(td) / "desktop-position"
            # Test 2-value legacy format
            pos_file.write_text("150,220\n", encoding="utf-8")
            widget = DesktopWidget.__new__(DesktopWidget)
            widget._position_file = pos_file
            geom = widget._load_geometry()
            self.assertEqual(geom, (150, 220, 390, 286))

            # Test 4-value geometry format (with width and height)
            pos_file.write_text("300,400,520,410\n", encoding="utf-8")
            geom4 = widget._load_geometry()
            self.assertEqual(geom4, (300, 400, 520, 410))


if __name__ == "__main__":
    unittest.main()
