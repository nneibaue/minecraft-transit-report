"""Zero-network checks for the allow rule, server probe and launcher (Phase 3 plan 03-01).

No real server, no bridge, no .env: rules.py runs against temp files, the server probe
against a throwaway local listener, and launcher.main() against a patched Settings. Same
dependency-free TAP layout as tests/test_harness_scenarios.py; every ``test_*`` function is
pytest-collectable later.

    uv run python tests/test_deploy_rules.py
"""

from __future__ import annotations

import contextlib
import io
import socket
import sys
import tempfile
import traceback
from collections.abc import Callable
from pathlib import Path
from typing import Any
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bridge.settings import Settings  # noqa: E402
from deploy import launcher  # noqa: E402
from deploy.rules import (  # noqa: E402
    PRIVATE_DENY_ANCHOR,
    insert_allow_rule,
    rule_already_present,
)
from deploy.server_state import is_server_running  # noqa: E402

TOKEN = "fixture-token-4f2a"
STOCK = (
    "[http]\n\tenabled = true\n\n"
    + PRIVATE_DENY_ANCHOR
    + '\n\t[[http.rules]]\n\t\thost = "*"\n\t\taction = "allow"\n'
)


def make_settings(**overrides: Any) -> Settings:
    """A Settings for tests that never reads the .env file on this machine."""
    values: dict[str, Any] = {
        "bridge_token": TOKEN,
        "allowed_players": ["Nate"],
        "anthropic_api_key": "sk-ant-test",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def write_raw(path: Path, text: str) -> None:
    """Write exactly these characters, with no newline translation."""
    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(text)


def test_rule_is_inserted_before_the_private_deny() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "computercraft-server.toml"
        write_raw(path, STOCK)
        assert insert_allow_rule(path) is True
        text = path.read_bytes().decode("utf-8")
        assert text.index('host = "127.0.0.1"') < text.index('host = "$private"')
        assert '\t[[http.rules]]\n\t\thost = "127.0.0.1"\n\t\taction = "allow"\n\n' in text
        assert text.count("127.0.0.1") == 1


def test_second_run_is_a_byte_identical_no_op() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "computercraft-server.toml"
        write_raw(path, STOCK)
        assert insert_allow_rule(path) is True
        after_first = path.read_bytes()
        assert insert_allow_rule(path) is False
        assert path.read_bytes() == after_first


def test_missing_anchor_raises_and_leaves_the_file_alone() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "computercraft-server.toml"
        original = '[http]\n\tenabled = true\n\t[[http.rules]]\n\t\thost = "*"\n'
        write_raw(path, original)
        try:
            insert_allow_rule(path)
        except ValueError as exc:
            assert "$private" in str(exc)
        else:
            raise AssertionError("expected ValueError for a missing $private anchor")
        assert path.read_bytes() == original.encode("utf-8")


def test_crlf_file_keeps_crlf_line_endings() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "computercraft-server.toml"
        write_raw(path, STOCK.replace("\n", "\r\n"))
        assert insert_allow_rule(path) is True
        raw = path.read_bytes()
        assert raw.count(b"\n") == raw.count(b"\r\n"), "a bare LF crept into a CRLF file"
        assert insert_allow_rule(path) is False


def test_a_hand_typed_rule_counts_as_present() -> None:
    content = '[[http.rules]]\n    host = "127.0.0.1"\n\n    action = "allow"\n'
    assert rule_already_present(content)
    assert not rule_already_present('[[http.rules]]\nhost = "127.0.0.1"\naction = "deny"\n')
    assert not rule_already_present(STOCK)


def test_server_probe_is_false_when_nothing_listens() -> None:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        free_port = s.getsockname()[1]
    assert is_server_running(mc_port=free_port, timeout=0.5) is False


def test_server_probe_is_true_when_the_port_accepts() -> None:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        assert is_server_running(mc_port=listener.getsockname()[1], timeout=0.5) is True


def refuse_spawn(*args: object, **kwargs: object) -> None:
    raise AssertionError("must not spawn a process")


def test_launch_commands_are_the_bridge_and_run_bat() -> None:
    server_dir = Path("C:/fixture/server")
    bridge_cmd, server_cmd = launcher.build_launch_commands(make_settings(), server_dir)
    assert bridge_cmd[-3:] == ["uv", "run", "bridge/bridge.py"], bridge_cmd
    assert server_cmd == [str(server_dir / "run.bat")], server_cmd


def test_launch_without_server_dir_refuses_and_spawns_nothing() -> None:
    err = io.StringIO()
    with (
        patch.object(launcher, "Settings", lambda: make_settings()),
        patch("subprocess.Popen", refuse_spawn),
        contextlib.redirect_stderr(err),
    ):
        assert launcher.main() == 2
    assert "config error: server_dir" in err.getvalue()


def test_launch_without_run_bat_refuses_and_spawns_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        err = io.StringIO()
        with (
            patch.object(launcher, "Settings", lambda: make_settings(server_dir=Path(tmp))),
            patch("subprocess.Popen", refuse_spawn),
            contextlib.redirect_stderr(err),
        ):
            assert launcher.main() == 2
        assert "run.bat not found" in err.getvalue()


TESTS: list[Callable[[], None]] = [
    test_rule_is_inserted_before_the_private_deny,
    test_second_run_is_a_byte_identical_no_op,
    test_missing_anchor_raises_and_leaves_the_file_alone,
    test_crlf_file_keeps_crlf_line_endings,
    test_a_hand_typed_rule_counts_as_present,
    test_server_probe_is_false_when_nothing_listens,
    test_server_probe_is_true_when_the_port_accepts,
    test_launch_commands_are_the_bridge_and_run_bat,
    test_launch_without_server_dir_refuses_and_spawns_nothing,
    test_launch_without_run_bat_refuses_and_spawns_nothing,
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
