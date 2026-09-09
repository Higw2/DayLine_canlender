"""Outlook-style day timeline layout and GTK rendering.

The layout functions are deliberately independent from GTK so event geometry
can be checked without starting a desktop session.
"""

from __future__ import annotations

import heapq
import math
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Callable, Iterable

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk

from .storage import Event


PX_PER_MINUTE = 1
DAY_MINUTES = 24 * 60
DAY_HEIGHT = DAY_MINUTES * PX_PER_MINUTE
MIN_EVENT_HEIGHT = 32
TIME_GUTTER_WIDTH = 64
TIMELINE_MIN_WIDTH = 460
CLOCK_REFRESH_SECONDS = 60
SELECTION_STEP_MINUTES = 15


@dataclass(frozen=True)
class ClippedEvent:
    """An event's half-open interval after clipping it to one calendar day."""

    event: Event
    starts_at: datetime
    ends_at: datetime

    @property
    def start(self) -> datetime:
        return self.starts_at

    @property
    def end(self) -> datetime:
        return self.ends_at

    @property
    def start_minute(self) -> int:
        return int((self.starts_at - datetime.combine(self.starts_at.date(), time.min)).total_seconds() // 60)

    @property
    def end_minute(self) -> int:
        return int((self.ends_at - datetime.combine(self.starts_at.date(), time.min)).total_seconds() // 60)

    @property
    def duration_minutes(self) -> int:
        return self.end_minute - self.start_minute


@dataclass(frozen=True)
class EventPlacement:
    """A clipped event and its horizontal overlap column."""

    event: Event
    starts_at: datetime
    ends_at: datetime
    column: int
    columns: int

    @property
    def start(self) -> datetime:
        return self.starts_at

    @property
    def end(self) -> datetime:
        return self.ends_at

    @property
    def column_index(self) -> int:
        return self.column

    @property
    def column_count(self) -> int:
        return self.columns

    @property
    def start_minute(self) -> int:
        return int((self.starts_at - datetime.combine(self.starts_at.date(), time.min)).total_seconds() // 60)

    @property
    def end_minute(self) -> int:
        return int((self.ends_at - datetime.combine(self.starts_at.date(), time.min)).total_seconds() // 60)

    @property
    def duration_minutes(self) -> int:
        return self.end_minute - self.start_minute


def clip_event_to_day(event: Event, day: date) -> ClippedEvent | None:
    """Return the event's overlap with ``day`` as a half-open interval.

    Events ending exactly at midnight are excluded from the following day,
    while events starting exactly at midnight are included in that day.
    """

    day_start = datetime.combine(day, time.min)
    day_end = day_start + timedelta(days=1)
    if event.starts_at >= day_end or event.ends_at <= day_start:
        return None
    return ClippedEvent(event, max(event.starts_at, day_start), min(event.ends_at, day_end))


def _visual_end(item: ClippedEvent) -> datetime:
    """Give short events a usable card height for overlap calculation."""

    return max(item.ends_at, item.starts_at + timedelta(minutes=MIN_EVENT_HEIGHT))


def assign_overlap_columns(events: Iterable[ClippedEvent]) -> list[EventPlacement]:
    """Assign stable overlap columns using connected components and a min heap.

    Endpoints are half-open: an event ending at 10:00 releases its column for
    an event beginning at 10:00.  The minimum visual duration is considered
    while assigning columns so short cards cannot paint over the next card.
    Each connected overlap component receives its own column count.
    """

    ordered = sorted(events, key=lambda item: (item.starts_at, item.ends_at, item.event.id))
    placements: list[EventPlacement] = []
    index = 0
    while index < len(ordered):
        component: list[ClippedEvent] = [ordered[index]]
        component_end = _visual_end(ordered[index])
        index += 1
        while index < len(ordered) and ordered[index].starts_at < component_end:
            item = ordered[index]
            component.append(item)
            component_end = max(component_end, _visual_end(item))
            index += 1

        # (visual end, column) makes the earliest available column win; the
        # second value also keeps placement deterministic when ends tie.
        active: list[tuple[datetime, int]] = []
        free_columns: list[int] = []
        component_placements: list[EventPlacement] = []
        next_column = 0
        for item in component:
            while active and active[0][0] <= item.starts_at:
                _, released = heapq.heappop(active)
                heapq.heappush(free_columns, released)
            column = heapq.heappop(free_columns) if free_columns else next_column
            next_column = max(next_column, column + 1)
            heapq.heappush(active, (_visual_end(item), column))
            component_placements.append(EventPlacement(item.event, item.starts_at, item.ends_at, column, 1))
        columns = next_column
        placements.extend(
            EventPlacement(item.event, item.starts_at, item.ends_at, item.column, columns)
            for item in component_placements
        )
    return placements


def selection_range(start_y: float, current_y: float) -> tuple[int, int]:
    """Convert a vertical drag into a 15-minute, half-open time range."""

    first = max(0, min(DAY_MINUTES, start_y / PX_PER_MINUTE))
    second = max(0, min(DAY_MINUTES, current_y / PX_PER_MINUTE))
    start = math.floor(min(first, second) / SELECTION_STEP_MINUTES) * SELECTION_STEP_MINUTES
    end = math.ceil(max(first, second) / SELECTION_STEP_MINUTES) * SELECTION_STEP_MINUTES
    start = min(start, DAY_MINUTES - SELECTION_STEP_MINUTES)
    end = min(DAY_MINUTES, max(end, start + SELECTION_STEP_MINUTES))
    return start, end


def format_minute(minute: int) -> str:
    """Format a minute offset, keeping the end-of-day value as 24:00."""

    return "24:00" if minute == DAY_MINUTES else f"{minute // 60:02d}:{minute % 60:02d}"


class TimelineCanvas(Gtk.Overlay):
    """A 24-hour, minute-positioned canvas with interactive event cards."""

    def __init__(
        self,
        card_factory: Callable[[Event, int], Gtk.Widget] | None = None,
        range_selected: Callable[[int, int], None] | None = None,
    ):
        super().__init__()
        self.card_factory = card_factory
        self.range_selected = range_selected
        self.day: date = date.today()
        self.placements: list[EventPlacement] = []
        self._clock_source_id = 0
        self._drag_start_y: float | None = None
        self.set_size_request(TIMELINE_MIN_WIDTH, DAY_HEIGHT)
        self.set_hexpand(True)
        self.set_vexpand(True)
        self.set_tooltip_text("在空白处拖拽选择时间并创建事件")

        self.grid = Gtk.Fixed()
        self.grid.add_css_class("timeline-grid")
        self.grid.set_size_request(TIMELINE_MIN_WIDTH, DAY_HEIGHT)
        self.grid.set_hexpand(True)
        self.grid.set_vexpand(True)
        self.set_child(self.grid)

        self._horizontal_lines: list[Gtk.Widget] = []
        for minute in range(0, DAY_MINUTES + 1, 30):
            line = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
            line.add_css_class("timeline-hour-line" if minute % 60 == 0 else "timeline-half-line")
            self.grid.put(line, TIME_GUTTER_WIDTH, minute * PX_PER_MINUTE)
            self._horizontal_lines.append(line)
        self._vertical_line = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self._vertical_line.add_css_class("timeline-gutter-line")
        self.grid.put(self._vertical_line, TIME_GUTTER_WIDTH, 0)
        self._hour_labels: list[Gtk.Label] = []
        for hour in range(24):
            label = Gtk.Label(label=f"{hour:02d}:00", xalign=1, valign=Gtk.Align.START)
            label.add_css_class("timeline-hour-label")
            self.grid.put(label, 8, hour * 60 + 8)
            self._hour_labels.append(label)
        self._now_line = Gtk.Box()
        self._now_line.add_css_class("timeline-now-line")
        self.grid.put(self._now_line, TIME_GUTTER_WIDTH, 0)
        self._now_dot = Gtk.Label(label="●")
        self._now_dot.add_css_class("timeline-now-dot")
        self.grid.put(self._now_dot, TIME_GUTTER_WIDTH - 6, 0)

        self.cards = Gtk.Fixed()
        self.cards.set_size_request(TIMELINE_MIN_WIDTH, DAY_HEIGHT)
        self.cards.set_hexpand(True)
        self.cards.set_vexpand(True)
        self.add_overlay(self.cards)

        self.selection_layer = Gtk.Fixed()
        self.selection_layer.set_can_target(False)
        self.selection_layer.set_size_request(TIMELINE_MIN_WIDTH, DAY_HEIGHT)
        self.selection_layer.set_hexpand(True)
        self.selection_layer.set_vexpand(True)
        self.selection_box = Gtk.Box()
        self.selection_box.add_css_class("timeline-selection")
        self.selection_box.set_visible(False)
        self.selection_label = Gtk.Label()
        self.selection_label.add_css_class("timeline-selection-label")
        self.selection_label.set_visible(False)
        self.selection_layer.put(self.selection_box, TIME_GUTTER_WIDTH + 4, 0)
        self.selection_layer.put(self.selection_label, TIME_GUTTER_WIDTH + 12, 2)
        self.add_overlay(self.selection_layer)

        drag = Gtk.GestureDrag(button=1)
        drag.connect("drag-begin", self._drag_begin)
        drag.connect("drag-update", self._drag_update)
        drag.connect("drag-end", self._drag_end)
        self.add_controller(drag)
        self.connect("notify::width", self._width_changed)
        self.connect("map", self._on_map)
        self.connect("unmap", self._on_unmap)

    def _on_map(self, _widget) -> None:
        if not self._clock_source_id:
            self._clock_source_id = GLib.timeout_add_seconds(CLOCK_REFRESH_SECONDS, self._refresh_clock)

    def _on_unmap(self, _widget) -> None:
        if self._clock_source_id:
            GLib.source_remove(self._clock_source_id)
            self._clock_source_id = 0

    def _refresh_clock(self) -> bool:
        self._update_now_line()
        return True

    def _drag_begin(self, gesture: Gtk.GestureDrag, start_x: float, start_y: float) -> None:
        if start_x <= TIME_GUTTER_WIDTH or self._point_is_event_card(start_x, start_y):
            gesture.set_state(Gtk.EventSequenceState.DENIED)
            return
        self._drag_start_y = start_y
        self._show_selection(*selection_range(start_y, start_y))

    def _drag_update(self, _gesture: Gtk.GestureDrag, offset_x: float, offset_y: float) -> None:
        if self._drag_start_y is None:
            return
        self._show_selection(*selection_range(self._drag_start_y, self._drag_start_y + offset_y))

    def _drag_end(self, _gesture: Gtk.GestureDrag, offset_x: float, offset_y: float) -> None:
        if self._drag_start_y is None:
            return
        start, end = selection_range(self._drag_start_y, self._drag_start_y + offset_y)
        self._drag_start_y = None
        self.selection_box.set_visible(False)
        self.selection_label.set_visible(False)
        if self.range_selected:
            self.range_selected(start, end)

    def _point_is_event_card(self, x: float, y: float) -> bool:
        widget = self.pick(x, y, Gtk.PickFlags.DEFAULT)
        while widget and widget is not self:
            if widget.get_parent() is self.cards:
                return True
            widget = widget.get_parent()
        return False

    def _show_selection(self, start: int, end: int) -> None:
        width = max(self.get_width(), TIMELINE_MIN_WIDTH) - TIME_GUTTER_WIDTH - 8
        y = start * PX_PER_MINUTE
        self.selection_box.set_size_request(width, (end - start) * PX_PER_MINUTE)
        self.selection_layer.move(self.selection_box, TIME_GUTTER_WIDTH + 4, y)
        self.selection_label.set_text(f"{format_minute(start)} – {format_minute(end)}")
        self.selection_layer.move(self.selection_label, TIME_GUTTER_WIDTH + 12, y + 2)
        self.selection_box.set_visible(True)
        self.selection_label.set_visible(True)

    def set_events(self, events: Iterable[Event], day: date) -> None:
        self.day = day
        clipped = [item for event in events if (item := clip_event_to_day(event, day)) is not None]
        self.placements = assign_overlap_columns(clipped)
        self._clear_cards()
        for placement in self.placements:
            if self.card_factory is None:
                continue
            card = self.card_factory(placement.event, placement.duration_minutes)
            card.set_valign(Gtk.Align.START)
            card.set_halign(Gtk.Align.START)
            card.set_size_request(-1, max(MIN_EVENT_HEIGHT, placement.duration_minutes * PX_PER_MINUTE))
            self.cards.put(card, 0, placement.start_minute * PX_PER_MINUTE)
        self._layout_cards()
        self._layout_grid()
        self._update_now_line()

    def _clear_cards(self) -> None:
        child = self.cards.get_first_child()
        while child:
            following = child.get_next_sibling()
            self.cards.remove(child)
            child = following

    def _width_changed(self, *_args) -> None:
        self._layout_grid()
        self._layout_cards()

    def _layout_grid(self) -> None:
        width = max(self.get_width(), TIMELINE_MIN_WIDTH)
        line_width = max(1, width - TIME_GUTTER_WIDTH)
        for minute, line in zip(range(0, DAY_MINUTES + 1, 30), self._horizontal_lines):
            line.set_size_request(line_width, 1)
            self.grid.move(line, TIME_GUTTER_WIDTH, minute * PX_PER_MINUTE)
        self._vertical_line.set_size_request(1, DAY_HEIGHT)
        self.grid.move(self._vertical_line, TIME_GUTTER_WIDTH, 0)
        for hour, label in enumerate(self._hour_labels):
            label.set_size_request(TIME_GUTTER_WIDTH - 12, 24)
            self.grid.move(label, 8, hour * 60 + 8)
        self._now_line.set_size_request(line_width, 2)

    def _update_now_line(self) -> None:
        visible = self.day == datetime.now().date()
        self._now_line.set_visible(visible)
        self._now_dot.set_visible(visible)
        if visible:
            now = datetime.now()
            minute = int(now.hour * 60 + now.minute + now.second / 60)
            self.grid.move(self._now_line, TIME_GUTTER_WIDTH, minute * PX_PER_MINUTE)
            self.grid.move(self._now_dot, TIME_GUTTER_WIDTH - 6, max(0, minute - 8))

    def _layout_cards(self) -> None:
        width = max(self.get_width(), TIMELINE_MIN_WIDTH)
        content_width = width - TIME_GUTTER_WIDTH
        child = self.cards.get_first_child()
        for placement in self.placements:
            if child is None:
                break
            column_width = content_width / placement.columns
            x = TIME_GUTTER_WIDTH + placement.column * column_width + 4
            card_width = max(44, column_width - 8)
            child.set_size_request(int(card_width), max(MIN_EVENT_HEIGHT, placement.duration_minutes * PX_PER_MINUTE))
            self.cards.move(child, int(x), placement.start_minute * PX_PER_MINUTE)
            child = child.get_next_sibling()
