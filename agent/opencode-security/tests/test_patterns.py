"""Tests for pattern matching."""

from pathlib import Path

import pytest

from opencode_security.patterns import PATTERNS, expand_pattern, match_pattern
from opencode_security.types import SpecificityLevel


class TestExpandPattern:
    def test_expands_tilde(self):
        result = expand_pattern("~/.ssh/id_rsa")
        assert result == str(Path.home() / ".ssh" / "id_rsa")

    def test_no_tilde_unchanged(self):
        result = expand_pattern("/etc/passwd")
        assert result == "/etc/passwd"


class TestMatchPattern:
    def test_extension_glob_pub(self):
        home = str(Path.home())
        assert match_pattern("*.pub", f"{home}/.ssh/id_ed25519.pub")
        assert not match_pattern("*.pub", f"{home}/.ssh/id_ed25519")

    def test_extension_glob_env(self):
        assert match_pattern("*.env", "/home/user/project/.env")
        assert match_pattern("*.env.*", "/home/user/.env.local")
        assert not match_pattern("*.env", "/home/user/env")

    def test_dir_glob_ssh(self):
        home = str(Path.home())
        assert match_pattern("~/.ssh/*", f"{home}/.ssh/config")
        assert match_pattern("~/.ssh/*", f"{home}/.ssh/id_rsa")

    def test_dir_glob_ssh_does_not_recurse(self):
        """Single * should not match subdirectories."""
        home = str(Path.home())
        # This should NOT match because * doesn't recurse
        assert not match_pattern("~/.ssh/*", f"{home}/.ssh/subdir/file")

    def test_glob_middle_secrets(self):
        assert match_pattern("**/secrets/**", "/any/path/secrets/api.key")
        assert match_pattern("**/secrets/**", "/home/user/project/secrets/db.json")
        # Should also match the directory itself, not just contents
        assert match_pattern("**/secrets/**", "/any/path/secrets")
        assert match_pattern("**/secrets/**", "/home/user/project/secrets")

    def test_glob_middle_credentials(self):
        assert match_pattern("*credentials*", "/path/to/credentials.json")
        assert match_pattern("*credentials*", "/path/aws_credentials")

    def test_exact_file_name(self):
        home = str(Path.home())
        assert match_pattern("~/.netrc", f"{home}/.netrc")
        assert not match_pattern("~/.netrc", f"{home}/.ssh/.netrc")


class TestPatternsConfig:
    def test_all_patterns_have_valid_levels(self):
        for p in PATTERNS:
            assert p.level in SpecificityLevel

    def test_has_ssh_patterns(self):
        ssh_patterns = [p for p in PATTERNS if ".ssh" in p.pattern]
        assert len(ssh_patterns) > 0

    def test_has_trusted_patterns(self):
        trusted = [p for p in PATTERNS if p.decision == "allow"]
        assert len(trusted) > 0

    def test_has_deny_patterns(self):
        deny = [p for p in PATTERNS if p.decision == "deny"]
        assert len(deny) > 0

    def test_has_all_specificity_levels(self):
        """Verify we have patterns at multiple specificity levels."""
        levels_present = {p.level for p in PATTERNS}
        assert SpecificityLevel.FILE_NAME in levels_present
        assert SpecificityLevel.FILE_EXTENSION in levels_present
        assert SpecificityLevel.DIR_GLOB in levels_present
        assert SpecificityLevel.SECURITY_DIRECTORY in levels_present
