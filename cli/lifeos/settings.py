"""Settings, with their defaults. Times are local "HH:MM"."""

import re

from store import LifeError

DEFAULTS = {
    # Strict mode: log only today or yesterday, a morning plan and evening
    # shutdown that open on their own, and a typed confirmation before a
    # habit with a streak can be deleted.
    "strict": "off",
    # Ask for the day's priorities when the day is not yet planned.
    "plan": "on",
    "morning": "08:00",
    "remind": "20:00",
    "shutdown": "21:00",
    "bedtime": "23:00",
    "notify": "on",
    # How notifications talk: gentle, coach, or savage (and savage nags).
    "tone": "coach",
}

TIME_KEYS = ("morning", "remind", "shutdown", "bedtime")
SWITCH_KEYS = ("strict", "plan", "notify")
TONES = ("gentle", "coach", "savage")


def read_settings(db) -> dict:
    out = dict(DEFAULTS)
    for row in db.all("SELECT key, value FROM settings"):
        if row["key"] in DEFAULTS:
            out[row["key"]] = row["value"]
    return out


def _normalize_time(value: str) -> str | None:
    m = re.fullmatch(r"(\d{1,2})(?::?(\d{2}))?", value.strip())
    if not m:
        return None
    h, mins = int(m.group(1)), int(m.group(2) or 0)
    if h > 23 or mins > 59:
        return None
    return f"{h:02d}:{mins:02d}"


def _normalize_switch(value: str) -> str | None:
    v = value.strip().lower()
    if v in ("on", "true", "yes", "1"):
        return "on"
    if v in ("off", "false", "no", "0"):
        return "off"
    return None


def write_setting(db, key: str, value: str) -> None:
    if key not in DEFAULTS:
        raise LifeError(f'unknown setting "{key}" — one of {", ".join(DEFAULTS)}')
    if key in TIME_KEYS:
        normalized = _normalize_time(value)
    elif key in SWITCH_KEYS:
        normalized = _normalize_switch(value)
    elif key == "tone":
        v = value.strip().lower()
        normalized = v if v in TONES else None
    else:
        normalized = value
    if normalized is None:
        if key in TIME_KEYS:
            raise LifeError(f"{key} needs a time like 21:00")
        if key == "tone":
            raise LifeError("tone is gentle, coach or savage")
        raise LifeError(f"{key} is on or off")
    db.run("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value", key, normalized)


def clock(now) -> str:
    """ "HH:MM" of a datetime, for comparing against settings."""
    return f"{now.hour:02d}:{now.minute:02d}"


def shift_clock(time: str, minutes: int) -> str:
    h, m = (int(p) for p in time.split(":"))
    total = max(0, min(24 * 60 - 1, h * 60 + m + minutes))
    return f"{total // 60:02d}:{total % 60:02d}"
