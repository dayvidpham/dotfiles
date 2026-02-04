"""Tests for SecurityProxy."""

import json
import pytest
from unittest.mock import MagicMock

from opencode_security.proxy import SecurityProxy
from opencode_security.filter import SecurityFilter
from opencode_security.acp import SECURITY_BLOCK_ERROR_CODE
from opencode_security.types import CheckResult, SecurityPattern, SpecificityLevel


def make_permission_request(
    request_id: str = "perm-123",
    tool_name: str = "read_file",
    tool_input: dict | None = None,
) -> bytes:
    """Create a permission request message as bytes."""
    if tool_input is None:
        tool_input = {"file_path": "/tmp/test.txt"}

    msg = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "session/request_permission",
        "params": {
            "sessionId": "sess-abc",
            "toolCall": {
                "toolCallId": "tc-456",
                "name": tool_name,
                "input": tool_input,
            },
            "options": ["allow_once", "reject_once"],
        },
    }
    return json.dumps(msg).encode("utf-8")


def make_other_message() -> bytes:
    """Create a non-permission message as bytes."""
    msg = {
        "jsonrpc": "2.0",
        "id": "1",
        "method": "session/update",
        "params": {},
    }
    return json.dumps(msg).encode("utf-8")


class TestSecurityProxyInit:
    def test_creates_default_filter(self):
        proxy = SecurityProxy()
        assert proxy.filter is not None
        assert isinstance(proxy.filter, SecurityFilter)

    def test_accepts_custom_filter(self):
        custom_filter = SecurityFilter()
        proxy = SecurityProxy(filter=custom_filter)
        assert proxy.filter is custom_filter

    def test_stores_cwd(self):
        proxy = SecurityProxy(cwd="/home/user/project")
        assert proxy.cwd == "/home/user/project"

    def test_set_cwd(self):
        proxy = SecurityProxy()
        assert proxy.cwd is None
        proxy.set_cwd("/tmp")
        assert proxy.cwd == "/tmp"


class TestProcessAgentMessageInvalidInput:
    def test_invalid_json_forwards_to_client(self):
        proxy = SecurityProxy()
        response, should_forward = proxy.process_agent_message(b"not valid json")

        assert response is None
        assert should_forward is True

    def test_invalid_utf8_forwards_to_client(self):
        proxy = SecurityProxy()
        # Invalid UTF-8 sequence
        response, should_forward = proxy.process_agent_message(b"\xff\xfe")

        assert response is None
        assert should_forward is True


class TestProcessAgentMessageNonPermission:
    def test_non_permission_message_forwards_to_client(self):
        proxy = SecurityProxy()
        raw = make_other_message()
        response, should_forward = proxy.process_agent_message(raw)

        assert response is None
        assert should_forward is True

    def test_notification_without_id_forwards_to_client(self):
        proxy = SecurityProxy()
        msg = {"jsonrpc": "2.0", "method": "session/request_permission", "params": {}}
        raw = json.dumps(msg).encode("utf-8")
        response, should_forward = proxy.process_agent_message(raw)

        assert response is None
        assert should_forward is True


class TestProcessAgentMessageNoPaths:
    def test_no_paths_extracted_forwards_to_client(self):
        proxy = SecurityProxy()
        # Unknown tool with no recognized path fields
        raw = make_permission_request(
            tool_name="unknown_tool", tool_input={"some_field": "value"}
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is None
        assert should_forward is True


class TestProcessAgentMessageBlocked:
    def test_blocked_path_returns_error_response(self):
        # Create mock filter that always denies
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="deny",
            reason="Blocked by security filter",
            file_path="/home/user/.ssh/id_rsa",
            canonical_path="/home/user/.ssh/id_rsa",
            matched_pattern=SecurityPattern(
                pattern="~/.ssh/*",
                decision="deny",
                level=SpecificityLevel.DIR_GLOB,
                description="SSH directory",
            ),
            matched_level=SpecificityLevel.DIR_GLOB,
        )

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_input={"file_path": "/home/user/.ssh/id_rsa"}
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False

        # Verify error response structure
        response_data = json.loads(response.decode("utf-8"))
        assert response_data["jsonrpc"] == "2.0"
        assert response_data["id"] == "perm-123"
        assert "error" in response_data
        assert response_data["error"]["code"] == SECURITY_BLOCK_ERROR_CODE
        assert response_data["error"]["data"]["type"] == "security_block"
        assert response_data["error"]["data"]["pattern"] == "~/.ssh/*"

    def test_first_denied_path_blocks_immediately(self):
        """If multiple paths and first is denied, should block without checking others."""
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="deny",
            reason="Blocked",
            file_path="/etc/shadow",
            canonical_path="/etc/shadow",
            matched_pattern=SecurityPattern(
                pattern="/etc/shadow",
                decision="deny",
                level=SpecificityLevel.FILE_NAME,
                description="Shadow file",
            ),
            matched_level=SpecificityLevel.FILE_NAME,
        )

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_name="bash",
            tool_input={"command": "cat /etc/shadow /etc/passwd"},
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False
        # Should have checked at least one path
        assert mock_filter.check.called


