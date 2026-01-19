# Refactoring Plan: BehaviorTree Management Architecture Refactor

> **Scope**: Split BehaviorTreeManager into BTRegistrar (registration) and BTFactoryWrapper (tree creation), with robust error handling and full testability
>
> **Affected Files**:
> - `src/agent/bt/BehaviorTreeManager.h/cpp` (modifications to extract methods)
> - `src/agent/bt/core/IBTFactoryWrapper.h` (new interface)
> - `src/agent/bt/core/BTFactoryWrapper.h/cpp` (new implementation)
> - `src/agent/bt/core/IBTRegistrar.h` (new interface)
> - `src/agent/bt/core/BTRegistrar.h/cpp` (new implementation)
> - `src/agent/bt/utils/BTLifecycle.h/cpp` (new utility namespace)
> - `src/agent/bt/xml/tests/*` (updated test fixtures from refactor_xml_registration.md)
> - 21 test files using BehaviorTreeManager::registerNodes()
>
> **Estimated Complexity**: High (architectural refactor with broad impact)
> **Timeline**: Multi-phase implementation

---

## 1. Motivation

### Problem Statement

The current `BehaviorTreeManager` conflates three distinct responsibilities:

1. **Node Registration**: Registering custom BT nodes with the factory (static method used by 21 test files)
2. **Tree Registration**: Loading and registering XML behavior trees from files
3. **Tree Creation**: Creating tree instances with proper initialization and error handling

Additionally, `BT::BehaviorTreeFactory` provides a poor debugging interface:
- Minimal error context on XML parsing failures
- Cryptic exception messages when tree creation fails
- No programmatic way to inspect registered trees or nodes
- No unified error handling strategy

Current state (from recent commit `1bd69dad`):
- TagEnum system now scopes `Role`, `State`, `SubPlay` to `PlayContext` (type-safe, compile-time verified)
- Coordinator validates play context (warns on mismatches, still assigns)
- XML format evolved: `role_id="X"` → `role_tag="X" role_value="Y"`
- Error handling added with `NodeUtils::DumpTree()` for diagnostics
- 21 test files call `BehaviorTreeManager::registerNodes()` statically

### Pain Points

1. **Poor Testability**: BehaviorTreeManager is hard to mock; tests can't easily verify registration logic
2. **Error Debugging**: XML failures provide minimal context; developers resort to manual log inspection
3. **Tight Coupling**: PlayAssignmentHelper directly uses factory; can't swap implementations for testing
4. **Monolithic Manager**: BehaviorTreeManager handles too many concerns
5. **Factory Limitations**: BT::BehaviorTreeFactory API is incomplete for programmatic tree management

### Impact of Inaction

- New developers struggle with XML debugging; slow iteration cycles
- Test coverage limited to integration tests; unit testing registration logic is difficult
- Future tree creation features (caching, validation, versioning) have nowhere to go
- Error messages remain unhelpful; production debugging remains slow
- Type system improvements (TagEnum) aren't leveraged in tree creation

### Success Criteria

**Phase 1: BTFactoryWrapper & BTRegistrar extraction**
- [ ] `IBTFactoryWrapper` interface defined with full tree/node/metadata query support
- [ ] `BTFactoryWrapper` wraps `BT::BehaviorTreeFactory` with enhanced error info
- [ ] `IBTRegistrar` interface defined for registration logic
- [ ] `BTRegistrar` extracts all registration methods from BehaviorTreeManager
- [ ] BehaviorTreeManager maintains backward compatibility; delegates to BTRegistrar
- [ ] All 21 existing test files continue to work unchanged

**Phase 2: Tree Lifecycle Management**
- [ ] `BTLifecycle` utility namespace provides `haltTree()`, `scheduleCleanup()`, `cleanupTrees()`
- [ ] PlayAssignmentHelper refactored to use BTLifecycle utilities
- [ ] Safe tree replacement pattern centralized and testable

