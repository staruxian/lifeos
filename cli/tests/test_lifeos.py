"""LifeOS CLI tests. Run: python3 -m unittest discover cli/tests"""

import datetime as dt
import os
import re
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lifeos"))
sys.dont_write_bytecode = True

import store  # noqa: E402
from dates import add_days, diff_days, next_birthday, parse_birthday, parse_day, parse_weekdays, weekday  # noqa: E402
from db import open_db  # noqa: E402
from notify import due_notes, escape_markup, tick  # noqa: E402
from quick import parse_quick  # noqa: E402
from settings import write_setting  # noqa: E402
from state import FIRE_STREAK, HEAT_WEEKS, build_state, build_week, flame_tier, write_state  # noqa: E402
from store import LifeError  # noqa: E402
from undo import capture, last_change, save_snapshot, undo  # noqa: E402
from voice import habit_line, topic_of  # noqa: E402

FRI = "2026-09-25"  # a Friday; its week runs Mon 21 – Sun 27
MON = "2026-09-21"


def at(time: str, day: str = FRI) -> dt.datetime:
    return dt.datetime.fromisoformat(f"{day}T{time}:00")


def fresh():
    return open_db(":memory:")


def state(db, day=FRI, time="12:00"):
    return build_state(db, day, at(time, day))


def cell(habit, day):
    return next(c for week in habit["heat"] for c in week if c["day"] == day)


class Dates(unittest.TestCase):
    def test_relative_words(self):
        self.assertEqual(parse_day("today", FRI), FRI)
        self.assertEqual(parse_day("tomorrow", FRI), "2026-09-26")
        self.assertEqual(parse_day("tmr", FRI), "2026-09-26")
        self.assertEqual(parse_day("in 3 days", FRI), "2026-09-28")
        self.assertEqual(parse_day("2w", FRI), "2026-10-09")
        self.assertEqual(parse_day("+1", FRI), "2026-09-26")
        self.assertEqual(parse_day("in 1 month", "2026-01-31"), "2026-03-03")  # rolls over, as Date.setMonth does

    def test_weekdays(self):
        self.assertEqual(parse_day("fri", FRI), FRI)
        self.assertEqual(parse_day("next fri", FRI), "2026-10-02")
        self.assertEqual(parse_day("mon", FRI), "2026-09-28")
        self.assertEqual(parse_day("thursday", FRI), "2026-10-01")
        self.assertIsNone(parse_day("t", FRI))

    def test_calendar_dates_roll_into_next_year(self):
        self.assertEqual(parse_day("nov 3", FRI), "2026-11-03")
        self.assertEqual(parse_day("3 november", FRI), "2026-11-03")
        self.assertEqual(parse_day("3.11", FRI), "2026-11-03")
        self.assertEqual(parse_day("jan 5", FRI), "2027-01-05")
        self.assertEqual(parse_day("03.11.2026", FRI), "2026-11-03")
        self.assertIsNone(parse_day("2026-02-30", FRI))
        self.assertIsNone(parse_day("31.02", FRI))
        self.assertIsNone(parse_day("banana", FRI))

    def test_day_math(self):
        self.assertEqual(diff_days(FRI, "2026-11-03"), 39)
        self.assertEqual(add_days("2026-12-31", 1), "2027-01-01")
        self.assertEqual(weekday(FRI), 4)
        self.assertEqual(parse_weekdays("mon,wed,fri"), 0b0010101)
        self.assertEqual(parse_weekdays("weekdays"), 0b0011111)
        self.assertIsNone(parse_weekdays("funday"))


class Tasks(unittest.TestCase):
    def test_bucket_by_due_date(self):
        db = fresh()
        store.add_task(db, "late", add_days(FRI, -2), FRI)
        store.add_task(db, "now", FRI, FRI)
        store.add_task(db, "soon", add_days(FRI, 3), FRI)
        someday = store.add_task(db, "someday", None, FRI)
        store.set_task_done(db, someday, True, FRI)
        s = state(db)
        titles = lambda group: [t["title"] for t in s["tasks"][group]]  # noqa: E731
        self.assertEqual(titles("overdue"), ["late"])
        self.assertEqual(titles("today"), ["now"])
        self.assertEqual(titles("upcoming"), ["soon"])
        self.assertEqual(titles("doneToday"), ["someday"])
        self.assertEqual(s["summary"]["tasksLeft"], 2)
        # Finished yesterday: gone from today's view.
        self.assertEqual(state(db, add_days(FRI, 1))["tasks"]["doneToday"], [])

    def test_empty_titles_are_refused(self):
        with self.assertRaises(LifeError):
            store.add_task(fresh(), "   ", None, FRI)


