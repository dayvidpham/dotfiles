---
description: Provide structured feedback on RFC or code review
---

# Leave Feedback

Provide structured feedback on RFC or code review.

## Format

```markdown
## Feedback: {RFC-number or PR-number}

**Reviewer:** {your-role}
**Date:** {timestamp}
**Vote:** {APPROVE | APPROVE_WITH_COMMENTS | REQUEST_CHANGES | REJECT}

### Comments

#### {BLOCKING | MAJOR | MINOR}: {Title}
**Location:** {file:line or RFC section}
**Issue:** {description}
**Suggestion:** {how to fix}

### Summary
{Overall assessment}
```

## Steps

1. Ask what to review (RFC, code changes, PR)
2. Read content thoroughly
3. Apply relevant checklists from `CONSTRAINTS.md`
4. Format feedback using the template
5. Be specific and actionable