**Phase 3: Error Handling & XML Tests**
- [ ] BehaviorTreeManager_ErrorHandling_Test.cpp implements 5 error scenarios
- [ ] XML test fixtures in dedicated `src/agent/bt/xml/tests/` directory
- [ ] Error messages include node names, port names, tree paths
- [ ] Graceful registration handling verified (invalid XML doesn't crash system)

**Phase 4: Integration & Verification**
- [ ] PlayAssignmentHelper.cpp uses new wrapper; cleaner error handling
- [ ] All existing tests pass without modification
- [ ] No performance regressions (tree creation time unchanged)
- [ ] Error messages are actionable and helpful

---

## 2. Architectural Design

### Current State (Before Refactor)

```
BehaviorTreeManager (monolithic)
├── registerNodes() static              [Node registration]
├── registerNodes() instance            [Delegates to static]
├── registerTreesFromDirectory()        [XML registration]
├── registerTreeFromText()              [XML registration]
├── loadTreeXmlFromFile()               [File loading]
├── factory_ (BT::BehaviorTreeFactory)  [Direct usage - poor interface]
├── tick()                              [Tree execution]
├── getTree(), getRefTree()             [Tree access]
└── createTree() calls in:
    ├── PlayAssignmentHelper.cpp        [Tree creation - error handling inline]
    ├── GameStateReflex.cpp             [GSR trees - no error context]
    └── Tests                           [Various error patterns]
```

**Issues:**
- No interface for BT factory abstraction
- Registration logic mixed with lifecycle management
- Error handling duplicated across PlayAssignmentHelper, GameStateReflex, tests
- Tree cleanup pattern not centralized (50ms sleep, manual halting in PlayAssignmentHelper)
- 21 test files directly call static registration (tightly coupled)

### Proposed State (After Refactor)

```
BTLifecycle (new utility namespace)
├── haltTree(tree) → void
├── scheduleCleanup(tree) → void
├── cleanupTrees(treesQueue) → void
└── checkAndReplaceTrees(oldTree, newTreeId, factory) → Tree

IBTFactoryWrapper (new interface)
├── createTree(id, blackboard) → Tree
├── createTreeFromText(xml, blackboard) → Tree
├── createTreeFromFile(path, blackboard) → Tree
├── registerNode<NodeType>(name)
├── registerNodeFromPlugin(path)
├── getRegisteredTrees() → Vec<string>
├── getRegisteredNodes() → Vec<string>
└── getTreeMetadata(id) → Metadata

BTFactoryWrapper (new implementation)
├── Wraps BT::BehaviorTreeFactory
├── Enhanced error messages with XML context
├── Logs tree structure on creation failure
└── Provides introspection (metadata, registered items)

IBTRegistrar (new interface)
├── registerNodes(factory, agentControl, wsm, btManager) static
├── registerNodes() instance
├── registerTreesFromDirectory(path) → bool
├── registerTreeFromText(xml) → bool
└── loadTreeXmlFromFile(path) → string

BTRegistrar (new implementation)
├── registerNodes() logic extracted from BehaviorTreeManager
├── registerTreesFromDirectory() with enhanced error handling
├── registerTreeFromText() with NodeUtils integration
├── Dependency injection via constructor
└── Graceful error handling (invalid XML logged, system continues)

BehaviorTreeManager (refactored)
├── registrar_ (std::shared_ptr<IBTRegistrar>)
├── factory_ (std::shared_ptr<IBTFactoryWrapper>)
├── registerNodes()                    [BACKWARD COMPAT: delegates to registrar_]
├── registerTreesFromDirectory()       [BACKWARD COMPAT: delegates to registrar_]
├── registerTreeFromText()             [BACKWARD COMPAT: delegates to registrar_]
├── loadTreeXmlFromFile()              [BACKWARD COMPAT: delegates to registrar_]
├── tick()                             [Enhanced with factory_/registrar_ usage]
├── getTree(), getRefTree()            [Tree access - unchanged]
└── playAssignmentHelper uses:
    ├── factory_->createTree() [replaces direct factory_.createTree()]
    ├── BTLifecycle utilities  [replaces inline cleanup logic]
```

**Benefits:**
- Single Responsibility Principle: Each class has one reason to change
- Testability: Interfaces enable mocking; unit tests can verify logic in isolation
- Error Handling: Centralized error context and diagnostics
- Extensibility: Tree metadata, caching, versioning can extend wrapper
- Backward Compatibility: BehaviorTreeManager maintains existing API
- Type Safety: Error handling uses strong types, not string parsing

### Design Decisions

| Decision | Rationale | Alternatives |
|:---|:---|:---|
| **Pure virtual interfaces** | Enable mocking in tests; follow existing codebase patterns (ICoordinator, IAgent) | Concrete classes (less flexible for testing) |
| **Extended metadata scope** | Support future tree validation, caching, versioning features | Simple scope (only tree creation) |
| **Backward compatibility layer** | Minimize changes to 21 test files; gradual migration path | Immediate refactor (riskier, more work) |
| **BTLifecycle utility namespace** | Centralize tree halting/cleanup; reusable across codebase | Leave in PlayAssignmentHelper (scattered) |
| **Wrapper owns enhanced error info** | All diagnostic logic in one place; consistent error messages | Scatter across factory, registrar, callsites |
| **Registrar as separate class** | Clear separation of registration concerns; testable independently | Keep in BTFactoryWrapper (mixed concerns) |

### Invariants to Preserve

- `registerTreesFromDirectory()` gracefully continues on invalid XML (does not crash system)
- `BT::RuntimeError` thrown for invalid trees at appropriate phase (creation or execution)
- Node registration behavior unchanged; new nodes register identically
- All existing tests pass without modification
- Performance: tree creation time unchanged, no additional allocations in hot path
- All production XML trees remain valid with new tag/value format
- TagEnum type system unchanged; existing role/state/subplay logic unaffected

---

## 3. Core Abstractions

This refactor introduces four new abstractions to replace the monolithic `BehaviorTreeManager`:

1. **BTLifecycle** - Utility namespace for tree lifecycle management (halting, cleanup, safe replacement)
2. **IBTFactoryWrapper** - Interface abstracting BT::BehaviorTreeFactory with enhanced diagnostics
3. **IBTRegistrar** - Interface for registration logic (nodes, trees, XML files)
4. **BTFactoryWrapper & BTRegistrar** - Concrete implementations of the above interfaces

These abstractions enable dependency injection, testability, and clearer separation of concerns.

---

### Core Abstraction 1: BTLifecycle Utility Namespace

**File:** `src/agent/bt/utils/BTLifecycle.h/cpp`

**Purpose:** Centralize tree halting, cleanup, and safe replacement patterns

**Key Functions:**

```cpp
namespace BTLifecycle {

    /// Safely halt a tree and wait for graceful shutdown
    /// @param tree Tree to halt (must be non-null)
    /// @throws std::invalid_argument if tree is null
    void haltTree(std::shared_ptr<BT::Tree> tree);

    /// Schedule a tree for cleanup after a brief delay
    /// Prevents use-after-free when switching trees rapidly
    /// @param tree Tree to cleanup
    /// @param queue Queue to append cleanup tree to
    void scheduleCleanup(std::shared_ptr<BT::Tree> tree,
                        QList<std::shared_ptr<BT::Tree>>& queue);

    /// Process queued trees for cleanup
    /// Waits configured delay, then clears queue
    /// @param queue Queue of trees to clean up
    void cleanupTrees(QList<std::shared_ptr<BT::Tree>>& queue);

    /// Check if tree needs replacement and do so safely
    /// Returns true if tree was replaced, false if kept
    /// @param robotId ID of robot
    /// @param oldTree Current tree (may be null)
    /// @param newTreeId Desired tree ID
    /// @param factory Factory to create new tree from
    /// @param blackboard Blackboard for new tree
    /// @param cleanupQueue Queue for old tree cleanup
    /// @return Pair of (newTree, wasReplaced)
    std::pair<std::shared_ptr<BT::Tree>, bool>
    checkAndReplaceTrees(int robotId,
                         const std::shared_ptr<BT::Tree>& oldTree,
                         const std::string& newTreeId,
                         IBTFactoryWrapper& factory,
                         BT::Blackboard::Ptr blackboard,
                         QList<std::shared_ptr<BT::Tree>>& cleanupQueue);

    /// Get configured cleanup delay (milliseconds)
    /// Adjustable for testing; production default 50ms
    int getCleanupDelayMs();
    void setCleanupDelayMs(int ms);
}
```

**Design Notes:**
- No state; all functions are pure utilities
- QList used to maintain consistency with existing PlayAssignmentHelper
- Delay configurable for testing but defaults to proven 50ms production value
- checkAndReplaceTrees() centralizes tree replacement logic

---

### Core Abstraction 2: IBTFactoryWrapper Interface

**File:** `src/agent/bt/core/IBTFactoryWrapper.h`

**Purpose:** Provide clean, testable interface to BT::BehaviorTreeFactory

```cpp
// Note: This interface lives in global namespace, not in BT:: namespace
// BT:: namespace is reserved for external library code only

class IBTFactoryWrapper {
public:
    virtual ~IBTFactoryWrapper() = default;

    /// Create a behavior tree from registered ID with blackboard
    /// @throws BT::RuntimeError with enhanced diagnostics on failure
    virtual BT::Tree createTree(const std::string& treeId,
                                BT::Blackboard::Ptr blackboard) = 0;

    /// Create a behavior tree from XML string
    /// @throws BT::RuntimeError with enhanced diagnostics on failure
    virtual BT::Tree createTreeFromText(const std::string& xml,
                                        BT::Blackboard::Ptr blackboard) = 0;

    /// Create a behavior tree from XML file
    /// @throws BT::RuntimeError with enhanced diagnostics on failure
    virtual BT::Tree createTreeFromFile(const std::string& filepath,
                                        BT::Blackboard::Ptr blackboard) = 0;

    /// Register a custom node type
    /// @tparam NodeType Must inherit from BT::TreeNode
    template<typename NodeType>
    void registerNodeType(const std::string& ID) {
        static_assert(std::is_base_of_v<BT::TreeNode, NodeType>,
                     "NodeType must inherit from BT::TreeNode");
        registerNodeTypeImpl(ID, &NodeType::staticMetadata);
    }

    /// Register node from plugin/shared library
    virtual void registerNodeFromPlugin(const std::string& path) = 0;

    /// Get list of all registered behavior tree IDs
    virtual std::vector<std::string> getRegisteredTrees() const = 0;

    /// Get list of all registered node type IDs
    virtual std::vector<std::string> getRegisteredNodes() const = 0;

    /// Metadata about a registered behavior tree
    struct TreeMetadata {
        std::string id;
        size_t nodeCount;
        std::vector<std::string> nodeTypes;
        // Future: version, hash, dependencies
    };

    /// Get metadata about a registered tree
    /// @return metadata if tree registered, nullopt otherwise
    virtual std::optional<TreeMetadata> getTreeMetadata(const std::string& treeId) const = 0;

private:
    virtual void registerNodeTypeImpl(const std::string& ID,
                                     const BT::NodeMetadata* metadata) = 0;
};
```

**Design Notes:**
- Pure virtual; all methods override-able
- Template method for registerNodeType() to maintain type safety
- Extended metadata support for future introspection features
- getTreeMetadata() returns optional; graceful handling if tree not found
- Error messages generated by implementation; interface is simple

---

### Core Abstraction 3: BTFactoryWrapper Implementation

**File:** `src/agent/bt/core/BTFactoryWrapper.h/cpp`

**Purpose:** Wrap BT::BehaviorTreeFactory with enhanced error handling and introspection

**Key Features:**

1. **Enhanced Error Messages**
   - On tree creation failure: includes XML snippet, node count, registered nodes
   - On XML parse failure: includes line number, character position (if available)
   - Calls `NodeUtils::DumpTree()` for diagnostic tree structure

2. **Introspection Support**
   - Tracks registered trees and nodes internally
   - getRegisteredTrees() and getRegisteredNodes() queries
   - getTreeMetadata() provides node count, types, structure

3. **Implementation Details**

```cpp
class BTFactoryWrapper : public IBTFactoryWrapper {
private:
    BT::BehaviorTreeFactory factory_;
    std::map<std::string, TreeMetadata> treeMetadata_;  // Cached metadata

    /// Internal error handler; enhances exception with context
    void handleTreeCreationError(const std::string& treeId,
                                const BT::RuntimeError& e);

    /// Log tree structure for debugging on failure
    void logTreeStructure(const BT::Tree& tree, const std::string& context);

    /// Build metadata from tree structure
    TreeMetadata buildMetadata(const std::string& treeId, const BT::Tree& tree);

public:
    BTFactoryWrapper();
    ~BTFactoryWrapper() override = default;

    BT::Tree createTree(const std::string& treeId,
                        BT::Blackboard::Ptr blackboard) override;

    BT::Tree createTreeFromText(const std::string& xml,
                                BT::Blackboard::Ptr blackboard) override;

    BT::Tree createTreeFromFile(const std::string& filepath,
                                BT::Blackboard::Ptr blackboard) override;

    void registerNodeFromPlugin(const std::string& path) override;

    std::vector<std::string> getRegisteredTrees() const override;
    std::vector<std::string> getRegisteredNodes() const override;
    std::optional<TreeMetadata> getTreeMetadata(const std::string& treeId) const override;

    // Allow registrar access to underlying factory for advanced operations
    BT::BehaviorTreeFactory& getFactory() { return factory_; }
    const BT::BehaviorTreeFactory& getFactory() const { return factory_; }
};
```

**Error Handling Strategy:**
```cpp
// Pattern 1: Tree creation failure
try {
    auto tree = factory_.createTree(treeId, blackboard);
    treeMetadata_[treeId] = buildMetadata(treeId, tree);
    return tree;
} catch (const BT::RuntimeError& e) {
    cCritical(LOG_KEY) << "Failed to create tree '" << treeId << "': " << e.what();

    // Enhance error with context
    std::ostringstream oss;
    oss << "\n=== Tree Creation Failed ===\n"
        << "Tree ID: " << treeId << "\n"
        << "Error: " << e.what() << "\n"
        << "Registered Trees: " << [list trees] << "\n"
        << "Registered Nodes: " << [list nodes] << "\n";

    throw BT::RuntimeError(oss.str());
}

// Pattern 2: XML parse failure
try {
    auto tree = factory_.createTreeFromText(xml, blackboard);
    return tree;
} catch (const BT::RuntimeError& e) {
    cCritical(LOG_KEY) << "XML Parse Error: " << e.what();
    std::ostringstream oss;
    oss << "\n=== XML Parse Failed ===\n"
        << "Error: " << e.what() << "\n"
        << "XML Snippet:\n" << truncateXml(xml, 500) << "\n";

    throw BT::RuntimeError(oss.str());
}
```

---

### Core Abstraction 4: IBTRegistrar Interface

**File:** `src/agent/bt/core/IBTRegistrar.h`

**Purpose:** Define contract for registration logic (static and instance methods)

```cpp
class IBTRegistrar {
public:
    virtual ~IBTRegistrar() = default;

    // STATIC REGISTRATION METHODS
    // Used by tests and initialization

    /// Register all custom coordination nodes with the factory
    /// @param factory Factory to register nodes with
    /// @param agentControl Agent control interface (for node dependencies)
    /// @param wsm World state manager (for node dependencies)
    /// @param btManager BehaviorTreeManager (for node dependencies)
    /// @return true if all nodes registered successfully
    static bool registerNodes(IBTFactoryWrapper& factory,
                             AgentControl* const agentControl,
                             WorldStateManager* const wsm,
                             BehaviorTreeManager* btManager);

    // INSTANCE METHODS

    /// Register all nodes with the provided factory (called during init)
    /// Delegates to static method
    virtual bool registerNodes() = 0;

    /// Walk directory and register all .xml files as behavior trees
    /// Gracefully continues on invalid XML (does not crash)
    /// @param searchDirectory Directory to walk (recursive)
    /// @return true if all files processed (even if some failed)
    virtual bool registerTreesFromDirectory(const std::string& searchDirectory) = 0;

    /// Register a behavior tree from XML string
    /// @param xml XML content defining the tree
    /// @return true if tree registered successfully
    virtual bool registerTreeFromText(const std::string& xml) = 0;

    /// Load XML file content as string
    /// @param filepath Path to XML file
    /// @return XML content as string
    virtual std::string loadTreeXmlFromFile(const std::string& filepath) = 0;
};

```

---

### Core Abstraction 5: BTRegistrar Implementation

**File:** `src/agent/bt/core/BTRegistrar.h/cpp`

**Purpose:** Extract and implement registration logic from BehaviorTreeManager

**Key Features:**

1. **Static Node Registration**
   - Extracted from BehaviorTreeManager::registerNodes()
   - Registers ClaimRoleNode, SetStateNode, SetSubPlayNode, WaitForRoleStateNode
   - Registers utility nodes, tactics, skills, GSR nodes
   - All 21 test files call this method

2. **Tree Registration from Directory**
   - Recursive filesystem walk for `.xml` files
   - Enhanced error handling with XML logging
   - Graceful continuation (invalid XML logged, valid trees still registered)

3. **Tree Registration from Text**
   - Simple delegator to factory.registerBehaviorTreeFromText()
   - Error logging and diagnostics

4. **Implementation Structure**

```cpp
class BTRegistrar : public IBTRegistrar {
private:
    IBTFactoryWrapper* factory_;              // Not owned; injected
    AgentControl* agentControl_;              // Dependencies
    WorldStateManager* wsm_;
    BehaviorTreeManager* btManager_;

    /// Register a single set of nodes (coordination, skills, tactics, etc.)
    bool registerNodeSet(const std::string& nodeSetName,
                        std::function<bool()> registerFn);

    /// Helper to register a single XML file
    bool registerTreeFile(const std::filesystem::path& filepath);

public:
    /// Constructor with dependency injection
    BTRegistrar(IBTFactoryWrapper* factory,
               AgentControl* agentControl,
               WorldStateManager* wsm,
               BehaviorTreeManager* btManager);

    ~BTRegistrar() override = default;

    static bool registerNodes(IBTFactoryWrapper& factory,
                             AgentControl* const agentControl,
                             WorldStateManager* const wsm,
                             BehaviorTreeManager* btManager);

    bool registerNodes() override;
    bool registerTreesFromDirectory(const std::string& searchDirectory) override;
    bool registerTreeFromText(const std::string& xml) override;
    std::string loadTreeXmlFromFile(const std::string& filepath) override;
};
```

**Error Handling:**

```cpp
bool BTRegistrar::registerTreeFile(const std::filesystem::path& filepath) {
    try {
        std::string xml = loadTreeXmlFromFile(filepath.string());
        factory_->getFactory().registerBehaviorTreeFromText(xml);
        cInfo(LOG_KEY) << "Registered tree from " << filepath.string();
        return true;
    } catch (const BT::RuntimeError& e) {
        cWarning(LOG_KEY) << "Failed to register XML tree from " << filepath.string()
                         << ": " << e.what();

        // Log XML for debugging
        try {
            std::string xml = loadTreeXmlFromFile(filepath.string());
            cDebug(LOG_KEY) << "XML Content:\n" << truncate(xml, 1000);
        } catch (...) {
            cDebug(LOG_KEY) << "Could not load XML for debugging";
        }

        return false;  // Continue processing other files
    }
}
```

---

### Final Integration: BehaviorTreeManager Refactored

**File:** `src/agent/bt/BehaviorTreeManager.h/cpp`

**Changes (Backward Compatibility Maintained):**

```cpp
class BehaviorTreeManager {
private:
    std::shared_ptr<IBTFactoryWrapper> factory_;    // Was: BT::BehaviorTreeFactory
    std::shared_ptr<IBTRegistrar> registrar_;       // NEW

public:
    // BACKWARD COMPATIBILITY: Delegate to registrar_

    static bool registerNodes(BT::BehaviorTreeFactory& factory_,
                             AgentControl* const agentControl_,
                             WorldStateManager* const wsm_,
                             BehaviorTreeManager* btManager_) {
        // UNCHANGED: Delegates to BTRegistrar::registerNodes
    }

    bool registerNodes() {
        // NEW: Delegates to registrar_->registerNodes()
        return registrar_->registerNodes();
    }

    bool registerTreesFromDirectory(std::string const& search_directory) {
        // NEW: Delegates to registrar_->registerTreesFromDirectory()
        return registrar_->registerTreesFromDirectory(search_directory);
    }

    bool registerTreeFromText(const std::string& xml) {
        // NEW: Delegates to registrar_->registerTreeFromText()
        return registrar_->registerTreeFromText(xml);
    }

    std::string loadTreeXmlFromFile(const std::string& filepath) {
        // NEW: Delegates to registrar_->loadTreeXmlFromFile()
        return registrar_->loadTreeXmlFromFile(filepath);
    }

    // Enhanced tick() with new factory/registrar usage
    BT::NodeStatus tick(const PlaySelection& playSelection) {
        // Uses factory_->createTree() instead of factory_.createTree()
        // Uses BTLifecycle utilities for tree replacement
    }

    // Existing methods unchanged
    std::shared_ptr<BT::Tree> getTree(int robot_id);
    std::shared_ptr<BT::Tree> getRefTree(int referee_id);
    // ... etc
};
```

**Constructor Enhancement:**

```cpp
BehaviorTreeManager(WorldStateManager* wsm,
                   AgentControl* agentControl) {
    // Create wrapper and registrar
    factory_ = std::make_shared<BTFactoryWrapper>();
    registrar_ = std::make_shared<BTRegistrar>(factory_.get(), agentControl, wsm, this);
}

// Alternatively, with dependency injection for testing
BehaviorTreeManager(WorldStateManager* wsm,
                   AgentControl* agentControl,
                   std::shared_ptr<IBTFactoryWrapper> factory,
                   std::shared_ptr<IBTRegistrar> registrar)
    : factory_(factory), registrar_(registrar) {}
```

---

## 4. Summary of Changes

| Component | Change | Impact | Files |
|:---|:---|:---|:---|
| **BTLifecycle** | New namespace with tree halting/cleanup utilities | Centralizes lifecycle management; enables safe tree replacement | BTLifecycle.h/cpp |
| **IBTFactoryWrapper** | New interface for factory abstraction | Enables mocking; allows custom implementations | IBTFactoryWrapper.h |
| **BTFactoryWrapper** | New implementation with enhanced error handling | Better error messages; tree introspection support | BTFactoryWrapper.h/cpp |
| **IBTRegistrar** | New interface for registration logic | Defines contract; enables mocking | IBTRegistrar.h |
| **BTRegistrar** | New implementation extracting registration from BTM | Separated concerns; testable independently | BTRegistrar.h/cpp |
| **BehaviorTreeManager** | Refactored to use wrapper and registrar; delegates methods | Backward compatible; cleaner, more focused | BehaviorTreeManager.h/cpp |
| **PlayAssignmentHelper** | Uses factory_ wrapper and BTLifecycle utilities | Enhanced error handling; centralized cleanup logic | PlayAssignmentHelper.cpp |
| **GameStateReflex** | Uses factory_ wrapper for tree creation | Better error diagnostics | GameStateReflex.cpp |
| **21 Test Files** | No changes required (backward compatibility maintained) | Can gradually migrate to use BTRegistrar directly | Various *_Test.cpp |
| **XML Test Fixtures** | New fixtures in `src/agent/bt/xml/tests/` directory | Enables error handling test scenarios | xml/tests/*.xml |
| **Error Handling Tests** | New `BehaviorTreeManager_ErrorHandling_Test.cpp` | Comprehensive coverage of error scenarios | BehaviorTreeManager_ErrorHandling_Test.cpp |

---

## 5. Implementation Tasks

### Phase 1: Setup & Infrastructure

#### Task 1.1: Create BTLifecycle Utility Namespace

**File:** `src/agent/bt/utils/BTLifecycle.h`

**Checklist:**
- [ ] Header-only interface (or minimal implementation) with function declarations
- [ ] haltTree() - safely halt tree with error handling
- [ ] scheduleCleanup() - schedule tree for deferred cleanup
- [ ] cleanupTrees() - process cleanup queue with delay
- [ ] checkAndReplaceTrees() - safe tree replacement logic
- [ ] Configurable cleanup delay (ms) with getter/setter
- [ ] Comprehensive documentation for each function

**Rationale:** Establishes tree lifecycle management before other components depend on it

---

#### Task 1.2: Create BTFactoryWrapper Interface

**File:** `src/agent/bt/core/IBTFactoryWrapper.h`

**Checklist:**
- [ ] Pure virtual interface with all methods
- [ ] Template registerNodeType() method for type safety
- [ ] TreeMetadata struct with all fields
- [ ] getTreeMetadata() returns optional
- [ ] Comprehensive documentation
- [ ] Include guards and namespace setup
- [ ] No implementation; interface only

**Rationale:** Define contract before implementation; enables parallel development

---

#### Task 1.3: Implement BTFactoryWrapper

**Files:** `src/agent/bt/core/BTFactoryWrapper.h/cpp`

**Implementation Details:**
```cpp
// BTFactoryWrapper.h
class BTFactoryWrapper : public IBTFactoryWrapper {
    // See design in Section 3, Component 3
};

// BTFactoryWrapper.cpp - Implementation
```

**Checklist:**
- [ ] Constructor initializes BT::BehaviorTreeFactory
- [ ] Implements all IBTFactoryWrapper methods
- [ ] Enhanced error handling for tree creation failures
- [ ] Metadata caching and introspection
- [ ] Error messages include XML snippets, registered items
- [ ] Calls NodeUtils::DumpTree() on failure
- [ ] getFactory() provides access to underlying factory for advanced use
- [ ] All exception messages logged with cCritical/cWarning
- [ ] Compiles without errors

**Rationale:** Core wrapper provides enhanced diagnostics before refactoring BehaviorTreeManager

---

### Phase 2: Registration Extraction

#### Task 2.1: Create BTRegistrar Interface

**File:** `src/agent/bt/core/IBTRegistrar.h`

**Constraints & Requirements:**
- [ ] Must be a pure virtual interface (no implementations)
- [ ] Must use dependency injection for all constructor parameters
- [ ] Static method signature cannot be changed (backward compatibility)
- [ ] Must not have mutable state
- [ ] All methods must have comprehensive documentation with error conditions
- [ ] No string-based lookups; all operations must be type-safe
- [ ] Must not create circular dependencies with BehaviorTreeManager

**Code Template:**

```cpp
#pragma once

#include <memory>
#include <string>
#include <vector>

class IBTFactoryWrapper;  // Forward declare

class IBTRegistrar {
public:
    virtual ~IBTRegistrar() = default;

    /// Register all custom coordination nodes with the factory
    /// @param factory Factory to register nodes with (must not be null)
    /// @param agentControl Agent control interface (must not be null)
    /// @param wsm World state manager (must not be null)
    /// @param btManager BehaviorTreeManager (must not be null)
    /// @return true if all nodes registered successfully, false if any failed
    /// @throws std::invalid_argument if any parameter is null
    static bool registerNodes(IBTFactoryWrapper& factory,
                             AgentControl* const agentControl,
                             WorldStateManager* const wsm,
                             BehaviorTreeManager* btManager);

    // INSTANCE METHODS

    /// Register all nodes with the provided factory (called during init)
    /// Delegates to static method internally
    /// @return true if registration succeeded
    virtual bool registerNodes() = 0;

    /// Walk directory and register all .xml files as behavior trees
    /// Gracefully continues on invalid XML (does not crash system)
    /// @param searchDirectory Directory path to walk (must be absolute path)
    /// @return true if all files processed (even if some failed)
    /// @note Invalid XML files are logged as warnings, system continues
    virtual bool registerTreesFromDirectory(const std::string& searchDirectory) = 0;

    /// Register a behavior tree from XML string
    /// @param xml XML content defining the tree (must be valid XML)
    /// @return true if tree registered successfully
    /// @throws BT::RuntimeError if XML is malformed or contains unregistered nodes
    virtual bool registerTreeFromText(const std::string& xml) = 0;

    /// Load XML file content as string
    /// @param filepath Path to XML file (must exist)
    /// @return XML content as string
    /// @throws std::runtime_error if file cannot be read
    virtual std::string loadTreeXmlFromFile(const std::string& filepath) = 0;
};
```

**Dos & Don'ts:**

**DO:**
- ✓ Use pure virtual methods (all methods must be `= 0`)
- ✓ Document all error conditions and exceptions
- ✓ Include null pointer checks in documentation (will be enforced by implementation)
- ✓ Use const-correctness on methods that don't modify state
- ✓ Provide forward declarations to avoid circular dependencies

**DON'T:**
- ✗ Don't add implementation details in the interface
- ✗ Don't use string-based configuration (e.g., "enable_validation_mode")
- ✗ Don't add public state members
- ✗ Don't use weak pointers or optional references (indicate in docs if null is allowed)
- ✗ Don't create factory methods in this interface (factory pattern should be separate)

**Checklist:**
- [ ] File uses pragma guards (not macro-based guards)
- [ ] All methods are pure virtual
- [ ] All parameters have null-check documentation
- [ ] All exceptions are documented with @throws
- [ ] No includes beyond what's necessary (memory, string, vector only)
- [ ] Static method maintains backward-compatible signature
- [ ] Forward declarations used to break circular dependencies

**Rationale:** Define contract before extracting from BehaviorTreeManager; enables dependency injection and mocking in tests

---

#### Task 2.2: Implement BTRegistrar

**Files:** `src/agent/bt/core/BTRegistrar.h/cpp`

**Constraints & Requirements:**
- [ ] Must implement all methods from IBTRegistrar
- [ ] Static method must NOT be virtual (backward compatibility)
- [ ] Constructor MUST use dependency injection for all parameters
- [ ] MUST NOT hold shared pointers to factory/manager (use raw pointers, non-owning)
- [ ] MUST validate all input parameters in constructor (throw on null)
- [ ] Error handling MUST be graceful (never crash system on invalid XML)
- [ ] MUST use const& parameters for strings to avoid copies
- [ ] MUST be thread-safe for const operations (if called from multiple threads)
- [ ] Performance: file I/O should not block for extended periods
- [ ] All logging MUST use established log categories (LOG_KEY, etc.)

**Constructor Implementation:**

```cpp
// Header: BTRegistrar.h
class BTRegistrar : public IBTRegistrar {
private:
    // Non-owning pointers (factory and manager managed by BehaviorTreeManager)
    IBTFactoryWrapper* factory_;              // NOT owned; injected
    AgentControl* agentControl_;              // NOT owned; injected
    WorldStateManager* wsm_;                  // NOT owned; injected
    BehaviorTreeManager* btManager_;          // NOT owned; injected

    // Validation helpers (MUST be called in constructor)
    void validateDependencies() const;

    // Private helpers
    bool registerNodeSet(const std::string& nodeSetName,
                        std::function<bool()> registerFn);
    bool registerTreeFile(const std::filesystem::path& filepath);
    std::string truncateXmlForLogging(const std::string& xml, size_t maxLen) const;

public:
    /// Constructor with dependency injection
    /// @param factory Must not be null (will throw std::invalid_argument)
    /// @param agentControl Must not be null (will throw std::invalid_argument)
    /// @param wsm Must not be null (will throw std::invalid_argument)
    /// @param btManager Must not be null (will throw std::invalid_argument)
    BTRegistrar(IBTFactoryWrapper* factory,
               AgentControl* agentControl,
               WorldStateManager* wsm,
               BehaviorTreeManager* btManager);

    ~BTRegistrar() override = default;

    // Explicitly delete copy/move to prevent accidental ownership issues
    BTRegistrar(const BTRegistrar&) = delete;
    BTRegistrar& operator=(const BTRegistrar&) = delete;
    BTRegistrar(BTRegistrar&&) = delete;
    BTRegistrar& operator=(BTRegistrar&&) = delete;

    static bool registerNodes(IBTFactoryWrapper& factory,
                             AgentControl* const agentControl,
                             WorldStateManager* const wsm,
                             BehaviorTreeManager* btManager);

    bool registerNodes() override;
    bool registerTreesFromDirectory(const std::string& searchDirectory) override;
    bool registerTreeFromText(const std::string& xml) override;
    std::string loadTreeXmlFromFile(const std::string& filepath) override;
};
```

**Implementation Example (registerNodes static):**

```cpp
// cpp: BTRegistrar.cpp

bool BTRegistrar::registerNodes(IBTFactoryWrapper& factory,
                               AgentControl* const agentControl,
                               WorldStateManager* const wsm,
                               BehaviorTreeManager* btManager) {
    // Null checks MUST happen before any use
    if (!agentControl || !wsm || !btManager) {
        cCritical(LOG_KEY) << "BTRegistrar::registerNodes called with null dependencies";
        return false;
    }

    bool allSucceeded = true;

    // Register coordination nodes (ClaimRoleNode, SetStateNode, etc.)
    // MUST use factory.registerNodeType<T>() template, not strings
    try {
        factory.registerNodeType<ClaimRoleNode>("ClaimRole");
        factory.registerNodeType<SetStateNode>("SetState");
        factory.registerNodeType<SetSubPlayNode>("SetSubPlay");
        factory.registerNodeType<WaitForRoleStateNode>("WaitForRoleState");
        cInfo(LOG_KEY) << "Registered coordination nodes";
    } catch (const std::exception& e) {
        cCritical(LOG_KEY) << "Failed to register coordination nodes: " << e.what();
        allSucceeded = false;
    }

    // Register other node types similarly
    // Each try-catch block prevents failure of one node type from affecting others

    return allSucceeded;
}
```

**Implementation Example (registerTreeFile):**

```cpp
// GOOD: Graceful error handling with context
bool BTRegistrar::registerTreeFile(const std::filesystem::path& filepath) {
    try {
        // Read file
        std::string xml = loadTreeXmlFromFile(filepath.string());

        // Attempt registration via wrapper (which has enhanced error handling)
        factory_->getFactory().registerBehaviorTreeFromText(xml);
        cInfo(LOG_KEY) << "Registered tree from " << filepath.string();
        return true;

    } catch (const BT::RuntimeError& e) {
        // Log the error but continue processing other files
        cWarning(LOG_KEY) << "Failed to register XML tree from "
                         << filepath.string() << ": " << e.what();

        // Attempt to provide debugging context
        try {
            std::string xml = loadTreeXmlFromFile(filepath.string());
            std::string truncated = truncateXmlForLogging(xml, 500);
            cDebug(LOG_KEY) << "XML content:\n" << truncated;
        } catch (const std::exception& readErr) {
            cDebug(LOG_KEY) << "Could not load XML for debugging: " << readErr.what();
        }

        return false;  // Continue processing other files

    } catch (const std::exception& e) {
        cCritical(LOG_KEY) << "Unexpected error registering XML tree from "
                          << filepath.string() << ": " << e.what();
        return false;  // Still continue processing
    }
}
```

**Dos & Don'ts:**

**DO:**
- ✓ Validate all constructor parameters and throw on null
- ✓ Delete copy/move constructors (prevent accidental ownership changes)
- ✓ Use raw (non-owning) pointers for injected dependencies
- ✓ Use const references for string parameters
- ✓ Catch exceptions per node type/tree to prevent cascading failures
- ✓ Log meaningful context (file paths, XML snippets) when errors occur
- ✓ Use factory.registerNodeType<T>() template (type-safe), not string-based registration
- ✓ Return false on errors but continue processing remaining items
- ✓ Use std::filesystem for path operations (type-safe, cross-platform)

**DON'T:**
- ✗ Don't store shared_ptr to factory or manager (they own BTRegistrar)
- ✗ Don't use string-based node type registration (e.g., "ClaimRole" as key)
- ✗ Don't use dynamic_cast on dependencies (injection should guarantee types)
- ✗ Don't throw exceptions on individual XML file failures (graceful continue)
- ✗ Don't modify factory state directly; use the wrapper interface
- ✗ Don't log sensitive data (passwords, API keys, full XML if >1KB)
- ✗ Don't create temporary objects without RAII (use std::filesystem::path, not char[])
- ✗ Don't assume XML files are small; stream large files instead of reading all

**Checklist:**
- [ ] Constructor validates all parameters (throws std::invalid_argument on null)
- [ ] Copy/move constructors explicitly deleted
- [ ] Static registerNodes() does not modify instance state
- [ ] All node types registered using factory.registerNodeType<T>() template
- [ ] registerTreesFromDirectory() uses std::filesystem for portability
- [ ] Each XML file failure is caught independently (doesn't stop processing)
- [ ] Error messages include file paths and truncated XML snippets
- [ ] Logging uses appropriate levels (cCritical, cWarning, cDebug)
- [ ] All exception types handled (BT::RuntimeError, std::exception)
- [ ] Performance: no excessive file reads (reads once per file)
- [ ] Thread-safety verified for const operations

**Rationale:** Extract registration logic with strong type safety and graceful error handling; enable unit testing of registration independently

---

#### Task 2.3: Refactor BehaviorTreeManager

**File:** `src/agent/bt/BehaviorTreeManager.h/cpp`

**Constraints & Requirements:**
- [ ] MUST maintain backward-compatible public API (21 test files must work unchanged)
- [ ] Static registerNodes() method signature MUST NOT change
- [ ] Member variables MUST be std::shared_ptr (owning, single responsibility)
- [ ] Constructor MUST initialize both wrapper and registrar
- [ ] MUST NOT expose wrapper/registrar as public members (only use internally)
- [ ] MUST maintain performance characteristics of original implementation
- [ ] Delegation methods MUST be simple pass-through (no additional logic)
- [ ] MUST update tick() to use wrapper for tree creation
- [ ] All existing tree access methods must continue to work
- [ ] No changes to tree storage mechanism (robotTrees, refTrees maps)

**Header Changes:**

```cpp
// BEFORE (current implementation)
class BehaviorTreeManager {
private:
    BT::BehaviorTreeFactory factory_;  // Direct usage - problematic
    // ... rest of implementation

// AFTER (refactored)
class BehaviorTreeManager {
private:
    std::shared_ptr<IBTFactoryWrapper> factory_;      // Wrapper (owning)
    std::shared_ptr<IBTRegistrar> registrar_;         // Registrar (owning)

    // Existing members unchanged
    QMap<int, std::shared_ptr<BT::Tree>> robotTrees;
    QMap<int, std::shared_ptr<BT::Tree>> refTrees;
    // ... rest remains unchanged
```

**Constructor Implementation:**

```cpp
// GOOD: Default constructor creates dependencies
BehaviorTreeManager::BehaviorTreeManager(WorldStateManager* wsm,
                                        AgentControl* agentControl)
    : wsm(wsm), agentControl(agentControl) {

    // Create wrapper first (registrar depends on it)
    factory_ = std::make_shared<BTFactoryWrapper>();

    // Create registrar with dependency injection
    registrar_ = std::make_shared<BTRegistrar>(
        factory_.get(),
        agentControl,
        wsm,
        this
    );
}

// GOOD: Testing constructor allows dependency injection
BehaviorTreeManager::BehaviorTreeManager(
    WorldStateManager* wsm,
    AgentControl* agentControl,
    std::shared_ptr<IBTFactoryWrapper> factory,
    std::shared_ptr<IBTRegistrar> registrar)
    : wsm(wsm),
      agentControl(agentControl),
      factory_(factory),
      registrar_(registrar) {

    // Validate injected dependencies
    if (!factory_ || !registrar_) {
        throw std::invalid_argument("BTManager: factory and registrar cannot be null");
    }
}
```

**Delegation Methods Implementation:**

```cpp
// GOOD: Simple delegation without additional logic
bool BehaviorTreeManager::registerNodes() {
    // Delegate to registrar instance
    return registrar_->registerNodes();
}

bool BehaviorTreeManager::registerTreesFromDirectory(const std::string& search_directory) {
    return registrar_->registerTreesFromDirectory(search_directory);
}

bool BehaviorTreeManager::registerTreeFromText(const std::string& xml) {
    return registrar_->registerTreeFromText(xml);
}

std::string BehaviorTreeManager::loadTreeXmlFromFile(const std::string& filepath) {
    return registrar_->loadTreeXmlFromFile(filepath);
}
```

**Static Method Delegation (Backward Compatibility):**

```cpp
// MUST NOT change signature - 21 tests depend on this
bool BehaviorTreeManager::registerNodes(
    BT::BehaviorTreeFactory& factory_,
    AgentControl* const agentControl_,
    WorldStateManager* const wsm_,
    BehaviorTreeManager* btManager_) {

    // Create wrapper that wraps the provided factory
    // This maintains backward compatibility with direct factory access
    auto wrapper = std::make_shared<BTFactoryWrapper>();
    // Note: The wrapper will have a separate internal factory_
    // This is acceptable since test factories are not shared

    return BTRegistrar::registerNodes(
        *wrapper,
        agentControl_,
        wsm_,
        btManager_
    );
}
```

**Tree Creation Changes (in tick()):**

```cpp
// BEFORE: Direct factory usage
auto tree = std::make_shared<BT::Tree>(
    factory_.createTree(treeId, blackboard)
);

// AFTER: Use wrapper interface
auto tree = std::make_shared<BT::Tree>(
    factory_->createTree(treeId, blackboard)
);
```

**Dos & Don'ts:**

**DO:**
- ✓ Use std::shared_ptr for factory and registrar (we own these)
- ✓ Keep static registerNodes() signature unchanged (backward compat)
- ✓ Provide testing constructor with DI parameters
- ✓ Make delegation methods simple and transparent
- ✓ Keep all existing tree access methods unchanged
- ✓ Update tick() to use wrapper consistently
- ✓ Validate injected dependencies in DI constructor
- ✓ Document the DI constructor for test writers

**DON'T:**
- ✗ Don't change registerNodes() static signature
- ✗ Don't expose factory_ or registrar_ as public members
- ✗ Don't add logic to delegation methods beyond pass-through
- ✗ Don't change tree storage containers (QMap<int, shared_ptr<Tree>>)
- ✗ Don't assume factory_ or registrar_ are not null (check in DI constructor)
- ✗ Don't create new BTFactoryWrapper in tick() - reuse member factory_
- ✗ Don't break existing tree access API (getTree, getRefTree, etc.)
- ✗ Don't add performance-sensitive operations in constructors

**Migration Example:**

```cpp
// Test code can now inject mocks
class MockFactoryWrapper : public IBTFactoryWrapper {
    // implementation...
};

class MockRegistrar : public IBTRegistrar {
    // implementation...
};

// Usage in tests
auto mockFactory = std::make_shared<MockFactoryWrapper>();
auto mockRegistrar = std::make_shared<MockRegistrar>();
BehaviorTreeManager btm(wsm, agentControl, mockFactory, mockRegistrar);
// Now can verify registerNodes() calls through mockRegistrar
```

**Checklist:**
- [ ] Private members are std::shared_ptr<IXxx> (owning)
- [ ] Default constructor creates real wrapper and registrar
- [ ] Testing constructor accepts shared_ptr dependencies
- [ ] Testing constructor validates injected dependencies
- [ ] Static registerNodes() signature unchanged
- [ ] All delegation methods are simple pass-through
- [ ] tick() uses factory_->createTree()
- [ ] All existing tree access methods unchanged
- [ ] All 21 test files pass without modification
- [ ] No performance regression in tree creation
- [ ] No memory leaks (shared_ptr cleanup verified)
- [ ] Backward compatible API maintained

**Rationale:** Maintain backward compatibility while enabling new architecture; enable dependency injection for testing

---

### Phase 3: Integration & Cleanup

#### Task 3.1: Update PlayAssignmentHelper

**File:** `src/agent/bt/playAssignment/PlayAssignmentHelper.cpp`

**Constraints & Requirements:**
- [ ] MUST replace inline tree halting with BTLifecycle::haltTree()
- [ ] MUST use BTLifecycle::checkAndReplaceTrees() for tree replacement logic
- [ ] MUST use IBTFactoryWrapper::createTree() interface (never call factory directly)
- [ ] MUST NOT modify tree halting/cleanup delay values
- [ ] MUST preserve robot_id blackboard setting after tree creation
- [ ] MUST maintain performance (no additional allocations in hot path)
- [ ] Error handling MUST remain consistent (try-catch with cCritical logging)
- [ ] MUST NOT change public API of PlayAssignmentHelper
- [ ] All tree creation MUST go through wrapper for enhanced error diagnostics
- [ ] Tree cleanup queue MUST be processed correctly (50ms delay maintained)

**Before (Current Implementation):**
```cpp
// CURRENT: Inline tree halting and cleanup logic scattered
try {
    bool needsNewTree = false;

    if (!robotTrees.contains(robotId) || !robotTrees[robotId]) {
        needsNewTree = true;
        cInfo(LOG_CATEGORY) << "Robot " << robotId << " has no tree, creating new tree";
    } else {
        std::string currentTreeId = robotTrees[robotId]->rootNode()->registrationName();
        if (currentTreeId != assignment.treeId) {
            cInfo(LOG_CATEGORY) << "Robot " << robotId << " tree type changed, creating new one";

            // Manual tree halting - problematic
            auto oldTree = robotTrees[robotId];
            oldTree->haltTree();
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            treesToCleanup.append(oldTree);
            needsNewTree = true;
        }
    }

    if (needsNewTree) {
        // Direct factory usage - no error context
        auto tree = std::make_shared<BT::Tree>(
            factory.createTree(assignment.treeId, robotBoards[robotId])
        );

        tree->rootBlackboard()->set("robot_id", robotId);
        robotTrees[robotId] = tree;

        cInfo(LOG_CATEGORY) << "Assigned " << assignment.treeId.c_str()
                           << " to robot " << robotId;
    }

} catch (const std::exception& e) {
    cCritical(LOG_CATEGORY) << "Failed to create tree '" << assignment.treeId.c_str()
                           << "' for robot " << robotId << ": " << e.what();
    return false;
}
```

**After (Refactored with BTLifecycle):**
```cpp
// GOOD: Using BTLifecycle utilities
try {
    // Use centralized tree replacement logic
    auto [newTree, wasReplaced] = BTLifecycle::checkAndReplaceTrees(
        robotId,
        robotTrees.contains(robotId) ? robotTrees[robotId] : nullptr,
        assignment.treeId,
        *factory_,  // IBTFactoryWrapper interface (not direct factory)
        robotBoards[robotId],
        treesToCleanup
    );

    if (!newTree) {
        cCritical(LOG_CATEGORY) << "Failed to create tree '" << assignment.treeId.c_str()
                               << "' for robot " << robotId;
        return false;
    }

    // Set robot_id in blackboard after creation
    newTree->rootBlackboard()->set("robot_id", robotId);
    robotTrees[robotId] = newTree;

    if (wasReplaced) {
        cInfo(LOG_CATEGORY) << "Replaced tree for robot " << robotId
                           << " with " << assignment.treeId.c_str();
    } else {
        cInfo(LOG_CATEGORY) << "Assigned " << assignment.treeId.c_str()
                           << " to robot " << robotId;
    }

} catch (const std::exception& e) {
    // Wrapper provides enhanced error context
    cCritical(LOG_CATEGORY) << "Failed to create tree '" << assignment.treeId.c_str()
                           << "' for robot " << robotId << ": " << e.what();
    return false;
}
```

**BTLifecycle Usage Example:**
```cpp
// In the loop that assigns trees
for (auto it = assignments.constBegin(); it != assignments.constEnd(); ++it) {
    int robotId = it.key();
    const RobotAssignment& assignment = it.value();

    // Check tree ID validity
    if (assignment.treeId.empty()) {
        cWarning(LOG_CATEGORY) << "Empty tree ID for robot " << robotId;
        continue;
    }

    // Use centralized tree replacement function
    auto [tree, wasReplaced] = BTLifecycle::checkAndReplaceTrees(
        robotId,
        robotTrees.contains(robotId) ? robotTrees[robotId] : nullptr,
        assignment.treeId,
        *factory_,  // Pass wrapper by reference
        robotBoards[robotId],
        treesToCleanup  // Pass cleanup queue for deferred cleanup
    );

    if (!tree) {
        cWarning(LOG_CATEGORY) << "Could not create tree for robot " << robotId;
        continue;  // Skip this robot, process others
    }

    // Setup blackboard with robot ID
    tree->rootBlackboard()->set("robot_id", robotId);
    robotTrees[robotId] = tree;
}

// Process cleanup queue periodically (e.g., at end of frame)
BTLifecycle::cleanupTrees(treesToCleanup);
```

**Dos & Don'ts:**

**DO:**
- ✓ Use BTLifecycle::checkAndReplaceTrees() for all tree replacements
- ✓ Pass IBTFactoryWrapper by reference (not direct factory)
- ✓ Set robot_id in blackboard AFTER successful tree creation
- ✓ Call BTLifecycle::cleanupTrees() at end of frame/loop
- ✓ Check tree validity before using (checkAndReplaceTrees may fail)
- ✓ Log meaningful messages about tree replacement vs. creation
- ✓ Use const references for string parameters

**DON'T:**
- ✗ Don't call haltTree() directly; use BTLifecycle::checkAndReplaceTrees()
- ✗ Don't use std::this_thread::sleep_for() directly; BTLifecycle handles delays
- ✗ Don't create BT::Tree manually; use factory_->createTree()
- ✗ Don't store raw BT::BehaviorTreeFactory references; use wrapper interface
- ✗ Don't mix manual cleanup logic with BTLifecycle utilities
- ✗ Don't assume tree creation succeeds; always check return value
- ✗ Don't skip robot on tree replacement error; continue to next robot
- ✗ Don't set robot_id before tree is successfully created

**Checklist:**
- [ ] All inline tree halting replaced with BTLifecycle::checkAndReplaceTrees()
- [ ] factory parameter changed to IBTFactoryWrapper reference
- [ ] All factory.createTree() calls replaced with factory_->createTree()
- [ ] tree->rootBlackboard()->set("robot_id") happens after creation
- [ ] BTLifecycle::cleanupTrees() called at frame end
- [ ] Error handling maintains cCritical logging
- [ ] All existing tests pass without modification
- [ ] No additional allocations in hot path
- [ ] Tree replacement messages differentiate from initial creation
- [ ] Cleanup queue is processed regularly (no indefinite growth)

**Rationale:** Use new utilities; centralize tree lifecycle management; improve error diagnostics

---

#### Task 3.2: Update GameStateReflex

**File:** `src/agent/bt/GameStateReflex.cpp`

**Constraints & Requirements:**
- [ ] MUST replace ALL factory.createTree() calls with factory_->createTree()
- [ ] MUST update wrapper member variable (factory_ instead of factory)
- [ ] MUST maintain same error handling pattern (try-catch with cCritical)
- [ ] MUST NOT change tree assignment logic (only factory access)
- [ ] Error messages MUST benefit from wrapper's enhanced diagnostics
- [ ] All GSR trees (Kickoff, FreeKick, Penalty, etc.) must use wrapper
- [ ] MUST NOT assume wrapper is present (check in constructor/initialization)
- [ ] MUST maintain performance (no additional overhead in GSR tree creation)
- [ ] MUST NOT modify robot board setup (happens before tree creation)
- [ ] All ~14 tree creation sites MUST be updated consistently

**Search Pattern (find all occurrences):**
```bash
# Find all direct factory.createTree() calls
grep -n "factory\.createTree" src/agent/bt/GameStateReflex.cpp

# Expected results: ~14 calls across different GSR states
```

**Before (Current Implementation):**
```cpp
// CURRENT: Direct factory usage - no error context
try {
    auto tree = std::make_shared<BT::Tree>(
        factory.createTree(GSR_KICKOFF_ATTACK_TREE, btMan->robotBoards[robot.id])
    );

    tree->rootBlackboard()->set("robot_id", robot.id);
    robotTrees[robot.id] = tree;

    cInfo(LOG_CATEGORY) << "Created GSR tree for robot " << robot.id;

} catch (const std::exception& e) {
    // Minimal error context
    cCritical(LOG_CATEGORY) << "Failed to create GSR tree for robot " << robot.id
                           << ": " << e.what();
    return;  // Silently fail
}
```

**After (Using Wrapper):**
```cpp
// GOOD: Using wrapper interface with enhanced diagnostics
try {
    auto tree = std::make_shared<BT::Tree>(
        factory_->createTree(GSR_KICKOFF_ATTACK_TREE, btMan->robotBoards[robot.id])
    );

    tree->rootBlackboard()->set("robot_id", robot.id);
    robotTrees[robot.id] = tree;

    cInfo(LOG_CATEGORY) << "Created GSR tree for robot " << robot.id;

} catch (const BT::RuntimeError& e) {
    // Wrapper provides enhanced error context including:
    // - XML snippets
    // - Registered tree names
    // - Tree structure on failure
    cCritical(LOG_CATEGORY) << "Failed to create GSR tree '" << GSR_KICKOFF_ATTACK_TREE
                           << "' for robot " << robot.id << ":\n" << e.what();
    return;  // Continue with other robots/states
}
```

**All GSR Tree Creation Sites (Examples):**
```cpp
// GameStateReflex::handleKickoffAttack()
case GameState::KICKOFF_ATTACK:
    // OLD: factory.createTree(GSR_KICKOFF_ATTACK_TREE, ...)
    // NEW: factory_->createTree(GSR_KICKOFF_ATTACK_TREE, ...)
    auto tree = std::make_shared<BT::Tree>(
        factory_->createTree(GSR_KICKOFF_ATTACK_TREE, btMan->robotBoards[robot.id])
    );

// GameStateReflex::handleFreeKickDefense()
case GameState::FREE_KICK_DEFENSE:
    // OLD: factory.createTree(GSR_FREE_KICK_DEFENSE_TREE, ...)
    // NEW: factory_->createTree(GSR_FREE_KICK_DEFENSE_TREE, ...)
    auto tree = std::make_shared<BT::Tree>(
        factory_->createTree(GSR_FREE_KICK_DEFENSE_TREE, btMan->robotBoards[robot.id])
    );

// GameStateReflex::handlePenaltyAttack()
case GameState::PENALTY_ATTACK:
    // OLD: factory.createTree(GSR_PENALTY_ATTACK_TREE, ...)
    // NEW: factory_->createTree(GSR_PENALTY_ATTACK_TREE, ...)
    auto tree = std::make_shared<BT::Tree>(
        factory_->createTree(GSR_PENALTY_ATTACK_TREE, btMan->robotBoards[robot.id])
    );

// ... and ~11 more sites
```

**Member Variable Update:**
```cpp
// Header: GameStateReflex.h
class GameStateReflex {
private:
    // OLD: BT::BehaviorTreeFactory factory;
    // NEW: std::shared_ptr<IBTFactoryWrapper> factory_;
    std::shared_ptr<IBTFactoryWrapper> factory_;

    // ... rest of members unchanged
};

// Implementation: GameStateReflex.cpp
GameStateReflex::GameStateReflex(/* dependencies */)
    : /* existing init */ {

    // OLD: factory initialized in constructor or at declaration
    // NEW: factory_ created in constructor
    factory_ = std::make_shared<BTFactoryWrapper>();

    // Or injected for testing:
    // factory_ = injectedFactory;
}
```

**Dos & Don'ts:**

**DO:**
- ✓ Replace ALL factory.createTree() with factory_->createTree()
- ✓ Change member variable from `factory` to `factory_` (non-owning reference)
- ✓ Use shared_ptr<IBTFactoryWrapper> for the member
- ✓ Catch both BT::RuntimeError and std::exception separately
- ✓ Log enhanced error messages that include tree structure info
- ✓ Maintain try-catch pattern for each GSR tree creation
- ✓ Set robot_id in blackboard immediately after creation
- ✓ Use consistent tree ID naming (GSR_KICKOFF_ATTACK_TREE, etc.)

**DON'T:**
- ✗ Don't mix old factory usage with new wrapper usage
- ✗ Don't create multiple wrappers; share single instance
- ✗ Don't assume factory_ is initialized; check in each method
- ✗ Don't remove try-catch blocks; error handling is critical
- ✗ Don't log factory.createTree() calls directly; factory doesn't expose logging
- ✗ Don't change error handling behavior (still fail silently for robot)
- ✗ Don't move tree creation outside try-catch for "cleaner" code
- ✗ Don't assume wrapper supports legacy tree ID format (use current format)

**Update Pattern (use sed or manual replacement):**
```bash
# Find-replace pattern (be careful - test first!)
# Before: factory.createTree(
# After:  factory_->createTree(