class Habits(unittest.TestCase):
    def test_streak_ignores_unfinished_today_and_catches_fire(self):
        db = fresh()
        h = store.add_habit(db, "Meditate", "check", add_days(FRI, -10))
        for i in range(1, FIRE_STREAK + 1):
            store.toggle_habit(db, h, add_days(FRI, -i))
        habit = state(db)["habits"][0]
        self.assertEqual(habit["streak"], FIRE_STREAK)
        self.assertTrue(habit["onFire"])
        self.assertFalse(habit["done"])
        store.toggle_habit(db, h, FRI)
        self.assertEqual(state(db)["habits"][0]["streak"], FIRE_STREAK + 1)
        # A missed yesterday breaks it.
        self.assertEqual(state(db, add_days(FRI, 2))["habits"][0]["streak"], 0)

    def test_rest_days_neither_count_nor_break(self):
        db = fresh()
        h = store.add_habit(db, "Gym", "check", add_days(FRI, -14), days=0b0010101)  # Mon/Wed/Fri
        for d in (-4, -2, 0):
            store.toggle_habit(db, h, add_days(FRI, d))
        habit = state(db)["habits"][0]
        self.assertEqual(habit["streak"], 3)
        self.assertEqual(cell(habit, add_days(FRI, -1))["state"], "off")
        self.assertEqual(cell(habit, FRI)["state"], "done")

    def test_count_habits_fill_up_and_grade_the_heatmap(self):
        db = fresh()
        h = store.add_habit(db, "Water", "count", FRI, target=8, unit="glasses")
        store.bump_habit(db, h, FRI, 3)
        habit = state(db)["habits"][0]
        self.assertEqual(habit["value"], 3)
        self.assertFalse(habit["done"])
        self.assertEqual(cell(habit, FRI)["level"], 2)
        store.bump_habit(db, h, FRI, 5)
        habit = state(db)["habits"][0]
        self.assertTrue(habit["done"])
        self.assertEqual(habit["progress"], 1)
        store.bump_habit(db, h, FRI, -20)
        self.assertEqual(state(db)["habits"][0]["value"], 0)

    def test_avoid_habits_count_clean_days(self):
        db = fresh()
        h = store.add_habit(db, "No sugar", "avoid", add_days(FRI, -4))
        self.assertEqual(state(db)["habits"][0]["streak"], 5)
        store.toggle_habit(db, h, add_days(FRI, -1))
        habit = state(db)["habits"][0]
        self.assertEqual(habit["streak"], 1)
        self.assertEqual(cell(habit, add_days(FRI, -1))["state"], "slip")

    def test_heatmap_is_whole_monday_first_weeks(self):
        db = fresh()
        store.add_habit(db, "Read", "check", FRI)
        heat = state(db)["habits"][0]["heat"]
        self.assertEqual(len(heat), HEAT_WEEKS)
        self.assertTrue(all(len(w) == 7 for w in heat))
        self.assertEqual(weekday(heat[0][0]["day"]), 0)
        self.assertEqual(heat[-1][4]["day"], FRI)
        self.assertEqual(heat[-1][5]["state"], "future")

    def test_backfill_moves_the_start_back(self):
        db = fresh()
        h = store.add_habit(db, "Walk", "check", FRI)
        for i in (1, 2, 3):
            store.toggle_habit(db, h, add_days(FRI, -i))
        habit = state(db)["habits"][0]
        self.assertEqual(habit["streak"], 3)
        self.assertEqual(cell(habit, add_days(FRI, -3))["state"], "done")


