"""Named harness scenarios (D-01, D-14).

Each scenario is a plain async function ``(dev, args)`` that drives one FakeDevice against the
real bridge and returns normally on pass. It raises ScenarioError, TimeoutError or SpendRefusedError
on failure; ``harness.main`` turns that into the one-line verdict and exit code. Every wait here
goes through FakeDevice.expect*, so every wait is bounded.
"""

from __future__ import annotations

from harness.harness import FakeDevice, Scenario, ScenarioArgs

HELLO_WINDOW = 5.0  # seconds without a close after hello = the bridge accepted it


async def hello_handshake(dev: FakeDevice, args: ScenarioArgs) -> None:
    """HARN-01: connect, send hello, and prove it was accepted (no close within the window)."""
    await dev.connect()
    await dev.expect_no_close(HELLO_WINDOW)


SCENARIOS: dict[str, Scenario] = {
    "hello-handshake": hello_handshake,
}
