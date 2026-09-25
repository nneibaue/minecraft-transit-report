"""Zero-network text checks over the device Lua files (Phase 3 plan 03-04, D-14..D-17).

There is no Lua runtime on the PC, so the in-game install and boot-time update are pinned
here at the text level: one pinned raw GitHub base, the download header every device checks,
download validation before any write, the masked token prompt, no print of the typed token,
no developer-device marker (D-19: every device updates on boot), and no loopback hostname.
Phase 4 plan 04-01 pins the ``$`` restore in chat.lua, the DEBUG marker and the no-token rule
for debug output.
Same dependency-free TAP layout as tests/test_deploy_rules.py; every ``test_*`` function is
pytest-collectable later.

    uv run python tests/test_device_lua.py
"""

from __future__ import annotations

import re
import sys
import traceback
from collections.abc import Callable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BASE = (
    "https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/"
)

# Device file name -> repo path: the files startup.lua and install.lua download and check.
DEVICE_FILES = {
    "chat.lua": REPO_ROOT / "base" / "chat.lua",
    "client.lua": REPO_ROOT / "turtle" / "client.lua",
    "startup.lua": REPO_ROOT / "startup.lua",
}
LUA_FILES = {**DEVICE_FILES, "install.lua": REPO_ROOT / "install.lua"}

GLOBAL_OUTPUT_CALL = re.compile(r"(?<![.\w])(print|write|printError)\s*\(")
# Device-side output: the global writers plus each file's own log() and dbg() helpers.
DEVICE_OUTPUT_CALL = re.compile(r"(?<![.\w])(print|write|printError|log|dbg)\s*\(")

# Device files that carry the DEBUG marker (Phase 4 D-11).
DEBUG_FILES: tuple[str, ...] = ("chat.lua", "client.lua")

DOLLAR_RESTORE = re.compile(
    r'if\s+hidden\s+and\s+text:sub\(1,\s*1\)\s*~=\s*"\$"\s+then\s+text\s*=\s*"\$"\s*\.\.\s*text'
)


def lua(name: str) -> str:
    return LUA_FILES[name].read_text(encoding="utf-8")


def code_lines(name: str) -> list[tuple[int, str]]:
    """Numbered lines of a Lua file, skipping comment lines so prose never trips a check."""
    return [
        (n, line)
        for n, line in enumerate(lua(name).splitlines(), 1)
        if not line.strip().startswith("--")
    ]


def test_device_files_start_with_their_download_header() -> None:
    for name, path in DEVICE_FILES.items():
        header = f"-- {name}".encode()
        assert path.read_bytes().startswith(header), f"{path} does not start with {header!r}"


def test_startup_and_install_pin_the_same_raw_base() -> None:
    for name in ("startup.lua", "install.lua"):
        found = re.findall(r'local BASE\s*=\s*"([^"]*)"', lua(name))
        assert found == [BASE], f"{name}: {found}"


def test_every_url_literal_is_under_the_pinned_base() -> None:
    for name in ("startup.lua", "install.lua"):
        text = lua(name)
        urls = re.findall(r"https?://[^\s\"']+", text)
        assert urls, f"{name} has no URL at all"
        for url in urls:
            assert url.startswith(BASE), f"{name}: {url}"
        assert "http://" not in text, f"{name} contains http://"


def test_no_lua_file_names_the_loopback_hostname() -> None:
    for name in LUA_FILES:
        assert "localhost" not in lua(name).lower(), f"{name} mentions localhost"


def test_startup_updates_then_detects_role() -> None:
    text = lua("startup.lua")
    role_check = 'peripheral.find("chatBox")'
    assert role_check in text
    assert 'shell.run("chat")' in text and 'shell.run("client")' in text
    assert "http.get" in text
    assert text.index("http.get") < text.index(role_check), "role check runs before the update"


def test_no_device_file_knows_a_marker() -> None:
    # D-19 removed the developer deploy path: no device skips the boot-time update.
    for name in ("startup.lua", "install.lua"):
        assert "_marker" not in lua(name), f"{name} still mentions _marker"


def test_downloads_are_validated_before_writing() -> None:
    for name in ("startup.lua", "install.lua"):
        text = lua(name)
        for needle in ("binary = true", "getResponseCode", "load(", '"wb"'):
            assert needle in text, f"{name} lacks {needle}"


def test_startup_never_touches_the_token() -> None:
    text = lua("startup.lua")
    assert "secret.txt" not in text
    assert "read(" not in text


def test_install_masks_the_token_and_keeps_an_existing_secret() -> None:
    text = lua("install.lua")
    for needle in (
        'read("*")',
        '"secret.txt"',
        "fs.exists",
        '"bridge.txt"',
        '"ws://127.0.0.1:8765"',
        "base/chat.lua",
        "turtle/client.lua",
        '"startup.lua"',
    ):
        assert needle in text, f"install.lua lacks {needle}"


def test_install_never_prints_the_typed_token() -> None:
    text = lua("install.lua")
    assert "newToken" in text
    for n, line in enumerate(text.splitlines(), 1):
        if GLOBAL_OUTPUT_CALL.search(line):
            assert "newToken" not in line, f"install.lua:{n} displays the token: {line.strip()}"


def test_chat_restores_the_dollar_ap_strips() -> None:
    # AP 0.7.46r strips every "$" from a hidden message; chat.lua puts the prefix back
    # before the event frame is built (Phase 4 RESEARCH Finding 1).
    lines = code_lines("chat.lua")
    restore = [n for n, line in lines if DOLLAR_RESTORE.search(line)]
    frame = [n for n, line in lines if 'name = "chat"' in line]
    assert restore, "chat.lua does not restore the $ on hidden chat"
    assert frame, "chat.lua builds no chat event frame"
    assert restore[0] < frame[0], "the $ restore comes after the event frame"


def test_device_output_never_shows_the_token() -> None:
    for name in ("chat.lua", "client.lua"):
        for n, line in code_lines(name):
            if DEVICE_OUTPUT_CALL.search(line):
                assert not re.search(
                    r"token|hello", line, re.IGNORECASE
                ), f"{name}:{n} may show the token: {line.strip()}"


def test_debug_is_a_marker_file() -> None:
    for name in DEBUG_FILES:
        text = lua(name)
        for needle in ('fs.exists("debug")', "local function dbg(", '"debug.log"'):
            assert needle in text, f"{name} lacks {needle}"
        for n, line in code_lines(name):
            assert not re.search(r"\bDEBUG\s*=\s*true\b", line), f"{name}:{n} forces DEBUG on"


TESTS: list[Callable[[], None]] = [
    test_device_files_start_with_their_download_header,
    test_startup_and_install_pin_the_same_raw_base,
    test_every_url_literal_is_under_the_pinned_base,
    test_no_lua_file_names_the_loopback_hostname,
    test_startup_updates_then_detects_role,
    test_no_device_file_knows_a_marker,
    test_downloads_are_validated_before_writing,
    test_startup_never_touches_the_token,
    test_install_masks_the_token_and_keeps_an_existing_secret,
    test_install_never_prints_the_typed_token,
    test_chat_restores_the_dollar_ap_strips,
    test_device_output_never_shows_the_token,
    test_debug_is_a_marker_file,
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
