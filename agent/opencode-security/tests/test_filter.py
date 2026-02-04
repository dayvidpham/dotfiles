"""Tests for security filter."""

import os
from pathlib import Path
import pytest

from opencode_security.filter import SecurityFilter
from opencode_security.types import SpecificityLevel


@pytest.fixture
def filter():
    return SecurityFilter()


class TestSecurityFilterCheck:
    def test_pub_file_allowed(self, filter):
        """Public key files should be allowed even in .ssh"""
        home = str(Path.home())
        result = filter.check(f"{home}/.ssh/id_ed25519.pub")
        assert result.decision == "allow"
        assert result.matched_level == SpecificityLevel.FILE_EXTENSION
        # Pattern is now regex: \.pub$ instead of *.pub
        assert result.matched_pattern.pattern == r"\.pub$"

    def test_env_in_dotfiles_denied(self, filter):
        """*.env denied even in trusted directories"""
        home = str(Path.home())
        result = filter.check(f"{home}/dotfiles/.env")
        assert result.decision == "deny"
        assert result.matched_level == SpecificityLevel.FILE_EXTENSION
        assert ".env" in result.reason

    def test_ssh_private_key_denied(self, filter):
        """SSH private keys should be denied"""
        home = str(Path.home())
        result = filter.check(f"{home}/.ssh/id_rsa")
        assert result.decision == "deny"

    def test_dotfiles_allowed(self, filter):
        """Files in trusted ~/dotfiles should be allowed"""
        home = str(Path.home())
        result = filter.check(f"{home}/dotfiles/flake.nix")
        assert result.decision == "allow"
        assert result.matched_level == SpecificityLevel.DIR_GLOB

    def test_secrets_dir_denied(self, filter):
        """**/secrets/** should be denied"""
        result = filter.check("/home/user/project/secrets/api.key")
        assert result.decision == "deny"
        assert result.matched_level == SpecificityLevel.SECURITY_DIRECTORY

    def test_restrictive_perms_denied(self, filter, tmp_path):
        """Files with mode 600 should be denied"""
        test_file = tmp_path / "secret.txt"
        test_file.write_text("secret")
        os.chmod(test_file, 0o600)

        result = filter.check(str(test_file))
        assert result.decision == "deny"
        assert result.matched_level == SpecificityLevel.PERMISSIONS

    def test_no_match_passes(self, filter):
        """Unmatched files with permissive perms pass through"""
        result = filter.check("/etc/hostname")
        assert result.decision == "pass"
        assert result.matched_pattern is None

    def test_fail_closed_on_error(self, filter):
        """Errors should result in deny (fail-closed)"""
        # Path with invalid characters to trigger error
        result = filter.check("/path/with\x00null")
        assert result.decision == "deny"
        assert "Error" in result.reason


class TestSecurityFilterHelpers:
    def test_check_multiple(self, filter):
        """check_multiple should process list of paths"""
        home = str(Path.home())
        paths = [f"{home}/.ssh/id_rsa", f"{home}/dotfiles/flake.nix"]
        results = filter.check_multiple(paths)
        assert len(results) == 2
        assert results[0].decision == "deny"
        assert results[1].decision == "allow"

    def test_should_block(self, filter):
        """should_block returns boolean for quick checks"""
        home = str(Path.home())
        assert filter.should_block(f"{home}/.ssh/id_rsa") is True
        assert filter.should_block(f"{home}/dotfiles/flake.nix") is False
