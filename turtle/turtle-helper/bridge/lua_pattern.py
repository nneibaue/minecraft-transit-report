"""Lua pattern matching for sorting rules, by translation to Python regular expressions.

Sorting rules were written for Lua's ``string.find`` while they lived on the device (plan 02-01
removed that code under D-07; D-08 keeps the rules in the bridge's rules.json), so the bridge must
match item ids with Lua's pattern semantics rather than Python's: the ``%a``/``%d``/``%l``/...
classes, ``%`` as the escape character, ``[...]`` sets, the ``*``/``+``/``-``/``?`` quantifiers
(``-`` is Lua's lazy repeat) and the ``^``/``$`` anchors. ``%b``, ``%f`` and back-references
(``%1``) are not translated: a pattern using them is rejected with LuaPatternError, as is a
malformed one, so add_rule can refuse it before it is saved.
"""

from __future__ import annotations

import re
import string
from functools import lru_cache

# Lua's character classes (C locale) as the body of a Python character set.
CLASS_BODIES: dict[str, str] = {
    "a": "A-Za-z",
    "c": "\\x00-\\x1f\\x7f",
    "d": "0-9",
    "g": "\\x21-\\x7e",
    "l": "a-z",
    "p": re.escape(string.punctuation),
    "s": " \\t\\n\\r\\f\\v",
    "u": "A-Z",
    "w": "A-Za-z0-9",
    "x": "0-9A-Fa-f",
}
QUANTIFIERS: dict[str, str] = {"*": "*", "+": "+", "-": "*?", "?": "?"}


class LuaPatternError(ValueError):
    """The pattern is malformed, or uses a Lua feature this translation does not support."""


def matches(text: str, pattern: str) -> bool:
    """True when Lua's ``string.find(text, pattern)`` would find a match."""
    return compile_pattern(pattern).search(text) is not None


@lru_cache(maxsize=256)
def compile_pattern(pattern: str) -> re.Pattern[str]:
    """The compiled Python regex for a Lua pattern; raises LuaPatternError if it cannot be one."""
    try:
        return re.compile(to_regex(pattern), re.DOTALL)
    except re.error as exc:
        raise LuaPatternError(f"{pattern!r}: {exc}") from None


def to_regex(pattern: str) -> str:
    """Translate one Lua pattern to an equivalent Python regular expression."""
    out: list[str] = []
    end = len(pattern)
    i = 0
    if pattern.startswith("^"):
        out.append("\\A")
        i = 1
    while i < end:
        ch = pattern[i]
        if ch == "$" and i == end - 1:
            out.append("\\Z")
            break
        if ch in "()":
            # Captures do not change whether a pattern matches; keep the grouping only.
            out.append("(?:" if ch == "(" else ")")
            i += 1
            continue
        if ch == "%":
            atom, i = _escape(pattern, i)
        elif ch == "[":
            atom, i = _set(pattern, i)
        else:
            atom = "." if ch == "." else re.escape(ch)
            i += 1
        if i < end and pattern[i] in QUANTIFIERS:
            atom += QUANTIFIERS[pattern[i]]
            i += 1
        out.append(atom)
    return "".join(out)


def _escape(pattern: str, i: int) -> tuple[str, int]:
    """Translate the ``%x`` at pattern[i] into one regex atom; returns it and the next index."""
    if i + 1 >= len(pattern):
        raise LuaPatternError(f"{pattern!r}: pattern ends with '%'")
    c = pattern[i + 1]
    if c in "bf" or c.isdigit():
        raise LuaPatternError(f"{pattern!r}: '%{c}' is not supported in sorting rules")
    body = CLASS_BODIES.get(c.lower())
    if body is None:
        return re.escape(c), i + 2
    return ("[^" if c.isupper() else "[") + body + "]", i + 2


def _set(pattern: str, i: int) -> tuple[str, int]:
    """Translate the ``[...]`` set starting at pattern[i]; returns the atom and the next index."""
    end = len(pattern)
    j = i + 1
    negate = j < end and pattern[j] == "^"
    if negate:
        j += 1
    parts: list[str] = []
    first = True  # a ']' right after '[' or '[^' is a member, not the closing bracket
    while True:
        if j >= end:
            raise LuaPatternError(f"{pattern!r}: unfinished character set")
        c = pattern[j]
        if c == "]" and not first:
            j += 1
            break
        first = False
        if c == "%":
            if j + 1 >= end:
                raise LuaPatternError(f"{pattern!r}: pattern ends with '%'")
            e = pattern[j + 1]
            body = CLASS_BODIES.get(e.lower())
            if body is not None and e.isupper():
                raise LuaPatternError(f"{pattern!r}: '%{e}' inside a set is not supported")
            parts.append(body if body is not None else _set_member(e))
            j += 2
        elif j + 2 < end and pattern[j + 1] == "-" and pattern[j + 2] != "]":
            parts.append(_set_member(c) + "-" + _set_member(pattern[j + 2]))
            j += 3
        else:
            parts.append(_set_member(c))
            j += 1
    return ("[^" if negate else "[") + "".join(parts) + "]", j


def _set_member(c: str) -> str:
    """One literal character inside a Python character set."""
    return "\\" + c if c in "\\]^-[" else c
