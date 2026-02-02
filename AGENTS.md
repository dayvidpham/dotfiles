# Aura Protocol - Agent Instructions

## Implementation Log

### 2026-02-02: Migrated to fw_cfg credentials

Replaced insecure 9p file share with microvm.credentialFiles for secrets:
- Host: Credentials passed via `microvm.credentialFiles` (uses fw_cfg on QEMU)
- Host: `sops.templates."openclaw.json"` renders config to `/run/secrets/rendered/openclaw.json`
- Host: `openclaw-secrets` group allows microvm user to read rendered template
- Guest: Gateway service uses `LoadCredential = "openclaw-config"` with `%d` (credentials directory)
- Guest: `OPENCLAW_CONFIG_PATH=%d/openclaw-config` points to credential
- Security: No 9p secrets share, no polling loops, no TOCTOU vulnerabilities
- Security: fw_cfg injects secret at boot, not via shared filesystem

## Constraints

**Given** shared resources **when** modifying **then** use atomic operations with timeouts **should never** check-then-act

**Given** external input **when** parsing **then** validate with schemas **should never** trust raw JSON or cast types

**Given** parallel work **when** assigning files **then** ensure each file has exactly one owner with atomic commits **should never** have multiple workers on same file

**Given** a feature request **when** writing requirements **then** use Given/When/Then/Should,Should Not format **should never** write vague criteria

**Given** a class with dependencies **when** designing **then** inject all deps (including clocks) **should never** hard-code

**Given** runtime events **when** logging **then** use structured JSONL with context **should never** log secrets or use `console.log`

**Given** status/type fields **when** defining **then** use PascalCase enums **should never** use strings

**Given** code changes **when** committing **then** typecheck and tests must pass **should never** allow optional CI

**Given** task is implemented **when** you are about to commit **then** you **should** use `git agent-commit -m ...`, **should never** use `git commit -m ...`

**Given** you want to execute Beads, **when** you are about to call `bd <bead_command>...</bead_command> ...` **then** you **should never** `cd <repo_root>...</repo_root> && bd <bead_command>...</bead_command> ...`, instead you **should** always just call `bd <bead_command>...<bead_command>`

## Behavior

**When uncertain, ask.** If requirements are ambiguous, scope is unclear, or multiple valid approaches exist—stop and ask before proceeding. Wrong assumptions compound.

**For coding standards, documentation standards, and Beads naming conventions, see [CONSTRAINTS.md](CONSTRAINTS.md).**

### Self-Validation Model

Before claiming completion:

1. **Plan backwards:** *"What does success look like, and what does it require?"*
   - Define the end state, then identify each prerequisite working backwards
   - Missing prerequisites reveal missing work
   - **Note:** Work backwards from the final API to define architecture—but implementation can be incremental. Define all public interfaces first; use mocks/stubs until full implementation is needed.

2. **Invert the problem:** *"What would make this fail?"*
   - List failure modes (edge cases, race conditions, unhandled errors)
   - Verify each is addressed or explicitly out of scope
   - If you can't falsify your own work, it's not ready

### Completion Checklist

- [ ] **Validated** — `nix flake check --no-build 2>&1` passes, new behavior doesn't break the flake
- [ ] **Meets requirement** — Re-read the original user request, the user requirements ellicatations, and the user acceptence tests (UATs); does the code actually do what the user wanted?

## Principles

- Per-task atomic commits (no DAG tracking)
- Single worktree, file ownership prevents conflicts
- Dual audit trail (Git + Aura transcripts)

## Agent Roles

| Role | Responsibility |
|------|----------------|
| Architect | Specs, tradeoffs, validation checklist, BDD criteria |
| Reviewer | End-user alignment, implementation gaps, MVP impact |
| Supervisor | Layer-cake task decomposition, then vertical-slice task allocation, merge order, commits |
| Worker | Single file implementation in isolated worktree |

**Consensus:** All 3 reviewers must ACCEPT. Revisions loop until consensus.

## Beads-Unified Workflow

All work flows through Beads tasks:

