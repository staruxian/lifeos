"""Calendar days are plain "YYYY-MM-DD" strings in local time. Everything in
LifeOS happens on a day, never at an instant, so there is no timezone math
beyond "what is today here"."""

import datetime as dt
import os
import re

EVERY_DAY = 0b1111111

MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
WEEKDAY_NAMES = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def now() -> dt.datetime:
    """The current local time; LIFEOS_NOW ("2026-09-25T20:30:00") pins it for tests."""
    pinned = os.environ.get("LIFEOS_NOW")
    return dt.datetime.fromisoformat(pinned) if pinned else dt.datetime.now()


def to_day(date: dt.date) -> str:
    return f"{date.year:04d}-{date.month:02d}-{date.day:02d}"


def from_day(day: str) -> dt.date:
    y, m, d = (int(p) for p in day.split("-"))
    return dt.date(y, m, d)


def today(at: dt.datetime | None = None) -> str:
    return to_day(at or now())


def add_days(day: str, n: int) -> str:
    return to_day(from_day(day) + dt.timedelta(days=n))


def diff_days(a: str, b: str) -> int:
    return (from_day(b) - from_day(a)).days


def weekday(day: str) -> int:
    """0 = Monday … 6 = Sunday."""
    return from_day(day).weekday()


def is_day(value: str) -> bool:
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return False
    try:
        return to_day(from_day(value)) == value
    except ValueError:
        return False


def _weekday_index(word: str) -> int:
    """Any unambiguous prefix of two letters or more: "tu", "thurs", "friday"."""
    w = word.lower()
    if len(w) < 2:
        return -1
    return next((i for i, name in enumerate(WEEKDAY_NAMES) if name.startswith(w)), -1)


def month_index(word: str) -> int:
    w = word.lower()
    if len(w) < 3:
        return -1
    return next((i for i, name in enumerate(MONTHS) if w.startswith(name)), -1)


def _date_or_none(year: int, month0: int, day: int) -> str | None:
    """new Date(y, m, d) that must not roll over into another month."""
    try:
        return to_day(dt.date(year, month0 + 1, day)) if 0 <= month0 <= 11 else None
    except ValueError:
        return None


def _upcoming(base: str, month0: int, day: int) -> str | None:
    """A month/day with no year means the next time that date comes around."""
    year = from_day(base).year
    for y in (year, year + 1):
        candidate = _date_or_none(y, month0, day)
        if candidate is None:
            return None
        if diff_days(base, candidate) >= 0:
            return candidate
    return None


def _add_months(day: str, n: int) -> str:
    """Date.setMonth(month + n): an overflowing day spills into the next month."""
    d = from_day(day)
    total = d.month - 1 + n
    y, m0 = d.year + total // 12, total % 12
    return to_day(dt.date(y, m0 + 1, 1) + dt.timedelta(days=d.day - 1))


