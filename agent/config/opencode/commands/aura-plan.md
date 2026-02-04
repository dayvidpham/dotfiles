---
description: Orchestrate full Aura planning workflow
agent: aura-architect
---

# Aura Plan

Orchestrate the full Beads/RFC planning workflow.

## When to Use

Starting any non-trivial implementation task.

## Steps

### 1. Create REQUEST_PLAN

Capture the user's request as a Beads task:

```bash
bd create --type=task \
  --labels="aura:request-plan" \
  --title="Request: <summary of user request>" \
  --description="<full user prompt verbatim>"
```

Store the returned task ID for subsequent steps.

### 2. Requirements Elicitation

Run `/aura-user-elicit` to gather comprehensive requirements before proposal.

### 3. Architect Proposes

Create PROPOSE_PLAN with problem space, engineering tradeoffs, MVP milestone, public interfaces, validation checklist, and BDD acceptance criteria.

Run `/aura-architect-propose-plan` when ready.

### 4. Request Review

Spawn 3 reviewers in parallel:

```
@aura-reviewer Review PROPOSE_PLAN task <propose-plan-id>. Apply end-user alignment criteria.
@aura-reviewer Review PROPOSE_PLAN task <propose-plan-id>. Apply end-user alignment criteria.
@aura-reviewer Review PROPOSE_PLAN task <propose-plan-id>. Apply end-user alignment criteria.
```

### 5. Handle Votes

Check comments on PROPOSE_PLAN:

```bash
bd comments <propose-plan-id>
```

- **All 3 ACCEPT**: Proceed to step 6
- **Any REVISE**: Architect creates REVISION task, re-spawn reviewers

### 6. User Approval

After all 3 reviewers vote ACCEPT, present plan summary to user for approval.

### 7. Ratify and Handoff

On user approval:
1. Run `/aura-architect-ratify` to create RATIFIED_PLAN
2. Run `/aura-architect-handoff` to spawn supervisor

## State Machine

```
IDLE -> REQUEST_PLAN -> ELICIT -> PROPOSE_PLAN -> REVIEW (loop) -> USER_APPROVAL -> RATIFIED_PLAN -> IMPLEMENTATION
```

$ARGUMENTS
