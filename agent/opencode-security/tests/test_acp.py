"""Tests for ACP message handling."""

import pytest

from opencode_security.acp import (
    SECURITY_BLOCK_ERROR_CODE,
    parse_message,
    serialize_message,
    is_permission_request,
    parse_permission_request,
    extract_paths_from_tool,
    create_rejection,
    create_passthrough_response,
    create_security_block_error,
    create_auto_allow_response,
)
from opencode_security.types import PermissionRequest


class TestParseMessage:
    def test_parses_valid_json(self):
        data = b'{"jsonrpc": "2.0", "id": 1}'
        result = parse_message(data)
        assert result == {"jsonrpc": "2.0", "id": 1}

    def test_handles_utf8(self):
        data = '{"msg": "héllo"}'.encode("utf-8")
        result = parse_message(data)
        assert result["msg"] == "héllo"


class TestSerializeMessage:
    def test_serializes_to_json_with_newline(self):
        msg = {"jsonrpc": "2.0", "id": 1}
        result = serialize_message(msg)
        assert result == b'{"jsonrpc": "2.0", "id": 1}\n'


class TestIsPermissionRequest:
    def test_valid_permission_request(self):
        msg = {
            "jsonrpc": "2.0",
            "id": "perm-123",
            "method": "session/request_permission",
            "params": {},
        }
        assert is_permission_request(msg) is True

    def test_other_method(self):
        msg = {
            "jsonrpc": "2.0",
            "id": "1",
            "method": "session/update",
        }
        assert is_permission_request(msg) is False

    def test_missing_id(self):
        msg = {
            "jsonrpc": "2.0",
            "method": "session/request_permission",
        }
        assert is_permission_request(msg) is False


class TestParsePermissionRequest:
    def test_parses_full_request(self):
        msg = {
            "jsonrpc": "2.0",
            "id": "perm-123",
            "method": "session/request_permission",
            "params": {
                "sessionId": "sess-abc",
                "toolCall": {
                    "toolCallId": "tc-456",
                    "name": "bash",
                    "input": {"command": "cat ~/.ssh/id_rsa"},
                },
                "options": ["allow_once", "reject_once"],
            },
        }
        result = parse_permission_request(msg)

        assert result is not None
        assert result.id == "perm-123"
        assert result.session_id == "sess-abc"
        assert result.tool_call_id == "tc-456"
        assert result.tool_name == "bash"
        assert result.tool_input == {"command": "cat ~/.ssh/id_rsa"}


class TestExtractPathsFromTool:
    def test_bash_cat_command(self):
        paths = extract_paths_from_tool("bash", {"command": "cat ~/.ssh/id_rsa"})
        assert "~/.ssh/id_rsa" in paths

    def test_bash_multiple_paths(self):
        paths = extract_paths_from_tool("bash", {"command": "cp /etc/passwd ~/backup/"})
        assert "/etc/passwd" in paths
        assert "~/backup/" in paths

    def test_read_file(self):
        paths = extract_paths_from_tool("read_file", {"file_path": "/etc/passwd"})
        assert paths == ["/etc/passwd"]

    def test_ignores_flags(self):
        paths = extract_paths_from_tool("bash", {"command": "ls -la /home"})
        assert "-la" not in paths
        assert "/home" in paths


class TestCreateRejection:
    def test_creates_valid_rejection(self):
        request = PermissionRequest(
            id="perm-123",
            session_id="sess",
            tool_call_id="tc",
            tool_name="bash",
            tool_input={},
            options=[],
        )
        result = create_rejection(request, "Blocked: ~/.ssh/*")

        assert result["jsonrpc"] == "2.0"
        assert result["id"] == "perm-123"
        assert result["result"]["outcome"] == "reject_once"
        assert "~/.ssh/*" in result["result"]["reason"]


class TestCreatePassthroughResponse:
    def test_creates_allow_response(self):
        result = create_passthrough_response("perm-123", "allow_once")

        assert result["id"] == "perm-123"
        assert result["result"]["outcome"] == "allow_once"


class TestCreateSecurityBlockError:
    def test_creates_error_response_with_directives(self):
        result = create_security_block_error(
            request_id="perm-123",
            path="/home/user/.ssh/id_rsa",
            pattern="~/.ssh/*",
            level=5,
        )

        assert result["jsonrpc"] == "2.0"
        assert result["id"] == "perm-123"
        assert "error" in result
        assert result["error"]["code"] == SECURITY_BLOCK_ERROR_CODE
        assert result["error"]["message"] == "Security filter: access denied"

        data = result["error"]["data"]
        assert data["type"] == "security_block"
        assert data["path"] == "/home/user/.ssh/id_rsa"
        assert data["pattern"] == "~/.ssh/*"
        assert data["level"] == 5
        assert "DANGEROUS" in data["warning"]
        assert "do_not" in data["directives"]
        assert "must" in data["directives"]
        assert len(data["directives"]["do_not"]) == 3
        assert len(data["directives"]["must"]) == 3

    def test_error_code_is_negative_32001(self):
        assert SECURITY_BLOCK_ERROR_CODE == -32001


class TestCreateAutoAllowResponse:
    def test_creates_auto_allow_with_selected_option(self):
        result = create_auto_allow_response("perm-456")

        assert result["jsonrpc"] == "2.0"
        assert result["id"] == "perm-456"
        assert "result" in result
        assert result["result"]["outcome"]["type"] == "selected"
        assert result["result"]["outcome"]["optionId"] == "allow_once"