class Books(unittest.TestCase):
    def test_logs_add_up_pace_and_finish_date_follow(self):
        db = fresh()
        b = store.add_book(db, "Dune", 100, add_days(FRI, -3))
        store.log_reading(db, b, 10, add_days(FRI, -3))
        store.log_reading(db, b, 10, add_days(FRI, -2))
        store.log_reading(db, b, 5, FRI)
        store.log_reading(db, b, 5, FRI)
        book = state(db)["books"]["reading"][0]
        self.assertEqual(book["read"], 30)
        self.assertEqual(book["today"], 10)
        self.assertEqual(book["pace"], 7.5)  # 30 pages over 4 days
        self.assertEqual(book["etaDays"], 10)  # 70 left
        self.assertEqual(len(book["recent"]), 14)

    def test_last_page_finishes_the_book(self):
        db = fresh()
        b = store.add_book(db, "Short", 50, FRI)
        store.log_reading(db, b, 80, FRI)
        s = state(db)
        self.assertEqual(s["books"]["reading"], [])
        self.assertEqual(s["books"]["finished"][0]["read"], 50)
        self.assertEqual(s["books"]["finished"][0]["finishedOn"], FRI)
        with self.assertRaises(LifeError):
            store.log_reading(db, b, 5, FRI)
        # Correcting downwards re-opens it.
        store.log_reading(db, b, -10, FRI)
        self.assertEqual(state(db)["books"]["reading"][0]["read"], 40)

    def test_read_goes_to_the_book_touched_last(self):
        db = fresh()
        a = store.add_book(db, "A", 300, add_days(FRI, -5))
        store.add_book(db, "B", 300, add_days(FRI, -4))
        store.log_reading(db, a, 10, FRI)
        self.assertEqual(store.current_book_id(db), a)


class Events(unittest.TestCase):
    def test_count_down_and_vanish_once_past(self):
        db = fresh()
        store.add_event(db, "Trip", "2026-11-03", "✈️", FRI)
        store.add_event(db, "Yesterday", add_days(FRI, -1), "", add_days(FRI, -5))
        store.add_event(db, "Tonight", FRI, "🎉", add_days(FRI, -4))
        s = state(db)
        self.assertEqual([e["title"] for e in s["events"]], ["Tonight", "Trip"])
        self.assertEqual(s["events"][0]["daysLeft"], 0)
        self.assertEqual(s["events"][0]["progress"], 1)
        self.assertEqual(s["events"][1]["daysLeft"], 39)
        self.assertEqual(s["summary"]["nextEvent"]["title"], "Tonight")


class Privacy(unittest.TestCase):
    def test_owner_only_even_under_a_loose_umask(self):
        previous = os.umask(0o022)
        try:
            root = tempfile.mkdtemp(prefix="lifeos-")
            # A directory and file left world-readable earlier get tightened.
            data_dir = os.path.join(root, "share/lifeos")
            os.makedirs(data_dir, mode=0o755)
            db_path = os.path.join(data_dir, "lifeos.db")
            open(db_path, "w").close()
            os.chmod(db_path, 0o644)
            db = open_db(db_path)
            store.add_task(db, "secret", None, FRI)
            state_path = os.path.join(root, "state/lifeos/state.json")
            write_state(state(db), state_path)
            db.close()
            mode = lambda p: os.stat(p).st_mode & 0o777  # noqa: E731
            self.assertEqual(mode(data_dir), 0o700)
            self.assertEqual(mode(db_path), 0o600)
            self.assertEqual(mode(os.path.dirname(state_path)), 0o700)
            self.assertEqual(mode(state_path), 0o600)
        finally:
            os.umask(previous)


