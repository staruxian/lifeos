"""Every change LifeOS makes to your data."""

import math
import re

from dates import EVERY_DAY
from jsmath import js_round


class LifeError(Exception):
    """A problem to show the person, in plain words."""


SKIP = -1
MAX_PRIORITIES = 3


def need(value, what: str):
    if value is None:
        raise LifeError(f"{what} not found")
    return value


def clean_title(title: str, what: str) -> str:
    text = re.sub(r"\s+", " ", title.strip())
    if text == "":
        raise LifeError(f"{what} needs a name")
    return text


def _changed(count: int, what: str) -> None:
    if count == 0:
        raise LifeError(f"{what} not found")


# ---- tasks ------------------------------------------------------------------


def add_task(db, title: str, due: str | None, today: str) -> int:
    return db.one("INSERT INTO tasks (title, due, created_on) VALUES (?, ?, ?) RETURNING id",
                  clean_title(title, "A task"), due, today)["id"]


def set_task_done(db, id: int, done: bool, today: str) -> None:
    _changed(db.run("UPDATE tasks SET done_on = ? WHERE id = ?", today if done else None, id), f"task {id}")


def toggle_task(db, id: int, today: str) -> None:
    row = need(db.one("SELECT done_on FROM tasks WHERE id = ?", id), f"task {id}")
    set_task_done(db, id, row["done_on"] is None, today)


def set_task_due(db, id: int, due: str | None) -> None:
    _changed(db.run("UPDATE tasks SET due = ? WHERE id = ?", due, id), f"task {id}")


def rename_task(db, id: int, title: str) -> None:
    _changed(db.run("UPDATE tasks SET title = ? WHERE id = ?", clean_title(title, "A task"), id), f"task {id}")


def remove_task(db, id: int) -> None:
    _changed(db.run("DELETE FROM tasks WHERE id = ?", id), f"task {id}")


def task_title(db, id: int) -> str:
    return need(db.one("SELECT title FROM tasks WHERE id = ?", id), f"task {id}")["title"]


def drop_task(db, id: int, today: str) -> None:
    """Decided against: gone from every list, kept in the table."""
    _changed(db.run("UPDATE tasks SET dropped_on = ?, focus_on = NULL WHERE id = ?", today, id), f"task {id}")


def set_focus(db, id: int, on: bool, today: str) -> None:
    """Making a task a priority for a day also makes it due that day at the
    latest, so it shows under Today."""
    task = need(db.one("SELECT focus_on, due, done_on FROM tasks WHERE id = ? AND dropped_on IS NULL", id), f"task {id}")
    if not on:
        db.run("UPDATE tasks SET focus_on = NULL WHERE id = ?", id)
        return
    if task["focus_on"] == today:
        return
    count = db.one("SELECT COUNT(*) AS n FROM tasks WHERE focus_on = ? AND dropped_on IS NULL", today)["n"]
    if count >= MAX_PRIORITIES:
        raise LifeError(f"{MAX_PRIORITIES} priorities is the limit — finish or swap one")
    db.run("UPDATE tasks SET focus_on = ?, due = CASE WHEN due IS NULL OR due > ? THEN ? ELSE due END WHERE id = ?",
           today, today, today, id)


# ---- the day ------------------------------------------------------------------


def _touch_day(db, day: str, column: str, at: str | None) -> None:
    assert column in ("planned_at", "shutdown_at")
    db.run(f"INSERT INTO days (day, {column}) VALUES (?, ?) ON CONFLICT (day) DO UPDATE SET {column} = excluded.{column}", day, at)


def mark_planned(db, day: str, at: str) -> None:
    _touch_day(db, day, "planned_at", at)


def mark_shutdown(db, day: str, at: str) -> None:
    """Shutting down asks that nothing due is left undecided."""
    open_ = db.one("""
        SELECT COUNT(*) AS n FROM tasks
        WHERE done_on IS NULL AND dropped_on IS NULL AND due IS NOT NULL AND due <= ?
    """, day)["n"]
    if open_ > 0:
        raise LifeError(f"{open_} task{' still needs' if open_ == 1 else 's still need'} a decision")
    _touch_day(db, day, "shutdown_at", at)


def check_in(db, day: str, mood, note: str) -> None:
    if not isinstance(mood, int) or mood < 1 or mood > 5:
        raise LifeError("rate the day from 1 to 5")
    text = re.sub(r"\s+", " ", note.strip())[:280]
    db.run("""
        INSERT INTO days (day, mood, note) VALUES (?, ?, ?)
        ON CONFLICT (day) DO UPDATE SET mood = excluded.mood, note = excluded.note
    """, day, mood, None if text == "" else text)


# ---- habits -----------------------------------------------------------------


