"""The SQLite database: where it lives, its schema, and opening it privately."""

import os
import sqlite3

HOME = os.path.expanduser("~")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
STATE_HOME = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state")

PATHS = {
    "db": os.environ.get("LIFEOS_DB") or os.path.join(DATA_HOME, "lifeos/lifeos.db"),
    "state": os.environ.get("LIFEOS_STATE") or os.path.join(STATE_HOME, "lifeos/state.json"),
    "undo": os.environ.get("LIFEOS_UNDO") or os.path.join(STATE_HOME, "lifeos/undo.db"),
}

# Each entry moves the schema one version forward. Never edit a shipped
# migration; append a new one. (The same SQL the TypeScript CLI shipped, so
# existing databases open unchanged.)
MIGRATIONS = [
    """
  CREATE TABLE tasks (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL,
    due        TEXT,
    done_on    TEXT,
    created_on TEXT NOT NULL
  );

  -- kind: check = did it or not, count = reach a target, avoid = stay clean.
  -- days: scheduled weekdays as a bitmask, bit 0 = Monday.
  CREATE TABLE habits (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL CHECK (kind IN ('check', 'count', 'avoid')),
    target     INTEGER NOT NULL DEFAULT 1,
    unit       TEXT NOT NULL DEFAULT '',
    days       INTEGER NOT NULL DEFAULT 127,
    position   INTEGER NOT NULL DEFAULT 0,
    created_on TEXT NOT NULL
  );

  -- check: value 1 = done. count: value = how many. avoid: value 1 = slipped.
  CREATE TABLE habit_logs (
    habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    day      TEXT NOT NULL,
    value    INTEGER NOT NULL,
    PRIMARY KEY (habit_id, day)
  );

  CREATE TABLE books (
    id          INTEGER PRIMARY KEY,
    title       TEXT NOT NULL,
    total_pages INTEGER NOT NULL CHECK (total_pages > 0),
    created_on  TEXT NOT NULL,
    finished_on TEXT
  );

  CREATE TABLE reading_logs (
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    day     TEXT NOT NULL,
    pages   INTEGER NOT NULL,
    PRIMARY KEY (book_id, day)
  );

  CREATE TABLE events (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL,
    day        TEXT NOT NULL,
    emoji      TEXT NOT NULL DEFAULT '',
    created_on TEXT NOT NULL
  );
    """,
    """
  -- focus_on: the day this task is one of the day's (at most three) priorities.
  -- dropped_on: decided against at shutdown; kept for the record, never shown.
  ALTER TABLE tasks ADD COLUMN focus_on TEXT;
  ALTER TABLE tasks ADD COLUMN dropped_on TEXT;

  -- One row per day that was planned in the morning or shut down at night.
  CREATE TABLE days (
    day         TEXT PRIMARY KEY,
    planned_at  TEXT,
    shutdown_at TEXT
  );

  CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );

  -- Notifications already sent, so each fires once however many bars ask.
  CREATE TABLE notified (
    key TEXT PRIMARY KEY,
    at  TEXT NOT NULL
  );
    """,
    """
  -- People and their birthdays. The year is optional: without it LifeOS
  -- still counts down, it just cannot say how old they turn.
  CREATE TABLE people (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    month      INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    day        INTEGER NOT NULL CHECK (day BETWEEN 1 AND 31),
    year       INTEGER,
    created_on TEXT NOT NULL
  );

  -- A habit's own reminder time, "HH:MM", or NULL for the evening one only.
  ALTER TABLE habits ADD COLUMN remind_at TEXT;

  -- The evening check-in: how the day felt (1–5) and one line about it.
  ALTER TABLE days ADD COLUMN mood INTEGER CHECK (mood BETWEEN 1 AND 5);
  ALTER TABLE days ADD COLUMN note TEXT;
    """
]


def make_private(path: str, mode: int) -> None:
    """Tasks, habits and reading are personal: readable by you alone."""
    if os.path.exists(path):
        os.chmod(path, mode)


def private_dir(path: str) -> None:
    os.makedirs(path, mode=0o700, exist_ok=True)
    # makedirs leaves an existing directory alone, so tighten one made earlier.
    make_private(path, 0o700)


class Db:
    """A thin wrapper so the rest of the code reads like the TypeScript it
    came from: one() for a row, all() for rows, run() for a change count."""

    def __init__(self, path: str):
        self.path = path
        self.conn = sqlite3.connect(path, timeout=2, isolation_level=None)
        self.conn.row_factory = sqlite3.Row

    def one(self, sql: str, *args):
        row = self.conn.execute(sql, args).fetchone()
        return dict(row) if row is not None else None

    def all(self, sql: str, *args) -> list[dict]:
        return [dict(r) for r in self.conn.execute(sql, args).fetchall()]

    def run(self, sql: str, *args) -> int:
        return self.conn.execute(sql, args).rowcount

    def exec(self, script: str) -> None:
        self.conn.executescript(script)

    def transaction(self, fn):
        self.conn.execute("BEGIN")
        try:
            result = fn()
        except BaseException:
            self.conn.execute("ROLLBACK")
            raise
        self.conn.execute("COMMIT")
        return result

    def serialize(self) -> bytes:
        return self.conn.serialize()

    def close(self) -> None:
        self.conn.close()


def open_db(path: str | None = None) -> Db:
    path = path or PATHS["db"]
    if path != ":memory:":
        private_dir(os.path.dirname(path))
    # SQLite creates the -wal and -shm companions itself; the umask covers them.
    previous = os.umask(0o077)
    try:
        db = Db(path)
        db.conn.execute("PRAGMA journal_mode = WAL")
        db.conn.execute("PRAGMA foreign_keys = ON")
        db.conn.execute("PRAGMA busy_timeout = 2000")
        migrate(db)
        if path != ":memory:":
            for suffix in ("", "-wal", "-shm"):
                make_private(path + suffix, 0o600)
        return db
    finally:
        os.umask(previous)


def migrate(db: Db) -> None:
    version = db.one("PRAGMA user_version")["user_version"]
    while version < len(MIGRATIONS):
        # executescript would commit on its own; run each statement inside one transaction.
        # (The migrations hold no "--" inside string literals, so comments can go first.)
        code = "\n".join(line.split("--", 1)[0] for line in MIGRATIONS[version].splitlines())
        statements = [s for s in code.split(";") if s.strip()]
        def step(v=version):
            for statement in statements:
                db.conn.execute(statement)
            db.conn.execute(f"PRAGMA user_version = {v + 1}")
        db.transaction(step)
        version += 1
