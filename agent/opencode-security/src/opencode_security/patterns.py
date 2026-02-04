"""Pattern configuration and matching for security filter.

All patterns are stored as pre-compiled regex for consistent matching behavior.
The SecurityPattern.matches() method provides the primary matching interface.
"""

import os
import re
from pathlib import Path

from .types import SecurityPattern, SpecificityLevel


def _home() -> str:
    """Get the home directory path with regex-safe escaping."""
    return re.escape(str(Path.home()))


def expand_pattern(pattern: str) -> str:
    """Expand ~ in pattern to home directory.

    This function is kept for backwards compatibility with tests.

    Args:
        pattern: A pattern string that may start with ~

    Returns:
        The pattern with ~ expanded to the home directory path.
    """
    if pattern.startswith("~"):
        return str(Path(pattern).expanduser())
    return pattern


def _build_dir_glob_regex(dir_path: str) -> str:
    """Build regex for directory glob pattern (e.g., ~/.ssh/*).

    Matches direct children of the directory only, not subdirectories.

    Args:
        dir_path: Path like ~/.ssh or ~/dotfiles (without trailing /*)

    Returns:
        Regex pattern string matching direct children only.
    """
    # Expand ~ and escape for regex
    expanded = str(Path(dir_path).expanduser())
    escaped = re.escape(expanded)
    # Match direct children only: /path/dir/[^/]+ (no slashes in child name)
    return f"^{escaped}/[^/]+$"


def _build_file_name_regex(file_path: str) -> str:
    """Build regex for exact file name pattern (e.g., ~/.netrc).

    Args:
        file_path: Exact file path with potential ~ expansion

    Returns:
        Regex pattern string matching the exact path.
    """
    expanded = str(Path(file_path).expanduser())
    escaped = re.escape(expanded)
    return f"^{escaped}$"


def _build_security_dir_regex(dir_name: str) -> str:
    """Build regex for security directory pattern (e.g., **/secrets/**).

    Matches the directory name as a path component anywhere in the path.
    This matches both the directory itself and any contents.

    Args:
        dir_name: Directory name like "secrets" or ".secrets"

    Returns:
        Regex pattern matching the directory name as a path component.
    """
    escaped = re.escape(dir_name)
    # Match: /secrets/, /secrets (at end), or secrets/ (at start)
    # Uses word boundary on directory separators
    return f"(^|/){escaped}(/|$)"


