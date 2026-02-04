# OpenCode Security Plugin - Architect Prompt

## User Request (Verbatim)

Create a security plugin for OpenCode that filters sensitive file access from AI agent tool calls. The solution should:

1. Prevent agents from reading sensitive files (credentials, secrets, SSH keys, etc.)
2. Use file permission checks (deny files without "others" read bit)
3. Allow trusted paths to bypass restrictions (~/dotfiles, ~/codebases)
4. Integrate with OpenCode's hook system
5. Generate OpenCode config with pattern expansion for commands

## User Requirements Elicitation (URE) - Decisions Made

### Q1: Sensitive File Patterns to Block
User selected ALL of these:
- `*.env`, `*.env.*` - Environment files
- `~/.ssh/*` - SSH keys (but .pub files ALLOWED)
- `~/.gnupg/*` - GPG keys
- `~/.aws/*` - AWS credentials
- `~/.config/gcloud/*` - Google Cloud credentials
- `~/.azure/*` - Azure credentials
- `~/.netrc` - FTP/HTTP credentials
- `**/secrets/**` - Any 'secrets' directory
- `**/.secrets/**` - Hidden secrets directories
- `*credentials*` - Files with 'credentials' in name
- `*password*` - Files with 'password' in name

User clarifications:
- `.pem` files should be ALLOWED (not blocked)
- `.pub` files should be ALLOWED (public keys are fine)
- **File permission-based filtering**: If a file has no "others" read bit (e.g., mode 600, 400, 640), it should be denied

### Q2: Trusted Directories (Always Allowed)
- `~/dotfiles` - User's dotfiles repo
- `~/codebases` - User's code projects

### Q3: Implementation Approach
User chose: **Hybrid approach** with runtime checks integrated into OpenCode hooks

### Q4: Runtime Hook Strategy
User chose: **Shell function injection** initially, but this was discovered to NOT WORK because OpenCode's bash tool uses non-interactive shell that doesn't source .bashrc/.zshrc.

**Revised approach**: Use OpenCode's native plugin/hook system.

## Research Findings

### OpenCode Hook System

OpenCode supports pre-tool-call hooks via plugins:

```typescript
// From packages/plugin/src/index.ts
interface Hooks {
  "tool.execute.before"?: (input, output) => Promise<void>  // Pre-execution
  "tool.execute.after"?: (input, output) => Promise<void>   // Post-execution
  "permission.ask"?: (input, output) => Promise<void>       // Permission evaluation
}
```

Plugin locations:
- Local: `.opencode/plugins/` (project) or `~/.config/opencode/plugins/` (global)
- npm packages: Configured in `opencode.json` under `"plugin": [...]`

### OpenCode Wildcard Pattern Matching

From `packages/opencode/src/util/wildcard.ts`:

```typescript
export function match(str: string, pattern: string) {
  let escaped = pattern
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*/g, ".*")
    .replace(/\?/g, ".")

  // "ls *" matches both "ls" and "ls -la"
  if (escaped.endsWith(" .*")) {
    escaped = escaped.slice(0, -3) + "( .*)?"
  }
  return new RegExp("^" + escaped + "$", "s").test(str)
}
```

Key insight: `"cat *"` matches `cat` and `cat file.txt` but NOT `cat | grep` or `cat && echo`.

**Pattern expansion requirement**: Each allowed command needs these variants:
- `tool` - bare command
- `tool *` - command with arguments
- `tool |*` - command piped
- `tool &&*` - command chained with &&
- `tool ||*` - command chained with ||

### OpenCode Bash Tool - Does NOT Source RC Files

From `packages/opencode/src/tool/bash.ts`:
```typescript
const proc = spawn(params.command, {
  shell,
  cwd,
  env: { ...process.env },
  stdio: ["ignore", "pipe", "pipe"],
  detached: process.platform !== "win32",
})
```

Uses non-interactive shell - `.bashrc`/`.zshrc` are NOT sourced. Shell function injection WILL NOT WORK.

### cc-filter Reference Implementation

cc-filter (github.com/wissem/cc-filter) is a Go-based security tool that:
- Uses Claude Code's hook system to intercept tool calls
- Cannot be bypassed by the AI (operates at hook level)
- Uses regex patterns for secret detection
- Supports block, redact, and mask operations

Key architecture:
```
Tool Call → Hook (JSON) → cc-filter → Decision (allow/deny/redact)
```

### Security Concern Identified

Blanket-allowing commands like `cat *: allow` is a security hole because `*` matches any arguments, including `cat ~/.ssh/id_rsa`.

**Solution**: Keep read commands as `"ask"` in static config, use `permission.ask` hook to dynamically evaluate based on:
1. Trusted path? → Allow
2. Restrictive file permissions? → Deny
3. Blocked pattern match? → Deny
4. Otherwise → Ask

## Architecture Requirements

### 1. OpenCode Plugin (`~/dotfiles/agent/opencode-plugin/`)

