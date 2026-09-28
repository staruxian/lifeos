"""What the quick-add box understands:
  pay rent fri          task, due Friday
  call mom next mon     task, due next Monday
  renew passport due:12.10
  ship the release!     task, one of today's priorities (due today)
  read 20               log 20 pages to the book you are reading"""

import re

from dates import parse_day


def parse_quick(text_in: str, today: str) -> dict | None:
    text = re.sub(r"\s+", " ", text_in.strip())
    if text == "":
        return None

    if m := re.fullmatch(r"read (\d+)(?: pages?)?", text, re.I):
        return {"kind": "read", "pages": int(m.group(1))}

    focus = False
    if re.search(r"!+$", text):
        focus = True
        text = re.sub(r"\s*!+$", "", text)
    elif re.match(r"!+\s*", text):
        focus = True
        text = re.sub(r"^!+\s*", "", text)

    due = None
    if tagged := re.search(r"(?:^|\s)due:(\S+(?:\s\d{1,2})?)$", text, re.I):
        due = parse_day(tagged.group(1), today)
        if due:
            text = text[:tagged.start()].strip()

    # The longest tail that reads as a date wins: "in 3 days", "next mon", "nov 3", "fri".
    # A date alone is not a task, so at least one word must remain.
    if not due:
        words = text.split(" ")
        for n in range(min(3, len(words) - 1), 0, -1):
            tail = " ".join(words[-n:])
            # Bare numbers and two-letter words ("we", "tu") are too easily just words.
            day = None if re.fullmatch(r"\d+", tail) or (n == 1 and len(tail) < 3) else parse_day(tail, today)
            if day:
                due = day
                text = " ".join(words[:-n])
                text = re.sub(r"\s+(?:on|by|due)$", "", text, flags=re.I)  # "on fri", "by tomorrow"
                break

    if text == "":
        return None
    if focus and (not due or due > today):
        due = today
    return {"kind": "task", "title": text, "due": due, "focus": focus}