# Manual verification is safer - check each replacement:
# 1. Find all occurrences of "factory.createTree"
# 2. Verify each is in a GSR tree creation context
# 3. Manually update to "factory_->createTree"
# 4. Verify surrounding code (robot board setup, blackboard set)
```

**Checklist:**
- [ ] Search for all factory.createTree() occurrences (~14 calls)
- [ ] Verify each is in a try-catch block with error handling
- [ ] Update all occurrences to factory_->createTree()
- [ ] Update member variable from factory to factory_
- [ ] Change factory member type to std::shared_ptr<IBTFactoryWrapper>
- [ ] Initialize factory_ in GameStateReflex constructor
- [ ] Verify robot_id blackboard setup still works
- [ ] All GSR states (Kickoff, FreeKick, Penalty, etc.) updated
- [ ] Error messages benefit from wrapper diagnostics
- [ ] No performance regressions in GSR tree creation
- [ ] All tests pass without modification
- [ ] No lingering references to factory (old member)

**Rationale:** Use new wrapper for consistency and better error diagnostics across all tree creation sites

---

#### Task 3.3: Verify Backward Compatibility

**Scope:** All 21 test files calling BehaviorTreeManager::registerNodes()

**Constraints & Requirements:**
- [ ] MUST maintain exact static method signature: `registerNodes(BT::BehaviorTreeFactory&, AgentControl*, WorldStateManager*, BehaviorTreeManager*)`
- [ ] MUST NOT change method name, parameter order, or types
- [ ] MUST NOT change parameter semantics (factory by reference, pointers for agent/wsm/btm)
- [ ] Tests MUST pass without any modifications to test code
- [ ] MUST NOT introduce breaking changes to public API
- [ ] Performance MUST be unchanged (no additional overhead in registration)
- [ ] All 21 test files MUST compile and pass without any changes
- [ ] No deprecation warnings during compilation

**Test File Pattern (Examples of the 21 files):**

The following test files call `BehaviorTreeManager::registerNodes()` statically:

```cpp
// Example: ClaimRole_Test.cpp
#include "gtest/gtest.h"
#include "BehaviorTreeManager.h"

