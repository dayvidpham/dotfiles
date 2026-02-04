"""Specificity-based resolution algorithm."""

from .types import (
    SecurityPattern, PatternMatch, SpecificityLevel, Decision
)
from .patterns import PATTERNS, match_pattern


def find_matching_patterns(canonical_path: str) -> list[PatternMatch]:
    """Find all patterns that match the given path."""
    matches = []
    for pattern in PATTERNS:
        if pattern.matches(canonical_path):
            matches.append(PatternMatch(pattern=pattern, matched_path=canonical_path))
    return matches


def group_by_level(matches: list[PatternMatch]) -> dict[SpecificityLevel, list[PatternMatch]]:
    """Group pattern matches by their specificity level."""
    grouped: dict[SpecificityLevel, list[PatternMatch]] = {}
    for match in matches:
        level = match.pattern.level
        if level not in grouped:
            grouped[level] = []
        grouped[level].append(match)
    return grouped


def resolve(
    canonical_path: str,
    has_restrictive_perms: bool
) -> tuple[Decision, str, SecurityPattern | None, SpecificityLevel | None]:
    """Resolve decision using specificity-based precedence.

    Algorithm (from REQUIREMENTS dotfiles-oytq UAT-3):
    1. Find all matching patterns
    2. Group by specificity level
    3. Check levels in order: FILE_NAME(1) > FILE_EXTENSION(2) > DIRECTORY(3) > SECURITY_DIRECTORY(4) > PERMISSIONS(5) > DIR_GLOB(6) > GLOB_MIDDLE(7)
    4. At each level: DENY supersedes ALLOW
    5. Level 5 (PERMISSIONS): check file mode bits
    6. If no matches: pass through

    Returns:
        (decision, reason, matched_pattern, matched_level)
    """
    matches = find_matching_patterns(canonical_path)
    grouped = group_by_level(matches)

    # Check levels 1-4 (file name, extension, directory, security directory)
    for level in [SpecificityLevel.FILE_NAME, SpecificityLevel.FILE_EXTENSION, SpecificityLevel.DIRECTORY, SpecificityLevel.SECURITY_DIRECTORY]:
        if level in grouped:
            patterns_at_level = grouped[level]
            # DENY supersedes ALLOW at same level
            for match in patterns_at_level:
                if match.pattern.decision == "deny":
                    return ("deny", f"Blocked by {match.pattern.pattern} ({match.pattern.description})", match.pattern, level)
            for match in patterns_at_level:
                if match.pattern.decision == "allow":
                    return ("allow", f"Allowed by {match.pattern.pattern} ({match.pattern.description})", match.pattern, level)

    # Level 5: Permission mode bits
    if has_restrictive_perms:
        return ("deny", "File has restrictive permissions (no others read)", None, SpecificityLevel.PERMISSIONS)

    # Check levels 6-7 (dir-glob, glob-middle)
    for level in [SpecificityLevel.DIR_GLOB, SpecificityLevel.GLOB_MIDDLE]:
        if level in grouped:
            patterns_at_level = grouped[level]
            for match in patterns_at_level:
                if match.pattern.decision == "deny":
                    return ("deny", f"Blocked by {match.pattern.pattern} ({match.pattern.description})", match.pattern, level)
            for match in patterns_at_level:
                if match.pattern.decision == "allow":
                    return ("allow", f"Allowed by {match.pattern.pattern} ({match.pattern.description})", match.pattern, level)

    # No matches - pass through
    return ("pass", "No matching patterns", None, None)
