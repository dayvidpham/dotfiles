"""Integration tests for opencode-security filter.

This module consolidates all verification scripts into proper pytest tests,
providing comprehensive integration testing of the pattern matching, resolver,
and filter components working together.
"""

from pathlib import Path

import pytest

from opencode_security.filter import SecurityFilter
from opencode_security.patterns import PATTERNS, match_pattern
from opencode_security.resolver import resolve
from opencode_security.types import SpecificityLevel


class TestImports:
    """Verify all modules import correctly."""

    def test_all_modules_import(self):
        """All core modules should import without errors."""
        # If we got this far, imports succeeded
        assert PATTERNS is not None
        assert SecurityFilter is not None
        assert SpecificityLevel is not None

    def test_specificity_levels_defined(self):
        """All required specificity levels should be defined."""
        assert hasattr(SpecificityLevel, "FILE_NAME")
        assert hasattr(SpecificityLevel, "FILE_EXTENSION")
        assert hasattr(SpecificityLevel, "DIRECTORY")
        assert hasattr(SpecificityLevel, "SECURITY_DIRECTORY")
        assert hasattr(SpecificityLevel, "PERMISSIONS")
        assert hasattr(SpecificityLevel, "DIR_GLOB")
        assert hasattr(SpecificityLevel, "GLOB_MIDDLE")

    def test_patterns_loaded(self):
        """Pattern database should load successfully."""
        assert len(PATTERNS) > 0, "Should have loaded patterns"
        assert any(p.decision == "allow" for p in PATTERNS), "Should have allow patterns"
        assert any(p.decision == "deny" for p in PATTERNS), "Should have deny patterns"


class TestSpecificityLevels:
    """Verify specificity level ordering and configuration."""

    def test_security_directory_level_exists(self):
        """SECURITY_DIRECTORY should be level 4."""
        assert SpecificityLevel.SECURITY_DIRECTORY == 4

    @pytest.mark.parametrize(
        "level_name,expected_value",
        [
            ("FILE_NAME", 1),
            ("FILE_EXTENSION", 2),
            ("DIRECTORY", 3),
            ("SECURITY_DIRECTORY", 4),
            ("PERMISSIONS", 5),
            ("DIR_GLOB", 6),
            ("GLOB_MIDDLE", 7),
        ],
    )
    def test_level_ordering(self, level_name, expected_value):
        """Specificity levels should have correct numeric values for precedence."""
        actual = getattr(SpecificityLevel, level_name)
        assert actual == expected_value, f"{level_name} should be {expected_value} but is {actual}"

    def test_security_patterns_at_correct_level(self):
        """Security directory patterns should be at SECURITY_DIRECTORY level."""
        security_patterns = [
            p for p in PATTERNS if p.level == SpecificityLevel.SECURITY_DIRECTORY
        ]
        assert len(security_patterns) >= 6, "Should have at least 6 security patterns"

        # Verify key security patterns are present (both singular and plural)
        pattern_strings = {p.pattern for p in security_patterns}
        assert "(^|/)secrets(/|$)" in pattern_strings
        assert "(^|/)secret(/|$)" in pattern_strings
        assert r"(^|/)\.secrets(/|$)" in pattern_strings
        assert r"(^|/)\.secret(/|$)" in pattern_strings


class TestPatternMatching:
    """Integration tests for pattern matching logic."""

    @pytest.mark.parametrize(
        "pattern,path,expected,description",
        [
            # **/secrets/** pattern tests
            (
                "**/secrets/**",
                "{home}/dotfiles/secrets",
                True,
                "directory itself",
            ),
            (
                "**/secrets/**",
                "{home}/dotfiles/secrets/api.key",
                True,
                "file inside directory",
            ),
            (
                "**/secrets/**",
                "/any/path/secrets",
                True,
                "secrets anywhere",
            ),
            (
                "**/secrets/**",
                "/any/path/secrets/file.txt",
                True,
                "file in secrets anywhere",
            ),
            (
                "**/secrets/**",
                "{home}/dotfiles/not-secrets",
                False,
                "different directory",
            ),
            # ~/dotfiles/* pattern tests
            (
                "~/dotfiles/*",
                "{home}/dotfiles/secrets",
                True,
                "dir in dotfiles",
            ),
            (
                "~/dotfiles/*",
                "{home}/dotfiles/flake.nix",
                True,
                "file in dotfiles",
            ),
            # Extension patterns
            (
                "*.env",
                "/home/user/project/.env",
                True,
                ".env file",
            ),
            (
                "*.pub",
                "{home}/.ssh/id_ed25519.pub",
                True,
                "public key",
            ),
        ],
    )
    def test_pattern_matching_cases(self, pattern, path, expected, description):
        """Test various pattern matching scenarios."""
        # Expand {home} placeholder
        actual_path = path.replace("{home}", str(Path.home()))
        result = match_pattern(pattern, actual_path)
        assert (
            result == expected
        ), f"Pattern '{pattern}' matching '{actual_path}' ({description})"