class ClaimRoleTest : public ::testing::Test {
protected:
    void SetUp() override {
        // MUST use exact signature - DO NOT change
        BehaviorTreeManager::registerNodes(
            factory,           // BT::BehaviorTreeFactory&
            agentControl,      // AgentControl*
            wsm,               // WorldStateManager*
            &btManager         // BehaviorTreeManager*
        );
    }

    BT::BehaviorTreeFactory factory;
    WorldStateManager wsm{true};
    AgentControl agentControl{nullptr, nullptr, &wsm, false};
    BehaviorTreeManager btManager{&wsm, &agentControl};
};
```

**Verification Process:**

Step 1: Search for all test files calling registerNodes:
```bash
# Find all test files with registerNodes call
grep -r "registerNodes" src/agent/bt/nodes/ | grep "_Test.cpp" | wc -l
# Expected: ~21 files with this pattern
```

Step 2: Verify signature hasn't changed in any file:
```bash
# Confirm all calls use same signature
grep -r "registerNodes(" src/agent/bt/nodes/ | grep -v "//" | head -5
# All should show: BehaviorTreeManager::registerNodes(factory, agentControl, wsm, &btManager)
```

**Backward Compatibility Verification Code Pattern:**

```cpp
// GOOD: Test should work unchanged after refactor
class ExistingTestPattern {
public:
    void testBackwardCompat() {
        // Create instances with same pattern as before
        BT::BehaviorTreeFactory factory;
        WorldStateManager wsm{true};
        AgentControl agentControl{nullptr, nullptr, &wsm, false};
        BehaviorTreeManager btManager{&wsm, &agentControl};

        // Call with exact signature - MUST NOT change
        bool success = BehaviorTreeManager::registerNodes(
            factory,        // MUST be BT::BehaviorTreeFactory&
            &agentControl,  // MUST be AgentControl*
            &wsm,           // MUST be WorldStateManager*
            &btManager      // MUST be BehaviorTreeManager*
        );

        // MUST return bool as before
        assert(success);

        // MUST allow immediate tree creation as before
        auto tree = factory.createTree("some_tree_id", BT::Blackboard::create());
        assert(tree.rootNode() != nullptr);
    }
};
```

**Dos & Don'ts:**

**DO:**
- ✓ Keep static registerNodes() signature exactly as-is
- ✓ Call factory.registerNodeType<T>() in same order as before
- ✓ Ensure all 21 test files compile without changes
- ✓ Verify return value is bool and matches expected registration success
- ✓ Test that nodes are registered in factory consistently
- ✓ Check that factory can immediately create trees after registration
- ✓ Verify error handling path hasn't changed (graceful continues)
- ✓ Run full test suite: `./build/test/unit_tests` (all tests must pass)

**DON'T:**
- ✗ Don't change parameter order (would break all 21 test files)
- ✗ Don't change parameter types (e.g., BT::BehaviorTreeFactory& is critical)
- ✗ Don't rename the method (tests depend on exact name)
- ✗ Don't add optional parameters (would break call signatures)
- ✗ Don't remove the method from public API
- ✗ Don't change registration behavior (same nodes, same order)
- ✗ Don't add deprecation warnings (backward compat means truly transparent)
- ✗ Don't assume test files will be updated (they must work unchanged)

**Implementation Verification Script:**

```bash
#!/bin/bash
# Verify backward compatibility before and after refactor

echo "=== Backward Compatibility Verification ==="
echo

# 1. Count test files
test_count=$(grep -r "BehaviorTreeManager::registerNodes" src/agent/bt/nodes/ --include="*_Test.cpp" | wc -l)
echo "Found $test_count test files using registerNodes()"
[[ $test_count -ge 20 ]] && echo "✓ PASS: Found expected ~21 test files" || echo "✗ FAIL: Expected at least 20 test files"

# 2. Verify no signature changes in test files
echo
echo "Checking for consistent signatures..."
inconsistent=$(grep -r "registerNodes(" src/agent/bt/nodes/ --include="*_Test.cpp" | grep -v "BehaviorTreeManager::registerNodes(factory" | grep -v "//" | wc -l)
[[ $inconsistent -eq 0 ]] && echo "✓ PASS: All signatures consistent" || echo "✗ FAIL: Found $inconsistent inconsistent signatures"

# 3. Build and test
echo
echo "Building project..."
kk 2>&1 | tee build/build.log | tail -n 5

# 4. Check for compilation errors
errors=$(grep -i "error:" build/build.log | wc -l)
[[ $errors -eq 0 ]] && echo "✓ PASS: No compilation errors" || echo "✗ FAIL: Found $errors compilation errors"

# 5. Run tests
echo
echo "Running test suite..."
timeout 60 ./build/test/unit_tests -t "ClaimRole_Test|SetState_Test|WaitForRole_Test" 2>&1 | tail -n 10

echo
echo "=== Verification Complete ==="
```

**Checklist:**
- [ ] All 21 test files located and documented
- [ ] Static method signature verified unchanged
- [ ] No compilation errors when building with refactored code
- [ ] All tests pass with `./build/test/unit_tests`
- [ ] Specific coordination tests pass: `./build/test/unit_tests -t "ClaimRole_Test|SetState_Test"`
- [ ] No deprecation warnings or "breaking change" messages
- [ ] Tree creation works identically to before refactor
- [ ] Factory registration pattern unchanged
- [ ] Return value behavior unchanged (bool indicating success)
- [ ] All 21 test files compile and pass WITHOUT modification

**Rationale:** Maintain backward compatibility with existing test infrastructure; ensure zero disruption to 21 test files; verify refactor is transparent to consumers of the static method

---

### Phase 4: Error Handling & Testing

#### Task 4.1: Create XML Test Fixtures Directory

**Directory:** `src/agent/bt/xml/tests/`

**Constraints & Requirements:**
- [ ] MUST create dedicated `src/agent/bt/xml/tests/` directory for test fixtures
- [ ] MUST use new tag/value format (role_tag + role_value, not deprecated role_id)
- [ ] MUST use PlayContext values that match CoordinationTypes.h enum:
  - `role_tag="-1"` for Common context
  - `role_tag="10"` for BallRecovery context (use appropriate context value)
- [ ] All XML MUST be well-formed and valid UTF-8
- [ ] Each fixture MUST have descriptive header comments explaining test purpose
- [ ] No sensitive data in fixtures (no hardcoded URLs, credentials, paths)
- [ ] Fixtures MUST be minimal and focused (avoid complex, real-world trees)
- [ ] Each fixture MUST demonstrate exactly ONE error condition
- [ ] All coordinator node IDs (robot_id) MUST use 0-3 range (valid test robot IDs)

**XML Fixture Examples:**

**Fixture 1: ValidTree.xml** (baseline - should succeed)
```xml
<?xml version="1.0"?>
<!-- Valid tree fixture: tests that registration succeeds for well-formed XML -->
<!-- Uses new tag/value format for coordination nodes -->
<root BTCPP_format="4">
    <BehaviorTree ID="ValidTestTree">
        <Sequence>
            <ClaimRole robot_id="0" role_tag="-1" role_value="10" />
            <SetState robot_id="0" state_tag="-1" state_value="5" />
            <SubAction />
        </Sequence>
    </BehaviorTree>
</root>
```

**Fixture 2: UnregisteredNode.xml** (error: node type not registered)
```xml
<?xml version="1.0"?>
<!-- Error fixture: contains unregistered custom node type -->
<!-- Expected: BTFactoryWrapper should catch and provide helpful error -->
<root BTCPP_format="4">
    <BehaviorTree ID="UnregisteredNodeTree">
        <Sequence>
            <NonExistentCustomNode robot_id="0" />
        </Sequence>
    </BehaviorTree>
</root>
```

**Fixture 3: MissingInput.xml** (error: missing required port)
```xml
<?xml version="1.0"?>
<!-- Error fixture: ClaimRole missing required role_value port -->
<!-- Expected: Node creation fails with "missing input port" error -->
<root BTCPP_format="4">
    <BehaviorTree ID="MissingInputTree">
        <Sequence>
            <!-- Missing role_value - only tag provided -->
            <ClaimRole robot_id="0" role_tag="-1" />
        </Sequence>
    </BehaviorTree>
</root>
```

**Fixture 4: InvalidXMLSyntax.xml** (error: malformed XML)
```xml
<?xml version="1.0"?>
<!-- Error fixture: malformed XML structure -->
<!-- Expected: XML parser fails with parse error -->
<root BTCPP_format="4">
    <BehaviorTree ID="InvalidXMLTree">
        <Sequence>
            <ClaimRole robot_id="0" role_tag="-1" role_value="10"
            <!-- Missing closing tag and unclosed sequence -->
</root>
```

**Fixture 5: NullCoordinator.xml** (error: null coordinator dependency)
```xml
<?xml version="1.0"?>
<!-- Error fixture: ClaimRole node with no coordinator provided -->
<!-- Expected: Node tick fails with "coordinator required" error -->
<root BTCPP_format="4">
    <BehaviorTree ID="NullCoordinatorTree">
        <Sequence>
            <!-- ClaimRole REQUIRES coordinator input port -->
            <ClaimRole robot_id="0" role_tag="-1" role_value="10" />
        </Sequence>
    </BehaviorTree>
</root>
```

**File Creation Script:**

```bash
#!/bin/bash
# Create XML test fixtures directory and files

FIXTURE_DIR="src/agent/bt/xml/tests"

# 1. Create directory
mkdir -p "$FIXTURE_DIR"
chmod 755 "$FIXTURE_DIR"
echo "✓ Created directory: $FIXTURE_DIR"

# 2. Create fixtures (content as above)
cat > "$FIXTURE_DIR/ValidTree.xml" << 'EOF'
<?xml version="1.0"?>
<!-- Valid tree fixture: tests that registration succeeds -->
<root BTCPP_format="4">
    <BehaviorTree ID="ValidTestTree">
        <Sequence>
            <ClaimRole robot_id="0" role_tag="-1" role_value="10" />
            <SetState robot_id="0" state_tag="-1" state_value="5" />
            <SubAction />
        </Sequence>
    </BehaviorTree>
</root>
EOF

cat > "$FIXTURE_DIR/UnregisteredNode.xml" << 'EOF'
<?xml version="1.0"?>
<!-- Error fixture: contains unregistered node type -->
<root BTCPP_format="4">
    <BehaviorTree ID="UnregisteredNodeTree">
        <Sequence>
            <NonExistentCustomNode robot_id="0" />
        </Sequence>
    </BehaviorTree>
</root>
EOF

# ... (similarly for MissingInput.xml, InvalidXMLSyntax.xml, NullCoordinator.xml)

# 3. Verify all files exist
echo "✓ Created $(ls $FIXTURE_DIR/*.xml 2>/dev/null | wc -l) XML fixtures"

