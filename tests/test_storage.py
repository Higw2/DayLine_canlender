import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

from dayline.storage import EventStore


class EventStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = EventStore(Path(self.temp.name) / "events.db")
        self.now = datetime(2026, 9, 7, 9, 0)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def add(self, start, end=None):
        return self.store.add_event("晨会", start, end or start + timedelta(hours=1), now=self.now)

    def test_validation(self):
        with self.assertRaisesRegex(ValueError, "事件名称"):
            self.store.add_event(" ", self.now + timedelta(hours=1), self.now + timedelta(hours=2), now=self.now)
        with self.assertRaisesRegex(ValueError, "结束时间"):
            self.store.add_event("倒序", self.now, self.now, now=self.now)

    def test_past_event_is_saved_without_retroactive_reminder(self):
        event = self.add(self.now - timedelta(hours=1))
        self.assertIsNotNone(event.alerted_at)
        self.assertEqual(self.store.due_events(now=self.now), [])

    def test_due_and_snooze_survive_reopen(self):
        event = self.add(self.now + timedelta(minutes=1))
        self.assertEqual([item.id for item in self.store.due_events(now=self.now + timedelta(minutes=1))], [event.id])
        self.store.mark_alerted(event.id, now=self.now + timedelta(minutes=1))
        self.store.snooze(event.id, minutes=10, now=self.now + timedelta(minutes=1))
        self.store.close()
        self.store = EventStore(Path(self.temp.name) / "events.db")
        self.assertEqual(self.store.due_events(now=self.now + timedelta(minutes=10)), [])
        self.assertEqual([item.id for item in self.store.due_events(now=self.now + timedelta(minutes=11))], [event.id])

    def test_title_edit_preserves_snooze_but_time_edit_rearms(self):
        event = self.add(self.now + timedelta(hours=2))
        self.store.snooze(event.id, 10, now=self.now)
        edited = self.store.update_event(event.id, "改名晨会", event.starts_at, event.ends_at, "备注")
        self.assertIsNotNone(edited.reminder_at)
        moved = self.store.update_event(event.id, "改名晨会", event.starts_at + timedelta(days=1), event.ends_at + timedelta(days=1), "备注")
        self.assertIsNone(moved.reminder_at)
        self.assertIsNone(moved.alerted_at)

    def test_cross_day_events_are_in_both_day_views(self):
        start = datetime(2026, 9, 7, 23, 30)
        event = self.add(start, datetime(2026, 9, 8, 1, 0))
        self.assertEqual([item.id for item in self.store.events_for_day(date(2026, 9, 7))], [event.id])
        self.assertEqual([item.id for item in self.store.events_for_day(date(2026, 9, 8))], [event.id])

    def test_stale_reminders_are_expired(self):
        event = self.add(self.now + timedelta(hours=1))
        self.assertEqual(self.store.expire_stale_reminders(now=self.now + timedelta(hours=26)), 1)
        self.assertEqual(self.store.due_events(now=self.now + timedelta(hours=26)), [])

    def test_uncomplete_future_event_rearms(self):
        event = self.add(datetime.now() + timedelta(days=2))
        self.store.set_completed(event.id)
        self.store.set_completed(event.id, False)
        self.assertIsNone(self.store.get(event.id).alerted_at)


if __name__ == "__main__":
    unittest.main()