class ThePlan(unittest.TestCase):
    def test_at_most_three_and_they_land_on_today(self):
        db = fresh()
        ids = [store.add_task(db, f"t{n}", add_days(FRI, 5) if n == 1 else None, FRI) for n in (1, 2, 3, 4)]
        for i in ids[:3]:
            store.set_focus(db, i, True, FRI)
        with self.assertRaisesRegex(LifeError, "3 priorities"):
            store.set_focus(db, ids[3], True, FRI)
        s = state(db, time="09:00")
        self.assertEqual([t["title"] for t in s["day"]["priorities"]], ["t1", "t2", "t3"])
        self.assertTrue(all(t["focus"] for t in s["tasks"]["today"]))  # pulled forward to today
        self.assertEqual(s["summary"]["priorities"], 3)
        # Tomorrow they are ordinary tasks again.
        self.assertEqual(state(db, add_days(FRI, 1), "09:00")["day"]["priorities"], [])

    def test_needs_a_plan_until_planned(self):
        db = fresh()
        self.assertFalse(state(db, time="03:00")["day"]["needsPlan"])
        self.assertTrue(state(db, time="08:30")["day"]["needsPlan"])
        store.mark_planned(db, FRI, "x")
        self.assertFalse(state(db, time="08:32")["day"]["needsPlan"])
        write_setting(db, "plan", "off")
        self.assertFalse(state(db, add_days(FRI, 1), "09:00")["day"]["needsPlan"])

    def test_shutdown_wants_every_due_task_decided(self):
        db = fresh()
        late = store.add_task(db, "late", add_days(FRI, -1), FRI)
        now = store.add_task(db, "now", FRI, FRI)
        store.add_task(db, "later", add_days(FRI, 2), FRI)
        s = state(db, time="21:30")
        self.assertTrue(s["day"]["needsShutdown"])
        self.assertEqual([t["title"] for t in s["day"]["leftovers"]], ["late", "now"])
        with self.assertRaisesRegex(LifeError, "2 tasks still need"):
            store.mark_shutdown(db, FRI, "x")
        store.set_task_due(db, late, add_days(FRI, 1))
        store.drop_task(db, now, FRI)
        store.mark_shutdown(db, FRI, "x")
        s = state(db, time="21:31")
        self.assertTrue(s["day"]["shutdown"])
        self.assertFalse(s["day"]["needsShutdown"])
        self.assertEqual(s["tasks"]["today"], [])  # dropped is gone


class Skips(unittest.TestCase):
    def test_once_a_week_keeps_the_streak(self):
        db = fresh()
        h = store.add_habit(db, "Run", "check", add_days(FRI, -6))
        for d in (-4, -3, -1):
            store.toggle_habit(db, h, add_days(FRI, d))
        store.skip_habit(db, h, add_days(FRI, -2), MON, add_days(MON, 6))
        store.toggle_habit(db, h, FRI)
        habit = state(db)["habits"][0]
        self.assertEqual(habit["streak"], 4)  # the skip did not break it, nor count
        self.assertFalse(habit["canSkip"])
        self.assertEqual(cell(habit, add_days(FRI, -2))["state"], "skip")
        with self.assertRaisesRegex(LifeError, "one skip a week"):
            store.skip_habit(db, h, FRI, MON, add_days(MON, 6))
        avoid = store.add_habit(db, "No sugar", "avoid", FRI)
        with self.assertRaises(LifeError):
            store.skip_habit(db, avoid, FRI, MON, add_days(MON, 6))

    def test_a_skipped_habit_is_not_due(self):
        db = fresh()
        h = store.add_habit(db, "Run", "check", FRI)
        store.add_habit(db, "Read", "check", FRI)
        store.skip_habit(db, h, FRI, MON, add_days(MON, 6))
        s = state(db)
        self.assertEqual(s["summary"]["habitsDue"], 1)
        self.assertTrue(s["habits"][0]["skipped"])


class Alerts(unittest.TestCase):
    def test_grow_louder(self):
        db = fresh()
        store.add_habit(db, "Read", "check", FRI)
        self.assertEqual(state(db, time="20:30")["day"]["alert"], "none")
        self.assertEqual(state(db, time="22:00")["day"]["alert"], "urgent")
        write_setting(db, "bedtime", "23:59")
        self.assertEqual(state(db, time="22:10")["day"]["alert"], "warn")
        self.assertEqual(state(db, time="23:00")["day"]["alert"], "urgent")


class WeeklyScore(unittest.TestCase):
    def test_promises_kept(self):
        db = fresh()
        h = store.add_habit(db, "Read", "check", add_days(MON, -7))
        g = store.add_habit(db, "Gym", "check", add_days(MON, -7), days=0b0010101)
        for i in range(7):
            store.toggle_habit(db, h, add_days(MON, -7 + i))  # last week: all 7
        store.toggle_habit(db, g, add_days(MON, -7))  # Gym: 1 of 3
        w = build_week(db, add_days(MON, -7), add_days(MON, -1), FRI)
        self.assertEqual((w["due"], w["kept"], w["perfectDays"]), (10, 8, 5))
        self.assertEqual(w["best"]["name"], "Read")
        self.assertEqual(w["worst"]["name"], "Gym")
        self.assertTrue(state(db, time="09:00")["review"]["due"])
        db.run("INSERT INTO settings (key, value) VALUES ('reviewed', ?)", add_days(MON, -7))
        self.assertFalse(state(db, time="09:00")["review"]["due"])