class TestProcessAgentMessageAllowed:
    def test_allowed_path_returns_auto_allow(self):
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="allow",
            reason="Allowed by security filter",
            file_path="/home/user/project/main.py",
            canonical_path="/home/user/project/main.py",
            matched_pattern=SecurityPattern(
                pattern="~/project/*",
                decision="allow",
                level=SpecificityLevel.DIR_GLOB,
                description="Project directory",
            ),
            matched_level=SpecificityLevel.DIR_GLOB,
        )

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_input={"file_path": "/home/user/project/main.py"}
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False

        # Verify auto-allow response structure
        response_data = json.loads(response.decode("utf-8"))
        assert response_data["jsonrpc"] == "2.0"
        assert response_data["id"] == "perm-123"
        assert "result" in response_data
        assert response_data["result"]["outcome"]["type"] == "selected"
        assert response_data["result"]["outcome"]["optionId"] == "allow_once"

    def test_all_paths_allowed_returns_auto_allow(self):
        """If multiple paths and all are allowed, should return auto-allow."""
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="allow",
            reason="Allowed",
            file_path="/tmp/test.txt",
            canonical_path="/tmp/test.txt",
            matched_pattern=None,
            matched_level=None,
        )

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_name="bash",
            tool_input={"command": "cp /tmp/a.txt /tmp/b.txt"},
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False

        response_data = json.loads(response.decode("utf-8"))
        assert response_data["result"]["outcome"]["optionId"] == "allow_once"


class TestProcessAgentMessagePassThrough:
    def test_pass_decision_forwards_to_client(self):
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="pass",
            reason="No matching rule",
            file_path="/some/random/path.txt",
            canonical_path="/some/random/path.txt",
            matched_pattern=None,
            matched_level=None,
        )

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(tool_input={"file_path": "/some/random/path.txt"})
        response, should_forward = proxy.process_agent_message(raw)

        assert response is None
        assert should_forward is True

    def test_mixed_allow_and_pass_forwards_to_client(self):
        """If some paths are allowed and some pass, forward to client."""
        mock_filter = MagicMock(spec=SecurityFilter)
        # First path is allowed, second is pass
        mock_filter.check.side_effect = [
            CheckResult(
                decision="allow",
                reason="Allowed",
                file_path="/tmp/allowed.txt",
                canonical_path="/tmp/allowed.txt",
                matched_pattern=None,
                matched_level=None,
            ),
            CheckResult(
                decision="pass",
                reason="No matching rule",
                file_path="/unknown/path.txt",
                canonical_path="/unknown/path.txt",
                matched_pattern=None,
                matched_level=None,
            ),
        ]

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_name="bash",
            tool_input={"command": "cp /tmp/allowed.txt /unknown/path.txt"},
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is None
        assert should_forward is True


class TestProcessAgentMessageMixedDecisions:
    def test_deny_takes_precedence_over_allow(self):
        """If any path is denied, block even if others are allowed."""
        mock_filter = MagicMock(spec=SecurityFilter)
        # First path is allowed, second is denied
        mock_filter.check.side_effect = [
            CheckResult(
                decision="allow",
                reason="Allowed",
                file_path="/tmp/allowed.txt",
                canonical_path="/tmp/allowed.txt",
                matched_pattern=None,
                matched_level=None,
            ),
            CheckResult(
                decision="deny",
                reason="Blocked",
                file_path="/etc/shadow",
                canonical_path="/etc/shadow",
                matched_pattern=SecurityPattern(
                    pattern="/etc/shadow",
                    decision="deny",
                    level=SpecificityLevel.FILE_NAME,
                    description="Shadow file",
                ),
                matched_level=SpecificityLevel.FILE_NAME,
            ),
        ]

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_name="bash",
            tool_input={"command": "cat /tmp/allowed.txt /etc/shadow"},
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False

        response_data = json.loads(response.decode("utf-8"))
        assert "error" in response_data
        assert response_data["error"]["code"] == SECURITY_BLOCK_ERROR_CODE

    def test_deny_takes_precedence_over_pass(self):
        """If any path is denied, block even if others are pass."""
        mock_filter = MagicMock(spec=SecurityFilter)
        # First path is pass, second is denied
        mock_filter.check.side_effect = [
            CheckResult(
                decision="pass",
                reason="No matching rule",
                file_path="/some/path.txt",
                canonical_path="/some/path.txt",
                matched_pattern=None,
                matched_level=None,
            ),
            CheckResult(
                decision="deny",
                reason="Blocked",
                file_path="/etc/shadow",
                canonical_path="/etc/shadow",
                matched_pattern=SecurityPattern(
                    pattern="/etc/shadow",
                    decision="deny",
                    level=SpecificityLevel.FILE_NAME,
                    description="Shadow file",
                ),
                matched_level=SpecificityLevel.FILE_NAME,
            ),
        ]

        proxy = SecurityProxy(filter=mock_filter)
        raw = make_permission_request(
            tool_name="bash",
            tool_input={"command": "cat /some/path.txt /etc/shadow"},
        )
        response, should_forward = proxy.process_agent_message(raw)

        assert response is not None
        assert should_forward is False


class TestProcessAgentMessageCwdPropagation:
    def test_cwd_passed_to_filter(self):
        mock_filter = MagicMock(spec=SecurityFilter)
        mock_filter.check.return_value = CheckResult(
            decision="allow",
            reason="Allowed",
            file_path="./relative.txt",
            canonical_path="/home/user/project/relative.txt",
            matched_pattern=None,
            matched_level=None,
        )

        proxy = SecurityProxy(filter=mock_filter, cwd="/home/user/project")
        raw = make_permission_request(tool_input={"file_path": "./relative.txt"})
        proxy.process_agent_message(raw)

        # Verify cwd was passed to the filter
        mock_filter.check.assert_called_with("./relative.txt", "/home/user/project")
