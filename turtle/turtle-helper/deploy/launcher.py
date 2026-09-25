"""Start the bridge and the local server side by side (Phase 3, D-07).

    uv run launch

Opens the bridge (``uv run bridge/bridge.py``) in its own console window, then the server's
``run.bat`` in another, both located from .env (SERVER_DIR), and returns at once. A
convenience for the operator only: it does not wait for, watch or restart either process,
and no automated check ever calls ``main()`` -- tests exercise ``build_launch_commands()``,
which starts nothing.

Exit codes: 0 both windows opened, 2 invalid configuration or not on Windows.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from pydantic import ValidationError

from bridge.settings import Settings

# The turtle-helper directory: the bridge runs from here.
REPO_ROOT = Path(__file__).resolve().parent.parent


def build_launch_commands(settings: Settings, server_dir: Path) -> tuple[list[str], list[str]]:
    """The bridge argv and the server argv; pure, spawns nothing."""
    return ["uv", "run", "bridge/bridge.py"], [str(server_dir / "run.bat")]


def main() -> int:
    """Entry point for ``uv run launch``: two console windows, no supervision."""
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2
    if settings.server_dir is None:
        print("config error: server_dir: SERVER_DIR is required for launch", file=sys.stderr)
        return 2
    run_bat = settings.server_dir / "run.bat"
    if not run_bat.is_file():
        print(f"config error: server_dir: {run_bat} not found", file=sys.stderr)
        return 2
    if sys.platform != "win32":
        print("launch opens console windows and runs run.bat: Windows only", file=sys.stderr)
        return 2
    bridge_cmd, server_cmd = build_launch_commands(settings, settings.server_dir)
    # CREATE_NEW_CONSOLE gives each process its own window directly; "cmd /c start <title>"
    # would need a quoted title that subprocess's argv quoting cannot produce.
    subprocess.Popen(bridge_cmd, cwd=REPO_ROOT, creationflags=subprocess.CREATE_NEW_CONSOLE)
    subprocess.Popen(
        server_cmd, cwd=settings.server_dir, creationflags=subprocess.CREATE_NEW_CONSOLE
    )
    print("bridge and server started in their own windows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
