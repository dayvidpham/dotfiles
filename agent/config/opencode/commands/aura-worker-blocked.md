---
description: Report blocker preventing progress
agent: aura-worker
---

# Worker: Handle Blockers

Report blocker preventing progress.

## When to Use

Cannot proceed due to missing dependency, unclear requirement, or need changes in another file.

## Given/When/Then/Should

**Given** a blocker **when** reporting **then** update Beads task status and document details **should never** guess or work around

**Given** blocker sent **when** waiting **then** wait for supervisor response **should never** continue with incomplete info

## Steps

1. Identify what's blocking (missing type, unclear requirement, file dependency)

2. Update Beads task:
   ```bash
   bd update <task-id> --status=blocked
   bd update <task-id> --notes="Blocked: <reason>. Missing: <dependency or clarification needed>"
   ```

3. Send blocker message to supervisor:
   ```bash
   aura agent send supervisor-main TaskBlocked --payload '{"type":"TaskBlocked","taskId":"<task-id>","reason":"<reason>","missingDependency":"<what is needed>"}'
   ```

4. Wait for unblock notification

## Common Blockers

- Missing type definition from another file
- Unclear requirement in acceptance_criteria
- Need interface defined in dependent file
- Conflicting constraints in validation_checklist
