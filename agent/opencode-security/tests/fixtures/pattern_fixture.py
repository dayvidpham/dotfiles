"""Combinatorial pattern test fixture loader and test case generator."""

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import yaml

from opencode_security.patterns import match_pattern as pattern_matches


def join_path(prefix: str, *parts: str) -> str:
    """Join path components using pathlib, preserving relative notation.

    Args:
        prefix: Path prefix (can be empty, ".", "./subdir", "/", "~", or absolute path)
        parts: Additional path components to join

    Returns:
        Properly joined path string
    """
    # Filter out empty parts
    parts = tuple(p for p in parts if p)
    if not parts:
        return prefix if prefix else "."

    if prefix == "":
        # Bare path without prefix
        return str(Path(*parts))
    elif prefix == ".":
        # Explicit current directory - preserve ./
        return "./" + str(Path(*parts))
    elif prefix.startswith("./"):
        # Relative path with ./ prefix - preserve it
        subdir = prefix[2:]  # Remove ./
        return "./" + str(Path(subdir, *parts))
    else:
        return str(Path(prefix, *parts))


@dataclass(frozen=True)
class TestCase:
    """A single test case generated from fixtures."""

    path: str
    pattern: str
    expected_decision: str
    level: str
    description: str
    category: str


class PatternFixture:
    """Load and generate combinatorial test cases from patterns.yaml fixture."""

    def __init__(self, fixture_path: str | None = None):
        """Initialize fixture from patterns.yaml.

        Args:
            fixture_path: Path to patterns.yaml. If None, uses default location.
        """
        if fixture_path is None:
            # Default to patterns.yaml in same directory as this module
            fixture_path = Path(__file__).parent / "patterns.yaml"

        with open(fixture_path) as f:
            self.data = yaml.safe_load(f)

    @property
    def path_prefixes(self) -> list[str]:
        """Get all path prefixes."""
        return self.data.get("path_prefixes", [])

    @property
    def denied_patterns(self) -> dict:
        """Get all denied pattern categories."""
        return self.data.get("denied_patterns", {})

    @property
    def allowed_patterns(self) -> dict:
        """Get all allowed pattern categories."""
        return self.data.get("allowed_patterns", {})

    @property
    def negative_cases(self) -> dict:
        """Get all negative test cases."""
        return self.data.get("negative_cases", {})

    def generate_denied_test_cases(self) -> Iterator[TestCase]:
        """Generate all denied pattern test cases.

        Combines path_prefixes with denied_patterns to create comprehensive
        test coverage for patterns that should be denied.

        Yields:
            TestCase: Each generated test case with path, pattern, and expected decision.
        """
        for category, pattern_def in self.denied_patterns.items():
            patterns = pattern_def.get("patterns", [])
            level = pattern_def.get("level", "UNKNOWN")
            description = pattern_def.get("description", category)
            decision = pattern_def.get("decision", "deny")

            # Handle different pattern types
            if level == "FILE_EXTENSION":
                # For extensions, generate: prefix + "/" + filename
                # Only yield if pattern actually matches the path
                filenames = pattern_def.get("filenames", [])
                for prefix in self.path_prefixes:
                    for filename in filenames:
                        path = join_path(prefix, filename)
                        for pattern in patterns:
                            # Filter: only include if pattern matches
                            if pattern_matches(pattern, path):
                                yield TestCase(
                                    path=path,
                                    pattern=pattern,
                                    expected_decision=decision,
                                    level=level,
                                    description=description,
                                    category=category,
                                )

            elif level == "FILE_NAME":
                # For exact file names, only use the pattern as-is
                for pattern in patterns:
                    # FILE_NAME patterns are like ~/.netrc (exact location)
                    yield TestCase(
                        path=pattern,
                        pattern=pattern,
                        expected_decision=decision,
                        level=level,
                        description=description,
                        category=category,
                    )

            elif level == "DIR_GLOB":
                # For dir globs (~/.ssh/*), generate: pattern directory + child files
                parent_dir = pattern_def.get("parent_dir", "")
                child_files = pattern_def.get("child_files", [])
                nested_parent = pattern_def.get("nested_parent", "")

                for pattern in patterns:
                    # Generate children of the directory
                    for child_file in child_files:
                        # Construct path based on pattern structure
                        # e.g., ~/.ssh/* -> ~/.ssh/config
                        if "~" in pattern:
                            # Home directory pattern
                            if nested_parent:
                                # e.g., ~/.config/gcloud/* -> ~/.config/gcloud/credentials.json
                                base = pattern.replace("/*", "")
                                path = f"{base}/{child_file}" if child_file else base
                            else:
                                # e.g., ~/.ssh/* -> ~/.ssh/config
                                base = pattern.replace("/*", "")
                                path = f"{base}/{child_file}" if child_file else base
                        else:
                            # Absolute path pattern
                            base = pattern.replace("/*", "")
                            path = f"{base}/{child_file}" if child_file else base

                        yield TestCase(
                            path=path,
                            pattern=pattern,
                            expected_decision=decision,
                            level=level,
                            description=description,
                            category=category,
                        )

            elif level == "SECURITY_DIRECTORY":
                # For **/xxx/** patterns, generate combinations with prefixes
                filenames = pattern_def.get("filenames", [])
                dir_names = pattern_def.get("dir_names", [])
                child_files = pattern_def.get("child_files", [])

                for pattern in patterns:
                    if "**/" in pattern and "/**" in pattern:
                        # Middle glob pattern like **/secrets/**
                        # Generate: prefix + "/" + dir_name + "/" + child_file
                        for prefix in self.path_prefixes:
                            for dir_name in dir_names:
                                # Match directory itself
                                path = join_path(prefix, dir_name)
                                yield TestCase(
                                    path=path,
                                    pattern=pattern,
                                    expected_decision=decision,
                                    level=level,
                                    description=description,
                                    category=category,
                                )

                                # Match files inside directory
                                for child_file in child_files:
                                    if child_file:  # Skip empty string
                                        child_path = join_path(prefix, dir_name, child_file)
                                        yield TestCase(
                                            path=child_path,
                                            pattern=pattern,
                                            expected_decision=decision,
                                            level=level,
                                            description=description,
                                            category=category,
                                        )

                    else:
                        # Simple glob pattern like *credential*
                        # Match files with pattern in name
                        all_filenames = filenames + child_files
                        for prefix in self.path_prefixes:
                            for filename in all_filenames:
                                if filename:  # Skip empty
                                    path = join_path(prefix, filename)
                                    yield TestCase(
                                        path=path,
                                        pattern=pattern,
                                        expected_decision=decision,
                                        level=level,
                                        description=description,
                                        category=category,
                                    )

    def generate_allowed_test_cases(self) -> Iterator[TestCase]:
        """Generate all allowed pattern test cases.

        Yields:
            TestCase: Each generated test case for allowed patterns.
        """
        for category, pattern_def in self.allowed_patterns.items():
            patterns = pattern_def.get("patterns", [])
            level = pattern_def.get("level", "UNKNOWN")
            description = pattern_def.get("description", category)
            decision = pattern_def.get("decision", "allow")

            # Handle different pattern types
            if level == "FILE_EXTENSION":
                # For extensions, generate: prefix + "/" + filename
                filenames = pattern_def.get("filenames", [])
                for prefix in self.path_prefixes:
                    for filename in filenames:
                        path = join_path(prefix, filename)
                        for pattern in patterns:
                            yield TestCase(
                                path=path,
                                pattern=pattern,
                                expected_decision=decision,
                                level=level,
                                description=description,
                                category=category,
                            )

            elif level == "DIR_GLOB":
                # For dir globs (~/dotfiles/*), generate: pattern directory + child files
                child_files = pattern_def.get("child_files", [])

                for pattern in patterns:
                    for child_file in child_files:
                        base = pattern.replace("/*", "")
                        path = f"{base}/{child_file}" if child_file else base
                        yield TestCase(
                            path=path,
                            pattern=pattern,
                            expected_decision=decision,
                            level=level,
                            description=description,
                            category=category,
                        )

    def generate_negative_test_cases(self) -> Iterator[TestCase]:
        """Generate negative test cases (should NOT match denied patterns).

        Yields:
            TestCase: Each negative test case with expected decision.
        """
        for category, case_def in self.negative_cases.items():
            should_match = case_def.get("should_match", False)
            description = case_def.get("description", category)
            expected_decision = case_def.get("decision", "allow")
            cases = case_def.get("cases", [])

            for path in cases:
                yield TestCase(
                    path=path,
                    pattern="",  # No specific pattern for negative cases
                    expected_decision=expected_decision,
                    level="NEGATIVE",
                    description=description,
                    category=category,
                )

    def generate_all_test_cases(self) -> Iterator[TestCase]:
        """Generate all test cases (denied, allowed, negative).

        Yields:
            TestCase: Every generated test case.
        """
        yield from self.generate_denied_test_cases()
        yield from self.generate_allowed_test_cases()
        yield from self.generate_negative_test_cases()

    def get_test_matrix(self) -> list[dict]:
        """Get the predefined test matrix from fixtures.

        Returns:
            List of test matrix entries with pattern, path, and expected decision.
        """
        return self.data.get("test_matrix", {})
