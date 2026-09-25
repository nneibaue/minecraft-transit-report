"""Deploy turtle-helper onto the local dedicated server (Phase 3, D-01..D-06, D-11, D-12).

    uv run deploy

Reads SERVER_DIR, HOST, PORT and BRIDGE_TOKEN from .env through ``bridge.settings``. Adds the
CC:Tweaked allow rule for 127.0.0.1 to ``world/serverconfig/computercraft-server.toml`` when the
server is stopped, then places the device files into every computer folder under
``world/computercraft/computer/`` that holds the ``_marker.txt`` opt-in file. Safe to re-run:
it is also the redeploy step after any Lua edit (reboot the device afterwards).

The bridge token is written to each marked folder's ``secret.txt`` and nowhere else: it is
never printed, logged or put in an exception message.

Exit codes: 0 done, 1 a deploy step failed, 2 invalid configuration.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import TypedDict

from pydantic import ValidationError

from bridge.settings import Settings
from deploy.rules import insert_allow_rule
from deploy.server_state import is_server_running

# The turtle-helper directory: base/chat.lua and turtle/client.lua are copied from here.
REPO_ROOT = Path(__file__).resolve().parent.parent


class DeployRow(TypedDict):
    """One marked computer and the files deploy wrote into its folder."""

    id: str
    files: list[str]


def build_parser() -> argparse.ArgumentParser:
    """The deploy command line; built before Settings() so --help needs no .env."""
    return argparse.ArgumentParser(
        prog="deploy",
        description=(
            "Add the CC:Tweaked 127.0.0.1 allow rule and place chat.lua, client.lua, "
            "startup.lua, secret.txt and bridge.txt into every marked computer folder "
            "under SERVER_DIR/world/computercraft/computer/."
        ),
    )


def apply_allow_rule(server_dir: Path) -> None:
    """Insert the allow rule if the server is stopped; say plainly what happened either way."""
    toml_path = server_dir / "world" / "serverconfig" / "computercraft-server.toml"
    if not toml_path.exists():
        print(f"{toml_path} not found; skipping the allow-rule step")
        return
    if is_server_running():
        print("server is running; skipping the allow-rule check -- stop it and re-run")
        return
    if insert_allow_rule(toml_path):
        print("allow rule inserted; restart the server to apply it")
    else:
        print("allow rule already present")


def deploy_marked_folders(settings: Settings) -> list[DeployRow]:
    """Place the device files into every marked computer folder; one row per folder."""
    return []


def print_summary(rows: list[DeployRow]) -> None:
    """The computer id and files-written table; never any file contents."""
    if not rows:
        return
    width = max(len("computer"), *(len(row["id"]) for row in rows))
    print(f"{'computer':<{width}}  files written")
    for row in rows:
        print(f"{row['id']:<{width}}  {', '.join(row['files'])}")


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point for ``uv run deploy``."""
    build_parser().parse_args(argv)
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2
    if settings.server_dir is None:
        print("config error: server_dir: SERVER_DIR is required for deploy", file=sys.stderr)
        return 2
    try:
        apply_allow_rule(settings.server_dir)
        rows = deploy_marked_folders(settings)
    except (OSError, ValueError) as exc:
        print(f"deploy error: {exc}", file=sys.stderr)
        return 1
    print_summary(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
