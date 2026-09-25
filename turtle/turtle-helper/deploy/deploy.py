"""Deploy turtle-helper onto the local dedicated server (Phase 3, D-01..D-06, D-11, D-12).

    uv run deploy

Reads SERVER_DIR, HOST, PORT and BRIDGE_TOKEN from .env through ``bridge.settings``. Adds the
CC:Tweaked allow rule for 127.0.0.1 to ``world/serverconfig/computercraft-server.toml`` when the
server is stopped, then places the device files into every computer folder under
``world/computercraft/computer/`` that holds the ``_marker.txt`` opt-in file. Safe to re-run:
it is also the no-push redeploy step after any Lua edit (reboot the device afterwards).

startup.lua is copied from the repo like the other Lua (D-16), not generated here. On a device
holding ``_marker.txt`` that startup.lua skips its boot-time GitHub update, so a reboot keeps
the files deploy placed instead of replacing them with whatever ``main`` holds.

The bridge token is written to each marked folder's ``secret.txt`` and nowhere else: it is
never printed, logged or put in an exception message.

Exit codes: 0 done, 1 a deploy step failed, 2 invalid configuration.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import TypedDict

from pydantic import ValidationError

from bridge.settings import Settings
from deploy.rules import insert_allow_rule
from deploy.server_state import is_server_running

# The turtle-helper directory: base/chat.lua, turtle/client.lua and startup.lua are copied
# from here.
REPO_ROOT = Path(__file__).resolve().parent.parent

# The opt-in file the author creates at a computer's own prompt; unmarked folders are never
# touched, so the other turtles on the server never receive a bridge secret (D-03).
MARKER_NAME = "_marker.txt"

# Device file name -> path under the repo root. startup.lua is the repo file install.lua also
# downloads (D-16): one source of truth for the boot code.
LUA_SOURCES = {
    "chat.lua": ("base", "chat.lua"),
    "client.lua": ("turtle", "client.lua"),
    "startup.lua": ("startup.lua",),
}


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
            "startup.lua (all copied from the repo), secret.txt and bridge.txt into every "
            "marked computer folder under SERVER_DIR/world/computercraft/computer/. Marked "
            "devices skip startup.lua's GitHub update at boot."
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


def scan_marked_folders(computer_root: Path, marker_name: str = MARKER_NAME) -> list[Path]:
    """Computer folders holding the opt-in marker file, numeric ids in numeric order."""
    marked = [
        folder
        for folder in computer_root.iterdir()
        if folder.is_dir() and (folder / marker_name).is_file()
    ]
    return sorted(marked, key=folder_sort_key)


def folder_sort_key(folder: Path) -> tuple[int, int, str]:
    """Numeric computer ids first and in numeric order (5 before 10), anything else after."""
    name = folder.name
    return (0, int(name), name) if name.isdigit() else (1, 0, name)


def deploy_to_folder(folder: Path, settings: Settings, repo_root: Path) -> list[str]:
    """Write the device files into one marked folder; the sorted names written.

    chat.lua, client.lua and startup.lua are byte-identical copies of the repo files; startup.lua
    is the repo's own boot script (D-16), which skips its GitHub update on this marked device.
    Every source is checked before anything is written, so a missing repo file raises
    FileNotFoundError naming only its repo-relative path and leaves the folder untouched.
    Every file is overwritten on every run, with no merge against what was there, so a Lua
    edit, a token rotation or a hand-edited startup.lua all converge on one re-run. The token
    goes into secret.txt and nowhere else.
    """
    sources = {name: repo_root.joinpath(*parts) for name, parts in LUA_SOURCES.items()}
    for name, source in sources.items():
        if not source.is_file():
            raise FileNotFoundError(f"repo file missing: {'/'.join(LUA_SOURCES[name])}")
    for name, source in sources.items():
        shutil.copy2(source, folder / name)
    # write_bytes, not write_text: text mode on Windows would turn LF into CRLF.
    (folder / "secret.txt").write_bytes(settings.bridge_token.encode("utf-8"))
    bridge_url = f"ws://{settings.host}:{settings.port}"
    (folder / "bridge.txt").write_bytes(bridge_url.encode("utf-8"))
    return sorted(["bridge.txt", "chat.lua", "client.lua", "secret.txt", "startup.lua"])


def deploy_marked_folders(settings: Settings, repo_root: Path = REPO_ROOT) -> list[DeployRow]:
    """Place the device files into every marked computer folder; one row per folder."""
    if settings.server_dir is None:
        raise ValueError("SERVER_DIR is required for deploy")
    computer_root = settings.server_dir / "world" / "computercraft" / "computer"
    if not computer_root.is_dir():
        print(f"{computer_root} not found; no computers have been placed yet -- skipping")
        return []
    folders = scan_marked_folders(computer_root)
    if not folders:
        print(
            f"no computer under {computer_root} has a {MARKER_NAME} yet; create one at the "
            "computer's own prompt (edit _marker.txt, save, exit) and re-run"
        )
        return []
    return [
        {"id": folder.name, "files": deploy_to_folder(folder, settings, repo_root)}
        for folder in folders
    ]


def print_summary(rows: list[DeployRow]) -> None:
    """The computer id and files-written table; never any file contents."""
    if not rows:
        return
    width = max(len("computer"), *(len(row["id"]) for row in rows))
    print(f"{'computer':<{width}}  files written")
    for row in rows:
        print(f"{row['id']:<{width}}  {', '.join(row['files'])}")
    print("reboot each computer listed above to load the new files")


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