def add_habit(db, name: str, kind: str, today: str, target=None, unit=None, days=None) -> int:
    target = max(1, js_round(target if target is not None else 1)) if kind == "count" else 1
    days = EVERY_DAY if kind == "avoid" else (days if days is not None else EVERY_DAY)
    if days <= 0 or days > EVERY_DAY:
        raise LifeError("a habit needs at least one day")
    position = db.one("SELECT COALESCE(MAX(position), 0) + 1 AS p FROM habits")["p"]
    return db.one(
        "INSERT INTO habits (name, kind, target, unit, days, position, created_on) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id",
        clean_title(name, "A habit"), kind, target, (unit or "").strip(), days, position, today)["id"]


def _habit(db, id: int) -> dict:
    return need(db.one("SELECT id, kind, target FROM habits WHERE id = ?", id), f"habit {id}")


def _log_value(db, id: int, day: str) -> int:
    row = db.one("SELECT value FROM habit_logs WHERE habit_id = ? AND day = ?", id, day)
    return max(0, row["value"] if row else 0)


def habit_name(db, id: int) -> str:
    return need(db.one("SELECT name FROM habits WHERE id = ?", id), f"habit {id}")["name"]


def set_habit_value(db, id: int, day: str, value) -> None:
    _habit(db, id)
    v = max(0, js_round(value))
    if v == 0:
        db.run("DELETE FROM habit_logs WHERE habit_id = ? AND day = ?", id, day)
    else:
        db.run("INSERT INTO habit_logs (habit_id, day, value) VALUES (?, ?, ?) "
               "ON CONFLICT (habit_id, day) DO UPDATE SET value = excluded.value", id, day, v)
        # Backfilling a day before the habit existed means it started earlier.
        db.run("UPDATE habits SET created_on = ? WHERE id = ? AND created_on > ?", day, id, day)


def toggle_habit(db, id: int, day: str) -> None:
    """One tap: check flips done, avoid flips "slipped", count jumps between
    empty and complete so a single click can still finish the day."""
    h = _habit(db, id)
    current = _log_value(db, id, day)
    if h["kind"] == "count":
        set_habit_value(db, id, day, 0 if current >= h["target"] else h["target"])
    else:
        set_habit_value(db, id, day, 0 if current > 0 else 1)


def bump_habit(db, id: int, day: str, by: int) -> None:
    h = _habit(db, id)
    if h["kind"] != "count":
        toggle_habit(db, id, day)
        return
    set_habit_value(db, id, day, _log_value(db, id, day) + by)


def update_habit(db, id: int, name=None, target=None, unit=None, days=None) -> None:
    h = _habit(db, id)
    if name is not None:
        db.run("UPDATE habits SET name = ? WHERE id = ?", clean_title(name, "A habit"), id)
    if target is not None and h["kind"] == "count":
        db.run("UPDATE habits SET target = ? WHERE id = ?", max(1, js_round(target)), id)
    if unit is not None:
        db.run("UPDATE habits SET unit = ? WHERE id = ?", unit.strip(), id)
    if days is not None and h["kind"] != "avoid":
        if days <= 0 or days > EVERY_DAY:
            raise LifeError("a habit needs at least one day")
        db.run("UPDATE habits SET days = ? WHERE id = ?", days, id)


def set_habit_reminder(db, id: int, time: str | None) -> None:
    _habit(db, id)
    db.run("UPDATE habits SET remind_at = ? WHERE id = ?", time, id)


def move_habit(db, id: int, direction: int) -> None:
    ids = [r["id"] for r in db.all("SELECT id FROM habits ORDER BY position, id")]
    if id not in ids:
        raise LifeError(f"habit {id} not found")
    frm = ids.index(id)
    to = frm + direction
    if to < 0 or to >= len(ids):
        return
    ids[frm], ids[to] = ids[to], ids[frm]
    db.transaction(lambda: [db.run("UPDATE habits SET position = ? WHERE id = ?", i + 1, hid) for i, hid in enumerate(ids)])


def remove_habit(db, id: int) -> None:
    _changed(db.run("DELETE FROM habits WHERE id = ?", id), f"habit {id}")


def skip_habit(db, id: int, day: str, week_start: str, week_end: str) -> None:
    """A skip keeps the chain without counting as kept. One per habit per week
    (Monday to Sunday), and never for avoid habits — there is nothing to skip."""
    h = _habit(db, id)
    if h["kind"] == "avoid":
        raise LifeError("an avoid habit cannot be skipped")
    used = db.one("SELECT day FROM habit_logs WHERE habit_id = ? AND value = ? AND day BETWEEN ? AND ?",
                  id, SKIP, week_start, week_end)
    if used and used["day"] != day:
        raise LifeError("one skip a week — this week's is used")
    db.run("INSERT INTO habit_logs (habit_id, day, value) VALUES (?, ?, ?) "
           "ON CONFLICT (habit_id, day) DO UPDATE SET value = excluded.value", id, day, SKIP)


# ---- books ------------------------------------------------------------------


def _pages(total) -> int:
    pages = js_round(total) if total is not None and math.isfinite(total) else 0
    if pages <= 0:
        raise LifeError("a book needs a page count")
    return pages