# Pattern configuration - all security patterns using compiled regex
PATTERNS: list[SecurityPattern] = [
    # Level 2: File ending patterns (ALLOW)
    # *.pub -> matches any path ending in .pub
    SecurityPattern(r"\.pub$", "allow", SpecificityLevel.FILE_EXTENSION, "Public keys"),
    SecurityPattern(r"\.pem$", "allow", SpecificityLevel.FILE_EXTENSION, "PEM certificates"),

    # Level 2: File ending patterns (DENY)
    # *.env -> matches paths ending in .env
    SecurityPattern(r"\.env$", "deny", SpecificityLevel.FILE_EXTENSION, "Environment files"),
    # *.env.* -> matches .env.local, .env.production, etc.
    SecurityPattern(r"\.env\.[^/]+$", "deny", SpecificityLevel.FILE_EXTENSION, "Environment files"),

    # Level 1: Specific file names (DENY)
    # ~/.netrc -> exact match for netrc in home directory
    SecurityPattern(
        _build_file_name_regex("~/.netrc"),
        "deny",
        SpecificityLevel.FILE_NAME,
        "FTP/HTTP credentials",
    ),

    # Private key filenames - match anywhere in path (but not .pub)
    # These catch bare filenames like "id_rsa" or paths like "/any/path/id_rsa"
    SecurityPattern(
        r"(^|/)id_rsa$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "RSA private key",
    ),
    SecurityPattern(
        r"(^|/)id_ed25519$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "Ed25519 private key",
    ),
    SecurityPattern(
        r"(^|/)id_ecdsa$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "ECDSA private key",
    ),
    SecurityPattern(
        r"(^|/)id_dsa$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "DSA private key",
    ),
    SecurityPattern(
        r"(^|/)id_ecdsa_sk$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "ECDSA-SK private key",
    ),
    SecurityPattern(
        r"(^|/)id_ed25519_sk$",
        "deny",
        SpecificityLevel.FILE_NAME,
        "Ed25519-SK private key",
    ),

    # Level 6: Directory + direct children (DENY)
    # ~/.ssh/* -> matches ~/.ssh/config but NOT ~/.ssh/subdir/file
    SecurityPattern(
        _build_dir_glob_regex("~/.ssh"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "SSH directory",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/.gnupg"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "GPG directory",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/.aws"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "AWS credentials",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/.config/gcloud"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "GCloud creds",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/.azure"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "Azure credentials",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/.config/sops"),
        "deny",
        SpecificityLevel.DIR_GLOB,
        "SOPS secrets",
    ),

    # Level 4: Security-critical directory names (DENY - high priority)
    # **/secrets/** -> matches /path/secrets/file or /path/to/secrets
    SecurityPattern(
        _build_security_dir_regex("secrets"),
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Secrets dirs",
    ),
    SecurityPattern(
        _build_security_dir_regex("secret"),
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Secret dir (singular)",
    ),
    SecurityPattern(
        _build_security_dir_regex(".secrets"),
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Hidden secrets",
    ),
    SecurityPattern(
        _build_security_dir_regex(".secret"),
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Hidden secret (singular)",
    ),

    # *credential* -> matches any path containing "credential" in filename
    SecurityPattern(
        r"credential",
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Credential files (singular/plural)",
    ),
    # *password* -> matches any path containing "password" in filename
    SecurityPattern(
        r"password",
        "deny",
        SpecificityLevel.SECURITY_DIRECTORY,
        "Password files",
    ),

    # Level 6: Directory + direct children (ALLOW - trusted paths)
    SecurityPattern(
        _build_dir_glob_regex("~/dotfiles"),
        "allow",
        SpecificityLevel.DIR_GLOB,
        "Trusted: dotfiles",
    ),
    SecurityPattern(
        _build_dir_glob_regex("~/codebases"),
        "allow",
        SpecificityLevel.DIR_GLOB,
        "Trusted: codebases",
    ),
]


def match_pattern(pattern: SecurityPattern | str, path: str) -> bool:
    """Match a pattern against a path using regex.

    This function supports both SecurityPattern objects (preferred) and
    legacy string patterns for backwards compatibility with tests.

    Args:
        pattern: Either a SecurityPattern with compiled regex, or a string
                 pattern (glob or regex) for backwards compatibility.
        path: The file path to match against.

    Returns:
        True if the pattern matches the path, False otherwise.
    """
    if isinstance(pattern, SecurityPattern):
        return pattern.matches(path)

    # Legacy support: string pattern (used by tests with glob patterns)
    # Convert glob to regex for backwards compatibility
    return _match_legacy_pattern(pattern, path)


def _match_legacy_pattern(pattern: str, path: str) -> bool:
    """Match a legacy glob pattern against a path.

    This provides backwards compatibility for tests that use glob patterns.
    New code should use SecurityPattern.matches() directly.

    Args:
        pattern: A glob pattern string (e.g., "*.env", "**/secrets/**")
        path: The file path to match against.

    Returns:
        True if the pattern matches the path, False otherwise.
    """
    # Expand ~ in pattern
    if pattern.startswith("~"):
        pattern = str(Path(pattern).expanduser())

    # Handle ** recursive patterns
    if "**/" in pattern and pattern.endswith("/**"):
        # Extract middle part: **/secrets/** -> secrets
        middle = pattern.replace("**/", "").replace("/**", "")
        escaped = re.escape(middle)
        regex = re.compile(f"(^|/){escaped}(/|$)")
        return regex.search(path) is not None

    # Handle **/X patterns
    if pattern.startswith("**/"):
        suffix = pattern[3:]
        escaped = re.escape(suffix)
        # Match as path component or at end
        regex = re.compile(f"(^|/){escaped}(/|$)")
        return regex.search(path) is not None

    # Handle dir/* patterns (direct children only)
    if pattern.endswith("/*") and "/" in pattern[:-2]:
        base = pattern[:-2]
        escaped = re.escape(base)
        regex = re.compile(f"^{escaped}/[^/]+$")
        return regex.search(path) is not None

    # Handle *X* patterns (contains X)
    if pattern.startswith("*") and pattern.endswith("*") and len(pattern) > 2:
        middle = pattern[1:-1]
        return middle in path

    # Handle *.ext patterns (file extension)
    if pattern.startswith("*."):
        ext = pattern[1:]  # Include the dot
        return path.endswith(ext)

    # Handle *.ext.* patterns (extension with suffix)
    if pattern.startswith("*.") and ".*" in pattern:
        # Parse *.env.* -> must have .env. in it and something after
        parts = pattern[2:]  # Remove "*."
        if parts.endswith(".*"):
            ext = "." + parts[:-2]  # ".env"
            # Match: filename must contain ".env." somewhere
            return ext + "." in path

    # Exact match (possibly with ~ expansion)
    return path == pattern