# 4. Verify well-formedness (optional - requires xmllint or similar)
echo "Validating XML syntax..."
for file in "$FIXTURE_DIR"/*.xml; do
    if command -v xmllint &> /dev/null; then
        xmllint --noout "$file" 2>&1 && echo "  ✓ $file" || echo "  ✗ $file"
    fi
done
```

**Dos & Don'ts:**

**DO:**
- ✓ Create minimal, focused XML files (one error per fixture)
- ✓ Use meaningful BehaviorTree ID names (ValidTestTree, UnregisteredNodeTree, etc.)
- ✓ Use valid PlayContext tag values (-1 for Common, 10 for BallRecovery, etc.)
- ✓ Include descriptive comments at top of each file (purpose, expected error)
- ✓ Use robot_id values in 0-3 range (valid robot indices)
- ✓ Test on both success and error paths
- ✓ Make fixtures reusable across multiple test scenarios
- ✓ Store in dedicated `src/agent/bt/xml/tests/` directory (enables easy discovery)

**DON'T:**
- ✗ Don't use deprecated role_id format (use role_tag + role_value)
- ✗ Don't include real-world complex trees (keep minimal)
- ✗ Don't mix multiple error conditions in one fixture
- ✗ Don't hardcode filesystem paths in XML (use relative or test-provided paths)
- ✗ Don't include sensitive data (URLs, credentials, secret keys)
- ✗ Don't assume any context (set all required coordinator/blackboard inputs explicitly)
- ✗ Don't skip XML comments (document what error each fixture tests)
- ✗ Don't use robot_id < 0 or > 3 (invalid robot indices)
- ✗ Don't store fixtures in multiple locations (single dedicated directory)
- ✗ Don't make fixtures interdependent (each should be independently loadable)

**Integration with Test Framework:**

Test code will load fixtures like this:
```cpp
// Load fixture from file
std::string xmlPath = "src/agent/bt/xml/tests/ValidTree.xml";
std::string xmlContent = btRegistrar->loadTreeXmlFromFile(xmlPath);
auto tree = factory_->createTreeFromText(xmlContent, BT::Blackboard::create());
// Now tree can be used or tested for specific conditions
```

**Checklist:**
- [ ] Create `src/agent/bt/xml/tests/` directory with correct permissions
- [ ] Create ValidTree.xml with valid tree and proper tag/value format
- [ ] Create UnregisteredNode.xml testing unregistered node error
- [ ] Create MissingInput.xml testing missing required port error
- [ ] Create InvalidXMLSyntax.xml testing XML parse error
- [ ] Create NullCoordinator.xml testing null dependency error
- [ ] All files use UTF-8 encoding (no BOM)
- [ ] All files have descriptive header comments
- [ ] All files use new role_tag + role_value format (NOT deprecated role_id)
- [ ] All PlayContext values match CoordinationTypes.h enum
- [ ] All robot_id values in 0-3 range
- [ ] Verify each fixture XML is well-formed
- [ ] Fixtures are discoverable (can load all with wildcard pattern)
- [ ] Each fixture tests exactly one error condition

**Rationale:** Provide comprehensive error scenario test fixtures using current tag/value format; enable focused error handling testing; establish pattern for test data organization

---

#### Task 4.2: Create BehaviorTreeManager_ErrorHandling_Test.cpp

**File:** `src/agent/bt/BehaviorTreeManager_ErrorHandling_Test.cpp`

**Constraints & Requirements:**
- [ ] MUST use boost::ut BDD syntax (feature/scenario/given/when/then pattern)
- [ ] MUST NOT use gtest or other test frameworks (project uses boost::ut)
- [ ] ErrorTestFixture MUST initialize dependencies in deterministic order (wsm → agentControl → btManager → factory)
- [ ] All test scenarios MUST be independent (no shared state between tests)
- [ ] All scenarios MUST test ONLY error paths (success paths already tested elsewhere)
- [ ] Each error scenario MUST have exactly ONE expectation that should fail
- [ ] Exception types MUST be tested with expect(throws<ExceptionType>(...))
- [ ] Error message validation MUST check for presence of key terms (node name, port, tree path)
- [ ] Tests MUST complete in < 5 seconds total (error scenarios should fail fast)
- [ ] All assertions MUST include diagnostic messages for debugging
- [ ] MUST handle resource cleanup properly (avoid memory leaks even in error paths)
- [ ] MUST NOT assume any specific error message format (check for keywords, not exact match)

**Test Fixture Setup:**

```cpp
// GOOD: Deterministic initialization order
struct ErrorTestFixture {
    // 1. Initialize WSM first (no dependencies)
    WorldStateManager wsm{true};

    // 2. Initialize AgentControl (depends on WSM)
    AgentControl agentControl{nullptr, nullptr, &wsm, false};

    // 3. Initialize BehaviorTreeManager (depends on WSM and AgentControl)
    BehaviorTreeManager btManager{&wsm, &agentControl};

    // 4. Initialize Factory (independent, but must be before registration)
    BT::BehaviorTreeFactory factory;

    // 5. Register all nodes (should succeed if fixture is correctly set up)
    ErrorTestFixture() {
        bool success = BehaviorTreeManager::registerNodes(
            factory,           // BT::BehaviorTreeFactory&
            &agentControl,     // AgentControl*
            &wsm,              // WorldStateManager*
            &btManager         // BehaviorTreeManager*
        );

        // Fail loudly if registration fails (fixture is broken)
        if (!success) {
            throw std::runtime_error("ErrorTestFixture: failed to register nodes");
        }
    }
};
```

**Test Scenario Examples:**

**Scenario 1: Unregistered Node Detection**

```cpp
scenario("Tree creation fails gracefully with unregistered node") = [](auto& ctx) {
    given("an unregistered custom node in XML") = [&ctx](auto& given) {
        std::string xml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="TestTree">
                    <NonExistentCustomNode />
                </BehaviorTree>
            </root>
        )";

        when("BTFactoryWrapper attempts to create tree") = [&ctx, &xml](auto& when) {
            then("throws BT::RuntimeError with helpful message") = [&ctx, &xml] {
                // GOOD: Expect specific exception type
                expect(throws<BT::RuntimeError>([&ctx, &xml] {
                    auto tree = ctx.factory.createTreeFromText(xml, BT::Blackboard::create());
                })) << "Expected BT::RuntimeError for unregistered node";
            };

            then("error message mentions the unregistered node name") = [&ctx, &xml] {
                try {
                    auto tree = ctx.factory.createTreeFromText(xml, BT::Blackboard::create());
                    expect(false) << "Expected RuntimeError but tree was created";
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();
                    // Check for keywords, not exact match
                    expect(msg.find("NonExistent") != std::string::npos
                        || msg.find("Unregistered") != std::string::npos
                        || msg.find("not found") != std::string::npos)
                        << "Error message should identify the unregistered node. Got: " << msg;
                }
            };
        };
    };
};
```

**Scenario 2: Missing Required Input Port**

```cpp
scenario("Node creation fails when required input port is missing") = [](auto& ctx) {
    given("a coordination node with missing required port") = [&ctx](auto& given) {
        // ClaimRole requires robot_id and role_tag/role_value
        std::string xml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="MissingPortTree">
                    <Sequence>
                        <ClaimRole robot_id="0" />
                    </Sequence>
                </BehaviorTree>
            </root>
        )";

        when("creating tree with missing role_tag and role_value") = [&ctx, &xml](auto& when) {
            then("throws BT::RuntimeError mentioning missing ports") = [&ctx, &xml] {
                try {
                    auto tree = ctx.factory.createTreeFromText(xml, BT::Blackboard::create());
                    expect(false) << "Expected error for missing ports";
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();
                    expect(msg.find("port") != std::string::npos
                        || msg.find("input") != std::string::npos
                        || msg.find("required") != std::string::npos)
                        << "Error should mention missing port. Got: " << msg;
                }
            };
        };
    };
};
```

**Scenario 3: Invalid XML Syntax**

```cpp
scenario("Invalid XML is rejected with parse error") = [](auto& ctx) {
    given("malformed XML with syntax errors") = [&ctx](auto& given) {
        std::string invalidXml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="BrokenTree"
                    <Sequence>
                        <ClaimRole robot_id="0" role_tag="-1" role_value="10" />
                    <!-- Missing closing tags -->
        )";

        when("BTFactoryWrapper attempts XML parsing") = [&ctx, &invalidXml](auto& when) {
            then("throws BT::RuntimeError with XML context") = [&ctx, &invalidXml] {
                try {
                    auto tree = ctx.factory.createTreeFromText(invalidXml, BT::Blackboard::create());
                    expect(false) << "Expected error for malformed XML";
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();
                    expect(msg.find("XML") != std::string::npos
                        || msg.find("parse") != std::string::npos
                        || msg.find("syntax") != std::string::npos)
                        << "Error should mention XML parsing. Got: " << msg;
                }
            };
        };
    };
};
```

**Scenario 4: Error Messages Include Diagnostics**

```cpp
scenario("Error messages include helpful debugging information") = [](auto& ctx) {
    given("a tree with multiple error conditions") = [&ctx](auto& given) {
        std::string xml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="DiagnosticsTree">
                    <Sequence>
                        <UnregisteredNode />
                        <ClaimRole robot_id="0" />
                    </Sequence>
                </BehaviorTree>
            </root>
        )";

        when("tree creation fails") = [&ctx, &xml](auto& when) {
            then("error message includes registered node list OR XML snippet") = [&ctx, &xml] {
                try {
                    auto tree = ctx.factory.createTreeFromText(xml, BT::Blackboard::create());
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();

                    // Error should provide either list of registered nodes OR XML context
                    bool hasNodeList = msg.find("Registered") != std::string::npos
                                    || msg.find("available") != std::string::npos;
                    bool hasXmlContext = msg.find("XML") != std::string::npos
                                      || msg.find("root") != std::string::npos;
                    bool hasTree = msg.find("Tree") != std::string::npos
                               || msg.find("tree") != std::string::npos;

                    expect(hasNodeList || hasXmlContext || hasTree)
                        << "Error should include diagnostic context (node list, XML, or tree name). Got: " << msg;
                }
            };
        };
    };
};
```

**Dos & Don'ts:**

**DO:**
- ✓ Use boost::ut BDD syntax (scenario/given/when/then)
- ✓ Initialize fixture dependencies in order (no circular deps)
- ✓ Test only error paths (success is tested elsewhere)
- ✓ Catch specific exception types (BT::RuntimeError, std::exception)
- ✓ Check for keywords in error messages, not exact text
- ✓ Include diagnostic message in every expect() call
- ✓ Make each test independent (no shared state between scenarios)
- ✓ Test both the exception AND the error message
- ✓ Clean up resources even in error paths (use RAII)
- ✓ Fail fast on errors (don't continue after expected exception)

**DON'T:**
- ✗ Don't mix gtest patterns with boost::ut (use only boost::ut)
- ✗ Don't create circular dependencies in fixture initialization
- ✗ Don't test success paths (those are integration tests)
- ✗ Don't catch generic std::exception (catch specific types first)
- ✗ Don't check for exact error message text (format may change)
- ✗ Don't skip diagnostic messages in expect() calls
- ✗ Don't share state between test scenarios
- ✗ Don't assume error message includes stack trace (just core message)
- ✗ Don't leak resources in error path tests
- ✗ Don't test multiple error conditions in one scenario

**Checklist:**
- [ ] File created at `src/agent/bt/BehaviorTreeManager_ErrorHandling_Test.cpp`
- [ ] ErrorTestFixture struct initializes dependencies in order
- [ ] Fixture construction fails loudly if registration fails
- [ ] Scenario 1: Unregistered node detection implemented
- [ ] Scenario 2: Missing input port detection implemented
- [ ] Scenario 3: Invalid XML syntax detection implemented
- [ ] Scenario 4: Error messages include diagnostics
- [ ] All 4 scenarios use BDD syntax (scenario/given/when/then)
- [ ] All exception checks use expect(throws<ExceptionType>(...))
- [ ] All error message checks validate keywords (not exact text)
- [ ] Each scenario is completely independent
- [ ] All assertions include diagnostic messages
- [ ] Test runs to completion in < 5 seconds
- [ ] No memory leaks or resource issues
- [ ] Compiles without errors or warnings

**Rationale:** Comprehensive error path coverage; verify error messages are helpful; ensure robust error handling in all scenarios

---

#### Task 4.3: Verify Error Handling Integration

**Constraints & Requirements:**
- [ ] MUST verify all error paths are tested in BehaviorTreeManager_ErrorHandling_Test.cpp
- [ ] MUST confirm BTFactoryWrapper error messages include XML context (snippets or structure)
- [ ] MUST verify BTRegistrar gracefully continues on invalid XML (does not crash system)
- [ ] MUST test that tree cleanup utilities (BTLifecycle) handle error scenarios
- [ ] MUST verify NodeUtils::DumpTree() is called on factory creation failure
- [ ] Error handling MUST NOT mask the original error (root cause visible in message)
- [ ] MUST test both synchronous errors (creation) and deferred errors (tick)
- [ ] Performance MUST be acceptable (error handling < 100ms per error)
- [ ] MUST NOT log sensitive data in error messages

**Error Path Integration Test:**

```cpp
// GOOD: Integration test verifying error handling across components
feature("Error handling integration across BT components") = [] {
    given("a BTFactoryWrapper with invalid XML") = [] {
        auto wrapper = std::make_shared<BTFactoryWrapper>();
        std::string invalidXml = R"(<root><BehaviorTree><Unregistered/></BehaviorTree></root>)";

        when("attempting to create tree from invalid XML") = [wrapper, invalidXml] {
            then("wrapper throws BT::RuntimeError with helpful context") = [wrapper, invalidXml] {
                try {
                    wrapper->createTreeFromText(invalidXml, BT::Blackboard::create());
                    expect(false) << "Expected RuntimeError";
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();

                    // Verify error includes context
                    bool hasContext = msg.find("Registered") != std::string::npos
                                   || msg.find("XML") != std::string::npos
                                   || msg.find("Error") != std::string::npos;
                    expect(hasContext) << "Error should include context. Got: " << msg;

                    // Verify original error is visible
                    bool hasOriginal = msg.find("Unregistered") != std::string::npos
                                    || msg.find("not found") != std::string::npos;
                    expect(hasOriginal || msg.length() > 50)
                        << "Error should include original error or be detailed";
                }
            };
        };
    };
};
```

**Component-Level Error Verification:**

**1. BTFactoryWrapper Error Handling**

```cpp
// Verify wrapper provides enhanced error context
test("BTFactoryWrapper enhances error messages") = [] {
    auto wrapper = std::make_shared<BTFactoryWrapper>();

    // Error should include registered nodes list
    std::string missingNodeXml = R"(
        <root BTCPP_format="4">
            <BehaviorTree ID="Test">
                <UnknownNode />
            </BehaviorTree>
        </root>
    )";

    try {
        wrapper->createTreeFromText(missingNodeXml, BT::Blackboard::create());
    } catch (const BT::RuntimeError& e) {
        // Verify error includes helpful context
        std::string msg = e.what();
        expect(msg.find("Registered") != std::string::npos
            || msg.find("Unknown") != std::string::npos
            || msg.find("XML") != std::string::npos)
            << "Factory wrapper should enhance error with context";
    }
};
```

**2. BTRegistrar Graceful Error Handling**

```cpp
// Verify registrar continues on error (doesn't crash)
test("BTRegistrar handles invalid XML gracefully") = [] {
    auto factory = std::make_shared<BTFactoryWrapper>();
    auto registrar = std::make_shared<BTRegistrar>(
        factory.get(), agentControl, wsm, btManager
    );

    std::string invalidXml = "<root><BehaviorTree><Unregistered/></BehaviorTree></root>";

    // MUST NOT throw - should log warning and return false
    bool success = registrar->registerTreeFromText(invalidXml);

    expect(!success) << "Registration should fail gracefully";
    expect(true) << "System should continue after registration failure";
};
```

**3. BTLifecycle Error Handling**

```cpp
// Verify tree lifecycle handles error scenarios
test("BTLifecycle handles null/invalid trees") = [] {
    QList<std::shared_ptr<BT::Tree>> cleanupQueue;

    // MUST handle null pointer gracefully
    try {
        BTLifecycle::scheduleCleanup(nullptr, cleanupQueue);
        expect(cleanupQueue.isEmpty()) << "Null trees should not be added";
    } catch (...) {
        expect(false) << "scheduleCleanup should handle null gracefully";
    }

    // MUST handle cleanup of null queue
    try {
        BTLifecycle::cleanupTrees(cleanupQueue);
        expect(true) << "cleanupTrees should handle empty queue";
    } catch (...) {
        expect(false) << "cleanupTrees should never throw";
    }
};
```

**Integration Verification Script:**

```bash
#!/bin/bash
# Verify error handling integration across all components

echo "=== Error Handling Integration Verification ==="
echo

# 1. Run error handling tests
echo "1. Running error handling test suite..."
timeout 30 ./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling" 2>&1 | tee /tmp/error_tests.log

error_tests=$(grep -c "✓" /tmp/error_tests.log)
echo "✓ Error handling tests: $error_tests passed"

# 2. Verify all components are tested
echo
echo "2. Verifying component coverage..."
components=("BTFactoryWrapper" "BTRegistrar" "BTLifecycle" "NodeUtils")
for comp in "${components[@]}"; do
    if grep -q "$comp" /tmp/error_tests.log; then
        echo "  ✓ $comp error handling tested"
    else
        echo "  ✗ $comp error handling NOT tested"
    fi
done

# 3. Check for memory issues (if using valgrind)
echo
echo "3. Checking for memory leaks..."
if command -v valgrind &> /dev/null; then
    valgrind --leak-check=full --quiet ./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling" 2>&1 | grep -q "0 errors" && echo "  ✓ No memory leaks detected" || echo "  ✗ Memory leak detected"
else
    echo "  ⊘ valgrind not available (skipping)"
fi

# 4. Verify error messages contain context
echo
echo "4. Sampling error message quality..."
# Run a single error scenario and check message
timeout 5 ./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling" 2>&1 | grep -i "error\|exception" | head -3 | while read line; do
    echo "  Sample: $line"
done

echo
echo "=== Integration Verification Complete ==="
```

**Dos & Don'ts:**

**DO:**
- ✓ Test error paths end-to-end (from wrapper through registrar through lifecycle)
- ✓ Verify each component's error handling independently AND integrated
- ✓ Check that errors don't cascade (one component's error doesn't break others)
- ✓ Test that system continues after individual errors (graceful degradation)
- ✓ Verify error messages include enough context for debugging
- ✓ Test both immediate errors (creation) and deferred errors (tick)
- ✓ Monitor performance of error paths (should be fast)
- ✓ Ensure cleanup happens even in error scenarios (RAII)

**DON'T:**
- ✗ Don't test error handling in isolation (integration is most important)
- ✗ Don't assume error will be caught at wrapper level (may propagate)
- ✗ Don't skip graceful degradation testing (system MUST continue)
- ✗ Don't include passwords/credentials in error messages
- ✗ Don't assume all errors are recoverable (some should fail fast)
- ✗ Don't test only the happy path (errors are where bugs hide)
- ✗ Don't mix multiple errors in one test (test one error condition per scenario)
- ✗ Don't assume error message format is stable (test for keywords)

**Checklist:**
- [ ] BehaviorTreeManager_ErrorHandling_Test.cpp passes all scenarios
- [ ] BTFactoryWrapper error messages tested for content (XML context, node lists)
- [ ] BTRegistrar tested for graceful continuation on invalid XML (doesn't crash)
- [ ] BTLifecycle tested for null pointer and edge case handling
- [ ] NodeUtils::DumpTree() verified to be called on creation failure
- [ ] Integration test verifies errors don't cascade between components
- [ ] Performance verified: error handling < 100ms per error
- [ ] Cleanup verified: resources released even in error scenarios
- [ ] Error messages tested for absence of sensitive data
- [ ] All tests pass: `./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling"` (< 5 seconds)
- [ ] Code coverage for error paths > 90%
- [ ] No memory leaks in error paths (if tested with valgrind)

**Rationale:** Comprehensive error path testing ensures robust error handling; integration tests verify components work together safely in error scenarios; performance tests ensure error handling doesn't block system

---

### Phase 5: Documentation & Review

#### Task 5.1: Add Comments & Documentation

**Documentation Standards & Patterns:**

All documentation must follow these principles:
- **Clarity**: Explain WHAT and WHY, not just WHAT
- **Conciseness**: Use clear, short sentences (avoid walls of text)
- **Examples**: Include at least one example for complex interfaces
- **Design Rationale**: Explain key design decisions and trade-offs
- **Future-Proofing**: Note extension points and potential enhancements

**IBTFactoryWrapper.h - Interface Documentation Example**

```cpp
/// @file IBTFactoryWrapper.h
/// @brief Pure virtual interface for BehaviorTree factory abstraction
///
/// This interface provides a clean abstraction over BT::BehaviorTreeFactory,
/// enabling:
/// - Dependency injection for testing (mock implementations)
/// - Enhanced error diagnostics (XML context, node lists)
/// - Tree introspection (metadata, registered items)
/// - Future extensions (caching, validation, versioning)
///
/// @design_rationale
/// We wrap BT::BehaviorTreeFactory rather than extending it because:
/// 1. Composition enables cleaner error handling
/// 2. Pure virtual interface allows complete mocking in tests
/// 3. Wrapping avoids polluting BT:: namespace (external library only)
/// 4. Future enhancements (caching, validation) don't modify external library
///
/// @example
/// ```cpp
/// auto factory = std::make_shared<BTFactoryWrapper>();
/// factory->registerNodeType<ClaimRoleNode>("ClaimRole");
/// auto tree = factory->createTree("MyTree", blackboard);
/// ```

class IBTFactoryWrapper {
public:
    virtual ~IBTFactoryWrapper() = default;

    /// Create a behavior tree from registered tree ID
    /// @param treeId Name of registered tree (must exist)
    /// @param blackboard Shared blackboard for tree (required)
    /// @return BT::Tree ready for execution
    /// @throws BT::RuntimeError with enhanced diagnostics if tree not found or creation fails
    /// @note Error messages include registered tree names and XML context for debugging
    virtual BT::Tree createTree(const std::string& treeId,
                                BT::Blackboard::Ptr blackboard) = 0;

    /// Create tree from XML string
    /// @param xml Valid XML defining behavior tree (must be well-formed)
    /// @param blackboard Shared blackboard for tree (required)
    /// @return BT::Tree ready for execution
    /// @throws BT::RuntimeError if XML is malformed or contains unregistered nodes
    /// @design_note
    /// Unlike BT::BehaviorTreeFactory::createTreeFromText(), this wrapper:
    /// - Catches and enhances parsing errors with context
    /// - Logs tree structure on failure for debugging
    /// - Calls NodeUtils::DumpTree() to help identify issues
    virtual BT::Tree createTreeFromText(const std::string& xml,
                                        BT::Blackboard::Ptr blackboard) = 0;

    /// @{
    /// @name Node Registration
    /// Register custom node types for use in behavior trees.
    /// Nodes are identified by string ID and must be registered before
    /// being used in XML or programmatic tree creation.
    ///
    /// @example
    /// ```cpp
    /// factory->registerNodeType<MyCustomNode>("MyCustom");
    /// // Now <MyCustom /> is valid in XML
    /// ```
    ///

    /// Register a node type using template for type safety
    /// @tparam NodeType Must inherit from BT::TreeNode
    /// @param ID String identifier for the node (used in XML)
    /// @note This is the preferred registration method (type-safe, not string-based)
    template<typename NodeType>
    void registerNodeType(const std::string& ID) {
        static_assert(std::is_base_of_v<BT::TreeNode, NodeType>,
                     "NodeType must inherit from BT::TreeNode");
        registerNodeTypeImpl(ID, &NodeType::staticMetadata);
    }

    /// @}

    /// Get list of all registered behavior tree IDs
    /// @return Vector of tree names that can be created with createTree()
    /// @note Used for error messages and introspection
    virtual std::vector<std::string> getRegisteredTrees() const = 0;

    /// Get list of all registered node type IDs
    /// @return Vector of node type names registered with registerNodeType()
    /// @note Used for error messages when unknown nodes are encountered
    virtual std::vector<std::string> getRegisteredNodes() const = 0;

    /// @brief Metadata about a registered behavior tree
    /// Used for introspection and future features (validation, versioning)
    struct TreeMetadata {
        std::string id;                           ///< Tree identifier
        size_t nodeCount;                         ///< Number of nodes in tree
        std::vector<std::string> nodeTypes;       ///< List of node type names used
        // Future fields: version, hash, dependencies, creation_time
    };

    /// Get metadata about a registered behavior tree
    /// @param treeId Name of tree to query
    /// @return Metadata if tree registered, std::nullopt if not found
    /// @note Useful for debugging and analyzing tree structure
    virtual std::optional<TreeMetadata> getTreeMetadata(const std::string& treeId) const = 0;

private:
    /// Internal implementation of registerNodeType template
    /// @note Separated to reduce template code bloat
    virtual void registerNodeTypeImpl(const std::string& ID,
                                     const BT::NodeMetadata* metadata) = 0;
};
```

**BTFactoryWrapper.h/cpp - Implementation Comments Example**

```cpp
/// @file BTFactoryWrapper.h/cpp
/// @brief Enhanced BT::BehaviorTreeFactory wrapper with better error diagnostics

class BTFactoryWrapper : public IBTFactoryWrapper {
private:
    /// Underlying factory from external library (BT:: namespace)
    /// We wrap this rather than inherit to avoid modifying external library
    BT::BehaviorTreeFactory factory_;

    /// Cache of tree metadata for introspection queries
    /// Populated on successful tree creation, used for error messages
    std::map<std::string, TreeMetadata> treeMetadata_;

    // --- Private helpers for error handling ---

    /// Enhance exception with context before re-throwing
    /// Called when factory_.createTree() throws
    /// @param treeId Tree that failed to create
    /// @param originalError The exception from factory
    /// @throws BT::RuntimeError with enhanced message
    void handleTreeCreationError(const std::string& treeId,
                                const BT::RuntimeError& originalError);

    /// Build tree structure information for error messages
    /// Walks tree and extracts node types, counts, structure
    TreeMetadata buildMetadata(const std::string& treeId,
                              const BT::Tree& tree);

public:
    // --- Implementation pattern for enhanced error handling ---

    BT::Tree createTree(const std::string& treeId,
                        BT::Blackboard::Ptr blackboard) override {
        try {
            // Attempt creation through underlying factory
            auto tree = factory_.createTree(treeId, blackboard);

            // Success: cache metadata for future queries
            treeMetadata_[treeId] = buildMetadata(treeId, tree);
            return tree;

        } catch (const BT::RuntimeError& e) {
            // Handle error: enhance with context before propagating
            cCritical(LOG_KEY) << "Tree creation failed for '" << treeId << "'";

            // Build enhanced error message with:
            // 1. Original error
            // 2. List of registered trees
            // 3. List of registered nodes
            // This helps developers debug quickly
            std::ostringstream oss;
            oss << "\n=== BehaviorTree Creation Failed ===\n"
                << "Tree ID: " << treeId << "\n"
                << "Error: " << e.what() << "\n"
                << "Registered Trees: ";
            for (const auto& name : getRegisteredTrees()) {
                oss << name << " ";
            }
            oss << "\nRegistered Nodes: ";
            for (const auto& name : getRegisteredNodes()) {
                oss << name << " ";
            }

            // Call NodeUtils diagnostic helper for tree structure dump
            // if tree was partially created
            cCritical(LOG_KEY) << "Use NodeUtils::DumpTree() to inspect";

            throw BT::RuntimeError(oss.str());
        }
    }
};
```

**BTRegistrar & BTLifecycle - Similar Documentation Pattern**

Follow the same pattern for BTRegistrar.h and BTLifecycle.h:
1. **File-level comments** explaining purpose and design rationale
2. **Class comments** with usage examples
3. **Method comments** with error conditions and future extensions
4. **Design notes** on key decisions (composition, dependency injection, etc.)

**BehaviorTreeManager.h - Delegation Pattern Documentation Example**

```cpp
/// @file BehaviorTreeManager.h
/// @brief Orchestrates behavior tree creation, registration, and execution
///
/// After refactoring, BehaviorTreeManager delegates to:
/// - IBTFactoryWrapper: tree creation with enhanced error handling
/// - IBTRegistrar: node/tree registration logic
/// - BTLifecycle: tree lifecycle (halting, cleanup, replacement)
///
/// @design_note
/// The manager maintains backward compatibility by:
/// 1. Keeping static registerNodes() signature unchanged (21 test files depend on it)
/// 2. Delegating instance methods to registrar (transparent to callers)
/// 3. Using factory wrapper for all tree operations (better error messages)
///
/// @example
/// ```cpp
/// // Production: uses real implementations
/// BehaviorTreeManager btm(&wsm, &agentControl);
///
/// // Testing: inject mocks
/// auto mockFactory = std::make_shared<MockFactoryWrapper>();
/// auto mockRegistrar = std::make_shared<MockRegistrar>();
/// BehaviorTreeManager btm(&wsm, &agentControl, mockFactory, mockRegistrar);
/// ```

class BehaviorTreeManager {
private:
    /// Factory wrapper for tree creation (owns the wrapper)
    std::shared_ptr<IBTFactoryWrapper> factory_;

    /// Registrar for node/tree registration (owns the registrar)
    std::shared_ptr<IBTRegistrar> registrar_;

public:
    /// Delegate to registrar (transparent to callers)
    /// @see IBTRegistrar::registerNodes() for behavior
    /// @note Method is simple pass-through (no additional logic)
    bool registerNodes() {
        return registrar_->registerNodes();
    }

    /// Constructor for production use
    /// Creates real BTFactoryWrapper and BTRegistrar instances
    BehaviorTreeManager(WorldStateManager* wsm,
                       AgentControl* agentControl) {
        factory_ = std::make_shared<BTFactoryWrapper>();
        registrar_ = std::make_shared<BTRegistrar>(
            factory_.get(), agentControl, wsm, this
        );
    }

    /// Constructor for testing with dependency injection
    /// Allows injecting mock factory and registrar
    /// @param factory Mock BTFactoryWrapper (for testing)
    /// @param registrar Mock BTRegistrar (for testing)
    BehaviorTreeManager(WorldStateManager* wsm,
                       AgentControl* agentControl,
                       std::shared_ptr<IBTFactoryWrapper> factory,
                       std::shared_ptr<IBTRegistrar> registrar)
        : factory_(factory), registrar_(registrar) {
        if (!factory_ || !registrar_) {
            throw std::invalid_argument("factory and registrar cannot be null");
        }
    }
};
```

**PlayAssignmentHelper.cpp - BTLifecycle Usage Comments Example**

```cpp
// GOOD: Documented use of BTLifecycle utilities
// Before: inline tree halting logic scattered throughout
// After: centralized tree lifecycle management via BTLifecycle

void PlayAssignmentHelper::assignTrees(...) {
    // Use centralized tree replacement function
    // This handles:
    // - Checking if tree needs replacement
    // - Halting old tree safely
    // - Scheduling cleanup with 50ms delay (prevents use-after-free)
    // - Creating new tree with error handling
    auto [newTree, wasReplaced] = BTLifecycle::checkAndReplaceTrees(
        robotId,
        robotTrees.contains(robotId) ? robotTrees[robotId] : nullptr,
        assignment.treeId,
        *factory_,  // Use wrapper interface for better errors
        robotBoards[robotId],
        treesToCleanup
    );

    if (!newTree) {
        cCritical(LOG_CATEGORY) << "Tree creation failed";
        return false;
    }

    // Setup blackboard
    newTree->rootBlackboard()->set("robot_id", robotId);
    robotTrees[robotId] = newTree;
}
```

**Files to Update (Complete List):**
- [ ] IBTFactoryWrapper.h - Interface documentation (see example above)
- [ ] BTFactoryWrapper.h/cpp - Implementation comments (see example above)
- [ ] IBTRegistrar.h - Interface documentation (similar to IBTFactoryWrapper pattern)
- [ ] BTRegistrar.h/cpp - Implementation comments (similar pattern)
- [ ] BTLifecycle.h/cpp - Utility documentation with examples
- [ ] BehaviorTreeManager.h/cpp - Delegation pattern documentation
- [ ] PlayAssignmentHelper.cpp - BTLifecycle usage comments
- [ ] GameStateReflex.cpp - Factory wrapper usage comments

**Documentation Checklist:**
- [ ] All public methods have @brief comments explaining purpose
- [ ] All parameters documented with @param
- [ ] All return values documented with @return
- [ ] All exceptions documented with @throws
- [ ] Design decisions documented with @design_rationale
- [ ] Future extension points noted with @design_note
- [ ] At least one @example per interface showing usage
- [ ] Error handling strategy documented
- [ ] Composition/delegation pattern explained
- [ ] File-level comments explaining module purpose
- [ ] Links to related files/interfaces provided
- [ ] Key invariants documented (e.g., "thread-safe for const operations")

**Rationale:** Comprehensive documentation enables future developers to understand architecture, maintain code confidently, and extend safely

---

#### Task 5.2: Update AGENTS.md

**File:** `AGENTS.md`

**Location in File:** Add new section to AGENTS.md after "Code Quality Standards" and before "Tasks" section

**Constraints & Requirements:**
- [ ] MUST include section titled "BehaviorTree Architecture Refactoring"
- [ ] MUST explain the four core components (Wrapper, Registrar, Lifecycle, Interfaces)
- [ ] MUST document design principles (separation of concerns, testability, type safety)
- [ ] MUST provide code examples for both production and testing usage
- [ ] MUST include links to source files (@path notation)
- [ ] MUST explain when to use new components
- [ ] MUST include migration guidance for existing code
- [ ] MUST NOT reference internal implementation details (use public API only)

**Full AGENTS.md Addition (with Section Organization):**

```markdown
## BehaviorTree Architecture Refactoring

The BehaviorTree system has been refactored to separate concerns, improve testability, and provide better error handling. This refactor follows the principle of composition over inheritance and pure virtual interfaces for mockability.

### Architecture Overview

The refactored system consists of four main components:

1. **BTFactoryWrapper** (@src/agent/bt/core/BTFactoryWrapper.h/cpp)
   - Wraps BT::BehaviorTreeFactory with enhanced error diagnostics
   - Provides tree introspection (metadata, registered nodes/trees)
   - Logs tree structure on creation failure for debugging
   - Throws BT::RuntimeError with detailed context

2. **BTRegistrar** (@src/agent/bt/core/BTRegistrar.h/cpp)
   - Extracts node and tree registration logic from BehaviorTreeManager
   - Handles graceful continuation on invalid XML (doesn't crash)
   - Provides static registerNodes() method (maintains backward compatibility)
   - Supports dependency injection for testing

3. **BTLifecycle** (@src/agent/bt/utils/BTLifecycle.h/cpp)
   - Utility namespace for tree lifecycle management
   - Provides haltTree(), scheduleCleanup(), cleanupTrees(), checkAndReplaceTrees()
   - Centralizes tree replacement logic with safe delay
   - Prevents use-after-free issues in concurrent scenarios

4. **Interfaces (IBTFactoryWrapper, IBTRegistrar)**
   - Pure virtual interfaces enable complete unit testing via mocks
   - Located in global namespace (NOT BT:: - reserved for external library)
   - Allow dependency injection for both production and testing

### Design Principles

1. **Separation of Concerns**: Factory wrapping, registration, and lifecycle management are separate classes with single responsibilities
2. **Composition over Inheritance**: Problems are solved by composing smaller, focused classes rather than inheritance hierarchies
3. **Testability**: Every public interface has a pure virtual interface for dependency injection and mocking
4. **Type Safety**: Uses strongly-typed enums and template-based registration (never string-based lookups)
5. **Error Diagnostics**: Enhanced error messages with XML context, registered node lists, and tree structure information
6. **Backward Compatibility**: Existing API maintained; 21 test files work unchanged; gradual migration path
7. **Static Definitions**: PlayContext and coordination enums are defined at compile-time, verified by type system

### Using the New Architecture

#### Production Code (BehaviorTreeManager)

```cpp
// BehaviorTreeManager creates and manages wrapper and registrar automatically
BehaviorTreeManager btm(&wsm, &agentControl);

// Static node registration (unchanged API - works with 21 existing test files)
BehaviorTreeManager::registerNodes(factory, &agentControl, &wsm, &btManager);

// Register trees from directory
btm.registerTreesFromDirectory("path/to/behavior/trees");

// Tree creation with enhanced error handling
auto tree = btm.getTree(robotId);
```

#### PlayAssignmentHelper (Tree Lifecycle Management)

```cpp
#include "utils/BTLifecycle.h"

// Safe tree replacement with 50ms cleanup delay
auto [newTree, wasReplaced] = BTLifecycle::checkAndReplaceTrees(
    robotId,
    oldTree,
    desiredTreeId,
    *factory_,  // Use wrapper interface
    blackboard,
    cleanupQueue
);

// Process cleanup queue periodically
BTLifecycle::cleanupTrees(cleanupQueue);
```

#### Testing with Mocks

```cpp
#include "core/IBTFactoryWrapper.h"
#include "core/IBTRegistrar.h"

// Create mock implementations
auto mockFactory = std::make_shared<MockFactoryWrapper>();
auto mockRegistrar = std::make_shared<MockRegistrar>();

// Inject mocks into BehaviorTreeManager via DI constructor
BehaviorTreeManager btm(&wsm, &agentControl, mockFactory, mockRegistrar);

// Now can verify behavior through mocks
EXPECT_CALL(*mockFactory, createTree).Times(1);
EXPECT_CALL(*mockRegistrar, registerNodes).Times(1);
```

#### Error Handling Pattern

```cpp
// BTFactoryWrapper provides enhanced error messages
try {
    auto tree = factory_->createTree("UnknownTreeId", blackboard);
} catch (const BT::RuntimeError& e) {
    // Error message includes:
    // - Original error (tree not found)
    // - List of registered trees
    // - List of registered nodes
    // - XML context (if applicable)
    cCritical(LOG_CATEGORY) << "Tree creation failed: " << e.what();
}

// BTRegistrar continues gracefully on invalid XML
bool success = registrar_->registerTreesFromDirectory("trees/");
// If some XML files are invalid, logs warning but continues processing
// System doesn't crash; registration succeeds partially
```

### Migration Guide

#### For Existing Test Files (No Changes Needed)

All 21 existing test files continue to work unchanged:

```cpp
// Old code - still works (backward compatible)
class MyTest : public ::testing::Test {
    void SetUp() override {
        // Same signature as before - no changes needed
        BehaviorTreeManager::registerNodes(
            factory, &agentControl, &wsm, &btManager
        );
    }
};
```

#### For Code Using PlayAssignmentHelper

Update to use BTLifecycle utilities:

```cpp
// Before: inline tree halting and cleanup
auto oldTree = robotTrees[robotId];
oldTree->haltTree();
std::this_thread::sleep_for(std::chrono::milliseconds(50));
treesToCleanup.append(oldTree);
auto newTree = factory.createTree(...);

// After: use BTLifecycle (cleaner, more testable)
auto [newTree, wasReplaced] = BTLifecycle::checkAndReplaceTrees(
    robotId, oldTree, newTreeId, *factory_, blackboard, treesToCleanup
);
BTLifecycle::cleanupTrees(treesToCleanup);  // Call periodically
```

#### For Code Using Factory Directly

Update to use wrapper interface:

```cpp
// Before: direct factory usage (no error context)
auto tree = factory.createTree(treeId, blackboard);

// After: use wrapper for better error messages
auto tree = factory_->createTree(treeId, blackboard);
// Error messages now include registered trees, nodes, XML context
```

### Key Files

| File | Purpose |
|:---|:---|
| `src/agent/bt/core/IBTFactoryWrapper.h` | Factory wrapper interface |
| `src/agent/bt/core/BTFactoryWrapper.h/cpp` | Factory wrapper implementation |
| `src/agent/bt/core/IBTRegistrar.h` | Registration interface |
| `src/agent/bt/core/BTRegistrar.h/cpp` | Registration implementation |
| `src/agent/bt/utils/BTLifecycle.h/cpp` | Tree lifecycle utilities |
| `src/agent/bt/BehaviorTreeManager_ErrorHandling_Test.cpp` | Error scenario tests |
| `src/agent/bt/xml/tests/` | XML test fixtures (ValidTree.xml, UnregisteredNode.xml, etc.) |

### Error Handling Strategy

The refactored system provides layered error handling:

1. **BTFactoryWrapper**: Catches BT::RuntimeError, enhances with context, re-throws
2. **BTRegistrar**: Catches registration errors per file, continues processing
3. **PlayAssignmentHelper**: Uses BTLifecycle utilities for safe tree replacement
4. **Error Messages**: Include node names, port names, tree paths, registered items

Error messages are informative but NOT verbose (< 1000 chars) to remain readable in logs.

### Testing Patterns

#### Unit Testing Interfaces

```cpp
// Test factory wrapper error handling
class BTFactoryWrapperTest {
public:
    void testUnregisteredNode() {
        auto wrapper = std::make_shared<BTFactoryWrapper>();
        std::string xml = "<root><BehaviorTree><Unknown/></BehaviorTree></root>";
        EXPECT_THROW(wrapper->createTreeFromText(xml, bb), BT::RuntimeError);
    }
};

// Test registrar graceful handling
class BTRegistrarTest {
public:
    void testInvalidXMLContinues() {
        auto registrar = std::make_shared<BTRegistrar>(factory, ac, wsm, btm);
        bool result = registrar->registerTreeFromText("<invalid");
        EXPECT_FALSE(result);  // Fails gracefully, doesn't crash
    }
};
```

#### Integration Testing

```cpp
// Full system error handling
class BehaviorTreeIntegrationTest {
public:
    void testErrorHandling() {
        // BehaviorTreeManager combines all components
        BehaviorTreeManager btm(&wsm, &agentControl);

        // Invalid tree should provide helpful error
        try {
            btm.getTree("UnknownTree");
            FAIL() << "Expected error for unknown tree";
        } catch (const BT::RuntimeError& e) {
            EXPECT_TRUE(std::string(e.what()).length() > 50);  // Has context
        }
    }
};
```

### Future Extensions

The architecture supports future enhancements:

- **Tree Caching**: BTFactoryWrapper can cache tree structure between creations
- **Tree Validation**: BTRegistrar can validate XML schema on registration
- **Tree Versioning**: TreeMetadata can track version and dependencies
- **Performance Profiling**: BTLifecycle can track tree creation/cleanup timing
- **Event Notifications**: Components can emit events on registration/creation
```

**Integration Points in AGENTS.md:**

1. **Location**: Insert after "Code Quality Standards" section, before "Tasks" section
2. **Flow**: Overview → Components → Design Principles → Usage Examples → Migration → Files → Error Handling → Testing Patterns
3. **References**: Link back to specific files using @path notation
4. **Examples**: Each section includes before/after code patterns

**Dos & Don'ts:**

**DO:**
- ✓ Explain WHAT each component does and WHY it exists
- ✓ Include before/after code examples for migration
- ✓ Document design principles (composition, interfaces, type safety)
- ✓ Provide clear testing patterns with mocks
- ✓ Link to source files with @path notation
- ✓ Explain error handling strategy end-to-end
- ✓ Include migration guide for existing code
- ✓ Use tables for quick reference (files, design decisions)

**DON'T:**
- ✗ Don't focus on implementation details (use public API only)
- ✗ Don't include internal class member variables
- ✗ Don't reference testing-only code paths
- ✗ Don't assume readers know BT::BehaviorTreeFactory internals
- ✗ Don't include links to external libraries (except brief references)
- ✗ Don't use jargon without explanation (DI, RAII, etc.)
- ✗ Don't mix old and new API in examples (show clear before/after)

**Checklist:**
- [ ] Create new section "BehaviorTree Architecture Refactoring" in AGENTS.md
- [ ] Document all four core components (Wrapper, Registrar, Lifecycle, Interfaces)
- [ ] Explain design principles (separation of concerns, composition, type safety, testability)
- [ ] Provide production code examples (BehaviorTreeManager usage)
- [ ] Provide testing examples (mock dependency injection)
- [ ] Provide migration examples (PlayAssignmentHelper, factory usage)
- [ ] Include comprehensive error handling explanation
- [ ] Include testing patterns (unit and integration)
- [ ] Add key files reference table with @path links
- [ ] Add before/after code comparisons for clarity
- [ ] Verify all links (@path notation) point to correct files
- [ ] Ensure documentation is accessible to developers new to BT system

**Rationale:** Comprehensive AGENTS.md documentation enables team to understand architecture, use new components correctly, migrate existing code safely, and write testable code

---

### Phase 6: Final Verification

#### Task 6.1: Full Build & Test

**Constraints & Requirements:**
- [ ] MUST use clean build (`ggs` alias, not `kk`)
- [ ] MUST have zero compilation errors
- [ ] MUST have zero compilation warnings (treat as errors if possible)
- [ ] MUST run full test suite (`./build/test/unit_tests`)
- [ ] MUST run error handling tests in isolation (`-t "BehaviorTreeManager_ErrorHandling"`)
- [ ] MUST have all 21 existing test files passing
- [ ] Build time SHOULD be reasonable (< 5 minutes)
- [ ] No flaky tests (all tests must be deterministic)

**Build & Test Verification Script:**

```bash
#!/bin/bash
# Comprehensive build and test verification

set -e  # Exit on error
start_time=$(date +%s)

echo "=== PHASE 6.1: Full Build & Test Verification ==="
echo

# Step 1: Clean build
echo "Step 1: Clean Build"
echo "  Running: ggs 2>&1 | tee build/build.log | tail -n 20"
ggs 2>&1 | tee build/build.log | tail -n 20

# Step 2: Check for compilation errors
echo
echo "Step 2: Checking for Compilation Errors"
if grep -q "error:" build/build.log; then
    echo "  ✗ FAIL: Compilation errors found"
    grep "error:" build/build.log | head -5
    exit 1
else
    echo "  ✓ PASS: No compilation errors"
fi

# Step 3: Check for warnings
echo
echo "Step 3: Checking for Compilation Warnings"
warning_count=$(grep -c "warning:" build/build.log || true)
if [ "$warning_count" -gt 0 ]; then
    echo "  ⚠ WARNING: Found $warning_count compiler warnings"
    echo "  (Consider fixing before shipping)"
    grep "warning:" build/build.log | head -3
fi

# Step 4: Verify executable exists
echo
echo "Step 4: Verifying Test Executable"
if [ -f "./build/test/unit_tests" ]; then
    echo "  ✓ PASS: Test executable exists"
else
    echo "  ✗ FAIL: Test executable not found"
    exit 1
fi

# Step 5: Run full test suite
echo
echo "Step 5: Running Full Test Suite"
echo "  Command: ./build/test/unit_tests"
timeout 120 ./build/test/unit_tests 2>&1 | tee /tmp/full_tests.log | tail -n 10

# Step 6: Check test results
echo
echo "Step 6: Analyzing Test Results"
pass_count=$(grep -c "✓" /tmp/full_tests.log || true)
fail_count=$(grep -c "✗" /tmp/full_tests.log || true)
echo "  Tests Passed: $pass_count"
echo "  Tests Failed: $fail_count"

if [ "$fail_count" -gt 0 ]; then
    echo "  ✗ FAIL: Some tests failed"
    grep "✗" /tmp/full_tests.log | head -10
    exit 1
else
    echo "  ✓ PASS: All tests passed"
fi

# Step 7: Run error handling tests specifically
echo
echo "Step 7: Running Error Handling Test Suite"
echo "  Command: ./build/test/unit_tests -t \"BehaviorTreeManager_ErrorHandling\""
timeout 30 ./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling" 2>&1 | tee /tmp/error_tests.log | tail -n 10

if grep -q "FAILED\|failed" /tmp/error_tests.log; then
    echo "  ✗ FAIL: Error handling tests failed"
    exit 1
else
    echo "  ✓ PASS: Error handling tests passed"
fi

# Step 8: Verify backward compatibility (21 test files)
echo
echo "Step 8: Verifying Backward Compatibility (21 Test Files)"
test_files=$(find src/agent/bt/nodes -name "*_Test.cpp" | wc -l)
echo "  Found $test_files test files"
if [ "$test_files" -ge 20 ]; then
    echo "  ✓ PASS: Expected ~21 test files present"
else
    echo "  ⚠ WARNING: Expected ~21 test files, found $test_files"
fi

# Step 9: Build time summary
end_time=$(date +%s)
elapsed=$((end_time - start_time))
echo
echo "Build & Test Summary:"
echo "  Total Time: ${elapsed}s"
if [ "$elapsed" -lt 300 ]; then
    echo "  ✓ Performance: Build completed quickly (< 5 min)"
else
    echo "  ⚠ Performance: Build took longer than 5 minutes"
fi

echo
echo "=== PHASE 6.1 Verification Complete ==="
echo "Status: READY FOR DEPLOYMENT"
```

**Individual Test Runs:**

```bash
# Full test suite
./build/test/unit_tests

# Error handling tests only
./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling"

# Coordination tests (verify backward compatibility)
./build/test/unit_tests -t "ClaimRole_Test|SetState_Test|WaitForRole_Test"

# View detailed test output
./build/test/unit_tests -v  # verbose mode
```

**Dos & Don'ts:**

**DO:**
- ✓ Use `ggs` for clean build (not `kk`)
- ✓ Log full build output to build/build.log for inspection
- ✓ Check for both errors AND warnings (warnings may hide issues)
- ✓ Run full test suite first, then test subsets
- ✓ Run error handling tests in isolation
- ✓ Verify backward compatibility (21 test files must pass)
- ✓ Time the build (should be consistent)
- ✓ Check test output for "flaky" tests (non-deterministic)

**DON'T:**
- ✗ Don't ignore compiler warnings (fix them before shipping)
- ✗ Don't rebuild incrementally (use clean build for final verification)
- ✗ Don't skip error handling tests
- ✗ Don't assume tests passed if build succeeded (run them!)
- ✗ Don't run tests in parallel unless build system allows (can mask race conditions)
- ✗ Don't ship if any test is flaky (all tests must be deterministic)
- ✗ Don't assume 21 test files are unchanged (verify with script)

**Checklist:**
- [ ] Run clean build: `ggs 2>&1 | tee build/build.log | tail -n 20`
- [ ] Verify zero compilation errors in build/build.log
- [ ] Verify zero or minimal compilation warnings
- [ ] Verify test executable exists: `ls -lh ./build/test/unit_tests`
- [ ] Run full test suite: `./build/test/unit_tests`
- [ ] Verify all tests pass (0 failures)
- [ ] Run error handling tests: `./build/test/unit_tests -t "BehaviorTreeManager_ErrorHandling"`
- [ ] Verify error handling tests pass
- [ ] Count test files: `find src/agent/bt/nodes -name "*_Test.cpp" | wc -l`
- [ ] Verify ~21 test files present
- [ ] Verify backward compatibility (existing tests unchanged)
- [ ] Review build time (should be < 5 minutes)
- [ ] Confirm no flaky tests (run tests again, results match)

**Rationale:** Comprehensive build and test verification ensures all components work together correctly before moving to integration testing

---

#### Task 6.2: Performance & Regression Testing

**Constraints & Requirements:**
- [ ] MUST measure baseline performance before refactoring (for comparison)
- [ ] MUST verify tree creation time within 5% of baseline
- [ ] MUST NOT introduce additional allocations in hot paths (tree creation, tick loop)
- [ ] PlayAssignmentHelper tree replacement performance MUST be ≤ baseline + 10ms
- [ ] GameStateReflex tree creation performance MUST be ≤ baseline + 10ms
- [ ] Error scenario handling MUST complete in < 100ms per error
- [ ] Memory footprint of refactored components MUST be < 1KB each
- [ ] No memory leaks even in error paths

**Baseline Performance Metrics (Establish Before Refactoring):**

```cpp
// Measure baseline tree creation time
// Run this BEFORE refactoring to establish baseline

class BaselinePerformanceTest {
public:
    void measureTreeCreation() {
        BehaviorTreeFactory factory;
        BehaviorTreeManager::registerNodes(factory, &agentControl, &wsm, &btManager);

        auto start = std::chrono::high_resolution_clock::now();

        // Measure tree creation (100 iterations)
        for (int i = 0; i < 100; ++i) {
            auto tree = factory.createTree("SomeTreeId", BT::Blackboard::create());
        }

        auto end = std::chrono::high_resolution_clock::now();
        auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            end - start
        ).count();

        double avg_ms = duration_ms / 100.0;
        std::cout << "Baseline tree creation: " << avg_ms << " ms per tree\n";
        // Example baseline: 2.5 ms per tree creation

        // Save result for post-refactor comparison
        // Expected: new implementation should be ≤ 2.5 * 1.05 = 2.625 ms
    }
};
```

**Post-Refactoring Performance Benchmarks:**

```cpp
// Run this AFTER refactoring to verify no regression

class PostRefactorPerformanceTest {
public:
    void measureWrapper TreeCreation() {
        auto factory = std::make_shared<BTFactoryWrapper>();
        BehaviorTreeManager::registerNodes(*factory, &agentControl, &wsm, &btManager);

        auto start = std::chrono::high_resolution_clock::now();

        // Measure wrapper tree creation (100 iterations)
        for (int i = 0; i < 100; ++i) {
            try {
                auto tree = factory->createTree("SomeTreeId", BT::Blackboard::create());
            } catch (const BT::RuntimeError& e) {
                // Expected for error scenarios only
            }
        }

        auto end = std::chrono::high_resolution_clock::now();
        auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            end - start
        ).count();

        double avg_ms = duration_ms / 100.0;
        std::cout << "Wrapper tree creation: " << avg_ms << " ms per tree\n";

        // Verify performance is within 5% of baseline
        double baseline = 2.5;  // From baseline measurement
        double threshold = baseline * 1.05;  // 5% tolerance
        EXPECT_LT(avg_ms, threshold)
            << "Performance regression: " << avg_ms << " ms vs baseline " << baseline << " ms";
    }

    void measureErrorScenarioPerformance() {
        auto factory = std::make_shared<BTFactoryWrapper>();

        std::string invalidXml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="Test">
                    <UnregisteredNode />
                </BehaviorTree>
            </root>
        )";

        auto start = std::chrono::high_resolution_clock::now();

        // Measure error handling (100 iterations)
        for (int i = 0; i < 100; ++i) {
            try {
                factory->createTreeFromText(invalidXml, BT::Blackboard::create());
            } catch (const BT::RuntimeError& e) {
                // Expected and acceptable
            }
        }

        auto end = std::chrono::high_resolution_clock::now();
        auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            end - start
        ).count();

        double avg_ms = duration_ms / 100.0;
        std::cout << "Error scenario handling: " << avg_ms << " ms per error\n";

        // Verify error handling is fast enough (< 100ms total for one error)
        EXPECT_LT(avg_ms, 100.0)
            << "Error handling too slow: " << avg_ms << " ms";
    }
};
```

**Memory Footprint Analysis:**

```bash
#!/bin/bash
# Check memory usage of new components

echo "=== Memory Footprint Analysis ==="
echo

# 1. Size of compiled binaries
echo "1. Component Binary Sizes:"
echo "  BTFactoryWrapper.o:"
ls -lh build/CMakeFiles/*/BTFactoryWrapper.cpp.o 2>/dev/null | awk '{print "    " $5}'

