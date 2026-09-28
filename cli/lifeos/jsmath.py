"""Small helpers that behave exactly like their JavaScript counterparts, so the
Python CLI produces the same numbers the TypeScript one did."""

import math


def js_round(x: float) -> int:
    """Math.round: halves go up (toward +infinity), unlike Python's round()."""
    return math.floor(x + 0.5)


def to_int32(x: int) -> int:
    return ((x & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000


def imul(a: int, b: int) -> int:
    """Math.imul: 32-bit signed multiplication."""
    return to_int32(to_int32(a) * to_int32(b))


def js_number(value) -> float | None:
    """Number(text) for the inputs a CLI sees: trims, "" is 0, junk is NaN (None)."""
    if value is None:
        return None
    text = str(value).strip()
    if text == "":
        return 0.0
    try:
        n = float(text)
    except ValueError:
        return None
    if math.isnan(n):
        return None
    return n


def plain(value):
    """JSON.stringify prints 1 for 1.0: turn whole floats into ints, deeply."""
    if isinstance(value, float):
        return int(value) if value.is_integer() else value
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items()}
    if isinstance(value, list):
        return [plain(v) for v in value]
    return value
