"""Persistent event storage.  This module deliberately has no GTK dependency."""

from __future__ import annotations

import sqlite3
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterable


def default_database_path() -> Path:
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return data_home / "dayline" / "events.db"


def as_iso(value: datetime) -> str:
    return value.replace(microsecond=0).isoformat(sep=" ")


def from_iso(value: str) -> datetime:
    return datetime.fromisoformat(value)


@dataclass(frozen=True)
class Event:
    id: int
    title: str
    starts_at: datetime
    ends_at: datetime
    notes: str = ""
    completed: bool = False
    alerted_at: datetime | None = None
    reminder_at: datetime | None = None

    @property
    def due_at(self) -> datetime:
        return self.reminder_at or self.starts_at


class EventStore:
    """Small SQLite repository used by both windows and the reminder service."""

    def __init__(self, database: str | Path | None = None):
        self.path = Path(database) if database else default_database_path()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        self._migrate()

    def _migrate(self) -> None:
        self.connection.execute(
            """CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                starts_at TEXT NOT NULL,
                ends_at TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                completed INTEGER NOT NULL DEFAULT 0,
                alerted_at TEXT,
                reminder_at TEXT,
                created_at TEXT NOT NULL
            )"""
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_events_schedule ON events(starts_at, ends_at)"
        )
        self.connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_events_due ON events(completed, alerted_at, reminder_at, starts_at)"
        )
        self.connection.commit()

    @staticmethod
    def validate(title: str, starts_at: datetime, ends_at: datetime) -> tuple[str, datetime, datetime]:
        title = title.strip()
        if not title:
            raise ValueError("请填写事件名称")
        if len(title) > 120:
            raise ValueError("事件名称不能超过 120 个字符")
        if ends_at <= starts_at:
            raise ValueError("结束时间必须晚于开始时间")
        return title, starts_at.replace(microsecond=0), ends_at.replace(microsecond=0)

    def add_event(self, title: str, starts_at: datetime, ends_at: datetime, notes: str = "", *, now: datetime | None = None) -> Event:
        title, starts_at, ends_at = self.validate(title, starts_at, ends_at)
        now = (now or datetime.now()).replace(microsecond=0)
        # A historical event is kept in the calendar but is not allowed to create a
        # surprising old reminder immediately after it is saved.
        alerted_at = as_iso(now) if starts_at <= now else None
        cursor = self.connection.execute(
            "INSERT INTO events(title, starts_at, ends_at, notes, alerted_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (title, as_iso(starts_at), as_iso(ends_at), notes.strip(), alerted_at, as_iso(now)),
        )
        self.connection.commit()
        return self.get(int(cursor.lastrowid))

    def update_event(self, event_id: int, title: str, starts_at: datetime, ends_at: datetime, notes: str = "", *, now: datetime | None = None) -> Event:
        title, starts_at, ends_at = self.validate(title, starts_at, ends_at)
        old = self.get(event_id)
        if old is None:
            raise KeyError(event_id)
        # A title/note-only edit must not resurrect an already shown alert or erase
        # a user's snooze.  A genuinely changed future schedule is re-armed.
        schedule_changed = starts_at != old.starts_at or ends_at != old.ends_at
        rearm = schedule_changed and starts_at > (now or datetime.now()) and not old.completed
        alerted_at = None if rearm else old.alerted_at
        reminder_at = None if rearm else old.reminder_at
        self.connection.execute(
            "UPDATE events SET title=?, starts_at=?, ends_at=?, notes=?, alerted_at=?, reminder_at=? WHERE id=?",
            (title, as_iso(starts_at), as_iso(ends_at), notes.strip(), as_iso(alerted_at) if alerted_at else None, as_iso(reminder_at) if reminder_at else None, event_id),
        )
        self.connection.commit()
        return self.get(event_id)

    def get(self, event_id: int) -> Event | None:
        row = self.connection.execute("SELECT * FROM events WHERE id=?", (event_id,)).fetchone()
        return self._event(row) if row else None

    def events_for_day(self, day) -> list[Event]:
        start = datetime.combine(day, datetime.min.time())
        end = start + timedelta(days=1)
        rows = self.connection.execute(
            "SELECT * FROM events WHERE starts_at < ? AND ends_at > ? ORDER BY starts_at, id",
            (as_iso(end), as_iso(start)),
        ).fetchall()
        return [self._event(row) for row in rows]

    def upcoming(self, limit: int = 5, *, now: datetime | None = None) -> list[Event]:
        now = now or datetime.now()
        rows = self.connection.execute(
            "SELECT * FROM events WHERE completed=0 AND ends_at >= ? ORDER BY starts_at, id LIMIT ?",
            (as_iso(now), limit),
        ).fetchall()
        return [self._event(row) for row in rows]

    def due_events(self, *, now: datetime | None = None) -> list[Event]:
        now = now or datetime.now()
        earliest = now - timedelta(hours=24)
        rows = self.connection.execute(
            """SELECT * FROM events WHERE completed=0 AND alerted_at IS NULL
               AND COALESCE(reminder_at, starts_at) BETWEEN ? AND ? ORDER BY COALESCE(reminder_at, starts_at), id""",
            (as_iso(earliest), as_iso(now)),
        ).fetchall()
        return [self._event(row) for row in rows]

    def expire_stale_reminders(self, *, now: datetime | None = None) -> int:
        """Silence reminders more than one day old; they remain visible in history."""
        now = now or datetime.now()
        cursor = self.connection.execute(
            "UPDATE events SET alerted_at=? WHERE completed=0 AND alerted_at IS NULL AND COALESCE(reminder_at, starts_at) < ?",
            (as_iso(now), as_iso(now - timedelta(hours=24))),
        )
        self.connection.commit()
        return cursor.rowcount

    def mark_alerted(self, event_id: int, *, now: datetime | None = None) -> None:
        self.connection.execute("UPDATE events SET alerted_at=?, reminder_at=NULL WHERE id=?", (as_iso(now or datetime.now()), event_id))
        self.connection.commit()

    def snooze(self, event_id: int, minutes: int = 10, *, now: datetime | None = None) -> None:
        future = (now or datetime.now()) + timedelta(minutes=minutes)
        self.connection.execute("UPDATE events SET alerted_at=NULL, reminder_at=? WHERE id=?", (as_iso(future), event_id))
        self.connection.commit()

    def set_completed(self, event_id: int, completed: bool = True) -> None:
        event = self.get(event_id)
        if event is None:
            raise KeyError(event_id)
        # Restoring a future task also restores its scheduled reminder.  A past
        # completed task stays acknowledged instead of producing an old alert.
        rearm = not completed and event.starts_at > datetime.now()
        self.connection.execute(
            "UPDATE events SET completed=?, alerted_at=? WHERE id=?",
            (int(completed), None if rearm else as_iso(event.alerted_at or datetime.now()), event_id),
        )
        self.connection.commit()

    def delete(self, event_id: int) -> None:
        self.connection.execute("DELETE FROM events WHERE id=?", (event_id,))
        self.connection.commit()

    def close(self) -> None:
        self.connection.close()

    @staticmethod
    def _event(row: sqlite3.Row) -> Event:
        return Event(
            id=row["id"], title=row["title"], starts_at=from_iso(row["starts_at"]),
            ends_at=from_iso(row["ends_at"]), notes=row["notes"], completed=bool(row["completed"]),
            alerted_at=from_iso(row["alerted_at"]) if row["alerted_at"] else None,
            reminder_at=from_iso(row["reminder_at"]) if row["reminder_at"] else None,
        )
