"""Is the local Minecraft server up? A TCP probe of its game port (Phase 3, D-12).

``world/session.lock`` is not used: a killed server leaves it behind, so it cannot tell a
running server from a crashed one (RESEARCH.md Pitfall 2, assumption A6). A listening game
port can.
"""

from __future__ import annotations

import socket


def is_server_running(host: str = "127.0.0.1", mc_port: int = 25565, timeout: float = 2.0) -> bool:
    """True when something accepts a TCP connection on the Minecraft server port.

    ``mc_port`` is the game port, never ``Settings.port`` (the bridge's websocket port).
    """
    try:
        with socket.create_connection((host, mc_port), timeout=timeout):
            return True
    except (OSError, TimeoutError):
        return False