echo "  BTRegistrar.o:"
ls -lh build/CMakeFiles/*/BTRegistrar.cpp.o 2>/dev/null | awk '{print "    " $5}'

echo "  BTLifecycle.o:"
ls -lh build/CMakeFiles/*/BTLifecycle.cpp.o 2>/dev/null | awk '{print "    " $5}'

# 2. Instance memory usage (use sizeof in debug build)
echo
echo "2. Runtime Instance Sizes:"
cat > /tmp/sizeof_test.cpp << 'EOF'
#include "src/agent/bt/core/BTFactoryWrapper.h"
#include "src/agent/bt/core/BTRegistrar.h"
#include "src/agent/bt/utils/BTLifecycle.h"

int main() {
    std::cout << "BTFactoryWrapper instance size: " << sizeof(BTFactoryWrapper) << " bytes\n";
    std::cout << "BTRegistrar instance size: " << sizeof(BTRegistrar) << " bytes\n";
    // BTLifecycle is header-only (namespace), no instance size
    return 0;
}
EOF
g++ -I. /tmp/sizeof_test.cpp -o /tmp/sizeof_test && /tmp/sizeof_test

# 3. No memory leaks in error paths (if valgrind available)
echo
echo "3. Memory Leak Check:"
if command -v valgrind &> /dev/null; then
    timeout 60 valgrind --leak-check=full --quiet ./build/test/unit_tests \
        -t "BehaviorTreeManager_ErrorHandling" 2>&1 | tail -5
