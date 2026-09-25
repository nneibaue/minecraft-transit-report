"""Zero-network checks for deploy's allow rule, server probe and CLI (Phase 3 plan 03-01).

No real server, no bridge, no .env: rules.py runs against temp files, the server probe
against a throwaway local listener, and deploy.main() against a patched Settings. Same
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
from deploy import deploy as d  # noqa: E402
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


def fixture_toml(server_dir: Path, text: str = STOCK) -> Path:
    """Create SERVER_DIR/world/serverconfig/computercraft-server.toml with this content."""
    toml = server_dir / "world" / "serverconfig" / "computercraft-server.toml"
    toml.parent.mkdir(parents=True)
    write_raw(toml, text)
    return toml


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


def run_main(settings: Settings, running: bool = False) -> tuple[int, str, str]:
    """deploy.main() against a patched Settings and server probe; returns code, out, err."""
    out, err = io.StringIO(), io.StringIO()
    with (
        patch.object(d, "Settings", lambda: settings),
        patch.object(d, "is_server_running", lambda: running),
        contextlib.redirect_stdout(out),
        contextlib.redirect_stderr(err),
    ):
        code = d.main([])
    return code, out.getvalue(), err.getvalue()


def test_main_requires_server_dir() -> None:
    code, _, err = run_main(make_settings())
    assert code == 2
    assert "config error: server_dir" in err


def test_main_says_so_when_the_toml_is_absent() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        code, out, _ = run_main(make_settings(server_dir=Path(tmp)))
        assert code == 0
        assert "not found; skipping the allow-rule step" in out


def test_main_never_edits_the_toml_while_the_server_runs() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        toml = fixture_toml(Path(tmp))
        code, out, _ = run_main(make_settings(server_dir=Path(tmp)), running=True)
        assert code == 0
        assert "server is running" in out
        assert toml.read_bytes() == STOCK.encode("utf-8")


def test_main_inserts_then_reports_already_present() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        fixture_toml(Path(tmp))
        settings = make_settings(server_dir=Path(tmp))
        code, out, _ = run_main(settings)
        assert code == 0 and "allow rule inserted" in out
        code, out, _ = run_main(settings)
        assert code == 0 and "allow rule already present" in out


def test_main_reports_a_missing_anchor_as_exit_1() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        fixture_toml(Path(tmp), "[http]\n")
        code, _, err = run_main(make_settings(server_dir=Path(tmp)))
        assert code == 1
        assert "deploy error:" in err


TESTS: list[Callable[[], None]] = [
    test_rule_is_inserted_before_the_private_deny,
    test_second_run_is_a_byte_identical_no_op,
    test_missing_anchor_raises_and_leaves_the_file_alone,
    test_crlf_file_keeps_crlf_line_endings,
    test_a_hand_typed_rule_counts_as_present,
    test_server_probe_is_false_when_nothing_listens,
    test_server_probe_is_true_when_the_port_accepts,
    test_main_requires_server_dir,
    test_main_says_so_when_the_toml_is_absent,
    test_main_never_edits_the_toml_while_the_server_runs,
    test_main_inserts_then_reports_already_present,
    test_main_reports_a_missing_anchor_as_exit_1,
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