class Settings(unittest.TestCase):
    def test_settings_validate(self):
        db = fresh()
        write_setting(db, "shutdown", "9:30")
        write_setting(db, "strict", "yes")
        s = state(db, time="09:00")["settings"]
        self.assertEqual(s["shutdown"], "09:30")
        self.assertEqual(s["strict"], "on")
        with self.assertRaises(LifeError):
            write_setting(db, "shutdown", "25:00")
        with self.assertRaises(LifeError):
            write_setting(db, "volume", "11")
        with self.assertRaisesRegex(LifeError, "gentle, coach or savage"):
            write_setting(db, "tone", "rude")


class Undo(unittest.TestCase):
    def test_puts_every_table_back(self):
        d = tempfile.mkdtemp(prefix="lifeos-undo-")
        path = os.path.join(d, "undo.db")
        db = open_db(os.path.join(d, "lifeos.db"))
        t = store.add_task(db, "keep me", None, FRI)
        before = capture(db)
        store.remove_task(db, t)
        store.add_habit(db, "new", "check", FRI)
        save_snapshot(before, "Deleted “keep me”", "x", path)
        self.assertEqual(last_change(path)["label"], "Deleted “keep me”")
        undo(db, path)
        s = state(db)
        self.assertEqual([x["title"] for x in s["tasks"]["someday"]], ["keep me"])
        self.assertEqual(s["habits"], [])
        with self.assertRaisesRegex(LifeError, "nothing to undo"):
            undo(db, path)

    def test_a_copy_from_an_older_schema_is_refused(self):
        d = tempfile.mkdtemp(prefix="lifeos-old-")
        old = sqlite3.connect(os.path.join(d, "old.db"))
        old.executescript("CREATE TABLE tasks (id INTEGER); PRAGMA user_version = 1;")
        data = old.serialize()
        old.close()
        save_snapshot(data, "old change", "x", os.path.join(d, "undo.db"))
        db = open_db(os.path.join(d, "now.db"))
        store.add_task(db, "keep", None, FRI)
        with self.assertRaisesRegex(LifeError, "nothing to undo"):
            undo(db, os.path.join(d, "undo.db"))
        self.assertEqual(len(state(db)["tasks"]["someday"]), 1)


class QuickAdd(unittest.TestCase):
    def test_reads_dates_off_the_end_and_bang_as_priority(self):
        task = lambda title, due=None, focus=False: {"kind": "task", "title": title, "due": due, "focus": focus}  # noqa: E731
        self.assertEqual(parse_quick("pay rent fri", FRI), task("pay rent", FRI))
        self.assertEqual(parse_quick("call mom next mon", FRI), task("call mom", "2026-09-28"))
        self.assertEqual(parse_quick("renew passport on nov 3", FRI), task("renew passport", "2026-11-03"))
        self.assertEqual(parse_quick("book dentist in 3 days", FRI), task("book dentist", "2026-09-28"))
        self.assertEqual(parse_quick("ship it!", FRI), task("ship it", FRI, True))
        self.assertEqual(parse_quick("what do we", FRI), task("what do we"))
        self.assertEqual(parse_quick("buy 2 apples", FRI), task("buy 2 apples"))
        self.assertEqual(parse_quick("tomorrow", FRI), task("tomorrow"))
        self.assertEqual(parse_quick("read 20", FRI), {"kind": "read", "pages": 20})
        self.assertIsNone(parse_quick("   ", FRI))