```
opencode-plugin/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts           # Plugin entry, exports hooks
│   └── lib/
│       ├── config.ts      # Trusted paths, blocked patterns
│       ├── checker.ts     # Permission checking logic
│       └── parser.ts      # Extract file paths from commands
```

### 2. Plugin Logic (permission.ask hook)

```typescript
export default {
  "permission.ask": async (input, output) => {
    // Only intercept bash and read tools
    if (input.permission !== "bash" && input.permission !== "read") return;
    
    const filePaths = extractFilePaths(input.pattern);
    
    for (const filePath of filePaths) {
      // 1. Check trusted paths (bypass all other checks)
      if (isTrustedPath(filePath)) continue;
      
      // 2. Check file permissions (deny if others can't read)
      if (await hasRestrictivePermissions(filePath)) {
        output.status = "deny";
        return;
      }
      
      // 3. Check blocked patterns
      if (matchesBlockedPattern(filePath)) {
        output.status = "deny";
        return;
      }
    }
    
    // If we get here, allow or keep as "ask"
  }
}
```

### 3. Config Generator (Nix or standalone script)

Generate OpenCode config with pattern expansion:

```typescript
const READ_COMMANDS = ["cat", "head", "tail", "grep", "rg", ...];

function generateBashPermissions() {
  const permissions: Record<string, string> = { "*": "ask" };
  
  for (const cmd of READ_COMMANDS) {
    // These are "ask" - plugin hook will evaluate dynamically
    permissions[cmd] = "ask";
    permissions[`${cmd} *`] = "ask";
    permissions[`${cmd} |*`] = "ask";
    permissions[`${cmd} &&*`] = "ask";
    permissions[`${cmd} ||*`] = "ask";
  }
  
  // Git commands (safe, no file reads)
  for (const gitCmd of ["git status", "git diff", "git log", ...]) {
    permissions[gitCmd] = "allow";
    permissions[`${gitCmd} *`] = "allow";
    // etc.
  }
  
  return permissions;
}
```

### 4. File Permission Check

```typescript
import { stat } from "node:fs/promises";

async function hasRestrictivePermissions(filePath: string): Promise<boolean> {
  try {
    const stats = await stat(filePath);
    const mode = stats.mode;
    const othersRead = (mode & 0o004) !== 0;  // Check "others" read bit
    return !othersRead;  // Restrictive if others can't read
  } catch {
    return false;  // File doesn't exist, let OpenCode handle
  }
}
```

## Deliverables

1. **OpenCode Plugin** - TypeScript plugin using `permission.ask` hook
2. **Config Generator** - Script to generate `opencode.json` with pattern expansion
3. **Nix Integration** - Home-manager module to install plugin and generate config
4. **Documentation** - README with usage instructions

## Validation Checklist

- [ ] Plugin intercepts bash and read tool calls
- [ ] Trusted paths (~/dotfiles, ~/codebases) always allowed
- [ ] Files with mode 600/400 are denied
- [ ] Blocked patterns (*.env, ~/.ssh/*, etc.) are denied
- [ ] .pub and .pem files are NOT blocked
- [ ] Pattern expansion covers: cmd, cmd *, cmd |*, cmd &&*, cmd ||*
- [ ] Plugin works as global (~/.config/opencode/plugins/) and local (.opencode/plugins/)
- [ ] Config generator produces valid opencode.json
- [ ] Tests cover all security scenarios

## BDD Acceptance Criteria

**Scenario 1: Trusted Path Access**
- Given: Agent requests `cat ~/dotfiles/flake.nix`
- When: permission.ask hook evaluates
- Then: Allow (trusted path)
- Should Not: Check blocked patterns or file permissions

**Scenario 2: Restrictive File Permissions**
- Given: File `~/.config/secrets/api.key` has mode 600
- When: Agent requests `cat ~/.config/secrets/api.key`
- Then: Deny (others read bit not set)
- Should Not: Allow despite file not matching blocked patterns

**Scenario 3: Blocked Pattern Match**
- Given: Agent requests `grep password .env`
- When: permission.ask hook evaluates
- Then: Deny (matches `*.env` and `*password*` patterns)

**Scenario 4: Public Key Allowed**
- Given: Agent requests `cat ~/.ssh/id_ed25519.pub`
- When: permission.ask hook evaluates
- Then: Allow (public keys explicitly allowed)

**Scenario 5: Pattern Expansion**
- Given: Config has `cat |*: ask`
- When: Agent requests `cat /etc/passwd | head`
- Then: Hook is invoked to evaluate `/etc/passwd`

---

## Instructions for Architect

1. Use `/aura:user:elicit` skill to confirm requirements if needed
2. Create a comprehensive proposal covering all components
3. Define clear interfaces between plugin, config generator, and Nix module
4. Ensure security-first design (deny by default, explicit allow)
5. Plan for testability (unit tests for checker, integration tests for plugin)
