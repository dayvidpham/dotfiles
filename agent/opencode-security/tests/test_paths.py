"""Tests for path canonicalization."""

import os
import pytest
from pathlib import Path

from opencode_security.paths import (
    canonicalize,
    resolve_symlinks,
    is_restrictive_permissions,
    MAX_SYMLINK_DEPTH,
)
from opencode_security.types import PathResolutionError, CircularSymlinkError


class TestCanonicalize:
    def test_expands_tilde(self):
        result = canonicalize("~/test.txt")
        expected = str(Path.home() / "test.txt")
        assert result == expected

    def test_resolves_dotdot(self):
        result = canonicalize("/home/user/../user/file.txt")
        assert ".." not in result
        assert result == "/home/user/file.txt"

    def test_handles_relative_with_cwd(self):
        result = canonicalize("file.txt", cwd="/home/user")
        assert result == "/home/user/file.txt"

    def test_handles_absolute_path(self):
        result = canonicalize("/etc/passwd")
        assert result == "/etc/passwd"


class TestResolveSymlinks:
    def test_resolves_regular_file(self, tmp_path):
        test_file = tmp_path / "test.txt"
        test_file.write_text("test")

        result = resolve_symlinks(test_file)
        assert result == test_file.resolve()

    def test_resolves_symlink(self, tmp_path):
        target = tmp_path / "target.txt"
        target.write_text("target")
        link = tmp_path / "link.txt"
        link.symlink_to(target)

        result = resolve_symlinks(link)
        assert result == target.resolve()

    def test_depth_limit_raises(self, tmp_path):
        # Create a path that would exceed depth limit
        path = tmp_path / "test"
        with pytest.raises(CircularSymlinkError):
            resolve_symlinks(path, depth=MAX_SYMLINK_DEPTH + 1)


class TestIsRestrictivePermissions:
    def test_mode_600_is_restrictive(self, tmp_path):
        test_file = tmp_path / "secret.txt"
        test_file.write_text("secret")
        os.chmod(test_file, 0o600)

        assert is_restrictive_permissions(str(test_file)) is True

    def test_mode_644_is_not_restrictive(self, tmp_path):
        test_file = tmp_path / "public.txt"
        test_file.write_text("public")
        os.chmod(test_file, 0o644)

        assert is_restrictive_permissions(str(test_file)) is False

    def test_mode_400_is_restrictive(self, tmp_path):
        test_file = tmp_path / "readonly.txt"
        test_file.write_text("readonly")
        os.chmod(test_file, 0o400)

        assert is_restrictive_permissions(str(test_file)) is True

    def test_nonexistent_file_not_restrictive(self):
        assert is_restrictive_permissions("/nonexistent/file.txt") is False
