---
description: User Requirements Elicitation (URE) survey - Phase 2 of epoch
agent: aura-architect
---

# User Requirements Elicitation (Phase 2)

Conduct a structured URE survey to gather comprehensive requirements before proposal creation.

## Elicitation Strategy

### 1. End Vision (Plan Backwards)
Ask about the user's ultimate goal and what interfaces they envision:
- What does the final feature look like?
- How will users interact with it?
- What other systems need to integrate?

### 2. MVP Scope (Plan Forward)
Jump to the starting point:
- What's the minimum viable version?
- What can be deferred to later iterations?
- What are the must-have vs nice-to-have features?

### 3. Engineering Dimensions
Ask targeted questions to map the problem space:
- Parallelism: Can operations run concurrently?
- Distribution: Single process or distributed?
- Scale: How many users/requests/items?
- Has-a / Is-a relationships in the domain

### 4. Boundaries and Constraints
- Performance requirements?
- Security considerations?
- Compatibility constraints?
- Error handling expectations?

### 5. Catch-All
Final question to capture anything missed.

## Survey Questions

Use the Question tool to ask:

1. **End Vision**: What is your end vision for this feature? How will users interact with it when complete?
   - Simple UI control
   - Automated process
   - API endpoint
   - Background service

2. **MVP Scope**: What is the minimum viable version (MVP) that would be useful?
   - Core functionality only
   - With confirmation
   - With feedback
   - Full featured

3. **Constraints**: Are there any specific constraints or requirements?
   - Performance critical
   - Security sensitive
   - Backwards compatible
   - No constraints

4. **Other**: Is there anything else we should know about this feature?

## Creating the Elicit Task

After survey completion:

```bash
bd create --labels aura:user:elicit \
  --title "ELICIT: {{feature name}}" \
  --description "## Questions and Responses

### End Vision
Q: What is your end vision...
A: {{user's verbatim selections and any custom input}}

### MVP Scope
Q: What is the minimum viable...
A: {{user's verbatim selections}}

### Constraints
Q: Are there any specific...
A: {{user's verbatim selections}}

### Other
Q: Is there anything else...
A: {{user's verbatim input}}"

# Chain dependency
bd dep add {{elicit-task-id}} {{request-task-id}}
```

## Next Phase

After elicitation, run `/aura-architect-propose-plan` to begin proposal creation (Phase 3).

$ARGUMENTS
