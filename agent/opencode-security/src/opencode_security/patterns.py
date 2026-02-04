"""Pattern configuration and matching for security filter."""

import fnmatch
import os
import re
from pathlib import Path

from .types import SecurityPattern, SpecificityLevel

# Pattern configuration - all security patterns
PATTERNS: list[SecurityPattern] = [
    # Level 2: File ending globs (ALLOW)
    SecurityPattern("*.pub", "allow", SpecificityLevel.FILE_EXTENSION, "Public keys"),
    SecurityPattern("*.pem", "allow", SpecificityLevel.FILE_EXTENSION, "PEM certificates"),
    # Level 2: File ending globs (DENY)
    SecurityPattern("*.env", "deny", SpecificityLevel.FILE_EXTENSION, "Environment files"),
    SecurityPattern(
        "*.env.*", "deny", SpecificityLevel.FILE_EXTENSION, "Environment files"
    ),
    # Level 1: Specific file names (DENY)
    SecurityPattern("~/.netrc", "deny", SpecificityLevel.FILE_NAME, "FTP/HTTP credentials"),
    # Level 5: Directory + trailing glob (DENY)
    SecurityPattern("~/.ssh/*", "deny", SpecificityLevel.DIR_GLOB, "SSH directory"),
    SecurityPattern("~/.gnupg/*", "deny", SpecificityLevel.DIR_GLOB, "GPG directory"),
    SecurityPattern("~/.aws/*", "deny", SpecificityLevel.DIR_GLOB, "AWS credentials"),
    SecurityPattern(
        "~/.config/gcloud/*", "deny", SpecificityLevel.DIR_GLOB, "GCloud creds"
    ),
    SecurityPattern("~/.azure/*", "deny", SpecificityLevel.DIR_GLOB, "Azure credentials"),
    SecurityPattern(
        "~/.config/sops/*", "deny", SpecificityLevel.DIR_GLOB, "SOPS secrets"
    ),
    # Level 5: Directory + trailing glob (ALLOW - trusted paths)
    SecurityPattern(
        "~/dotfiles/*", "allow", SpecificityLevel.DIR_GLOB, "Trusted: dotfiles"
    ),
    SecurityPattern(
        "~/codebases/*", "allow", SpecificityLevel.DIR_GLOB, "Trusted: codebases"
    ),
    # Level 6: Glob in middle (DENY)
    SecurityPattern(
        "**/secrets/**", "deny", SpecificityLevel.GLOB_MIDDLE, "Secrets dirs"
    ),
    SecurityPattern(
        "**/.secrets/**", "deny", SpecificityLevel.GLOB_MIDDLE, "Hidden secrets"
    ),
    SecurityPattern(
        "*credentials*", "deny", SpecificityLevel.GLOB_MIDDLE, "Credentials files"
    ),
    SecurityPattern(
        "*password*", "deny", SpecificityLevel.GLOB_MIDDLE, "Password files"
    ),
]


def expand_pattern(pattern: str) -> str:
    """Expand ~ in pattern to home directory."""
    if pattern.startswith("~"):
        return str(Path(pattern).expanduser())
    return pattern


def match_pattern(pattern: str, path: str) -> bool:
    """Match a glob pattern against a path.

    Handles:
    - ~ expansion to home directory
    - ** for recursive matching
    - * for single-level matching
    """
    expanded_pattern = expand_pattern(pattern)

    # Handle ** recursive matching
    if "**" in expanded_pattern:
        # Convert ** to work with fnmatch
        # Split into parts and match recursively
        return _match_recursive(expanded_pattern, path)

    # Simple fnmatch for non-recursive patterns
    return fnmatch.fnmatch(path, expanded_pattern)


def _match_recursive(pattern: str, path: str) -> bool:
    """Handle ** recursive glob matching."""
    # Convert pattern for fnmatch compatibility
    # ** should match any number of path components

    # Handle **/X/** pattern (glob in middle)
    if pattern.startswith("**"):
        # Match anywhere in path
        suffix = pattern[2:].lstrip("/")
        if "**" in suffix:
            # Multiple ** - complex case
            return _fnmatch_recursive(pattern, path)
        # Simple case: **/<name>
        return fnmatch.fnmatch(os.path.basename(path), suffix) or any(
            fnmatch.fnmatch(part, suffix) for part in Path(path).parts
        )

    return _fnmatch_recursive(pattern, path)


def _fnmatch_recursive(pattern: str, path: str) -> bool:
    """Recursive fnmatch implementation for ** patterns."""
    # Simple implementation: check if pattern matches path with ** as wildcard
    # Convert glob to regex
    regex_pattern = pattern.replace("**", "<<STARSTAR>>")
    regex_pattern = fnmatch.translate(regex_pattern)
    regex_pattern = regex_pattern.replace("<<STARSTAR>>", ".*")
    return bool(re.match(regex_pattern, path))
