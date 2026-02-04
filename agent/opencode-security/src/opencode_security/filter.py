"""Security filter orchestrating all checks."""

from .types import CheckResult
from .paths import canonicalize, is_restrictive_permissions
from .resolver import resolve


class SecurityFilter:
    """Security filter that checks file access permissions.

    Uses specificity-based precedence:
    - More specific patterns supersede broader patterns
    - DENY supersedes ALLOW at each specificity level
    - Fail-closed on errors
    """

    def check(self, file_path: str, cwd: str | None = None) -> CheckResult:
        """Check if a file path should be allowed, denied, or passed through.

        Args:
            file_path: The file path to check
            cwd: Current working directory for relative paths

        Returns:
            CheckResult with decision, reason, and match details
        """
        try:
            # Step 1: Canonicalize path (resolve ~, .., symlinks)
            canonical_path = canonicalize(file_path, cwd)

            # Step 2: Check permission mode bits
            try:
                has_restrictive_perms = is_restrictive_permissions(canonical_path)
            except (OSError, IOError):
                # File doesn't exist or can't read - treat as not restrictive
                has_restrictive_perms = False

            # Step 3: Run specificity-based resolution
            decision, reason, pattern, level = resolve(canonical_path, has_restrictive_perms)

            return CheckResult(
                decision=decision,
                reason=reason,
                file_path=file_path,
                canonical_path=canonical_path,
                matched_pattern=pattern,
                matched_level=level
            )

        except Exception as e:
            # Fail-closed: any error results in DENY
            return CheckResult(
                decision="deny",
                reason=f"Error during security check: {e}",
                file_path=file_path,
                canonical_path=file_path,  # Best effort
                matched_pattern=None,
                matched_level=None
            )

    def check_multiple(self, file_paths: list[str], cwd: str | None = None) -> list[CheckResult]:
        """Check multiple file paths."""
        return [self.check(path, cwd) for path in file_paths]

    def should_block(self, file_path: str, cwd: str | None = None) -> bool:
        """Quick check if path should be blocked."""
        result = self.check(file_path, cwd)
        return result.decision == "deny"