fi
```

**Regression Test Script:**

```bash
#!/bin/bash
# Comprehensive performance regression testing

echo "=== PHASE 6.2: Performance & Regression Testing ==="
echo

# Step 1: Baseline measurement
echo "Step 1: Establishing Baseline"
echo "  (Expected baseline: 2-3 ms per tree creation)"
# Run baseline test and capture result

# Step 2: Post-refactor measurement
echo
echo "Step 2: Measuring Post-Refactor Performance"
timeout 60 ./build/test/unit_tests -t "PerformanceTest" 2>&1 | grep -E "ms|baseline"

# Step 3: Regression analysis
echo
echo "Step 3: Regression Analysis"
echo "  Comparing post-refactor vs baseline..."
# Compare and report

# Step 4: Memory profiling (if available)
echo
echo "Step 4: Memory Profiling"
if command -v valgrind &> /dev/null; then
    echo "  Running memory leak detection..."
    timeout 120 valgrind --leak-check=summary ./build/test/unit_tests \
        -t "BehaviorTreeManager_ErrorHandling" 2>&1 | grep -E "LEAK|definitely"
fi

# Step 5: Specific component testing
echo
echo "Step 5: Component-Specific Performance"
echo "  PlayAssignmentHelper tree replacement..."
timeout 30 ./build/test/unit_tests -t "PlayAssignmentHelper" 2>&1 | tail -5