def add_book(db, title: str, total_pages, today: str) -> int:
    pages = _pages(total_pages)
    return db.one("INSERT INTO books (title, total_pages, created_on) VALUES (?, ?, ?) RETURNING id",
                  clean_title(title, "A book"), pages, today)["id"]


def book_title(db, id: int) -> str:
    return need(db.one("SELECT title FROM books WHERE id = ?", id), f"book {id}")["title"]


def _pages_read(db, id: int) -> int:
    return db.one("SELECT COALESCE(SUM(pages), 0) AS n FROM reading_logs WHERE book_id = ?", id)["n"]


def log_reading(db, id: int, pages, day: str) -> None:
    """Adds to what was already logged that day, so logging twice after two
    sittings just works. Negative numbers correct a typo. Crossing the last
    page finishes the book; dropping back below un-finishes it."""
    book = need(db.one("SELECT total_pages FROM books WHERE id = ?", id), f"book {id}")
    read = _pages_read(db, id)
    delta = max(-read, min(js_round(pages), book["total_pages"] - read))
    if delta == 0 and pages > 0:
        raise LifeError("that book is already finished")

    def write():
        current = db.one("SELECT pages FROM reading_logs WHERE book_id = ? AND day = ?", id, day)
        nxt = (current["pages"] if current else 0) + delta
        if nxt <= 0:
            db.run("DELETE FROM reading_logs WHERE book_id = ? AND day = ?", id, day)
        else:
            db.run("INSERT INTO reading_logs (book_id, day, pages) VALUES (?, ?, ?) "
                   "ON CONFLICT (book_id, day) DO UPDATE SET pages = excluded.pages", id, day, nxt)
        done = read + delta >= book["total_pages"]
        db.run("UPDATE books SET finished_on = CASE WHEN ? THEN COALESCE(finished_on, ?) ELSE NULL END WHERE id = ?",
               1 if done else 0, day, id)

    db.transaction(write)


def current_book_id(db) -> int:
    """The book you touched last, so `lifeos read 20` needs no id."""
    row = db.one("""
        SELECT b.id FROM books b
        LEFT JOIN reading_logs r ON r.book_id = b.id
        WHERE b.finished_on IS NULL
        GROUP BY b.id
        ORDER BY COALESCE(MAX(r.day), b.created_on) DESC, b.id DESC
        LIMIT 1
    """)
    return need(row, "a book you are reading")["id"]


def update_book(db, id: int, title=None, total_pages=None) -> None:
    need(db.one("SELECT id FROM books WHERE id = ?", id), f"book {id}")
    if title is not None:
        db.run("UPDATE books SET title = ? WHERE id = ?", clean_title(title, "A book"), id)
    if total_pages is not None:
        db.run("UPDATE books SET total_pages = ? WHERE id = ?", _pages(total_pages), id)


def remove_book(db, id: int) -> None:
    _changed(db.run("DELETE FROM books WHERE id = ?", id), f"book {id}")


# ---- events -----------------------------------------------------------------


def add_event(db, title: str, day: str, emoji: str, today: str) -> int:
    return db.one("INSERT INTO events (title, day, emoji, created_on) VALUES (?, ?, ?, ?) RETURNING id",
                  clean_title(title, "An event"), day, emoji.strip(), today)["id"]


def event_title(db, id: int) -> str:
    return need(db.one("SELECT title FROM events WHERE id = ?", id), f"event {id}")["title"]


def update_event(db, id: int, title=None, day=None, emoji=None) -> None:
    need(db.one("SELECT id FROM events WHERE id = ?", id), f"event {id}")
    if title is not None:
        db.run("UPDATE events SET title = ? WHERE id = ?", clean_title(title, "An event"), id)
    if day is not None:
        db.run("UPDATE events SET day = ? WHERE id = ?", day, id)
    if emoji is not None:
        db.run("UPDATE events SET emoji = ? WHERE id = ?", emoji.strip(), id)


def remove_event(db, id: int) -> None:
    _changed(db.run("DELETE FROM events WHERE id = ?", id), f"event {id}")


# ---- people -----------------------------------------------------------------


def add_person(db, name: str, birthday: dict, today: str) -> int:
    return db.one("INSERT INTO people (name, month, day, year, created_on) VALUES (?, ?, ?, ?, ?) RETURNING id",
                  clean_title(name, "A person"), birthday["month"], birthday["day"], birthday["year"], today)["id"]


def person_name(db, id: int) -> str:
    return need(db.one("SELECT name FROM people WHERE id = ?", id), f"person {id}")["name"]


def update_person(db, id: int, name=None, birthday=None) -> None:
    need(db.one("SELECT id FROM people WHERE id = ?", id), f"person {id}")
    if name is not None:
        db.run("UPDATE people SET name = ? WHERE id = ?", clean_title(name, "A person"), id)
    if birthday:
        db.run("UPDATE people SET month = ?, day = ?, year = ? WHERE id = ?",
               birthday["month"], birthday["day"], birthday["year"], id)


def remove_person(db, id: int) -> None:
    _changed(db.run("DELETE FROM people WHERE id = ?", id), f"person {id}")