class TestSecurityDirectoryPrecedence:
    """Verify SECURITY_DIRECTORY level overrides lower-specificity allowlists.

    This is the critical security property: security-sensitive directories like
    **/secrets/** must be denied even when inside otherwise-trusted paths like
    ~/dotfiles/*.
    """

    def test_dotfiles_secrets_denied(self):
        """~/dotfiles/secrets should be DENIED by **/secrets/** (L4), not ALLOWED by ~/dotfiles/* (L6)."""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/secrets", False)

        assert decision == "deny", f"Expected deny but got {decision}: {reason}"
        assert (
            level == SpecificityLevel.SECURITY_DIRECTORY
        ), f"Expected SECURITY_DIRECTORY but got {level}"
        assert pattern is not None and pattern.pattern == "(^|/)secrets(/|$)"

    def test_dotfiles_secret_singular_denied(self):
        """~/dotfiles/secret (singular) should also be DENIED."""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/secret", False)

        assert decision == "deny", f"Expected deny but got {decision}: {reason}"
        assert level == SpecificityLevel.SECURITY_DIRECTORY
        assert pattern is not None and pattern.pattern == "(^|/)secret(/|$)"

    def test_dotfiles_normal_allowed(self):
        """~/dotfiles/flake.nix should still be ALLOWED."""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/flake.nix", False)

        assert decision == "allow", f"Expected allow but got {decision}: {reason}"
        assert level == SpecificityLevel.DIR_GLOB

    def test_env_file_denied_in_dotfiles(self):
        """~/dotfiles/.env should be DENIED by *.env (L2), not ALLOWED by ~/dotfiles/* (L6)."""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/dotfiles/.env", False)

        assert decision == "deny"
        assert level == SpecificityLevel.FILE_EXTENSION
        assert pattern is not None and pattern.pattern == r"\.env$"

    def test_pub_key_allowed_in_ssh(self):
        """~/.ssh/id_ed25519.pub should be ALLOWED by *.pub (L2), not DENIED by ~/.ssh/* (L6)."""
        home = str(Path.home())
        decision, reason, pattern, level = resolve(f"{home}/.ssh/id_ed25519.pub", False)

        assert decision == "allow"
        assert level == SpecificityLevel.FILE_EXTENSION
        assert pattern is not None and pattern.pattern == r"\.pub$"


class TestResolverDecisions:
    """Integration tests for resolver decision-making."""

    @pytest.mark.parametrize(
        "path,expected_decision,expected_level,description",
        [
            (
                "{home}/dotfiles/secrets",
                "deny",
                SpecificityLevel.SECURITY_DIRECTORY,
                "secrets in dotfiles",
            ),
            (
                "{home}/dotfiles/flake.nix",
                "allow",
                SpecificityLevel.DIR_GLOB,
                "normal file in dotfiles",
            ),
            (
                "{home}/dotfiles/.env",
                "deny",
                SpecificityLevel.FILE_EXTENSION,
                ".env in dotfiles",
            ),
            (
                "{home}/.ssh/id_ed25519.pub",
                "allow",
                SpecificityLevel.FILE_EXTENSION,
                ".pub in .ssh",
            ),
            (
                "{home}/.ssh/id_rsa",
                "deny",
                SpecificityLevel.FILE_NAME,  # Matches new id_rsa filename pattern
                "private key in .ssh",
            ),
            (
                "/home/user/project/secrets/api.key",
                "deny",
                SpecificityLevel.SECURITY_DIRECTORY,
                "secrets anywhere",
            ),
        ],
    )
    def test_resolver_comprehensive(
        self, path, expected_decision, expected_level, description
    ):
        """Test resolver makes correct decisions for various paths."""
        # Expand {home} placeholder
        actual_path = path.replace("{home}", str(Path.home()))
        decision, reason, pattern, level = resolve(actual_path, False)

        assert (
            decision == expected_decision
        ), f"{description}: expected {expected_decision} but got {decision} ({reason})"
        assert (
            level == expected_level
        ), f"{description}: expected {expected_level.name} but got {level.name if level else 'None'}"


class TestRecursivePatternMatching:
    """Tests for recursive pattern matching logic (**/pattern/**)."""

    def test_secrets_directory_matches(self):
        """**/secrets/** should match the directory itself."""
        assert match_pattern("**/secrets/**", "/any/path/secrets")
        assert match_pattern("**/secrets/**", str(Path.home() / "dotfiles" / "secrets"))

    def test_secrets_file_matches(self):
        """**/secrets/** should match files inside the directory."""
        assert match_pattern("**/secrets/**", "/any/path/secrets/file.txt")
        assert match_pattern(
            "**/secrets/**", str(Path.home() / "dotfiles" / "secrets" / "api.key")
        )

    def test_non_secrets_no_match(self):
        """**/secrets/** should not match non-secrets paths."""
        assert not match_pattern("**/secrets/**", "/any/path/not-secrets")
        assert not match_pattern("**/secrets/**", str(Path.home() / "dotfiles" / "src"))

    def test_git_directory_matches(self):
        """**/.git/** should match .git directories."""
        assert match_pattern("**/.git/**", "/any/path/.git")
        assert match_pattern("**/.git/**", "/any/path/.git/config")
        assert not match_pattern("**/.git/**", "/any/path/git")


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_empty_path(self):
        """Empty path should not crash."""
        decision, reason, pattern, level = resolve("", False)
        assert decision == "pass"

    def test_relative_path_handling(self):
        """Relative paths should work correctly."""
        decision, reason, pattern, level = resolve("./secrets/api.key", False)
        # Should match **/secrets/** pattern
        assert decision == "deny"
        assert level == SpecificityLevel.SECURITY_DIRECTORY

    def test_restrictive_permissions_override(self):
        """Restrictive permissions should deny access even without pattern match."""
        decision, reason, pattern, level = resolve("/tmp/random.txt", True)
        assert decision == "deny"
        assert level == SpecificityLevel.PERMISSIONS
        assert "restrictive permissions" in reason

    def test_no_match_no_restrictive_perms(self):
        """Unmatched path with normal permissions should pass."""
        decision, reason, pattern, level = resolve("/etc/hostname", False)
        assert decision == "pass"
        assert pattern is None
        assert level is None


