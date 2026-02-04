"""Path canonicalization and permission checking."""

import os
from pathlib import Path

from .types import PathResolutionError, CircularSymlinkError

MAX_SYMLINK_DEPTH = 40  # Match Linux kernel limit


def canonicalize(path: str, cwd: str | None = None) -> str:
    """Canonicalize a path, resolving ~, .., and symlinks.

    Args:
        path: The path to canonicalize
        cwd: Current working directory for relative paths

    Returns:
        Absolute canonical path with symlinks resolved

    Raises:
        PathResolutionError: If path can't be resolved
        CircularSymlinkError: If circular symlink detected
    """
    try:
        # Expand ~ first
        expanded = os.path.expanduser(path)

        # Handle relative paths
        if not os.path.isabs(expanded):
            if cwd:
                expanded = os.path.join(cwd, expanded)
            else:
                expanded = os.path.join(os.getcwd(), expanded)

        # Normalize the path (resolve ..)
        normalized = os.path.normpath(expanded)

        # Resolve symlinks with depth protection
        resolved = resolve_symlinks(Path(normalized))

        return str(resolved)

    except CircularSymlinkError:
        raise
    except Exception as e:
        raise PathResolutionError(f"Cannot resolve path '{path}': {e}") from e


def resolve_symlinks(path: Path, depth: int = 0) -> Path:
    """Resolve symlinks with depth limit to prevent infinite loops.

    Args:
        path: Path to resolve
        depth: Current recursion depth

    Returns:
        Resolved path

    Raises:
        CircularSymlinkError: If depth exceeds MAX_SYMLINK_DEPTH
    """
    if depth > MAX_SYMLINK_DEPTH:
        raise CircularSymlinkError(f"Symlink depth exceeded ({MAX_SYMLINK_DEPTH}): {path}")

    try:
        if path.is_symlink():
            target = path.resolve()
            return resolve_symlinks(target, depth + 1)
        return path.resolve()
    except OSError:
        # Path might not exist, return as-is
        return path


def is_restrictive_permissions(path: str) -> bool:
    """Check if file has restrictive permissions (no others read).

    Returns True if the file exists and has no 'others' read bit,
    meaning mode is 600, 400, 640, etc.

    Args:
        path: Path to check

    Returns:
        True if file has restrictive permissions (no others read)
        False if file doesn't exist or has permissive permissions
    """
    try:
        mode = os.stat(path).st_mode
        others_read = mode & 0o004
        return others_read == 0
    except (OSError, IOError):
        # File doesn't exist or can't stat - not restrictive
        return False
