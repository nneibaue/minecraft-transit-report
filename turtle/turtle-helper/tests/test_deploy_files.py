"""Zero-network checks for deploy's marker scan and per-device file placement (Phase 3 plan 03-01).

Everything runs inside temp directories: a fake repo tree (base/chat.lua, turtle/client.lua)
and a fake server tree (world/computercraft/computer/<id>/). No real server, no bridge, no
.env. Same dependency-free TAP layout as tests/test_harness_scenarios.py; every ``test_*``
function is pytest-collectable later.

    uv run python tests/test_deploy_files.py
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import traceback
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bridge.settings import Settings  # noqa: E402
from deploy import deploy as d  # noqa: E402

TOKEN = "fixture-token-9c1e"
CHAT_LUA = b"-- fixture chat.lua\r\nprint('chat')\n\xe2\x9c\x93\n"
CLIENT_LUA = b"-- fixture client.lua\nprint('client')\n"
ALL_FILES = ["bridge.txt", "chat.lua", "client.lua", "secret.txt", "startup.lua"]


def make_settings(**overrides: Any) -> Settings:
    """A Settings for tests that never reads the .env file on this machine."""
    values: dict[str, Any] = {
        "bridge_token": TOKEN,
        "allowed_players": ["Nate"],
        "anthropic_api_key": "sk-ant-test",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


@dataclass
class Fixture:
    repo: Path
    server: Path
    computers: Path


@contextlib.contextmanager
def fixture() -> Iterator[Fixture]:
    """Fake repo plus fake server: computers 5 and 10 are marked, 6 is not."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        repo, server = root / "repo", root / "server"
        (repo / "base").mkdir(parents=True)
        (repo / "turtle").mkdir()
        (repo / "base" / "chat.lua").write_bytes(CHAT_LUA)
        (repo / "turtle" / "client.lua").write_bytes(CLIENT_LUA)
        computers = server / "world" / "computercraft" / "computer"
        for cid in ("5", "6", "10"):
            (computers / cid).mkdir(parents=True)
        (computers / "5" / "_marker.txt").write_bytes(b"")
        (computers / "10" / "_marker.txt").write_bytes(b"")
        (computers / "6" / "quarry.lua").write_bytes(b"-- someone else's turtle\n")
        yield Fixture(repo, server, computers)


def snapshot(folder: Path) -> dict[str, bytes]:
    return {p.name: p.read_bytes() for p in sorted(folder.iterdir()) if p.is_file()}


def test_scan_finds_marked_folders_and_skips_unmarked() -> None:
    with fixture() as fx:
        found = d.scan_marked_folders(fx.computers)
        assert [p.name for p in found] == ["5", "10"], found


def test_deploy_writes_byte_identical_lua_copies() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        written = d.deploy_to_folder(folder, make_settings(server_dir=fx.server), fx.repo)
        assert written == ALL_FILES, written
        assert (folder / "chat.lua").read_bytes() == CHAT_LUA
        assert (folder / "client.lua").read_bytes() == CLIENT_LUA


def test_secret_txt_holds_exactly_the_token() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        d.deploy_to_folder(folder, make_settings(server_dir=fx.server), fx.repo)
        assert (folder / "secret.txt").read_bytes() == TOKEN.encode("utf-8")


def test_bridge_txt_is_the_ipv4_literal_url() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        d.deploy_to_folder(folder, make_settings(server_dir=fx.server), fx.repo)
        url = (folder / "bridge.txt").read_bytes()
        assert url == b"ws://127.0.0.1:8765", url
        assert b"localhost" not in url


def test_startup_lua_detects_role_and_is_always_overwritten() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        settings = make_settings(server_dir=fx.server)
        d.deploy_to_folder(folder, settings, fx.repo)
        first = (folder / "startup.lua").read_text(encoding="utf-8")
        assert 'peripheral.find("chatBox")' in first
        assert 'shell.run("chat")' in first and 'shell.run("client")' in first
        (folder / "startup.lua").write_text("-- hand edit\nshell.run('quarry')\n")
        d.deploy_to_folder(folder, settings, fx.repo)
        assert (folder / "startup.lua").read_text(encoding="utf-8") == first


def test_second_run_is_byte_identical() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        settings = make_settings(server_dir=fx.server)
        d.deploy_to_folder(folder, settings, fx.repo)
        first = snapshot(folder)
        d.deploy_to_folder(folder, settings, fx.repo)
        assert snapshot(folder) == first
        assert set(ALL_FILES) <= set(first)


def test_token_rotation_rewrites_secret_txt() -> None:
    with fixture() as fx:
        folder = fx.computers / "5"
        d.deploy_to_folder(folder, make_settings(server_dir=fx.server), fx.repo)
        rotated = make_settings(server_dir=fx.server, bridge_token="rotated-token")
        d.deploy_to_folder(folder, rotated, fx.repo)
        assert (folder / "secret.txt").read_bytes() == b"rotated-token"


def test_marked_folders_get_rows_and_unmarked_is_untouched() -> None:
    with fixture() as fx:
        before = snapshot(fx.computers / "6")
        rows = d.deploy_marked_folders(make_settings(server_dir=fx.server), repo_root=fx.repo)
        assert rows == [{"id": "5", "files": ALL_FILES}, {"id": "10", "files": ALL_FILES}], rows
        assert snapshot(fx.computers / "6") == before


def test_missing_computer_root_is_reported_not_raised() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rows = d.deploy_marked_folders(make_settings(server_dir=Path(tmp)))
        assert rows == []
        assert "no computers have been placed yet" in out.getvalue()


def test_token_never_reaches_stdout_or_stderr() -> None:
    with fixture() as fx:
        settings = make_settings(server_dir=fx.server)
        out, err = io.StringIO(), io.StringIO()
        with (
            patch.object(d, "Settings", lambda: settings),
            patch.object(d, "REPO_ROOT", fx.repo),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            assert d.main([]) == 0
            d.deploy_marked_folders(settings, repo_root=fx.repo)
        printed = out.getvalue() + err.getvalue()
        assert (fx.computers / "5" / "secret.txt").exists(), "deploy wrote nothing"
        assert TOKEN not in printed
        assert "5" in printed and "10" in printed and "bridge.txt" in printed


TESTS: list[Callable[[], None]] = [
    test_scan_finds_marked_folders_and_skips_unmarked,
    test_deploy_writes_byte_identical_lua_copies,
    test_secret_txt_holds_exactly_the_token,
    test_bridge_txt_is_the_ipv4_literal_url,
    test_startup_lua_detects_role_and_is_always_overwritten,
    test_second_run_is_byte_identical,
    test_token_rotation_rewrites_secret_txt,
    test_marked_folders_get_rows_and_unmarked_is_untouched,
    test_missing_computer_root_is_reported_not_raised,
    test_token_never_reaches_stdout_or_stderr,
]


def main() -> int:
    passed = failed = 0
    print(f"1..{len(TESTS)}")
    for n, fn in enumerate(TESTS, 1):
        try:
            fn()
        except Exception as exc:
            failed += 1
            print(f"not ok {n} - {fn.__name__}")
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            print("  ---")
            print(f"  error: {detail}")
            print("  ...")
        else:
            passed += 1
            print(f"ok {n} - {fn.__name__}")
    print(f"# tests {len(TESTS)}")
    print(f"# pass {passed}")
    print(f"# fail {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