```
REQUEST_PLAN (user prompt)
    ↓
PROPOSE_PLAN (architect drafts full plan)
    ↓
REVIEW_1, REVIEW_2, REVIEW_3 (parallel, vote ACCEPT/REVISE)
    ↓ (loop if any REVISE)
REVISION_N (architect addresses feedback)
    ↓ (back to reviews)
RATIFIED_PLAN (consensus reached, all sign off)
    ↓
IMPLEMENTATION_PLAN (supervisor placeholder)
    ↓
LAYER 1: [SLICE-A-1, SLICE-B-1, ...] (parallel, no deps)
    ↓
LAYER 2: [SLICE-A-2, SLICE-B-2, ...] (parallel, deps on L1)
    ↓ ...

LAYER N: [SLICE-A-N, SLICE-B-N, ...] (parallel, deps on LN-1)
    ↓ ...
IMPLEMENTATION_DONE
    ↓
REVIEW_IMPLEMENTATION: 3x Opus agents each with same review criteria
    ↓
USER_ACCEPTANCE_TEST
    ↓
REVISIONS ?
    ↓
ACCEPT
```

### When Reviewing

Check **end-user alignment**, not technical specializations:

- Who are the end-users?
- What would end-users want?
- How would this affect them?
- Are there implementation gaps?
- Does MVP scope make sense?
- Is validation checklist complete?

### When Working

**Supervisor** creates implementation tasks with:
- Topologically sorted layers (parallel within layer)
- Key details from ratified plan
- Tradeoffs relevant to each file
- Link back to RATIFIED_PLAN task
- Validation checklist items per task
- BDD acceptance criteria (Given/When/Then/Should Not)
- Explicit file ownership boundaries
- NEVER implements code themselves, ALWAYS starts parallel subagent to implement

**Worker** implements by:
- Working in isolated worktree
- Following interface contracts from ratified plan
- Satisfying validation checklist items
- Meeting BDD acceptance criteria
- Running `nix eval ... 2>&1`
- Running `nix build --no-link .#< relevant target here > 2>&1`
- Running `nix flake check --no-build 2>&1 ...`
- Signaling TaskComplete or TaskBlocked

## Commit Format

```
feat|fix|docs|refactor(scope): description

Files: file1.ts
Requirement: REQ-X.Y

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

## Agent Commits

Agents use `git agent-commit` instead of `git commit` for signed commits with a passwordless GPG key:

```bash
git agent-commit -m "feat(scope): description"
```

**Setup** (one-time, via `aura install`):
1. Create passwordless GPG key for agents
2. Run `aura install --signing-key <KEY_ID>` or accept prompt during install

The alias uses a dedicated signing key that doesn't require passphrase unlocking, enabling non-interactive agent commits.

## Worktree & Beads Integration

**IMPORTANT FOR AGENTS:** This is a git worktree with `.beads` directory redirected to the parent repository.

When using beads commands:
- **DO**: Run `bd` commands from anywhere in this worktree directory tree
- **DO NOT**: `cd` to the parent directory just to access beads
- **DO NOT**: Check if `.beads` exists locally—the redirect is transparent
- **DO**: Use beads to track multi-session work, dependencies, and collaboration

The redirect is intentional and allows all worktree clones to share a single beads database. Commands like:
```bash
bd ready              # Works from any path in the worktree
bd show <issue-id>    # Works from any path in the worktree
bd update <id> ...    # Works from any path in the worktree
bd close <id> ...     # Works from any path in the worktree
```

**Exception**: If you absolutely need to inspect parent-directory files (which should be rare), use absolute paths: `/home/minttea/dev/david-agent-data-leverage/.beads/...` instead of `cd ../..`.

## Commands

```bash
# Validation (run both - eval only checks syntax, build catches runtime issues)
nix eval --impure .#nixosConfigurations.<host>.config.<path> --apply 'x: "ok"'  # Syntax check
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link   # Actual build

# Examples:
nix eval --impure .#nixosConfigurations.desktop.config.microvm.vms.openclaw-vm --apply 'x: "ok"'
nix build .#nixosConfigurations.desktop.config.system.build.toplevel --no-link

# Flake check (MUST pass before commit)
nix flake check --no-build 2>&1

# Beads commands work from ANY worktree (redirect is transparent)
bd <command>
```

## References

- `.claude/commands/aura:*.md` - Agent role definitions (source of truth)

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **COMMIT AND PUSH** - This is MANDATORY:
   ```bash
   git add <files>
   git agent-commit -m "feat(scope): description"  # Uses passwordless GPG key
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Use `git agent-commit` (not `git commit`) for signed commits without passphrase prompts
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
