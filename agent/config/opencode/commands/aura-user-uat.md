---
description: User Acceptance Testing with demonstrative examples
agent: aura-architect
---

# User Acceptance Test (UAT)

Conduct UAT at key checkpoints (after plan review, after implementation) to verify alignment with user's vision and MVP requirements.

## Given/When/Then/Should

**Given** reviewers reach consensus **when** conducting UAT **then** show demonstrative examples **should never** ask abstract questions

**Given** UAT questions **when** asking **then** use multiSelect: true with examples **should never** force yes/no answers

**Given** user feedback **when** storing **then** record verbatim with context **should never** paraphrase concerns

**Given** user rejects **when** plan UAT **then** return to proposal phase **should never** proceed to implementation

**Given** user rejects **when** impl UAT **then** return to relevant slice **should never** proceed to landing

## UAT Phases

### Plan UAT (Phase 5)
After 3 reviewers ACCEPT the proposal, verify with user:
- Does the proposed solution match their vision?
- Is the MVP scope appropriate?
- Are the interfaces as expected?

### Implementation UAT (Phase 11)
After code review consensus, verify with user:
- Does the implementation match the plan?
- Do the interfaces work as expected?
- Is the user satisfied with the result?

## Demonstrative Examples

**Critical:** Show concrete examples, not abstract descriptions.

### For Plan UAT
```
"Based on your request for a logout button, we propose:

**Interface:**
- Button in top-right of header, labeled 'Logout'
- On click: clears session, redirects to /login
- Shows brief 'Logging out...' message

**Example user flow:**
1. User clicks 'Logout' button
2. Sees 'Logging out...' for 500ms
3. Session cleared, redirected to /login
4. Cannot access protected pages without re-login

Does this match your vision?"
```

### For Implementation UAT
```
"The logout feature has been implemented:

**What was built:**
- LogoutButton component in src/components/Header/
- clearSession() in src/auth/session.ts
- Route guard updated for post-logout redirect

**Demo:**
[If possible, show actual output or screenshots]

**Test it yourself:**
npm run dev
# Click logout in header

Does this work as expected?"
```

## UAT Survey Template

```
AskUserQuestion(questions: [
  {
    question: "Does this {{plan/implementation}} match your end vision?",
    header: "Vision Match",
    multiSelect: true,
    options: [
      { label: "Yes, exactly", description: "Matches my expectations" },
      { label: "Mostly yes", description: "Minor adjustments needed" },
      { label: "Partially", description: "Some concerns" },
      { label: "No", description: "Doesn't match vision" }
    ]
  },
  {
    question: "Is the MVP scope appropriate?",
    header: "MVP Scope",
    multiSelect: true,
    options: [
      { label: "Right scope", description: "Good balance" },
      { label: "Too minimal", description: "Missing important features" },
      { label: "Too much", description: "Could be simpler" },
      { label: "Wrong focus", description: "Different priorities" }
    ]
  },
  {
    question: "Any specific concerns or changes needed?",
    header: "Concerns",
    multiSelect: true,
    options: [
      { label: "Interface changes", description: "UI/API tweaks" },
      { label: "Behavior changes", description: "Logic adjustments" },
      { label: "Missing feature", description: "Something not included" },
      { label: "No concerns", description: "Looks good" }
    ]
  },
  {
    question: "Do you ACCEPT this {{plan/implementation}} to proceed?",
    header: "Decision",
    multiSelect: false,
    options: [
      { label: "ACCEPT", description: "Proceed to next phase" },
      { label: "REVISE", description: "Needs changes before proceeding" }
    ]
  }
])
```

## Creating UAT Task

```bash
# For Plan UAT (Phase 5)
bd create --labels aura-user-uat,proposal-{{N}}-uat-{{M}} \
  --title "UAT-{{M}}: Plan acceptance for {{feature}}" \
  --description "## Demonstrative Examples
{{examples shown to user}}

## User Responses
### Vision Match
{{verbatim response}}

### MVP Scope
{{verbatim response}}

### Concerns
{{verbatim response}}

### Decision
{{ACCEPT or REVISE with reason}}"

bd dep add {{uat-task-id}} {{last-review-task-id}}
```

```bash
# For Implementation UAT (Phase 11)
bd create --labels aura-impl-uat \
  --title "IMPL-UAT: {{feature}}" \
  --description "## Implementation Demo
{{demos shown to user}}

## User Responses
{{verbatim responses}}

## Decision
{{ACCEPT or REVISE}}"

bd dep add {{impl-uat-task-id}} {{last-code-review-task-id}}
```

## Handling REVISE

If user selects REVISE:
- **Plan UAT:** Return to architect for proposal revision
- **Impl UAT:** Return to relevant slice for implementation fixes

Document the required changes in the task description.
