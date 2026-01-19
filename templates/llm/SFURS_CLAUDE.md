# Build Instructions & Workflow

To maintain token efficiency and avoid cluttering the context window, always redirect build output to a log file and use `tail` to see the summary.

## Build Alias (`kk`)
To build the project, use `tee` to capture the log and `tail` for the CLI output.

```bash
kk 2>&1 | tee build/build.log | tail -n 20
```

If the build fails and the error is not visible in the summary, inspect the full log at `build/build.log` using `grep` or `read_file`.

The definition of `kk` is here at @~/dev/sfurs-software-nixified/scripts/kk:

```bash
#!/usr/bin/env bash

cmake -S . -B build -DCMAKE_CXX_COMPILER="clang++" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=On -DGRSIM_PATH="$(which grSim)" -DUSE_SYSTEM_BEHAVIOR_TREE_CPP=On -DUSE_SYSTEM_BOOST_UT=On -DCMAKE_PREFIX_PATH="$(realpath ../../prefix)" -DPYTHON_PACKAGES_PATH="$(realpath ../../prefix/python)" -GNinja && ninja -C build -j16
```

## Clean Build Alias (`ggs`)

Use the `ggs` alias similarly:

```bash
ggs 2>&1 | tee build/build.log | tail -n 20
```

```bash
#!/usr/bin/env bash

cmake -S . -B build -DCMAKE_CXX_COMPILER="clang++" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=On -DGRSIM_PATH="$(which grSim)" -DUSE_SYSTEM_BEHAVIOR_TREE_CPP=On -DUSE_SYSTEM_BOOST_UT=On -DCMAKE_PREFIX_PATH="$(realpath ../../prefix)" -DPYTHON_PACKAGES_PATH="$(realpath ../../prefix/python)" -GNinja && ninja -C build -j16
```

## Clean Build Alias (`ggs`)

Use the `ggs` alias similarly:

```bash
ggs 2>&1 | tail -n 20
```

The definition of `ggs` is here at @~/dev/sfurs-software-nixified/scripts/ggs:

```bash
#!/usr/bin/env bash

SCRIPTS_DIR="${0%/*}"
kk="$SCRIPTS_DIR/kk"

printf "Initiating clean build ...\n------------------------\n"

if [[ -d ./build ]]; then
    printf "\t./build/ exists, wiping ... "
    rm -rf build
    printf "done!\n\n"
fi

printf "\tRunning '%s' to build project ...\n\t------------------------\n" "$kk"
source "$kk"
printf "\t... done!\n\n"

echo "... done!"
```

## Building and Testing After Code Changes

After making code changes, always build the project and run the tests:

```bash
kk 2>&1 | tee build/build.log | tail -n 20
```

Once the build completes successfully, run the test suite:

```bash
./build/test/unit_tests
```

To run a specific test suite, use the `-t` flag:

```bash
# Run only the ClaimRole_Test suite
./build/test/unit_tests -t "ClaimRole_Test"

# Run only the KickTo test suite
./build/test/unit_tests -t "KickTo"

# Run all coordination-related tests
./build/test/unit_tests -t "ClaimRole_Test|SetState_Test|WaitForRole_Test"
```

Tests use the boost-ut framework with BDD syntax (feature/scenario/given/when/then).

# Refactoring Summary: Play-Scoped Tagged Enums for Multi-Robot Coordination

## Overview
This refactor introduces a type-safe, play-scoped coordination system. It replaces the previous `Common`-only enum approach with a tagged enum system where Roles, States, and SubPlays are scoped to a specific `PlaySelection`. This allows defining play-specific behaviors (e.g., `BallRecovery::Roles::Interceptor`) while maintaining compatibility with `Common` behaviors.

## Key Changes

### 1. PlaySelection & PlayContext
`PlaySelection` (FSM) and `PlayContext` (Coordination) are now aligned. `PlayContext` supports negative values (e.g., `Common = -1`) to represent universal behaviors.

**File:** `src/agent/fsm/PlaySelection.h`
```cpp
enum PlaySelection {
    BT_TEST = -1,
    NOT_IN_PLAY = 0,
    BUILD_UP = 1,
    // ...
    BALL_RECOVERY = 10
};
```

**File:** `src/agent/bt/coordination/CoordinationTypes.h`
```cpp
namespace Coordination {
    struct PlayContext {
        int8_t value;
        enum Values : int8_t {
            Common = -1,
            NotInPlay = 0,
            BallRecovery = 10,
            // ...
        };
        // ...
    };
}
```

### 2. Tagged Enums (Role, State, SubPlay)
The `TagEnum` struct serves as the base for `Role`, `State`, and `SubPlay`. It stores a `PlayContext` tag and a `uint8_t` value. Strict equality checks ensure safety.

**File:** `src/agent/bt/coordination/CoordinationTypes.h`
```cpp
struct TagEnum {
    PlayContext tag;
    Enum value;
    
    // Strict equality: tag AND value must match
    constexpr bool operator==(const TagEnum& other) const {
        return tag == other.tag && value == other.value;
    }
    
    constexpr bool isContext(PlayContext ctx) const {
        return tag == ctx || tag == PlayContext::Common;
    }
};

struct Role : TagEnum { using TagEnum::TagEnum; };
struct State : TagEnum { using TagEnum::TagEnum; };
struct SubPlay : TagEnum { using TagEnum::TagEnum; };
```

### 3. Play-Specific Namespaces
Roles and States are now defined in play-specific namespaces, with `Common` being available universally.

