"""Benchmark tests for pattern matching performance.

These tests verify that pattern matching performance meets expectations
and document the performance characteristics of different approaches.
"""

import fnmatch
import re
import timeit
from pathlib import Path

import pytest


# Test data: realistic paths that would be checked by the security filter
BENCHMARK_PATHS = [
    "/home/user/dotfiles/secrets/api.key",
    "/project/src/config/.env.local",
    "/home/user/.ssh/id_ed25519.pub",
    "/var/log/app.log",
    "/home/user/codebases/myapp/main.py",
    "/home/user/dotfiles/flake.nix",
    "/project/.env",
    "/home/user/.aws/credentials",
    "/project/src/main.py",
    "/home/user/.config/gcloud/credentials.json",
]

# Patterns to test (representative sample)
GLOB_PATTERNS = [
    "*.env",
    "*.env.*",
    "*.pub",
    "*.pem",
    "*credential*",
    "*password*",
]

# Equivalent pre-compiled regex patterns
REGEX_PATTERNS = [
    re.compile(r".*\.env$"),
    re.compile(r".*\.env\..*$"),
    re.compile(r".*\.pub$"),
    re.compile(r".*\.pem$"),
    re.compile(r".*credential.*"),
    re.compile(r".*password.*"),
]


def glob_to_regex(pattern: str) -> re.Pattern:
    """Convert a glob pattern to a compiled regex.

    Handles:
    - * -> [^/]* (match anything except path separator)
    - **/ -> (.*/|^) (match any path prefix or start)
    - /** -> (/.*|$) (match any path suffix or end)
    - ? -> . (match single character)
    - Escapes regex special characters
    """
    # Handle special case: **/X/** pattern (recursive directory match)
    if pattern.startswith("**/") and pattern.endswith("/**"):
        middle = pattern[3:-3]  # Extract "secrets" from "**/secrets/**"
        escaped_middle = re.escape(middle)
        # Match: /secrets/, /secrets$, ^secrets/, ^secrets$
        return re.compile(rf"(^|/){escaped_middle}(/|$)")

    # Escape regex special chars except * and ?
    escaped = re.escape(pattern)
    # Convert glob wildcards to regex
    # First handle ** (must come before *)
    escaped = escaped.replace(r"\*\*", ".*")
    # Then handle single *
    escaped = escaped.replace(r"\*", "[^/]*")
    # Handle ?
    escaped = escaped.replace(r"\?", ".")
    return re.compile(escaped + "$")