class People(unittest.TestCase):
    def test_parse_birthdays(self):
        self.assertEqual(parse_birthday("12.10.2001"), {"month": 10, "day": 12, "year": 2001})
        self.assertEqual(parse_birthday("12.10"), {"month": 10, "day": 12, "year": None})
        self.assertEqual(parse_birthday("oct 12"), {"month": 10, "day": 12, "year": None})
        self.assertEqual(parse_birthday("12 October 1998"), {"month": 10, "day": 12, "year": 1998})
        self.assertEqual(parse_birthday("2001-10-12"), {"month": 10, "day": 12, "year": 2001})
        self.assertEqual(parse_birthday("29.02"), {"month": 2, "day": 29, "year": None})
        self.assertIsNone(parse_birthday("31.02"))
        self.assertIsNone(parse_birthday("12.10.2090"))  # not born yet
        self.assertIsNone(parse_birthday("soon"))

    def test_next_birthday(self):
        self.assertEqual(next_birthday({"month": 9, "day": 25, "year": None}, FRI), FRI)
        self.assertEqual(next_birthday({"month": 9, "day": 24, "year": None}, FRI), "2027-09-24")
        self.assertEqual(next_birthday({"month": 2, "day": 29, "year": None}, FRI), "2027-02-28")

    def test_ages_and_kept_apart_from_events(self):
        db = fresh()
        store.add_person(db, "Aziz", {"month": 10, "day": 12, "year": 2001}, FRI)
        store.add_person(db, "Mom", {"month": 9, "day": 26, "year": None}, FRI)
        store.add_event(db, "Trip", "2026-10-01", "✈️", FRI)
        s = state(db, time="09:00")
        self.assertEqual([p["name"] for p in s["people"]], ["Mom", "Aziz"])
        self.assertEqual(s["people"][1]["turning"], 25)
        self.assertIsNone(s["people"][0]["turning"])
        self.assertEqual([e["title"] for e in s["events"]], ["Trip"])
        self.assertEqual(s["summary"]["nextBirthday"]["name"], "Mom")

    def test_birthday_notification(self):
        db = fresh()
        store.add_person(db, "Aziz", {"month": 9, "day": 26, "year": 2001}, FRI)
        note = next(n for n in due_notes(state(db, time="09:00"), at("09:00")) if n["key"].startswith("birthday:"))
        self.assertEqual(note["title"], "🎂 Aziz turns 25 tomorrow")


class Notifications(unittest.TestCase):
    def test_each_fires_once_and_habit_reminders_collapse(self):
        db = fresh()
        store.add_habit(db, "Read", "check", FRI)
        store.add_task(db, "late", FRI, FRI)
        store.add_event(db, "Trip", add_days(FRI, 3), "✈️", FRI)
        sent = []
        tick(db, state(db, time="08:05"), at("08:05"), sent.append)
        self.assertEqual(sent[0]["key"], f"plan:{FRI}")
        self.assertTrue(sent[1]["key"].startswith("event:"))
        self.assertEqual(len(sent), 2)
        # Booting late: remind + shutdown + bedtime are all due; the habit ones collapse.
        tick(db, state(db, time="22:30"), at("22:30"), sent.append)
        self.assertEqual([n["key"].split(":")[0] for n in sent[2:]], ["shutdown", "bedtime"])
        self.assertTrue(sent[-1]["urgent"])
        count = len(sent)
        tick(db, state(db, time="22:31"), at("22:31"), sent.append)
        self.assertEqual(len(sent), count)

    def test_quiet_when_off(self):
        db = fresh()
        store.add_habit(db, "Read", "check", FRI)
        write_setting(db, "notify", "off")
        self.assertEqual(due_notes(state(db, time="22:30"), at("22:30")), [])

    def test_habit_reminder_once_while_open(self):
        db = fresh()
        h = store.add_habit(db, "Gym", "check", FRI)
        store.set_habit_reminder(db, h, "18:00")
        habit_keys = lambda time: [n["key"] for n in due_notes(state(db, time=time), at(time)) if n["key"].startswith("habit:")]  # noqa: E731
        self.assertEqual(habit_keys("17:59"), [])
        self.assertEqual(habit_keys("18:00"), [f"habit:{h}:{FRI}"])
        store.toggle_habit(db, h, FRI)
        self.assertEqual(habit_keys("18:30"), [])
        self.assertEqual(state(db, time="18:30")["habits"][0]["remindAt"], "18:00")

    def test_savage_nags_five_times_then_stops(self):
        db = fresh()
        h = store.add_habit(db, "Gym", "check", FRI)
        store.set_habit_reminder(db, h, "18:00")
        write_setting(db, "tone", "savage")
        write_setting(db, "remind", "23:00")  # keep the general reminder out of the way
        sent = []
        for time in ("18:00", "18:20", "18:45", "19:30", "20:15", "21:00", "21:45", "22:30"):
            tick(db, state(db, time=time), at(time), sent.append)
        nags = [n for n in sent if n["key"].startswith("habit:")]
        self.assertEqual(len(nags), 5)
        self.assertTrue(nags[-1]["urgent"])
        self.assertTrue(all(not re.search(r"\{\w+\}", n["body"]) for n in nags))  # placeholders filled
        store.toggle_habit(db, h, FRI)
        self.assertFalse(any(n["key"].startswith("habit:") for n in due_notes(state(db, time="22:40"), at("22:40"))))

    def test_coach_asks_once(self):
        db = fresh()
        h = store.add_habit(db, "Gym", "check", FRI)
        store.set_habit_reminder(db, h, "18:00")
        sent = []
        for time in ("18:00", "19:00", "20:00"):
            tick(db, state(db, time=time), at(time), sent.append)
        self.assertEqual(len([n for n in sent if n["key"].startswith("habit:")]), 1)

    def test_markup_is_escaped(self):
        self.assertEqual(escape_markup('<img src="http://x/y.png"> & <b>Gym</b>'),
                         '&lt;img src="http://x/y.png"&gt; &amp; &lt;b&gt;Gym&lt;/b&gt;')