**File:** `src/agent/bt/coordination/CoordinationTypes.h`
```cpp
namespace BallRecovery {
    namespace Roles {
        constexpr Role Interceptor = Role(PlayContext::BallRecovery, 1);
        constexpr Role Presser = Role(PlayContext::BallRecovery, 2);
    }
    namespace States {
        constexpr State Intercepting = State(PlayContext::BallRecovery, 31);
    }
}
```

### 4. Coordinator Validation
The `Coordinator` now tracks the current `PlayContext` and warns if a robot tries to claim a role or set a state that doesn't match the active play (unless it's a `Common` role/state).

**File:** `src/agent/bt/coordination/Coordinator.cpp`
```cpp
void Coordinator::claimRole(int robotId, Role role) {
    if (registeredRobots.contains(robotId)) {
        if (!role.isCommon() && role.tag != playTag) {
            qWarning() << "[Coordinator] Robot" << robotId
                      << "claiming role with tag" << role.tag.str()
                      << "but current play context is" << playTag.str();
        }
        robotRoles[robotId] = role;
    }
}
```

### 5. Updated BT Nodes (XML Interface)
Coordination nodes (`ClaimRole`, `SetState`, etc.) now accept explicit `tag` and `value` parameters instead of a single `role_id`. They use `NodeUtils` for robust error handling.

**File:** `src/agent/bt/nodes/coordination/ClaimRoleNode.h`
```cpp
static PortsList providedPorts() {
    return {
        BT::InputPort<int>("robot_id"),
        BT::InputPort<std::shared_ptr<ICoordinator>>("coordinator"),
        BT::InputPort<int8_t>("role_tag"),    // PlayContext
        BT::InputPort<uint8_t>("role_value")  // Value
    };
}
```

### 6. BehaviorTreeManager Integration
The `BehaviorTreeManager` updates the `Coordinator`'s context whenever the play changes.

**File:** `src/agent/bt/BehaviorTreeManager.cpp`
```cpp
void BehaviorTreeManager::tick(const PlaySelection& playSelection) {
    // ...
    if (effectivePlaySelection != currentPlaySelection) {
        coordinator_->setPlayContext(Coordination::PlayContext(static_cast<int8_t>(effectivePlaySelection)));
        assignBehaviors(effectivePlaySelection);
        currentPlaySelection = effectivePlaySelection;
    }
    // ...
}
```

## XML Usage Example

Old syntax (deprecated):
```xml
<ClaimRole robot_id="0" role_id="10" />
```

New syntax:
```xml
<!-- Common Role (BallCarrier) -->
<ClaimRole robot_id="0" role_tag="-1" role_value="10" />

<!-- BallRecovery Role (Interceptor) -->
<ClaimRole robot_id="0" role_tag="10" role_value="1" />
```

---

## Planning Refactoring and Feature Changes

When planning or implementing significant refactoring changes or new features (especially test suites), always start by creating a comprehensive plan document using the template at `@TEMPLATE_REFACTOR.md`, following the style and patterns shown in `@EXAMPLE_CLAUDE.md`.

### Why Use the Refactor Template?

The template ensures:

1. **Problem Clarity**: Articulate what is broken, brittle, or suboptimal
2. **Architectural Analysis**: Document current state vs. proposed state with diagrams
3. **Design Decisions**: Explain trade-offs and rationale for each choice
4. **Implementation Roadmap**: Break work into concrete, reviewable tasks with checklists
5. **Test Strategy**: Plan tests and success criteria upfront
6. **Reviewability**: Clear documentation helps reviewers understand intent and catch issues early

### Using the Template

1. Review `@EXAMPLE_CLAUDE.md` for documentation style and depth expectations
2. Copy `TEMPLATE_REFACTOR.md` content
3. Fill in sections with your specific context:
   - **Motivation**: What problem does this solve? Why now?
   - **Architectural Design**: Current vs. proposed architecture with diagrams
   - **Core Abstraction**: New types, functions, or abstractions
   - **Implementation Tasks**: Step-by-step breakdown with detailed checklists
   - **Testing Strategy**: Unit, integration, manual verification plans
4. Save as `refactor_<feature_name>.md` in the project root
5. Reference this document in your PR description

### Example Refactoring Plans

- `refactor_xml_registration.md` - BehaviorTree XML error handling tests
  - Demonstrates comprehensive test suite planning using the template
  - Shows structured approach to error scenario testing
  - Includes dependency injection patterns for testability
  - Organized implementation tasks with clear success criteria

### Template Sections Quick Reference

| Section | Purpose |
| :--- | :--- |
| **Motivation** | Define problem, impact, success criteria |
| **Architectural Design** | Current vs. proposed state, design decisions, invariants |
| **Core Abstraction** | New types, functions, or interfaces (with examples) |
| **Summary of Changes** | Table of affected components and impact |
| **Implementation Tasks** | Detailed breakdown with numbered steps and checklists |
| **Testing Strategy** | Unit, integration, and manual verification |
| **Migration Notes** | Breaking changes, deprecation paths, rollback plans |
| **Implementation Checklist** | Master checklist for tracking progress across phases |

### Documentation Standards (from @EXAMPLE_CLAUDE.md)

- Use clear, concrete examples with before/after code
- Include diagrams for architectural changes
- Document design decisions with rationale and alternatives considered
- Organize implementation tasks with verification steps
- Provide rollback/recovery procedures
- Use tables for component changes and test coverage

---
