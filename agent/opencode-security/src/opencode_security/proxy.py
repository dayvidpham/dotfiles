"""SecurityProxy for intercepting ACP messages."""

from .types import PermissionRequest
from .filter import SecurityFilter
from .acp import (
    parse_message,
    is_permission_request,
    parse_permission_request,
    extract_paths_from_tool,
    create_security_block_error,
    create_auto_allow_response,
    serialize_message,
)


class SecurityProxy:
    """Proxy that intercepts ACP messages and applies security filtering.

    Three-Way Decision Flow (PROPOSAL-7):
    1. BLOCKED paths -> Return ERROR response (code -32001) with security directives
    2. TRUSTED paths -> Return permission response (allow_once)
    3. OTHER -> Forward to client unchanged
    """

    def __init__(self, filter: SecurityFilter | None = None, cwd: str | None = None):
        """Initialize the security proxy.

        Args:
            filter: SecurityFilter instance to use for checking paths.
                    If None, creates a new SecurityFilter.
            cwd: Current working directory for resolving relative paths.
        """
        self._filter = filter if filter is not None else SecurityFilter()
        self._cwd = cwd

    @property
    def filter(self) -> SecurityFilter:
        """Get the security filter instance."""
        return self._filter

    @property
    def cwd(self) -> str | None:
        """Get the current working directory."""
        return self._cwd

    def set_cwd(self, cwd: str | None) -> None:
        """Update the current working directory."""
        self._cwd = cwd

    def process_agent_message(self, raw: bytes) -> tuple[bytes | None, bool]:
        """Process a message from the agent.

        Args:
            raw: Raw bytes of the JSON-RPC message from the agent.

        Returns:
            A tuple of (response_to_agent, should_forward_to_client):
            - If response_to_agent is not None, send it back to the agent.
            - If should_forward_to_client is True, forward the original message to client.

        Decision logic:
            1. Parse message; if invalid JSON, forward unchanged
            2. If not a permission request, forward unchanged
            3. Extract paths from the tool call
            4. Check each path against the security filter:
               - If any path is DENIED -> return error response, don't forward
               - If all paths are ALLOWED -> return auto-allow response, don't forward
               - If any path is PASS -> forward to client for user decision
            5. No paths extracted -> forward to client
        """
        # Step 1: Try to parse the message
        try:
            msg = parse_message(raw)
        except (ValueError, UnicodeDecodeError):
            # Invalid JSON or encoding - forward unchanged (fail-open for non-security)
            return (None, True)

        # Step 2: Check if this is a permission request
        if not is_permission_request(msg):
            # Not a permission request - forward unchanged
            return (None, True)

        # Step 3: Parse the permission request
        request = parse_permission_request(msg)
        if request is None:
            # Failed to parse - forward unchanged
            return (None, True)

        # Step 4: Extract paths from the tool call
        paths = extract_paths_from_tool(request.tool_name, request.tool_input)

        if not paths:
            # No paths to check - forward to client
            return (None, True)

        # Step 5: Check each path
        return self._evaluate_paths(request, paths)

    def _evaluate_paths(
        self, request: PermissionRequest, paths: list[str]
    ) -> tuple[bytes | None, bool]:
        """Evaluate paths and determine the response.

        Args:
            request: The parsed permission request.
            paths: List of paths extracted from the tool call.

        Returns:
            A tuple of (response_to_agent, should_forward_to_client).
        """
        has_pass = False

        for path in paths:
            result = self._filter.check(path, self._cwd)

            if result.decision == "deny":
                # Any denied path -> immediate block
                error_response = create_security_block_error(
                    request_id=request.id,
                    path=result.canonical_path,
                    pattern=result.matched_pattern.pattern if result.matched_pattern else path,
                    level=result.matched_level.value if result.matched_level else 0,
                )
                return (serialize_message(error_response), False)

            if result.decision == "pass":
                has_pass = True

        # If any path needs user decision, forward to client
        if has_pass:
            return (None, True)

        # All paths are allowed -> auto-allow
        allow_response = create_auto_allow_response(request.id)
        return (serialize_message(allow_response), False)
