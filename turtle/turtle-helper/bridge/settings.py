"""Typed, validated bridge configuration sourced from the environment and .env."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

from pydantic import BeforeValidator, Field
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


def split_comma_separated(value: object) -> list[str]:
    """Parse a comma-separated string into a stripped, non-empty list of strings."""
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    if isinstance(value, list):
        return value
    return []


# NoDecode stops pydantic-settings from trying to JSON-decode this env var before the
# validator runs -- without it, a comma-separated ALLOWED_PLAYERS value fails with a raw
# JSONDecodeError instead of reaching split_comma_separated(). Empirically confirmed during
# Task 1 execution (pydantic-settings 2.15 treats list[str] as a "complex type" and attempts
# json.loads() on the raw env string first).
CommaSeparatedPlayers = Annotated[list[str], NoDecode, BeforeValidator(split_comma_separated)]


def blank_to_none(value: object) -> object:
    """Treat a blank or whitespace-only value as unset, so ``SERVER_DIR=`` means None."""
    if isinstance(value, str) and not value.strip():
        return None
    return value


# Without this, a blank SERVER_DIR= line (the documented default in .env.example) parses as
# Path("."), and deploy would treat the current working directory as the server root.
OptionalPath = Annotated[Path | None, BeforeValidator(blank_to_none)]


class Settings(BaseSettings):
    """Bridge configuration; required fields raise ValidationError if missing or empty."""

    host: str = Field(default="127.0.0.1", description="WebSocket server bind address.")
    port: int = Field(default=8765, description="WebSocket server listen port.")
    model: str = Field(
        default="claude-sonnet-5", description="Claude model ID used for chat requests."
    )
    command_prefix: str = Field(
        default="$robot", description="Chat prefix that triggers the agent."
    )
    robot_name: str = Field(default="Robot", description="Name shown in Chat Box messages.")
    cmd_timeout: int = Field(
        default=120, description="Seconds to wait for a device command to finish."
    )
    ping_interval: int = Field(
        default=20, description="WebSocket keepalive ping interval in seconds (0 disables)."
    )
    ping_timeout: int = Field(
        default=20, description="WebSocket ping timeout in seconds (0 disables)."
    )
    bridge_token: str = Field(
        min_length=1,
        description="Shared secret devices present in their hello handshake; required, non-empty.",
    )
    allowed_players: CommaSeparatedPlayers = Field(
        min_length=1,
        description="Comma-separated player names allowed to give orders; required, at least one.",
    )
    anthropic_api_key: str = Field(
        description="Anthropic API key used to authenticate Claude API calls."
    )
    server_dir: OptionalPath = Field(
        default=None,
        description=(
            "Server root directory (where run.bat and world/ live) for local deployment; "
            "required by `uv run deploy`, unused by the bridge itself."
        ),
    )

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )
