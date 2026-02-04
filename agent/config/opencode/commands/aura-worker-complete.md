---
description: Signal successful completion to supervisor
agent: aura-worker
---

# Worker: Signal Completion

Signal successful completion to supervisor.

## When to Use

Implementation complete and all checks pass.

## Given/When/Then/Should

**Given** implementation done **when** signaling **then** verify `npm run typecheck && npm run test:unit` pass **should never** report done with failing checks

**Given** validation_checklist **when** completing **then** confirm all items satisfied **should never** complete with unchecked items

**Given** completion **when** reporting **then** update Beads task status **should never** omit Beads update

## Steps

1. Run `npm run typecheck` - must pass
2. Run `npm run test:unit` - must pass
3. **Verify production code path via code inspection:**
   - [ ] Tests import production code (not test-only export)
   - [ ] No dual-export anti-pattern
   - [ ] No TODO placeholders in production code
   - [ ] Service wired with real dependencies (not mocks in production)
4. Verify all validation_checklist items satisfied:
   ```bash
   bd show <task-id>  # Review checklist items
   ```
5. Update Beads task:
   ```bash
   bd update <task-id> --status=done
   bd update <task-id> --notes="Implementation complete. Production code verified working."
   ```
6. Send completion message to supervisor

## Message

```bash
aura agent send supervisor-main TaskComplete --payload '{"type":"TaskComplete","taskId":"<task-id>","result":"success","filesModified":["src/path/file.ts"]}'
```