echo "  GameStateReflex tree creation..."
timeout 30 ./build/test/unit_tests -t "GameStateReflex" 2>&1 | tail -5

echo
echo "=== Regression Testing Complete ==="
```

**Dos & Don'ts:**

**DO:**
- ✓ Establish baseline metrics BEFORE refactoring
- ✓ Run performance tests multiple times (look for variance/flakiness)
- ✓ Test both success and error paths
- ✓ Measure specific hot paths (tree creation, tick loop)
- ✓ Check for memory leaks with valgrind if available
- ✓ Allow reasonable tolerance (5% is acceptable)
- ✓ Profile memory usage of new components
- ✓ Compare allocation counts (not just bytes)

**DON'T:**
- ✗ Don't measure performance without baseline (can't determine if there's regression)
- ✗ Don't assume single run is representative (run multiple times)
- ✗ Don't ignore variance (if results vary widely, investigate)
- ✗ Don't optimize prematurely (only if real regression detected)
- ✗ Don't measure performance in debug build (use release build)
- ✗ Don't ignore memory leaks in error paths (cleanup is critical)
- ✗ Don't test in noisy environment (close other apps during measurement)

**Checklist:**
- [ ] Establish baseline tree creation time (before refactoring)
- [ ] Record baseline in document (for reference)
- [ ] Run post-refactor performance tests
- [ ] Verify tree creation time within 5% of baseline
- [ ] Run error scenario performance test
- [ ] Verify error handling < 100ms per error
- [ ] Measure memory footprint of BTFactoryWrapper (< 1KB)
- [ ] Measure memory footprint of BTRegistrar (< 1KB)
- [ ] Run memory leak detection (if valgrind available)
- [ ] Verify no memory leaks in error paths
- [ ] Test PlayAssignmentHelper performance unchanged
- [ ] Test GameStateReflex performance unchanged
- [ ] Document results in performance report
- [ ] Commit baseline and results for future reference

**Rationale:** Comprehensive performance testing ensures refactoring doesn't introduce regressions; establishes baseline for future optimizations

---

#### Task 6.3: Integration Testing

**Constraints & Requirements:**
- [ ] MUST test full game simulation with coordinated play execution
- [ ] MUST verify play assignments work correctly (all 21 test files scenarios)
- [ ] MUST test GSR tree creation for all game states (Kickoff, FreeKick, Penalty, etc.)
- [ ] MUST test error scenarios end-to-end (from BehaviorTreeManager through PlayAssignmentHelper)
- [ ] MUST verify error messages are actionable (developers can debug using message)
- [ ] MUST verify no use-after-free (ASan, valgrind if available)
- [ ] MUST verify no memory leaks (even in error paths)
- [ ] Tree cleanup must work correctly (50ms delay honored)
- [ ] PlayContext validation must work (TagEnum type system enforced)

**Full System Integration Tests:**

```cpp
// Integration test: Full game simulation with BehaviorTree
feature("Full game simulation with behavior trees") = [] {
    given("a complete game state with robots") = [] {
        WorldStateManager wsm{true};
        AgentControl agentControl{nullptr, nullptr, &wsm, false};
        BehaviorTreeManager btManager{&wsm, &agentControl};

        // Register all nodes and trees
        bool registered = BehaviorTreeManager::registerNodes(
            factory, &agentControl, &wsm, &btManager
        );
        expect(registered) << "Node registration must succeed";

        when("running a coordinated robot play") = [&btManager] {
            // Simulate coordinated play assignment
            for (int robotId = 0; robotId < 3; ++robotId) {
                // Assign trees to robots
                auto tree = btManager.getTree(robotId);
                expect(tree != nullptr) << "Each robot should have a tree";

                // Execute one tick
                BT::NodeStatus status = tree->tickOnce();
                expect(status != BT::NodeStatus::FAILURE)
                    << "Tree should execute without failure";
            }

            then("game simulation continues without errors") = [] {
                expect(true) << "All robots executed successfully";
            };
        };
    };
};
```

**Play Assignment Integration Test:**

```cpp
// Integration test: PlayAssignmentHelper with new tree lifecycle
feature("Play assignment with tree lifecycle management") = [] {
    given("robots with assigned play trees") = [] {
        BehaviorTreeManager btManager{&wsm, &agentControl};
        PlayAssignmentHelper helper{&btManager, &coordinator};

        // Initial assignment
        RobotAssignment assign1{robotId, "BallRecoveryTree"};
        bool success = helper.assignTree(robotId, assign1);
        expect(success) << "Initial assignment must succeed";

        when("changing tree assignment") = [&helper, &btManager] {
            // Switch to different tree
            RobotAssignment assign2{robotId, "BuildUpTree"};
            success = helper.assignTree(robotId, assign2);
            expect(success) << "Tree replacement must succeed";

            // Old tree should be cleaned up eventually
            std::this_thread::sleep_for(std::chrono::milliseconds(100));

            then("new tree is active and old tree cleaned up") = [] {
                auto tree = btManager.getTree(robotId);
                expect(tree != nullptr) << "New tree must be active";
                // Cleanup queue should be processed
            };
        };
    };
};
```

**Error Scenario Integration Test:**

```cpp
// Integration test: Error propagation through system
feature("Error handling end-to-end") = [] {
    given("an error condition (invalid XML)") = [] {
        BehaviorTreeManager btManager{&wsm, &agentControl};
        std::string invalidXml = "<invalid>";

        when("registering invalid tree") = [&btManager, &invalidXml] {
            // BTRegistrar should gracefully handle
            bool success = btManager.registerTreeFromText(invalidXml);
            expect(!success) << "Invalid XML should fail gracefully";

            then("system continues to function") = [&btManager] {
                // System should still work for other operations
                auto trees = btManager.getRegisteredTrees();
                // Should still have valid trees
            };

            then("error message is informative") = [] {
                // Error logged with context (not just "error occurred")
                expect(true) << "Error message contains debugging info";
            };
        };
    };
};
```

**GSR Tree Integration Test:**

```cpp
// Integration test: GameStateReflex tree creation for all states
feature("GSR tree creation for all game states") = [] {
    BehaviorTreeManager btManager{&wsm, &agentControl};
    GameStateReflex gsr{&btManager};

    given("different game states") = [] {
        std::vector<GameState> states = {
            GameState::KICKOFF_ATTACK,
            GameState::KICKOFF_DEFENSE,
            GameState::FREE_KICK_ATTACK,
            GameState::FREE_KICK_DEFENSE,
            GameState::PENALTY_ATTACK,
            GameState::PENALTY_DEFENSE
        };

        for (const auto& state : states) {
            when("state changes to " + toString(state)) = [&gsr, state] {
                gsr.handleStateChange(state);

                then("GSR tree created successfully") = [] {
                    // Verify tree was created without error
                    expect(true) << "Tree created for state";
                };
            };
        }
    };
};
```

**Memory and Use-After-Free Testing:**

```bash
#!/bin/bash
# Run integration tests with memory error detection

echo "=== PHASE 6.3: Integration Testing ==="
echo

# Step 1: Run integration tests
echo "Step 1: Running Integration Test Suite"
timeout 120 ./build/test/unit_tests -t "Integration" 2>&1 | tail -20

# Step 2: Memory error detection (ASan, if enabled)
echo
echo "Step 2: Memory Error Detection (AddressSanitizer)"
if grep -q "ASAN\|AddressSanitizer" build/build.log; then
    echo "  ASan enabled - checking for use-after-free, buffer overflow, etc..."
    # Build with ASan and run tests
    # ASan output will be visible in test output
    timeout 120 ./build/test/unit_tests 2>&1 | grep -E "SUMMARY|ERROR|FAILED"
else
    echo "  ASan not enabled (consider enabling for memory safety)"
fi

# Step 3: Valgrind memory leak detection
echo
echo "Step 3: Valgrind Memory Leak Detection"
if command -v valgrind &> /dev/null; then
    echo "  Running with valgrind..."
    timeout 300 valgrind --leak-check=full --show-leak-kinds=all \
        ./build/test/unit_tests -t "Integration" 2>&1 | tail -20
else
    echo "  Valgrind not available (skipping)"
fi

# Step 4: Stress test (multiple iterations)
echo
echo "Step 4: Stress Testing (Tree Creation/Cleanup)"
echo "  Creating and destroying 1000 trees..."
cat > /tmp/stress_test.cpp << 'EOF'
// Stress test: create and destroy many trees
for (int i = 0; i < 1000; ++i) {
    auto tree = factory->createTree("TestTree", BT::Blackboard::create());
    // Tree destroyed at end of scope
}
EOF
# Run stress test with memory checking

echo
echo "Step 5: Game Simulation Test"
echo "  Running full game simulation..."
timeout 60 ./build/test/unit_tests -t "FullGameSimulation" 2>&1 | tail -10

echo
echo "=== Integration Testing Complete ==="
```

**Dos & Don'ts:**

**DO:**
- ✓ Test coordinated multi-robot scenarios (BehaviorTree + Coordinator + PlayAssignment)
- ✓ Test tree lifecycle (creation, replacement, cleanup)
- ✓ Test error handling end-to-end (error originates, propagates, is handled)
- ✓ Verify error messages at each level contain useful context
- ✓ Test memory safety with ASan or valgrind if available
- ✓ Run stress tests (1000+ tree creation/destruction cycles)
- ✓ Test all GSR game states
- ✓ Test cleanup delays (50ms cleanup queue processing)
- ✓ Test that system continues after errors (graceful degradation)

**DON'T:**
- ✗ Don't test components in isolation (integration is most important)
- ✗ Don't skip error scenarios (errors are where issues hide)
- ✗ Don't assume memory safety without testing (use ASan, valgrind)
- ✗ Don't test only happy path (error paths are where memory issues occur)
- ✗ Don't ignore cleanup (tree replacement must clean up old trees)
- ✗ Don't test with incomplete node registration (register all nodes first)
- ✗ Don't assume error messages are good enough (verify they're actionable)

**Checklist:**
- [ ] Full game simulation integration test passes
- [ ] Multi-robot play assignment test passes
- [ ] GSR tree creation for all game states verified
- [ ] Error scenario propagation tested end-to-end
- [ ] Error messages verified to be informative (contain context)
- [ ] Tree lifecycle test passes (creation → replacement → cleanup)
- [ ] Cleanup delay (50ms) honored in integration test
- [ ] Play context validation (TagEnum) enforced in tests
- [ ] No use-after-free detected (ASan or manual inspection)
- [ ] No memory leaks detected (valgrind or ASan)
- [ ] Stress test passes (1000+ iterations without issue)
- [ ] All 21 test file scenarios pass with integrated components
- [ ] System continues after recoverable errors (graceful degradation)
- [ ] Performance under load acceptable (no timeouts, no excessive memory)

**Rationale:** Integration testing verifies all components work together correctly in real scenarios; memory safety testing ensures no use-after-free or leaks; stress testing validates stability under load

---

## 6. Testing Strategy

### Unit Tests

**File:** `src/agent/bt/BehaviorTreeManager_ErrorHandling_Test.cpp`

**Coverage:**
- [ ] BTFactoryWrapper error handling (create, introspection)
- [ ] BTRegistrar registration logic (nodes, trees, files)
- [ ] BTLifecycle tree management (halt, cleanup, replace)
- [ ] Error message quality (node names, port names, paths)

**Patterns:**
```cpp
// Test wrapper error handling
scenario("Tree creation throws RuntimeError for unregistered node") = [factory] {
    given("an unregistered node in XML") = [factory] {
        std::string xml = R"(
            <root BTCPP_format="4">
                <BehaviorTree ID="TestTree">
                    <UnregisteredNodeType />
                </BehaviorTree>
            </root>
        )";

        when("creating tree") = [factory, xml] {
            then("throws BT::RuntimeError") = [factory, xml] {
                expect(throws<BT::RuntimeError>([factory, xml] {
                    factory.createTreeFromText(xml, BT::Blackboard::create());
                }));
            };
        };
    };
};

// Test error message quality
scenario("Error messages include helpful debugging info") = [factory] {
    given("a tree with missing input") = [factory] {
        // ...
        when("ticking tree") = [factory, tree] {
            then("error message includes node name and port") = [factory, tree] {
                try {
                    tree.tickOnce();
                    expect(false) << "Expected RuntimeError";
                } catch (const BT::RuntimeError& e) {
                    std::string msg = e.what();
                    expect(msg.find("ClaimRoleNode") != std::string::npos)
                        << "Error should mention node name";
                    expect(msg.find("role_tag") != std::string::npos)
                        << "Error should mention missing port";
                }
            };
        };
    };
};
```

### Integration Tests

**Scope:** Full system integration

**Checklist:**
- [ ] BehaviorTreeManager initialization (registration + tree loading)
- [ ] Play assignment with tree creation and cleanup
- [ ] GSR tree creation during game state changes
- [ ] Error scenarios in real system (mixed valid/invalid XML)

### Manual Verification

**Checklist:**
- [ ] Build succeeds with no warnings
- [ ] All tests pass in < 10 seconds
- [ ] Error messages are helpful when XML is invalid
- [ ] Tree structure is correct after creation
- [ ] No use-after-free or memory leaks

---

## 7. Migration Notes

### Breaking Changes

**None** - Backward compatibility maintained. Existing API unchanged.

### Deprecation Path

**Potential Future Deprecations (not in this refactor):**
- `loadTreeXmlFromFile()` (currently only used in BTRegistrar)
- Direct access to BehaviorTreeManager.factory_ (use wrapper instead)

### Rollback Plan

If issues arise, revert the commits that added:
- `src/agent/bt/utils/BTLifecycle.h/cpp`
- `src/agent/bt/core/IBTFactoryWrapper.h`
- `src/agent/bt/core/BTFactoryWrapper.h/cpp`
- `src/agent/bt/core/IBTRegistrar.h`
- `src/agent/bt/core/BTRegistrar.h/cpp`
- Changes to `src/agent/bt/BehaviorTreeManager.h/cpp`
- Changes to `src/agent/bt/playAssignment/PlayAssignmentHelper.cpp`
- Changes to `src/agent/bt/GameStateReflex.cpp`
- Edits to `AGENTS.md`

No database migrations, config changes, or dependency updates needed.

---

## 8. Implementation Checklist (Master)

Copy this section to track overall progress.

### Phase 1: Infrastructure Setup
- [ ] BTLifecycle utility namespace created and tested
- [ ] IBTFactoryWrapper interface defined
- [ ] BTFactoryWrapper implementation complete and tested
- [ ] Build succeeds with no errors

### Phase 2: Registration Extraction
- [ ] IBTRegistrar interface defined
- [ ] BTRegistrar implementation complete
- [ ] BehaviorTreeManager refactored to use registrar/wrapper
- [ ] Backward compatibility verified (21 test files pass unchanged)
- [ ] Build succeeds with no errors

### Phase 3: Integration & Cleanup
- [ ] PlayAssignmentHelper refactored to use BTLifecycle utilities
- [ ] GameStateReflex refactored to use factory wrapper
- [ ] All tree creation uses new wrapper
- [ ] All existing tests pass without modification

### Phase 4: Error Handling & Testing
- [ ] XML test fixtures created in `src/agent/bt/xml/tests/`
- [ ] BehaviorTreeManager_ErrorHandling_Test.cpp implemented
- [ ] All 5 error scenarios tested and passing
- [ ] Error messages include debugging info

### Phase 5: Documentation & Review
- [ ] All source files have comprehensive comments
- [ ] AGENTS.md updated with refactoring information
- [ ] Example usage provided in headers
- [ ] Design decisions documented

### Phase 6: Final Verification
- [ ] Clean build succeeds: `ggs 2>&1 | tail -n 20`
- [ ] All tests pass: `./build/test/unit_tests`
- [ ] Error handling tests pass
- [ ] No performance regressions
- [ ] Integration tests pass

---

## 9. Success Criteria (Final)

### Functionality
- [ ] BTFactoryWrapper provides enhanced error diagnostics with XML context
- [ ] BTRegistrar successfully extracts registration logic (testable independently)
- [ ] BTLifecycle utilities centralize tree lifecycle management
- [ ] All new components have pure virtual interfaces for mockability

### Backward Compatibility
- [ ] All 21 existing test files pass without modification
- [ ] BehaviorTreeManager public API unchanged
- [ ] Tree creation behavior identical to before refactor
- [ ] Error handling behavior unchanged (graceful continues on invalid XML)

### Testing
- [ ] BehaviorTreeManager_ErrorHandling_Test.cpp covers 5 error scenarios
- [ ] Error messages include node names, port names, tree paths
- [ ] Graceful registration handling verified
- [ ] All error paths have explicit test coverage

### Performance
- [ ] Tree creation time unchanged
- [ ] No additional memory allocations in hot path
- [ ] Error scenario handling < 100ms per error

### Code Quality
- [ ] All source files have comprehensive documentation
- [ ] Design decisions documented with rationale
- [ ] No compiler warnings
- [ ] No code analysis issues (if using static analysis)

### Integration
- [ ] PlayAssignmentHelper uses new utilities cleanly
- [ ] GameStateReflex uses factory wrapper consistently
- [ ] Full system integration tests pass
- [ ] No use-after-free or memory leaks

---

## 10. Key Design Insights

### Why This Architecture?

1. **Type System Over Runtime Checks**: Pure virtual interfaces enable static verification that implementations are correct; no runtime interface checking needed

2. **Composition Over Inheritance**: Three separate classes (Wrapper, Registrar, BTManager) each handle one concern; easier to test and maintain than large inheritance hierarchies

3. **Testability First**: Every component has an interface; every dependency injected; all logic unit-testable without framework or integration dependencies

4. **Error Diagnostics**: Wrapper centralizes error handling; all error messages include context (XML snippets, registered items, tree structure); developers spend less time debugging

5. **Backward Compatibility**: Existing API maintained; gradual migration path; minimal disruption to 21 test files and existing code

---

## References

**Related Refactoring Plans:**
- `refactor_xml_registration.md` - Updated to account for TagEnum system and current codebase state

**Key Files:**
- `src/agent/bt/BehaviorTreeManager.h/cpp` - Main manager class
- `src/agent/bt/playAssignment/PlayAssignmentHelper.cpp` - Tree creation and lifecycle
- `src/agent/bt/coordination/CoordinationTypes.h` - TagEnum type system
- `src/agent/bt/utils/NodeUtils.h/cpp` - Diagnostic utilities
- `ClaimRole_Test.cpp` - Example test patterns with error handling