def parse_day(text_in: str, base: str | None = None) -> str | None:
    """today, tomorrow, fri, next mon, in 3 days, 2w, +5, 2026-11-03, 3.11,
    03.11.2026, nov 3, 3 nov, november 3 2026."""
    base = base or today()
    text = re.sub(r"\s+", " ", text_in.strip().lower())
    if text == "":
        return None
    if is_day(text):
        return text
    if text in ("today", "tod"):
        return base
    if text in ("tomorrow", "tmr", "tom"):
        return add_days(base, 1)
    if text == "yesterday":
        return add_days(base, -1)

    m = re.fullmatch(r"(?:in )?\+?(\d+) ?(d|day|days|w|wk|week|weeks|m|mo|month|months)?", text)
    if m and (m.group(2) or text.startswith("+") or text.startswith("in ")):
        n = int(m.group(1))
        unit = m.group(2) or "d"
        if unit.startswith("w"):
            return add_days(base, n * 7)
        if unit.startswith("m"):
            return _add_months(base, n)
        return add_days(base, n)

    m = re.fullmatch(r"(next )?([a-z]+)", text)
    if m:
        index = _weekday_index(m.group(2))
        if index >= 0:
            # "fri" is the coming Friday, today included; "next fri" skips today.
            delta = (index - weekday(base) + 7) % 7
            if m.group(1) and delta == 0:
                delta = 7
            return add_days(base, delta)

    # Day-first numerics, the way most of the world writes them.
    m = re.fullmatch(r"(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?", text)
    if m:
        d, mo = int(m.group(1)), int(m.group(2)) - 1
        if m.group(3):
            y = int("20" + m.group(3) if len(m.group(3)) == 2 else m.group(3))
            return _date_or_none(y, mo, d)
        return _upcoming(base, mo, d)

    m = re.fullmatch(r"([a-z]+) (\d{1,2})(?:,? (\d{4}))?", text)
    if m:
        mo = month_index(m.group(1))
        if mo >= 0:
            return _date_or_none(int(m.group(3)), mo, int(m.group(2))) if m.group(3) else _upcoming(base, mo, int(m.group(2)))

    m = re.fullmatch(r"(\d{1,2}) ([a-z]+)(?:,? (\d{4}))?", text)
    if m:
        mo = month_index(m.group(2))
        if mo >= 0:
            return _date_or_none(int(m.group(3)), mo, int(m.group(1))) if m.group(3) else _upcoming(base, mo, int(m.group(1)))

    return None


def parse_weekdays(text_in: str) -> int | None:
    """Scheduled weekdays as a 7-bit mask, bit 0 = Monday."""
    text = text_in.strip().lower()
    if text in ("", "daily", "everyday", "every day"):
        return EVERY_DAY
    if text == "weekdays":
        return 0b0011111
    if text == "weekends":
        return 0b1100000
    mask = 0
    for part in re.split(r"[\s,]+", text):
        if not part:
            continue
        index = _weekday_index(part)
        if index < 0:
            return None
        mask |= 1 << index
    return None if mask == 0 else mask


def is_scheduled(mask: int, day: str) -> bool:
    return (mask & (1 << weekday(day))) != 0


def parse_birthday(text_in: str) -> dict | None:
    """ "12.10", "12.10.2001", "12/10/01", "2001-10-12", "oct 12", "12 october 2001"."""
    text = re.sub(r"\s+", " ", text_in.strip().lower().replace(",", " "))
    y = None
    if m := re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", text):
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    elif m := re.fullmatch(r"(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?", text):
        d, mo = int(m.group(1)), int(m.group(2))
        if m.group(3):
            yy = m.group(3)
            y = ((1900 if int(yy) > 30 else 2000) + int(yy)) if len(yy) == 2 else int(yy)
    elif (m := re.fullmatch(r"([a-z]+) (\d{1,2})(?: (\d{4}))?", text)) and month_index(m.group(1)) >= 0:
        mo, d = month_index(m.group(1)) + 1, int(m.group(2))
        y = int(m.group(3)) if m.group(3) else None
    elif (m := re.fullmatch(r"(\d{1,2}) ([a-z]+)(?: (\d{4}))?", text)) and month_index(m.group(2)) >= 0:
        d, mo = int(m.group(1)), month_index(m.group(2)) + 1
        y = int(m.group(3)) if m.group(3) else None
    else:
        return None

    if mo < 1 or mo > 12 or d < 1:
        return None
    # Feb 29 is a real birthday; check against a leap year when none is given.
    if _date_or_none(y if y is not None else 2000, mo - 1, d) is None:
        return None
    if y is not None and (y < 1900 or to_day(dt.date(y, mo, d)) > today()):
        return None
    return {"month": mo, "day": d, "year": y}


def next_birthday(b: dict, base: str) -> str:
    """The next time the birthday comes round, today included. Feb 29 falls on
    Feb 28 in common years."""
    year = from_day(base).year
    for y in (year, year + 1):
        day = _date_or_none(y, b["month"] - 1, b["day"]) or _date_or_none(y, b["month"] - 1, 28)
        if day >= base:
            return day
    return base
