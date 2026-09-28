"""One level of undo. Before a change the whole database (it is small) is
kept in memory; once the change has succeeded it is written beside the state
file with a label, and undo copies the tables back. Sent notifications are
not part of it — undoing a check-off should not send the evening reminder
twice."""

import json
import os

import db as dbmod
from store import LifeError

TABLES = ["tasks", "habits", "habit_logs", "books", "reading_logs", "events", "days", "settings", "people"]


def _meta(path: str) -> str:
    return path + ".json"


def capture(db) -> bytes:
    return db.serialize()


def _write_private(path: str, data: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)


def save_snapshot(data: bytes, label: str, at: str, path: str | None = None) -> None:
    path = path or dbmod.PATHS["undo"]
    dbmod.private_dir(os.path.dirname(path))
    _write_private(path, data)
    _write_private(_meta(path), json.dumps({"label": label, "at": at}, ensure_ascii=False, separators=(",", ":")).encode())


def last_change(path: str | None = None) -> dict | None:
    path = path or dbmod.PATHS["undo"]
    try:
        with open(_meta(path), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _forget(path: str) -> None:
    for p in (path, _meta(path)):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass


def undo(db, path: str | None = None) -> dict:
    path = path or dbmod.PATHS["undo"]
    change = last_change(path)
    if not change or not os.path.exists(path):
        raise LifeError("nothing to undo")

    db.conn.execute("PRAGMA foreign_keys = OFF")
    try:
        db.conn.execute("ATTACH DATABASE ? AS saved", (path,))
        try:
            # A copy from before an upgrade has a different shape; it cannot come back.
            version = db.one("PRAGMA main.user_version")["user_version"]
            saved = db.one("PRAGMA saved.user_version")["user_version"]
            if saved != version:
                db.conn.execute("DETACH DATABASE saved")
                _forget(path)
                raise LifeError("nothing to undo")

            def restore():
                for table in TABLES:
                    db.conn.execute(f"DELETE FROM main.{table}")
                    db.conn.execute(f"INSERT INTO main.{table} SELECT * FROM saved.{table}")

            db.transaction(restore)
        finally:
            if any(r["name"] == "saved" for r in db.all("PRAGMA database_list")):
                db.conn.execute("DETACH DATABASE saved")
    finally:
        db.conn.execute("PRAGMA foreign_keys = ON")

    _forget(path)
    return change
