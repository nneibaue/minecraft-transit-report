"""The CC:Tweaked ``[[http.rules]]`` allow rule for 127.0.0.1 (Phase 3, D-11 / D-12).

CC:Tweaked denies private and local addresses by default through a ``$private`` deny rule, and
evaluates rules top to bottom, so the allow rule must sit before that deny. This is a plain text
insertion, not a TOML rewrite: Forge regenerates the file's comments on boot but keeps values
and rule order, and a text edit leaves everything else in the file byte-for-byte alone.
"""

from __future__ import annotations

import re
from pathlib import Path

# The stock private-address deny block, byte-for-byte as CC:Tweaked writes it into
# world/serverconfig/computercraft-server.toml (one tab before the table header, two before
# each key).
PRIVATE_DENY_ANCHOR = '\t[[http.rules]]\n\t\thost = "$private"\n\t\taction = "deny"\n'


def allow_block(host: str = "127.0.0.1") -> str:
    """The exact block this module inserts, in the anchor's own indentation."""
    return f'\t[[http.rules]]\n\t\thost = "{host}"\n\t\taction = "allow"\n'


def rule_already_present(content: str, host: str = "127.0.0.1") -> bool:
    """True when a ``host = "<host>"`` line is followed, next non-blank line, by an allow.

    This recognises this module's own prior output (and the same rule typed by hand), which
    is what makes a second deploy run a no-op. It is not a general TOML parse.
    """
    host_line = re.compile(rf'^\s*host\s*=\s*"{re.escape(host)}"\s*$')
    allow_line = re.compile(r'^\s*action\s*=\s*"allow"\s*$')
    lines = [line for line in content.splitlines() if line.strip()]
    return any(
        host_line.match(line) and allow_line.match(nxt)
        for line, nxt in zip(lines, lines[1:], strict=False)
    )


def insert_allow_rule(toml_path: Path, host: str = "127.0.0.1") -> bool:
    """Insert the allow rule before the ``$private`` deny; True if the file changed.

    Returns False without writing when the rule is already there. Raises ValueError when the
    stock ``$private`` deny block is missing, rather than guessing where the rule should go.
    """
    # newline="" on both ends keeps the file's own line endings (LF or CRLF) untouched;
    # a default text-mode write on Windows would turn every LF in the file into CRLF.
    with toml_path.open(encoding="utf-8", newline="") as f:
        content = f.read()
    if rule_already_present(content, host):
        return False
    eol = "\r\n" if "\r\n" in content else "\n"
    index = content.find(PRIVATE_DENY_ANCHOR.replace("\n", eol))
    if index < 0:
        raise ValueError(
            f'{toml_path}: stock [[http.rules]] block with host = "$private" / '
            'action = "deny" not found; add the 127.0.0.1 allow rule by hand before it'
        )
    block = allow_block(host).replace("\n", eol)
    updated = content[:index] + block + eol + content[index:]
    with toml_path.open("w", encoding="utf-8", newline="") as f:
        f.write(updated)
    return True
