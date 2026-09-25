"""Zero-network text checks over the device Lua files (Phase 3 plan 03-04, D-14..D-17).

There is no Lua runtime on the PC, so the in-game install and boot-time update are pinned
here at the text level: one pinned raw GitHub base, the download header every device checks,
download validation before any write, the masked token prompt, no print of the typed token,
the developer-device marker skip, and no loopback hostname. Same dependency-free TAP layout
as tests/test_deploy_files.py; every ``test_*`` function is pytest-collectable later.

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


def lua(name: str) -> str:
    return LUA_FILES[name].read_text(encoding="utf-8")


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


def test_startup_skips_update_on_marked_devices() -> None:
    # The code guard, not just a comment naming the file.
    assert 'if fs.exists("_marker.txt") then' in lua("startup.lua")


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


TESTS: list[Callable[[], None]] = [
    test_device_files_start_with_their_download_header,
    test_startup_and_install_pin_the_same_raw_base,
    test_every_url_literal_is_under_the_pinned_base,
    test_no_lua_file_names_the_loopback_hostname,
    test_startup_updates_then_detects_role,
    test_startup_skips_update_on_marked_devices,
    test_downloads_are_validated_before_writing,
    test_startup_never_touches_the_token,
    test_install_masks_the_token_and_keeps_an_existing_secret,
    test_install_never_prints_the_typed_token,
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