class TestSecurityFilterIntegration:
    """Integration tests using the SecurityFilter class."""

    def test_filter_initialization(self):
        """SecurityFilter should initialize without errors."""
        filter_obj = SecurityFilter()
        assert filter_obj is not None

    def test_filter_denies_secrets(self):
        """SecurityFilter should deny access to secrets directory."""
        filter_obj = SecurityFilter()
        home = str(Path.home())

        result = filter_obj.check(f"{home}/dotfiles/secrets")
        assert result.decision == "deny"
        assert result.matched_level == SpecificityLevel.SECURITY_DIRECTORY
        assert result.matched_pattern is not None
        assert result.matched_pattern.pattern == "(^|/)secrets(/|$)"

    def test_filter_allows_dotfiles(self):
        """SecurityFilter should allow normal files in dotfiles."""
        filter_obj = SecurityFilter()
        home = str(Path.home())

        result = filter_obj.check(f"{home}/dotfiles/flake.nix")
        assert result.decision == "allow"
        assert result.matched_level == SpecificityLevel.DIR_GLOB

    def test_filter_should_block_method(self):
        """SecurityFilter.should_block() should correctly identify blocked paths."""
        filter_obj = SecurityFilter()
        home = str(Path.home())

        # Should block secrets
        assert filter_obj.should_block(f"{home}/dotfiles/secrets")
        # Should not block normal files
        assert not filter_obj.should_block(f"{home}/dotfiles/flake.nix")

    def test_filter_check_multiple(self):
        """SecurityFilter.check_multiple() should handle multiple paths."""
        filter_obj = SecurityFilter()
        home = str(Path.home())

        paths = [
            f"{home}/dotfiles/secrets",
            f"{home}/dotfiles/flake.nix",
            f"{home}/.ssh/id_rsa.pub",
        ]
        results = filter_obj.check_multiple(paths)

        assert len(results) == 3
        assert results[0].decision == "deny"  # secrets
        assert results[1].decision == "allow"  # flake.nix
        assert results[2].decision == "allow"  # .pub file


class TestCriticalSecurityProperties:
    """Critical security properties that must always hold."""

    def test_secrets_never_allowed(self):
        """No path containing /secrets/ should ever be allowed."""
        test_paths = [
            "/home/user/secrets",
            "/home/user/project/secrets/api.key",
            str(Path.home() / "dotfiles" / "secrets"),
            str(Path.home() / "dotfiles" / "secrets" / "config.json"),
            "/var/lib/secrets/db.key",
        ]

        for path in test_paths:
            decision, reason, pattern, level = resolve(path, False)
            assert (
                decision != "allow"
            ), f"Path {path} should never be allowed, but got: {decision}"

    def test_env_files_never_allowed(self):
        """*.env files should never be allowed."""
        test_paths = [
            "/home/user/project/.env",
            "/home/user/.env.local",
            str(Path.home() / "dotfiles" / ".env"),
            "/var/www/.env.production",
        ]

        for path in test_paths:
            decision, reason, pattern, level = resolve(path, False)
            assert (
                decision != "allow"
            ), f".env file {path} should never be allowed, but got: {decision}"

    def test_private_keys_never_allowed(self):
        """Private keys in ~/.ssh should never be allowed."""
        home = str(Path.home())
        test_paths = [
            f"{home}/.ssh/id_rsa",
            f"{home}/.ssh/id_ed25519",
            f"{home}/.ssh/id_ecdsa",
        ]

        for path in test_paths:
            decision, reason, pattern, level = resolve(path, False)
            assert (
                decision != "allow"
            ), f"Private key {path} should never be allowed, but got: {decision}"

    def test_public_keys_always_allowed(self):
        """Public keys (*.pub) should always be allowed."""
        home = str(Path.home())
        test_paths = [
            f"{home}/.ssh/id_rsa.pub",
            f"{home}/.ssh/id_ed25519.pub",
            f"{home}/.ssh/id_ecdsa.pub",
        ]

        for path in test_paths:
            decision, reason, pattern, level = resolve(path, False)
            assert (
                decision == "allow"
            ), f"Public key {path} should be allowed, but got: {decision} ({reason})"
