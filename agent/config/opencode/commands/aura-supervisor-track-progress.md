---
description: Monitor worker completion status via Beads and messaging
agent: aura-supervisor
---

# Supervisor: Track Progress

Monitor worker completion status via Beads and messaging.

## When to Use

Workers spawned, monitoring for completions and blockers.

## Given/When/Then/Should

**Given** workers running **when** monitoring **then** check Beads status and inbox **should never** poll aggressively

**Given** worker complete **when** all files for layer done **then** proceed to next layer or commit **should never** commit partial work

**Given** worker blocked **when** handling **then** resolve or reassign immediately **should never** leave workers waiting

## Beads Status Queries

```bash
# Check all implementation tasks
bd list --labels="aura:impl" --status=in_progress

# Check for blocked tasks
bd list --labels="aura:impl" --status=blocked

# Check specific task
bd show <task-id>

# Check completed tasks
bd list --labels="aura:impl" --status=done
```

## Messaging Commands

```bash
# Check for messages
aura agent inbox
aura agent inbox --wait --timeout 30000

# Acknowledge processed messages
aura agent inbox ack <message-id>
```

## Message Types

| Type | Action |
|------|--------|
| TaskComplete | Mark layer progress, check if layer complete |
| TaskBlocked | Review `bd show <id>` for blocker details, resolve or reassign |
| ClarificationRequest | Provide clarification |
