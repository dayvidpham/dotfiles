# OpenCode Security Filter

ACP-compliant security proxy for OpenCode file access control.

## Installation

```bash
uv tool install .
```

## Usage

### Check a single path

```bash
opencode-security-filter --check ~/.ssh/id_rsa
```

### Run as proxy

```bash
opencode-security-filter
```

The proxy reads JSON-RPC messages from stdin and writes responses to stdout.

## Architecture

Uses specificity-based precedence for security decisions:

1. FILE_NAME (exact path) - highest priority
2. FILE_EXTENSION (*.pub, *.env)
3. DIRECTORY (exact directory)
4. SECURITY_DIRECTORY (**/secrets/**, *credentials*) - security-critical patterns
5. PERMISSIONS (file mode bits)
6. DIR_GLOB (~/.ssh/*, ~/dotfiles/*)
7. GLOB_MIDDLE (other glob patterns) - lowest priority

At each level, DENY supersedes ALLOW.

## License

MIT
