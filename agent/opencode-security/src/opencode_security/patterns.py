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
    # Level 4: Security-critical directory names (DENY - high priority)
    SecurityPattern(
        "**/secrets/**", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Secrets dirs"
    ),
    SecurityPattern(
        "**/secret/**", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Secret dir (singular)"
    ),
    SecurityPattern(
        "**/.secrets/**", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Hidden secrets"
    ),
    SecurityPattern(
        "**/.secret/**", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Hidden secret (singular)"
    ),
    SecurityPattern(
        "*credential*", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Credential files (singular/plural)"
    ),
    SecurityPattern(
        "*password*", "deny", SpecificityLevel.SECURITY_DIRECTORY, "Password files"
    ),
    # Level 6: Directory + trailing glob (ALLOW - trusted paths)
    SecurityPattern(
        "~/dotfiles/*", "allow", SpecificityLevel.DIR_GLOB, "Trusted: dotfiles"
    ),
    SecurityPattern(
        "~/codebases/*", "allow", SpecificityLevel.DIR_GLOB, "Trusted: codebases"
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
    - * for single-level matching in DIR_GLOB patterns (does NOT cross directory boundaries)
    - * matches any characters including / in FILE_EXTENSION patterns
    """
    expanded_pattern = expand_pattern(pattern)

    # Handle ** recursive matching
    if "**" in expanded_pattern:
        # Convert ** to work with fnmatch
        # Split into parts and match recursively
        return _match_recursive(expanded_pattern, path)

    # For DIR_GLOB patterns (dir/*), ensure * doesn't match subdirectories
    # e.g., ~/.ssh/* should match ~/.ssh/config but NOT ~/.ssh/subdir/file
    # But *.pub should match any .pub file at any depth
    if "/" in expanded_pattern and "*" in expanded_pattern:
        # This is a directory glob - depth should match
        pattern_depth = len(Path(expanded_pattern).parts)
        path_depth = len(Path(path).parts)
        if path_depth != pattern_depth:
            return False

    # Simple fnmatch for extension and other patterns
    return fnmatch.fnmatch(path, expanded_pattern)


def _match_recursive(pattern: str, path: str) -> bool:
    """Handle ** recursive glob matching."""
    # Convert pattern for fnmatch compatibility
    # ** should match any number of path components

    # Handle **/X/** pattern (glob in middle) - should match:
    # - /path/to/X (the directory itself)
    # - /path/to/X/anything (contents of the directory)
    if "/**" in pattern and pattern.endswith("/**"):
        # Extract the middle part (e.g., "secrets" from "**/secrets/**")
        # This pattern should match both the directory and its contents
        middle = pattern.rstrip("/**").lstrip("**/").lstrip("/")
        path_parts = Path(path).parts
        # Check if any path component matches the middle pattern
        for i, part in enumerate(path_parts):
            if fnmatch.fnmatch(part, middle):
                # Matches - this could be the directory or something inside it
                return True
        return False

    # Handle **/X pattern (glob at start)
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
