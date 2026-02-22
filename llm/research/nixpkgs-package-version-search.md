---
title: "Nixpkgs Package Version Search Tools — Domain Research"
date: "2026-02-20"
depth: "standard-research"
request: "standalone"
---

## Executive Summary

There are four well-known tools for mapping package versions to Nixpkgs revisions. The space has converged on two data backends (lazamar's Haskell-based index and Jetify's NixHub index) with multiple frontends. For your use case — finding the Nixpkgs revision that contains a specific package version (e.g., cmake 3.10) — **`vic/nix-versions`** is the strongest recommendation: it's a single Go binary CLI that queries both backends, supports version constraints, and can generate flake inputs directly.

---

## Web-Based Tools

### lazamar.co.uk/nix-versions (Lazamar's Nix Package Versions)

The original and most widely referenced tool. A web interface backed by a Haskell server that indexes Nixpkgs history at **5-week intervals**. You select a channel (e.g., `nixos-25.11`), search a package name, and get a table of versions with their Nixpkgs revision hashes.

- **GitHub**: [lazamar/nix-package-versions](https://github.com/lazamar/nix-package-versions) — 410 stars, 318 commits
- **Web**: https://lazamar.co.uk/nix-versions/
- **Language**: Haskell (97%)
- **Limitation**: 5-week sampling means short-lived versions can be missed

### NixHub.io (by Jetify)

A newer, more comprehensive index with **400,000+ package versions** indexed. Built by the Jetify team (makers of Devbox). Web-only — no CLI. Provides Nixpkgs commit hashes and `nix profile install` commands.

- **Web**: https://www.nixhub.io/
- **Maintainer**: Jetify
- **Advantage**: Denser index than lazamar (fewer gaps)
- **Limitation**: Web-only, no CLI, tied to Jetify's infrastructure

### Assessment

| Aspect              | Lazamar                     | NixHub                       |
|---------------------|-----------------------------|------------------------------|
| Index density       | Every ~5 weeks              | Denser, 400k+ versions      |
| Interface           | Web                         | Web                          |
| Open source         | Yes (Haskell)               | No (proprietary service)     |
| Scriptable          | No (scraping needed)        | API available (undocumented) |
| Community trust     | High (long-established)     | High (Jetify backing)        |
| Self-hostable       | Yes (Docker)                | No                           |

**Adoption recommendation:** Use either as a quick lookup. Neither is ideal for scripting or flake integration on its own.

---

## CLI Tools

### vic/nix-versions

A Go CLI that unifies multiple backends (NixHub, lazamar, search.nixos.org) into a single tool. Can search package versions, apply semver constraints, and **generate flake inputs** for version-pinned packages. Also functions as a lightweight devshell/version manager (similar to asdf/mise).

- **GitHub**: [vic/nix-versions](https://github.com/vic/nix-versions) — 36 stars, 127 commits, v1.0.1 (Sep 2025)
- **Language**: Go
- **Install**: `nix run github:vic/nix-versions -- <package>@<version>`
- **Backends**: `--nixhub` (default), `--lazamar`, `--history`, `--system`
- **Key feature**: Generates flake inputs with pinned Nixpkgs revisions

Example usage:
```bash
# Find cmake 3.10 revision
nix run github:vic/nix-versions -- cmake@3.10

# Use lazamar backend instead
nix run github:vic/nix-versions -- --lazamar cmake@3.10

# Generate a flake input
nix run github:vic/nix-versions -- --flake cmake@3.10
```

### jeff-hykin/nix_version_search_cli (nvs)

A JavaScript/Node CLI that also aggregates from multiple sources (history.nix-packages.com, NixHub, lazamar). Interactive prompts for package/version selection. More user-friendly but heavier runtime dependency (Node.js).

- **GitHub**: [jeff-hykin/nix_version_search_cli](https://github.com/jeff-hykin/nix_version_search_cli) — 284 commits
- **Language**: JavaScript (93%)
- **Install**: `nix run github:jeff-hykin/nix_version_search_cli`
- **Key feature**: Interactive mode with guided selection

### Assessment

| Aspect              | vic/nix-versions            | nvs (jeff-hykin)             |
|---------------------|-----------------------------|------------------------------|
| Language            | Go (single binary)          | JavaScript (Node runtime)    |
| Startup speed       | Fast                        | Slower (Node boot)           |
| Backends            | 4 (nixhub, lazamar, etc.)   | 3 (similar set)              |
| Flake generation    | Yes                         | No                           |
| Interactive mode    | No                          | Yes                          |
| Semver constraints  | Yes                         | Basic (`@3.10`)              |
| Maintenance         | Active (v1.0.1, Sep 2025)   | Active                       |

**Adoption recommendation:** Adopt `vic/nix-versions` — fastest, most scriptable, generates flake inputs.

---

## Relevance to Current Project

Your `flake.nix` pins `nixpkgs-stable` to `nixos-25.11` and `nixpkgs-unstable` to `nixos-unstable`. If you need to pin a specific package to an older version (e.g., cmake 3.10 while the rest stays on 25.11), the workflow would be:

1. Use `nix-versions` to find the Nixpkgs revision containing cmake 3.10
2. Add that revision as an additional flake input (e.g., `nixpkgs-cmake310`)
3. Import that specific package from the pinned input

```nix
inputs = {
  nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
  nixpkgs-cmake310.url = "github:NixOS/nixpkgs/<revision-hash>";
  # ...
};
```

---

## Summary

| Tool                    | Recommendation | Rationale                                                |
|-------------------------|---------------|----------------------------------------------------------|
| vic/nix-versions (CLI)  | Adopt         | Single binary, multi-backend, flake generation, scriptable |
| lazamar.co.uk (web)     | Adopt         | Quick visual lookups, self-hostable, long-established     |
| NixHub.io (web)         | Adopt         | Denser index, good for when lazamar misses a version      |
| nvs / jeff-hykin (CLI)  | Defer         | Interactive is nice but Node dependency and no flake gen   |

## Key Takeaways

### Adopt
- **vic/nix-versions** as the primary CLI tool for finding Nixpkgs revisions by package version
- **lazamar.co.uk/nix-versions** as a quick web lookup when you just need to eyeball it
- **NixHub.io** as a fallback when lazamar's 5-week sampling misses a version

### Adapt
- Use `nix-versions --flake` output to generate additional pinned inputs in your `flake.nix`

### Defer
- jeff-hykin/nix_version_search_cli — nice interactive UX but unnecessary if you have `nix-versions`

### Skip
- Rolling your own indexer — the existing tools cover this well
