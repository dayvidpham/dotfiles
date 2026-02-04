"""Tests for specificity resolver."""

from pathlib import Path
import pytest

from opencode_security.resolver import (
    find_matching_patterns,
    group_by_level,
    resolve,
)
from opencode_security.types import SpecificityLevel


class TestFindMatchingPatterns:
    def test_finds_ssh_patterns(self):
        home = str(Path.home())
        matches = find_matching_patterns(f"{home}/.ssh/id_rsa")
        assert len(matches) > 0
        patterns = [m.pattern.pattern for m in matches]
        assert "~/.ssh/*" in patterns or any(".ssh" in p for p in patterns)

    def test_finds_pub_key_patterns(self):
        home = str(Path.home())
        matches = find_matching_patterns(f"{home}/.ssh/id_ed25519.pub")
        patterns = [m.pattern.pattern for m in matches]
        assert r"\.pub$" in patterns


class TestGroupByLevel:
    def test_groups_correctly(self):
        home = str(Path.home())
        matches = find_matching_patterns(f"{home}/.ssh/id_ed25519.pub")
        grouped = group_by_level(matches)
        # Should have FILE_EXTENSION level for *.pub
        assert SpecificityLevel.FILE_EXTENSION in grouped or SpecificityLevel.DIR_GLOB in grouped


class TestResolve:
    def test_pub_file_in_ssh_allowed(self):
        """*.pub (L2, ALLOW) supersedes ~/.ssh/* (L6, DENY)"""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/.ssh/id_ed25519.pub", False)
        assert decision == "allow"
        assert level == SpecificityLevel.FILE_EXTENSION
        assert pattern is not None
        assert pattern.pattern == r"\.pub$"

    def test_env_in_dotfiles_denied(self):
        """*.env (L2, DENY) supersedes ~/dotfiles/* (L6, ALLOW)"""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/.env", False)
        assert decision == "deny"
        assert level == SpecificityLevel.FILE_EXTENSION
        assert pattern.pattern == r"\.env$"

    def test_ssh_config_denied(self):
        """~/.ssh/config matches only ~/.ssh/* (L6, DENY)"""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/.ssh/config", False)
        assert decision == "deny"
        assert level == SpecificityLevel.DIR_GLOB

    def test_dotfiles_nix_allowed(self):
        """~/dotfiles/flake.nix matches only ~/dotfiles/* (L6, ALLOW)"""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/flake.nix", False)
        assert decision == "allow"
        assert level == SpecificityLevel.DIR_GLOB

    def test_secrets_dir_denied(self):
        """**/secrets/** (L4, DENY - SECURITY_DIRECTORY)"""
        decision, reason, pattern, level = resolve("/home/user/project/secrets/api.key", False)
        assert decision == "deny"
        assert level == SpecificityLevel.SECURITY_DIRECTORY

    def test_dotfiles_secrets_denied(self):
        """~/dotfiles/secrets should be DENIED by **/secrets/** (L4) not ALLOWED by ~/dotfiles/* (L6)"""
        home = str(Path.home())
        # This is the critical test: secrets dir inside trusted dotfiles should be denied
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/secrets", False)
        assert decision == "deny"
        assert level == SpecificityLevel.SECURITY_DIRECTORY
        assert pattern.pattern == "(^|/)secrets(/|$)"

    def test_restrictive_perms_denied(self):
        """Mode 600 file with no pattern matches -> DENY at L5"""
        decision, reason, pattern, level = resolve("/tmp/random.txt", True)
        assert decision == "deny"
        assert level == SpecificityLevel.PERMISSIONS
        assert "restrictive permissions" in reason

    def test_no_match_passes(self):
        """File with no matches and permissive perms -> PASS"""
        decision, reason, pattern, level = resolve("/etc/hostname", False)
        assert decision == "pass"
        assert pattern is None
        assert level is None
