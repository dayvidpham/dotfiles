# Refactoring Plan: [TITLE]

> **Scope:** [Brief one-liner describing what this refactor touches]  
> **Affected Files:** @path/to/file1.py, @path/to/file2.py  
> **Estimated Complexity:** Low | Medium | High

---

## 1. Motivation

### Problem Statement
[1-2 paragraphs describing the concrete problem this refactor solves. Include:]
- What is broken, brittle, or suboptimal?
- What symptoms or pain points exist?
- Why does this matter now?

### Impact of Inaction
[What happens if we don't do this? Technical debt, bugs, maintenance burden, etc.]

### Success Criteria
- [ ] [Measurable outcome 1]
- [ ] [Measurable outcome 2]
- [ ] [Measurable outcome 3]

---

## 2. Architectural Design

### Current State
[Describe the existing architecture. Include a brief diagram if helpful.]

```
┌──────────────┐      ┌──────────────┐
│  ComponentA  │ ───► │  ComponentB  │
└──────────────┘      └──────────────┘
       │                     │
       ▼                     ▼
[Current data flow / responsibility description]
```

### Proposed State
[Describe the target architecture after refactoring.]

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  ComponentA  │ ───► │  NewAbstract │ ───► │  ComponentB  │
└──────────────┘      └──────────────┘      └──────────────┘
```

### Design Decisions

| Decision | Rationale | Alternatives Considered |
| :--- | :--- | :--- |
| [Choice 1] | [Why this approach] | [What else was considered] |
| [Choice 2] | [Why this approach] | [What else was considered] |

### Invariants to Preserve
- [Invariant 1: e.g., "All existing tests must pass unchanged"]
- [Invariant 2: e.g., "Public API signatures remain stable"]
- [Invariant 3: e.g., "Output file formats unchanged"]

---

## 3. The Core Abstraction: `[NewType]`

[Introduce the new type/abstraction if applicable. Explain its purpose and responsibility.]

**Location:** @path/to/module.py

```python
from dataclasses import dataclass

@dataclass
class NewType:
    """
    [Docstring explaining purpose]
    """
    field_a: TypeA
    field_b: TypeB
```

**Checklist:**
- [ ] Dataclass defined with appropriate fields
- [ ] Type hints complete and accurate
- [ ] Docstring describes purpose and usage
- [ ] Placement in module is logical (near related types)

---

## 4. Summary of Changes

| Component | Change Description | Impact |
| :--- | :--- | :--- |
| **`NewType`** | **New Dataclass** | [What this enables] |
| **`function_a`** | **Signature Update** | [What changes in behavior] |
| **`function_b`** | **Logic Overhaul** | [What changes in behavior] |
| **`module_c`** | **Import Addition** | [Minimal impact] |

---

## 5. Implementation Tasks

### Task A: [Define New Abstraction]

**File:** @path/to/module.py

[Brief description of what to add/change]

```python
# Before (if applicable)
def old_signature(arg1: OldType) -> ReturnType:
    ...

# After
def new_signature(arg1: NewType) -> ReturnType:
    ...
```

**Checklist:**
- [ ] New type/function added at correct location
- [ ] All imports updated
- [ ] Type hints verified
- [ ] Unit test exists or is not required

---

### Task B: [Refactor Driver Function]

**File:** @path/to/driver.py

**Current Problem:** [What's wrong with the current implementation]

**Fix:** [How the new approach solves it]

```python
# Key change: iterate by enum instead of string
for metric, keys in metric_groups.items():
    task = NewType(metric=metric, keys=keys)
    process(task)
```

**Checklist:**
- [ ] Old iteration/grouping logic removed
- [ ] New grouping logic implemented
- [ ] All downstream calls updated
- [ ] Edge cases handled (empty groups, single items)

---

### Task C: [Update Consumer Function]

**File:** @path/to/consumer.py

**Current Problem:** [Specific issue, e.g., "Hardcoded filter for `SomeEnum.Value`"]

**Fix:** [How to fix, e.g., "Use `task.keys` instead of filtering internally"]

```python
def consumer_function(
    task: NewType,  # Updated signature
    filepath: Path,
) -> None:
    # Use task.field_a directly
    for key in task.keys:
        process(key)
```

**Checklist:**
- [ ] Signature updated to accept new type
- [ ] Internal filtering/hardcoding removed
- [ ] Labels/titles use task properties
- [ ] Function docstring updated

---

### Task D: [Update Remaining Consumers]

**Files:** @path/to/file1.py, @path/to/file2.py

Apply the same pattern to all remaining functions that consume the old signature.

| Function | Key Change |
| :--- | :--- |
| `function_1` | Replace `old_arg` with `task.property` |
| `function_2` | Remove internal split logic |
| `function_3` | Update axis labels to `task.display_name` |

**Checklist:**
- [ ] All consumers identified and listed
- [ ] Each consumer updated consistently
- [ ] No orphaned imports of old types
- [ ] Integration test passes

---

## 6. Testing Strategy

### Unit Tests
- [ ] New abstraction has dedicated tests for construction
- [ ] Edge cases: empty collections, single items, missing fields

### Integration Tests
- [ ] End-to-end flow produces expected outputs
- [ ] File outputs match expected naming conventions
- [ ] No regressions in existing functionality

### Manual Verification
- [ ] Run full pipeline with sample data
- [ ] Visually inspect outputs (if applicable)
- [ ] Compare output checksums with baseline (if applicable)

---

## 7. Migration Notes

### Breaking Changes
- [List any breaking changes to public APIs]
- [Or state "None—internal refactor only"]

### Deprecation Path (if applicable)
```python
import warnings

def old_function(*args, **kwargs):
    warnings.warn(
        "old_function is deprecated, use new_function instead",
        DeprecationWarning
    )
    return new_function(*args, **kwargs)
```

### Rollback Plan
[How to revert if issues arise. Usually: "Revert commit [hash]"]

---

## 8. Implementation Checklist (Master)

Copy this section to track overall progress.

- [ ] **Phase 1: Core Abstraction**
  - [ ] Define `NewType` dataclass
  - [ ] Add to module exports
- [ ] **Phase 2: Driver Refactor**
  - [ ] Update iteration logic
  - [ ] Generate tasks instead of raw data
- [ ] **Phase 3: Consumer Updates**
  - [ ] Update `function_a`
  - [ ] Update `function_b`
  - [ ] Update `function_c`
- [ ] **Phase 4: Cleanup**
  - [ ] Remove dead code
  - [ ] Update docstrings
  - [ ] Run linter/formatter
- [ ] **Phase 5: Validation**
  - [ ] All tests pass
  - [ ] Manual verification complete
  - [ ] PR ready for review
