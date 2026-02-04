"""OpenCode Security Filter - Type definitions."""

import re
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Literal


class SpecificityLevel(IntEnum):
    """Precedence levels (lower = more specific, wins)."""

    FILE_NAME = 1  # Exact file path: ~/.ssh/id_ed25519
    FILE_EXTENSION = 2  # Extension glob: *.pub, *.env
    DIRECTORY = 3  # Exact directory: ~/.ssh/
    SECURITY_DIRECTORY = 4  # Security-critical dir names: **/secrets/**, *credentials*
    PERMISSIONS = 5  # Mode bits: 600, 400
    DIR_GLOB = 6  # Dir + glob: ~/.ssh/*, ~/dotfiles/*
    GLOB_MIDDLE = 7  # Glob in middle: other patterns


Decision = Literal["allow", "deny", "pass"]
PermissionOutcome = Literal[
    "allow_once", "allow_always", "reject_once", "reject_always", "cancelled"
]


@dataclass
class SecurityPattern:
    """A security pattern with its decision and specificity level.

    The pattern field contains a regex string that will be compiled on first use.
    Use the matches() method to check if a path matches the pattern.
    """

    pattern: str
    decision: Literal["allow", "deny"]
    level: SpecificityLevel
    description: str
    _regex: re.Pattern | None = field(default=None, init=False, repr=False, compare=False)

    def __post_init__(self) -> None:
        """Compile the regex pattern on initialization."""
        object.__setattr__(self, "_regex", re.compile(self.pattern))

    def matches(self, path: str) -> bool:
        """Check if the given path matches this pattern.

        Args:
            path: The file path to check against the pattern.

        Returns:
            True if the pattern matches the path, False otherwise.
        """
        if self._regex is None:
            object.__setattr__(self, "_regex", re.compile(self.pattern))
        return self._regex.search(path) is not None

    def __hash__(self) -> int:
        """Make SecurityPattern hashable for use in sets and as dict keys."""
        return hash((self.pattern, self.decision, self.level, self.description))

    def __eq__(self, other: object) -> bool:
        """Check equality based on pattern fields (not the compiled regex)."""
        if not isinstance(other, SecurityPattern):
            return NotImplemented
        return (
            self.pattern == other.pattern
            and self.decision == other.decision
            and self.level == other.level
            and self.description == other.description
        )


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
