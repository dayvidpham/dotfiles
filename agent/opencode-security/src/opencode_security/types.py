"""OpenCode Security Filter - Type definitions."""

from dataclasses import dataclass
from enum import IntEnum
from typing import Literal


class SpecificityLevel(IntEnum):
    """Precedence levels (lower = more specific, wins)."""

    FILE_NAME = 1  # Exact file path: ~/.ssh/id_ed25519
    FILE_EXTENSION = 2  # Extension glob: *.pub, *.env
    DIRECTORY = 3  # Exact directory: ~/.ssh/
    PERMISSIONS = 4  # Mode bits: 600, 400
    DIR_GLOB = 5  # Dir + glob: ~/.ssh/*, ~/dotfiles/*
    GLOB_MIDDLE = 6  # Glob in middle: **/secrets/**


Decision = Literal["allow", "deny", "pass"]
PermissionOutcome = Literal[
    "allow_once", "allow_always", "reject_once", "reject_always", "cancelled"
]


@dataclass(frozen=True)
class SecurityPattern:
    """A security pattern with its decision and specificity level."""

    pattern: str
    decision: Literal["allow", "deny"]
    level: SpecificityLevel
    description: str


@dataclass(frozen=True)
class PatternMatch:
    """A matched pattern with the path it matched."""

    pattern: SecurityPattern
    matched_path: str


@dataclass
class CheckResult:
    """Result of a security check."""

    decision: Decision
    reason: str
    file_path: str
    canonical_path: str
    matched_pattern: SecurityPattern | None = None
    matched_level: SpecificityLevel | None = None


@dataclass
class PermissionRequest:
    """ACP permission request from agent."""

    id: str | int
    session_id: str
    tool_call_id: str
    tool_name: str
    tool_input: dict
    options: list[PermissionOutcome]


@dataclass
class PermissionResponse:
    """ACP permission response to agent."""

    id: str | int
    outcome: PermissionOutcome
    reason: str | None = None


# Exceptions
class SecurityFilterError(Exception):
    """Base exception for security filter errors."""

    pass


class PathResolutionError(SecurityFilterError):
    """Error resolving/canonicalizing path."""

    pass


class CircularSymlinkError(PathResolutionError):
    """Circular symlink detected."""

    pass


__all__ = [
    "SpecificityLevel",
    "Decision",
    "PermissionOutcome",
    "SecurityPattern",
    "PatternMatch",
    "CheckResult",
    "PermissionRequest",
    "PermissionResponse",
    "SecurityFilterError",
    "PathResolutionError",
    "CircularSymlinkError",
]
