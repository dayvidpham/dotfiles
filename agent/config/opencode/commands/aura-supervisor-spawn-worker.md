---
description: Launch worker for a file assignment
agent: aura-supervisor
---

# Supervisor: Spawn Worker

Launch worker for a file assignment.

## When to Use

Implementation tasks ready, spawning workers for parallel execution.

## Given/When/Then/Should

**Given** Implementation tasks **when** spawning **then** use Task tool with `run_in_background: true` **should never** block on worker completion

**Given** multiple workers **when** launching **then** spawn all in layer in parallel **should never** spawn sequentially

**Given** worker assignment **when** providing context **then** include Beads task ID and full context **should never** omit checklist or criteria

## Task Call

```
Task(
  description: "Worker: implement src/path/file.ts",
  prompt: "Beads Task ID: <task-id>\n\nImplement the following file...",
  subagent_type: "worker",
  run_in_background: true
)
```

## Worker Should Update Beads Status

- On start: `bd update <task-id> --status=in_progress`
- On complete: `bd update <task-id> --status=done`
- On blocked: `bd update <task-id> --status=blocked`

## Send Assignment

```bash
aura agent send worker-001 TaskAssignment --payload '{"taskId":"<beads-task-id>","file":"src/path/file.ts"}'
```
