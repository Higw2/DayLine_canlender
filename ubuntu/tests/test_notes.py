import tempfile
import unittest
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

from dayline.storage import EventStore, Note


class NoteStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "events.db"
        self.store = EventStore(self.path)
        self.now = datetime(2026, 9, 14, 9, 0)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_add_preserves_body_and_derives_title(self):
        body = "\n  买牛奶  \n第二行\n"
        note = self.store.add_note(body, now=self.now)
        self.assertIsInstance(note, Note)
        self.assertEqual(note.title, "买牛奶")
        self.assertEqual(note.body, body)
        self.assertTrue(note.auto_title)
        self.assertEqual(note.created_at, self.now)
        self.assertEqual(note.updated_at, self.now)
        self.assertEqual(self.store.get_note(note.id), note)

    def test_update_keeps_creation_time_and_moves_note_to_top(self):
        first = self.store.add_note("第一条", now=self.now)
        second = self.store.add_note("第二条", now=self.now + timedelta(minutes=1))
        self.assertEqual([note.id for note in self.store.list_notes()], [second.id, first.id])

        edited = self.store.update_note(
            first.id, "更新后的正文\n更多内容", " 自定标题 ",
            now=self.now + timedelta(minutes=2),
        )
        self.assertEqual(edited.title, "自定标题")
        self.assertEqual(edited.body, "更新后的正文\n更多内容")
        self.assertFalse(edited.auto_title)
        self.assertEqual(edited.created_at, self.now)
        self.assertEqual(edited.updated_at, self.now + timedelta(minutes=2))
        self.assertEqual([note.id for note in self.store.list_notes()], [first.id, second.id])

    def test_notes_survive_reopen_and_delete(self):
        note = self.store.add_note("留存内容", now=self.now)
        self.store.close()
        self.store = EventStore(self.path)
        self.assertEqual(self.store.get_note(note.id), note)
        self.assertEqual(self.store.list_notes(), [note])

        self.store.delete_note(note.id)
        self.assertIsNone(self.store.get_note(note.id))
        self.assertEqual(self.store.list_notes(), [])
        self.store.close()
        self.store = EventStore(self.path)
        self.assertIsNone(self.store.get_note(note.id))

    def test_validation_and_missing_note(self):
        with self.assertRaisesRegex(ValueError, "便笺标题"):
            self.store.add_note("正文", title="长" * 121)
        with self.assertRaises(KeyError):
            self.store.update_note(999, "正文")

    def test_auto_title_tracks_body_edits(self):
        note = self.store.add_note("原正文", now=self.now)
        edited = self.store.update_note(note.id, "新首行\n其他内容", now=self.now + timedelta(minutes=1))
        self.assertTrue(edited.auto_title)
        self.assertEqual(edited.title, "新首行")

    def test_explicit_placeholder_title_stays_manual(self):
        note = self.store.add_note("原正文", title="无标题便笺", now=self.now)
        self.assertFalse(note.auto_title)
        edited = self.store.update_note(note.id, "新正文", title=note.title, now=self.now + timedelta(minutes=1))
        self.assertFalse(edited.auto_title)
        self.assertEqual(edited.title, "无标题便笺")

    def test_blank_existing_note_survives_reopen(self):
        note = self.store.add_note("初始内容", now=self.now)
        edited = self.store.update_note(note.id, "", now=self.now + timedelta(minutes=1))
        self.assertEqual(edited.title, "无标题便笺")
        self.assertEqual(edited.body, "")
        self.assertTrue(edited.auto_title)
        self.store.close()
        self.store = EventStore(self.path)
        self.assertEqual(self.store.get_note(note.id), edited)

    def test_existing_notes_table_migrates_with_manual_title_default(self):
        self.store.close()
        with sqlite3.connect(self.path) as connection:
            connection.execute("DROP TABLE notes")
            connection.execute(
                """CREATE TABLE notes (
                    id INTEGER PRIMARY KEY,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )"""
            )
            connection.execute(
                "INSERT INTO notes(title, body, created_at, updated_at) VALUES (?, ?, ?, ?)",
                ("旧标题", "旧正文", self.now.isoformat(sep=" "), self.now.isoformat(sep=" ")),
            )
        self.store = EventStore(self.path)
        note = self.store.list_notes()[0]
        self.assertEqual(note.title, "旧标题")
        self.assertEqual(note.body, "旧正文")
        self.assertFalse(note.auto_title)


if __name__ == "__main__":
    unittest.main()
