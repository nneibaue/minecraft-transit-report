"""Zero-network checks for harness/scenarios.py's pure helpers (Phase 2 plan 02-07).

No bridge, no socket, no Settings(): only the predicates a scenario applies to frames it has
already received. Same dependency-free TAP layout as tests/test_agent.py; every ``test_*``
function is pytest-collectable later.

    uv run python tests/test_harness_scenarios.py
"""

from __future__ import annotations

import sys
import traceback
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from harness.scenarios import is_error_fallback  # noqa: E402

PRE_SWAP_FALLBACK = "Sorry DisraSenkovi, something went wrong: BadRequestError"
PRE_SWAP_ANSWER = (
    'Right now I only see one computer, "harness-worker", which can list and access a connected '
    "chest, plus the chat interface. No turtles or sorting network are hooked up at the moment."
)


def test_the_bridge_error_fallback_is_recognised() -> None:
    """The exact text 02-04's 21:02 attempt received, which the scenario wrongly passed on."""
    assert is_error_fallback(PRE_SWAP_FALLBACK)


def test_fallback_shape_matches_any_user_and_error_name() -> None:
    """bridge.on_event formats `Sorry {user}, something went wrong: {type(e).__name__}`."""
    assert is_error_fallback("Sorry Nate, something went wrong: UsageLimitExceeded")
    assert is_error_fallback("  Sorry x, Something Went Wrong: ValidationError\n")


def test_a_real_devices_answer_is_not_a_fallback() -> None:
    """The successful pre-swap answer (02-04 transcript) must still pass."""
    assert not is_error_fallback(PRE_SWAP_ANSWER)


def test_an_apology_that_is_not_the_fallback_is_not_rejected() -> None:
    """Only the bridge's catch-all shape is rejected; a model apology is still an answer."""
    assert not is_error_fallback("Sorry, no turtles are connected right now.")


def test_non_string_text_is_not_a_fallback() -> None:
    """Missing or non-string text is handled by the scenario's own text check, not here."""
    assert not is_error_fallback(None)
    assert not is_error_fallback({"text": PRE_SWAP_FALLBACK})


TESTS: list[Callable[[], None]] = [
    test_the_bridge_error_fallback_is_recognised,
    test_fallback_shape_matches_any_user_and_error_name,
    test_a_real_devices_answer_is_not_a_fallback,
    test_an_apology_that_is_not_the_fallback_is_not_rejected,
    test_non_string_text_is_not_a_fallback,
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
