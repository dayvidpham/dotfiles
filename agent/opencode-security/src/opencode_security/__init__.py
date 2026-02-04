"""OpenCode Security Filter - Pattern-based security for file access."""

from .acp import (
    SECURITY_BLOCK_ERROR_CODE,
    create_auto_allow_response,
    create_passthrough_response,
    create_rejection,
    create_security_block_error,
    extract_paths_from_tool,
    is_permission_request,
    parse_message,
    parse_permission_request,
    serialize_message,
)
from .filter import SecurityFilter
from .proxy import SecurityProxy
from .paths import (
    MAX_SYMLINK_DEPTH,
    canonicalize,
    is_restrictive_permissions,
    resolve_symlinks,
)
from .resolver import (
    find_matching_patterns,
    group_by_level,
    resolve,
)
from .types import (
    CheckResult,
    CircularSymlinkError,
    Decision,
    PathResolutionError,
    PatternMatch,
    PermissionOutcome,
    PermissionRequest,
    PermissionResponse,
    SecurityFilterError,
    SecurityPattern,
    SpecificityLevel,
)

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
    "SecurityFilter",
    "SecurityProxy",
    "MAX_SYMLINK_DEPTH",
    "canonicalize",
    "resolve_symlinks",
    "is_restrictive_permissions",
    "find_matching_patterns",
    "group_by_level",
    "resolve",
    "parse_message",
    "serialize_message",
    "is_permission_request",
    "parse_permission_request",
    "extract_paths_from_tool",
    "create_rejection",
    "create_passthrough_response",
    "SECURITY_BLOCK_ERROR_CODE",
    "create_security_block_error",
    "create_auto_allow_response",
]