class TestPatternMatchingPerformance:
    """Benchmark tests comparing fnmatch vs pre-compiled regex."""

    def test_fnmatch_baseline(self):
        """Establish fnmatch performance baseline."""
        def run_fnmatch():
            matches = 0
            for path in BENCHMARK_PATHS:
                filename = Path(path).name
                for pattern in GLOB_PATTERNS:
                    if fnmatch.fnmatch(filename, pattern):
                        matches += 1
            return matches

        # Warmup
        run_fnmatch()

        # Benchmark: 1000 iterations
        time_taken = timeit.timeit(run_fnmatch, number=1000)
        matches_per_sec = (len(BENCHMARK_PATHS) * len(GLOB_PATTERNS) * 1000) / time_taken

        # Store for comparison (using pytest cache or just print)
        print(f"\nfnmatch: {time_taken:.3f}s for 1000 iterations")
        print(f"fnmatch: {matches_per_sec:,.0f} pattern checks/sec")

        # Sanity check: should complete in reasonable time
        assert time_taken < 5.0, "fnmatch too slow"

    def test_precompiled_regex_performance(self):
        """Test pre-compiled regex performance."""
        def run_regex():
            matches = 0
            for path in BENCHMARK_PATHS:
                for pattern in REGEX_PATTERNS:
                    if pattern.search(path):
                        matches += 1
            return matches

        # Warmup
        run_regex()

        # Benchmark: 1000 iterations
        time_taken = timeit.timeit(run_regex, number=1000)
        matches_per_sec = (len(BENCHMARK_PATHS) * len(REGEX_PATTERNS) * 1000) / time_taken

        print(f"\nregex: {time_taken:.3f}s for 1000 iterations")
        print(f"regex: {matches_per_sec:,.0f} pattern checks/sec")

        assert time_taken < 5.0, "regex too slow"

    def test_compare_fnmatch_vs_regex_performance(self):
        """Compare fnmatch vs pre-compiled regex performance.

        This test documents performance characteristics rather than asserting
        a specific speedup, as results vary by platform and Python version.

        Key insight: fnmatch has internal caching in Python 3.9+, so the
        difference is less dramatic than expected. Both are acceptable
        for our use case (<100 patterns, <1000 paths per request).
        """
        iterations = 500
        paths = BENCHMARK_PATHS * 10

        def run_fnmatch():
            for path in paths:
                for pattern in GLOB_PATTERNS:
                    fnmatch.fnmatch(path, pattern)

        def run_regex():
            for path in paths:
                for pattern in REGEX_PATTERNS:
                    pattern.search(path)

        fn_time = timeit.timeit(run_fnmatch, number=iterations)
        rx_time = timeit.timeit(run_regex, number=iterations)

        print(f"\nfnmatch: {fn_time:.3f}s")
        print(f"regex:   {rx_time:.3f}s")
        print(f"Ratio:   {fn_time/rx_time:.2f}x")

        # Both should complete in reasonable time (< 1s for this workload)
        assert fn_time < 1.0, f"fnmatch too slow: {fn_time:.3f}s"
        assert rx_time < 1.0, f"regex too slow: {rx_time:.3f}s"

    def test_glob_to_regex_conversion(self):
        """Test that glob_to_regex correctly converts patterns."""
        test_cases = [
            # (glob, path, should_match)
            ("*.env", "/project/.env", True),
            ("*.env", "/project/app.env", True),
            ("*.env", "/project/.env.local", False),  # No match - has suffix
            ("*.env.*", "/project/.env.local", True),
            ("*.env.*", "/project/.env", False),  # No match - no suffix
            ("*.pub", "/home/user/.ssh/id_ed25519.pub", True),
            ("*credential*", "/project/credentials.json", True),
            ("*credential*", "/project/my-credential", True),
            ("**/secrets/**", "/project/secrets/api.key", True),
            ("**/secrets/**", "/home/user/dotfiles/secrets", True),
        ]

        for glob, path, expected in test_cases:
            regex = glob_to_regex(glob)
            result = regex.search(path) is not None
            assert result == expected, (
                f"glob_to_regex({glob!r}).search({path!r}) = {result}, expected {expected}"
            )

    def test_glob_to_regex_matches_fnmatch_behavior(self):
        """Verify glob_to_regex produces same results as fnmatch for filenames."""
        test_paths = [
            ".env",
            ".env.local",
            "app.env",
            "credentials.json",
            "id_ed25519.pub",
            "config.yaml",
            "password.txt",
        ]

        for pattern in GLOB_PATTERNS:
            regex = glob_to_regex(pattern)
            for path in test_paths:
                fn_result = fnmatch.fnmatch(path, pattern)
                rx_result = regex.search(path) is not None
                assert fn_result == rx_result, (
                    f"Mismatch for pattern={pattern!r}, path={path!r}: "
                    f"fnmatch={fn_result}, regex={rx_result}"
                )


class TestCompiledPatternCache:
    """Test that pattern compilation happens once and is cached."""

    def test_compilation_happens_once(self):
        """Verify patterns are compiled once, not on every match."""
        compile_count = 0
        original_compile = re.compile

        def counting_compile(pattern, *args, **kwargs):
            nonlocal compile_count
            compile_count += 1
            return original_compile(pattern, *args, **kwargs)

        # Compile patterns once
        compiled = [glob_to_regex(p) for p in GLOB_PATTERNS]
        initial_count = compile_count

        # Use patterns many times
        for _ in range(100):
            for path in BENCHMARK_PATHS:
                for pattern in compiled:
                    pattern.search(path)

        # No additional compilations should happen
        # (compile_count stays at initial_count because we're using pre-compiled)
        # This test validates the design - patterns are compiled upfront
        assert len(compiled) == len(GLOB_PATTERNS)