class Voice(unittest.TestCase):
    def test_topics(self):
        for name, topic in [("Gym", "fitness"), ("30 push ups", "fitness"), ("Read 20 pages", "reading"),
                            ("Drink water", "water"), ("Meditate", "mind"), ("AS Math prep", "study"), ("Call grandma", "general")]:
            self.assertEqual(topic_of(name), topic, name)

    def test_same_key_same_words_tone_changes_them(self):
        a = habit_line("savage", "habit:1:2026-09-25", "Gym")
        self.assertEqual(habit_line("savage", "habit:1:2026-09-25", "Gym"), a)
        self.assertNotEqual(habit_line("gentle", "habit:1:2026-09-25", "Gym"), a)
        week = {habit_line("savage", f"habit:1:{add_days(FRI, i)}", "Gym") for i in range(7)}
        self.assertGreater(len(week), 2)


class Milestones(unittest.TestCase):
    def test_seven_days_is_marked_celebrated_once_and_grows_the_flame(self):
        db = fresh()
        h = store.add_habit(db, "Meditate", "check", add_days(FRI, -10))
        for i in range(1, 7):
            store.toggle_habit(db, h, add_days(FRI, -i))
        self.assertIsNone(state(db, time="09:00")["habits"][0]["milestone"])
        store.toggle_habit(db, h, FRI)
        habit = state(db, time="09:00")["habits"][0]
        self.assertEqual((habit["streak"], habit["milestone"], habit["flame"]), (7, 7, 1))
        sent = []
        tick(db, state(db, time="09:00"), at("09:00"), sent.append)
        tick(db, state(db, time="09:01"), at("09:01"), sent.append)
        milestones = [n for n in sent if n["key"].startswith("milestone:")]
        self.assertEqual(len(milestones), 1)
        self.assertIn("7", milestones[0]["title"])

    def test_flame_tiers(self):
        self.assertEqual([flame_tier(s) for s in (2, 7, 29, 30, 99, 100)], [0, 1, 1, 2, 2, 3])


class CheckInAndInsights(unittest.TestCase):
    def test_rating_and_note_are_kept(self):
        db = fresh()
        store.check_in(db, FRI, 4, "  good   focus day ")
        s = state(db, time="21:00")
        self.assertEqual((s["day"]["mood"], s["day"]["note"]), (4, "good focus day"))
        self.assertEqual(s["insights"]["mood"][-1], {"day": FRI, "mood": 4, "note": "good focus day"})
        with self.assertRaises(LifeError):
            store.check_in(db, FRI, 6, "")

    def test_weekday_pattern_and_longest_run(self):
        db = fresh()
        start = add_days(FRI, -83)
        h = store.add_habit(db, "Read", "check", start)
        day = start
        while day < FRI:
            if weekday(day) < 5:  # kept every weekday, never at weekends
                store.toggle_habit(db, h, day)
            day = add_days(day, 1)
        i = state(db)["insights"]
        self.assertTrue(any(re.search(r"best on Mondays .*slip most on (Saturdays|Sundays)", l["text"]) for l in i["lines"]))
        self.assertEqual(i["records"][0]["best"], 5)
        self.assertEqual(i["weekdays"][0]["rate"], 1)
        self.assertEqual(i["weekdays"][6]["rate"], 0)

    def test_quiet_with_little_data(self):
        db = fresh()
        store.add_habit(db, "Read", "check", FRI)
        self.assertEqual(state(db)["insights"]["lines"], [])


if __name__ == "__main__":
    unittest.main()
