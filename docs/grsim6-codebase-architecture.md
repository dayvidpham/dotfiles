---
title: Exploratory Documentation
date: 2026-02-20
author: David Huu Pham, Deejot Grewal
---

# Exploratory Documentation

Deepjot wanted some guidance or tops on how to understand a new codebase.
David showed him his process of exploration.
This is their scrambled-together notes doc.

## Random Thoughts

several main.cpp
* means several binaries
* looks like theres' a cli/, probably means a headless CLI tool

main juice is in app/
* headers in include/
* impl in src/


## Two Main APIs

```
1. Simulator
    |
    |--- Network
    |
    |- Physics Abstraction Layer (PAL ---- wip-pal git branch )
    |  |- SimWorld
    |      |-> step
    |           ^
    |           |   ????
    |--- graphics.h <-> CGraphics <-> lower-level interface to OpenGL
    |           |
    |--- glwidget.h <-> CGraphics <-> lower-level interface to OpenGL
    |     ^
    |     | glwidget is the UI's handle to OpenGL
          |    (it is the main entrypoint for the UI to do graphics stuff)
2. MainWindow
```

==========

- graphics:
  - OpenGL
- gui: Qt6
  - MainWindow


```md
- simulator:
| - Simulator: what are we simulating?
|   -> the world,
|     -> Physics engine / backend;
|       -> What's the common interface / API to each backend?
|         -> **SimWorld**: wrapper on top of the Physics API
|           -> Mujoco
|           -> ODE
|     -> the cameras that capture visual information about the world,
|       -> sends over the network
|    
- networking: Protobuf
  - is the source of data which we have to transmit
```

## Big Questions

```md
1. Physics engine / backend;
      -> What's the common interface / API to each backend?
2. Where's the "main loop"?
      -> Simulator::tick()? 
```

=============

---
title: UI OpenGL Notes
date: 2025-12-??
author: David Huu Pham, Jimmy Z
---

# UI OpenGL Notes

## Files

#### app/include/

OpenGLWidget.h
- general opengl funcs
- exists as a handle to the OpenGL library
- the actual thing that draws stuff 
    - calls the OpenGL methods

graphics/
- the objects themselves
- e.g. gyclinder.h
    - calls OpenGLWidget to draw itself
    - GCylinder : GObject

GObject is the base class that holds the handle to OpenGLWidget
    - noted because cannot draw from the parent in the GCylinder constructor
    - didn't store parent in GCylinder class itself because of duplication and other architectural design dependencies
        - is stored in GObject so don't need to copy


#### OpenGLRenderer

Basically the delegate for all graphics drawing / camera movements

Handles texture generation as well
    - reads in images for the top of the robot and turns them into a OpenGL texture
    - passes these to the GRobots and GWheels (in the GRobots) and the GField

Contains and uses these GObject classes (e.g. GCylinder) store colour information and texture information required for drawing
    - further delegates to these, to draw the corresponding objects

## Todos

1. Conversion from screen space to world space for mouse
    - requires "collision detection" -> i.e. knowing what is clicked on: was the reason why physics engine was included in the graphics API
2. Conversion world space to screen space for text rendering for robot Ids
3. Debugging for why robots are "freaking out"
    - maybe related to ODE physics refactor impl
4. Jimmy Z looking into how a Orientation class will work
    - to integrate MuJoCo and UI under the same interface as ODE engine

(1) and (2) probably going to be put inside OpenGLWidget and then called by OpenGLRenderer

============================================

# LLM Research Output

## Initial Prompt

/research I'm trying to understand how this codebase and its architecture works and connects together? What are the main interfaces, and how do they connect, interact, relate together? What is their hierarchy amongst each other and the information flow? I know it renders graphics and handles physics simulations, but where's the main loop and how does it work? How does step / tick everything uniformly? How does the physics engine update the robots, and then eventually propagate those changes to the renderer?

On an unrelated note, what is a good TUI or CLI tool that can help me visualize these architectural relationships between the types?

Launch as many Sonnet Explore agents as necessary to determine the answer to these questions


## LLM Reply


# grSim6 Architecture - Complete Map

## The Big Picture

grSim6 is a RoboCup Small Size League (SSL) robot soccer simulator. External AI programs send
robot commands over UDP, the physics engine simulates the world, and simulated camera vision
data is sent back over UDP multicast. An optional Qt GUI renders the scene via OpenGL.

### Three Binaries

Binary: grSim6
Entry Point: app/src/main.cpp
Mode: Full GUI, --headless for no GUI, --headless-app for hidden window
────────────────────────────────────────
Binary: sim-cli
Entry Point: cli/main.cpp
Mode: Pure headless (no GUI at all)
────────────────────────────────────────
Binary: grSim_qt_client
Entry Point: clients/qt/main.cpp
Mode: Example client that sends commands to the simulator

### Module Dependency Graph

```
grSim6 (GUI exe)
  ├── libgrSim6 (core simulation library)
  │     ├── libgrSim6_proto (protobuf messages)
  │     ├── Qt6::Core, Qt6::Network
  │     ├── vartypes (config tree)
  │     └── [ODE or MuJoCo] (compile-time selected)
  ├── Qt6::Widgets, Qt6::OpenGL, Qt6::OpenGLWidgets
  └── vartypes

sim-cli (headless exe)
  └── libgrSim6 (same core lib, no GUI deps)
```

### Ownership Hierarchy

```
MainWindow (GUI mode)              |  main() (headless mode)
  ├── Simulator ──────────────────────── Simulator
  │     ├── Config                │        ├── Config
  │     ├── SimWorld              │        ├── SimWorld
  │     │     ├── Physics*        │        │     └── (same)
  │     │     ├── Robot*[16] x2   │        │
  │     │     ├── Ball*           │        │
  │     │     ├── Field*          │        │
  │     │     └── Camera*[]       │        │
  │     ├── Network               │        ├── Network
  │     ├── Protobuf              │        ├── Protobuf
  │     └── QTimer (unused in GUI)│        └── QTimer (drives tickAuto)
  ├── PreviewWidget               │
  │     └── OpenGLRenderer        │
  │           ├── OpenGLWidget    │
  │           ├── GRobot*[] ──→ Robot*   (direct pointers to physics)
  │           ├── GBall* ──→ Ball*
  │           └── GField* ──→ Field*
  ├── QTimer (drives update)      │
  └── UI widgets (docks, labels)  │
```

## The Main Loop

Both GUI and headless modes use a QTimer firing at ceil(1000/DesiredFPS) ms (~17ms for 60 FPS).

### Per-Tick Order of Operations

```
QTimer fires
  │
  ├── [GUI only] preview->draw()          ← render frame FIRST
  │
  └── sim->tick(wall_clock_now)
        │
        ├── world->step(DeltaTime=1/60s)
        │     ├── Watchdog: halt teams with stale commands (>1s)
        │     ├── ball->step(dt)          [ODE: 5x dWorldStep; MJC: no-op]
        │     ├── yellow_robots[16]->step  [set wheel/kicker ctrl signals]
        │     ├── blue_robots[16]->step    [same]
        │     └── field->step(dt)          [ODE: no-op; MJC: mj_step() HERE]
        │
        └── sendVision(time)
              └── for each camera:
                    generateVision() → UDP multicast to 224.5.23.2:10020
```

Fixed timestep, wall-clock drift: Physics always advances by exactly DeltaTime (1/60s). No
accumulator pattern. Vision timestamps use wall-clock, not sim-time.

## Key ODE vs MuJoCo Asymmetry

Aspect: Who calls the engine?
ODE: PBall::step() calls dWorldStep 5x
MuJoCo: MJCField::step() calls mj_step 1x
────────────────────────────────────────
Aspect: Ball step
ODE: Runs full world 5 sub-steps
MuJoCo: No-op
────────────────────────────────────────
Aspect: Field step
ODE: No-op
MuJoCo: Runs full world integration
────────────────────────────────────────
Aspect: State storage
ODE: Each body owns a dBodyID
MuJoCo: All share one mjModel*/mjData* via mjc::handle

## Physics Abstraction Layer (PAL)

Compile-time backend selection via BUILD_ODE_BACKEND / BUILD_MUJOCO_BACKEND preprocessor
defines:

```
Physics (abstract factory)
├── ODEPhysics  → creates PField, PBall, PRobot, PWheel, PKicker
└── MJCPhysics  → creates MJCField, MJCBall, MJCRobot, MJCWheel, MJCKicker
```

### Abstract Interface Hierarchy

```
Physics          → newField(), newBall(), newRobot()
  Robot          → setPos/getPos, setAngle/getAngle, setMoveSpeed, getOrientation, step
    Wheel[4]     → setSpeed/getSpeed, getPos, getOrientation, step
    Kicker       → kick, activateRoller, isTouchingBall, step
  Ball           → setPos/getPos, get/setLinearVelocity, step, getOrientation
  Field          → setGravity, step
```

All positions in millimeters, all angles in radians at the abstract interface. MuJoCo converts
to/from meters internally via mjc::MM_PER_M = 1000.0.

### MuJoCo Model Construction

MJCPhysics::buildModel():
1. Parse world.xml + robot.xml via mj_parseXML
2. Attach 32 robot instances via mjs_attach() with prefixes like "robot_blue_5_"
3. Programmatically add 224 actuators (32 robots x 7 each: 4 drives, roller, kick piston,
chipper)
4. mj_compile() → single mjModel, single mjData

Each MJCRobot resolves its indices at construction: bodyId, jointId, qposId (7 DOF: xyz +
quaternion), qvelId (6 DOF: linear + angular).

## Data Flow: Command → Physics → Vision → Network

```
External AI ──UDP──→ Network (readyRead signal, async)
                       │
                       ├── grSim_Packet (legacy port 20011)
                       ├── RobotControl blue (port 10301)
                       └── RobotControl yellow (port 10302)
                              │
                              v
                       Protobuf::handleRobotControl()
                              │ deserializes, per robot:
                              │  setWheelSpeed() or setMoveSpeed()
                              │  kick(), activateRoller()
                              v
                       Robot::setMoveSpeed(vx, vy, vw)
                              │ clamp to limits
                              │ acceleration limiting
                              │ inverse kinematics → 4 wheel speeds
                              v
                       Wheel::setSpeed(desiredSpeed) × 4
                              │
                       ════════════ TICK BOUNDARY ════════════
                              │
                       Wheel::step() → writes to ctrl[]
                       Field::step() → mj_step(model, data)
                              │
                              v
                       Robot::getPos/getAngle (reads from qpos[])
                              │
                              v
                       Camera::getRobots() + Gaussian noise
                              │
                              v
                       SSL_WrapperPacket (protobuf)
                              │
                              v
                       Network::sendVision() → UDP multicast 224.5.23.2:10020
                              │
                              v
                       External AI receives vision
```

## Graphics Pipeline

Direct polling, no events or state copies:

```
OpenGLRenderer::draw()
  ├── gl->initFrame()              (clear, projection, lights)
  ├── ball->draw()                 → Ball::getPos(), Ball::getOrientation()
  ├── robots[32]->draw()           → Robot::getPos(), Robot::getOrientation()
  │     ├── chassis->draw()        → GCylinder with team-colored texture
  │     ├── wheels[4]->draw()      → Wheel::getPos(), Wheel::getOrientation()
  │     └── kicker->draw()         → Kicker::getPos(), Kicker::getOrientation()
  ├── field->draw()                → walls + textured ground
  └── gl->draw()                   → QOpenGLWidget::update()
```

Every GObject subclass holds a raw pointer to its physics counterpart and polls
position/orientation every frame. Units: physics mm → GL meters (divided by 1000). The
Orientation struct wraps a 4x4 row-major rotation matrix, transposed to column-major for
OpenGL.

## Renderer Abstraction

```
MainWindow → PreviewWidget → PreviewRenderer (abstract)
                                └── OpenGLRenderer (concrete)
                                      └── OpenGLWidget (QOpenGLWidget)
```

PreviewWidget::swapRenderer(GraphicsMode) supports runtime switching, but only OpenGLRenderer
is currently implemented.

## Known Bugs / Issues Found

1. Protobuf* never initialized in Simulator constructor → null deref in sendVision()
2. Yellow control socket reads from wrong socket (simControlSocket instead of
yellowControlSocket)
3. Double draw per tick in GUI mode: OpenGLRenderer::draw() called explicitly, then again via
paintGL() → draw()
4. ODE returns degrees, MJC returns radians from getAngle() → backend switch would break
consumers
5. Camera confidence bug: 0.9 + bernoulli(0/1) → confidence can be 1.9
6. Geometry packets never sent: Camera::geometryReady() hard-returns false

## Config System

VarTypes tree persisted to ~/.grsim.xml. Three top-level groups: Geometry, Physics,
Communication. Robot INI files in config/*.ini provide per-team settings. Hot-reloadable via Qt
 signals when team selection changes.

---

## TUI/CLI Visualization Tools

For visualizing these architectural relationships in the terminal:

Tool: https://github.com/bkryza/clang-uml
What it does: Auto-generates UML class/sequence/package diagrams from C++ using Clang AST
Notes: Best for this codebase - needs compile_commands.json, outputs PlantUML/Mermaid/JSON
────────────────────────────────────────
Tool: https://graphviz.org/ (dot)
What it does: Renders DAGs/dependency graphs from .dot files
Notes: CLI tool, can output to terminal via graph-easy or to SVG/PNG
────────────────────────────────────────
Tool: https://mermaid.js.org/
What it does: Text-to-diagram (class, sequence, flowchart)
Notes: Renders in markdown, GitHub, or CLI via mmdc
────────────────────────────────────────
Tool: https://d2lang.com/
What it does: Modern text-to-diagram language with auto-layout
Notes: CLI d2 command, cleaner syntax than Mermaid for architecture diagrams
────────────────────────────────────────
Tool: https://github.com/swark-io/swark
What it does: LLM-powered auto architecture diagram generation
Notes: Generates Mermaid from code using AI
────────────────────────────────────────
Tool: https://metacpan.org/pod/Graph::Easy
What it does: ASCII art graph rendering in terminal
Notes: Converts Graphviz .dot to ASCII, pure terminal output

My recommendation: clang-uml for generating accurate class hierarchy diagrams from this C++
codebase, piped into D2 or Mermaid for rendering. For quick ASCII visualization in the
terminal, graph-easy converts .dot files to ASCII art.

==========================================

# grSim6 Architecture - Complete Map

When asked to write the above reply to a file. Contains slightly more noise and fluff.

## The Big Picture

grSim6 is a **RoboCup Small Size League (SSL) robot soccer simulator**. External AI programs send robot commands over UDP, the physics engine simulates the world, and simulated camera vision data is sent back over UDP multicast. An optional Qt GUI renders the scene via OpenGL.

## Three Binaries

| Binary | Entry Point | Mode |
|---|---|---|
| `grSim6` | `app/src/main.cpp` | Full GUI, `--headless` for no GUI, `--headless-app` for hidden window |
| `sim-cli` | `cli/main.cpp` | Pure headless (no GUI at all) |
| `grSim_qt_client` | `clients/qt/main.cpp` | Example client that sends commands to the simulator |

## Module Dependency Graph

```
grSim6 (GUI exe)
  ├── libgrSim6 (core simulation library)
  │     ├── libgrSim6_proto (protobuf messages)
  │     ├── Qt6::Core, Qt6::Network
  │     ├── vartypes (config tree)
  │     └── [ODE or MuJoCo] (compile-time selected)
  ├── Qt6::Widgets, Qt6::OpenGL, Qt6::OpenGLWidgets
  └── vartypes

sim-cli (headless exe)
  └── libgrSim6 (same core lib, no GUI deps)
```

## Ownership Hierarchy

```
MainWindow (GUI mode)              |  main() (headless mode)
  ├── Simulator ──────────────────────── Simulator
  │     ├── Config                │        ├── Config
  │     ├── SimWorld              │        ├── SimWorld
  │     │     ├── Physics*        │        │     └── (same)
  │     │     ├── Robot*[16] x2   │        │
  │     │     ├── Ball*           │        │
  │     │     ├── Field*          │        │
  │     │     └── Camera*[]       │        │
  │     ├── Network               │        ├── Network
  │     ├── Protobuf              │        ├── Protobuf
  │     └── QTimer (unused in GUI)│        └── QTimer (drives tickAuto)
  ├── PreviewWidget               │
  │     └── OpenGLRenderer        │
  │           ├── OpenGLWidget    │
  │           ├── GRobot*[] ──→ Robot*   (direct pointers to physics)
  │           ├── GBall* ──→ Ball*
  │           └── GField* ──→ Field*
  ├── QTimer (drives update)      │
  └── UI widgets (docks, labels)  │
```

---

## The Main Loop

Both GUI and headless modes use a **QTimer** firing at `ceil(1000/DesiredFPS)` ms (~17ms for 60 FPS).

### Per-Tick Order of Operations

```
QTimer fires
  │
  ├── [GUI only] preview->draw()          ← render frame FIRST
  │
  └── sim->tick(wall_clock_now)
        │
        ├── world->step(DeltaTime=1/60s)
        │     ├── Watchdog: halt teams with stale commands (>1s)
        │     ├── ball->step(dt)          [ODE: 5x dWorldStep; MJC: no-op]
        │     ├── yellow_robots[16]->step  [set wheel/kicker ctrl signals]
        │     ├── blue_robots[16]->step    [same]
        │     └── field->step(dt)          [ODE: no-op; MJC: mj_step() HERE]
        │
        └── sendVision(time)
              └── for each camera:
                    generateVision() → UDP multicast to 224.5.23.2:10020
```

**Fixed timestep, wall-clock drift**: Physics always advances by exactly `DeltaTime` (1/60s). No accumulator pattern. Vision timestamps use wall-clock, not sim-time.

### Key ODE vs MuJoCo Asymmetry

| Aspect | ODE | MuJoCo |
|---|---|---|
| Who calls the engine? | `PBall::step()` calls `dWorldStep` 5x | `MJCField::step()` calls `mj_step` 1x |
| Ball step | Runs full world 5 sub-steps | No-op |
| Field step | No-op | Runs full world integration |
| State storage | Each body owns a `dBodyID` | All share one `mjModel*/mjData*` via `mjc::handle` |

### Detailed Timeline Per Tick

```
QTimer fires (every ~17ms wall clock)
  |
  +-- [GUI] preview->draw()               [render]
  |
  +-- sim->tick(wall_clock_now)
        |
        +-- world->step(DeltaTime=1/60s)
              |
              +-- watchdog halt check (per-team)
              +-- ball->step(dt)           [ODE: 5x dWorldStep; MJC: no-op]
              +-- yellow_robots[16]->step(dt)
              |     +-- wheel[4]->step()   [set motor targets]
              |     +-- kicker->step()
              +-- blue_robots[16]->step(dt)
              |     (same as above)
              +-- field->step(dt)          [ODE: no-op; MJC: mj_step() <-- integrates full world]
              +-- lastTick = now
        |
        +-- sendVision(wall_clock_now)
              +-- for each camera:
                    protobuf->generateVision() -> network->sendVision() [UDP multicast]

Asynchronous (Qt event loop, not synchronized with tick):
  network->grSimCommandRecv()   -> protobuf->handleGrSimControl() -> robot->setMoveSpeed() / kick()
  network->simControlRecv()     -> protobuf->handleSimControl()   -> teleport / reset
  network->blueControlRecv()    -> protobuf->handleBlueControl()
  network->yellowControlRecv()  -> protobuf->handleYellowControl()
```

---

## Physics Abstraction Layer (PAL)

**Compile-time backend selection** via `BUILD_ODE_BACKEND` / `BUILD_MUJOCO_BACKEND` preprocessor defines.

### Factory

`Physics::newPhysics(Config* cfg)` in `lib/src/physics/Physics.cpp`:

```cpp
#if defined(BUILD_ODE_BACKEND)
    return new ODEPhysics(cfg);
#elif defined(BUILD_MUJOCO_BACKEND)
    return new MJCPhysics(cfg);
#endif
```

### Backend Implementations

```
Physics (abstract factory)
├── ODEPhysics  → creates PField, PBall, PRobot, PWheel, PKicker
└── MJCPhysics  → creates MJCField, MJCBall, MJCRobot, MJCWheel, MJCKicker
```

### Abstract Interface Hierarchy

```
Physics          → newField(), newBall(), newRobot()

Robot            → setPos/getPos, setAngle/getAngle, setMoveSpeed, getOrientation, step
  Wheel[4]       → setSpeed/getSpeed, getPos, getOrientation, step
  Kicker         → kick, activateRoller, isTouchingBall, step

Ball             → setPos/getPos, get/setLinearVelocity, step, getOrientation

Field            → setGravity, step
```

All positions in **millimeters**, all angles in **radians** at the abstract interface. MuJoCo converts to/from meters internally via `mjc::MM_PER_M = 1000.0`.

### Full Class Hierarchy

```
Physics (abstract factory)
├── ODEPhysics   : public Physics
└── MJCPhysics   : public Physics

Robot (abstract)
├── PRobot       : public Robot   (ODE backend)
└── MJCRobot     : public Robot   (MuJoCo backend)

Wheel (abstract)
├── PWheel       : public Wheel   (ODE)
└── MJCWheel     : public Wheel   (MuJoCo)

Kicker (abstract)
├── PKicker      : public Kicker  (ODE)
└── MJCKicker    : public Kicker  (MuJoCo)

Ball (abstract)
├── PBall        : public Ball    (ODE)
└── MJCBall      : public Ball    (MuJoCo)

Field (abstract)
├── PField       : public Field   (ODE) [owns PWorld → dWorldID]
└── MJCField     : public Field   (MuJoCo) [calls mj_step]
```

---

## SimWorld - The World State Container

`lib/include/SimWorld.h` — owns all physics objects, orchestrates stepping:

```cpp
class SimWorld {
    Physics* physics;
    std::array<Robot*, 16> yellow_robots;
    std::array<Robot*, 16> blue_robots;
    Ball* ball;
    Field* field;
    std::vector<Camera*> cameras;
    Config* cfg;

    void step(Float step);
    void step(Float step, time_point time);
    Robot* getRobot(Team team, int id);
    void teleportRobot(Team team, int id, RobotTeleport tp);
    void teleportBall(BallTeleport tp);
    void moveToFormation(Team team, RobotFormation form);
    void updateBallConfig(Config* cfg);
    void updateRobotConfig(Config* cfg);
    void updateFieldConfig(Config* cfg);
    void restartWorld();
    // ... accessors for all owned objects
};
```

---

## MuJoCo Backend Details

### Shared State

All MuJoCo objects share a single `mjc::handle { mjModel* model; mjData* data; }`. Unlike ODE where each body is independent, the entire world is one compiled MuJoCo model.

### Model Construction (`MJCPhysics::buildModel`)

1. Parse `scenes/world.xml` and `robots/robot.xml` via `mj_parseXML`
2. Attach 32 robot instances via `mjs_attach()` with prefixes like `"robot_blue_5_"`
3. Programmatically add **224 actuators** (32 robots x 7 each: 4 drives, roller, kick piston, chipper)
4. `mj_compile()` → single `mjModel`, `mj_makeData()` → single `mjData`

### MJCRobot Internal Structure

```
MJCRobot
├── bodyId     → mj_name2id("robot_blue_5_robot_base")
├── jointId    → sim.model->body_jntadr[bodyId]   (free joint)
├── qposId     → sim.model->jnt_qposadr[jointId]  → [x, y, z, qw, qx, qy, qz]
├── qvelId     → sim.model->jnt_dofadr[jointId]   → [vx, vy, vz, wx, wy, wz]
├── MJCWheel[4]
│   ├── actuatorId  → mj_name2id("robot_blue_5_drive_0..3")
│   └── wheelBodyId → mj_name2id("robot_blue_5_wheel_N_orientation")
└── MJCKicker
    ├── kickActuatorId    → "robot_blue_5_kick_actuator"
    ├── chipperActuatorId → "robot_blue_5_chipper_actuator"
    ├── rollerActuatorId  → "robot_blue_5_roller_drive"
    └── kickerBodyId      → "robot_blue_5_top_piston"
```

### Coordinate Transforms (MJC)

```cpp
// setPos: mm -> meters, add height offset
qpos[0] = pos.x / 1000.0;
qpos[1] = pos.y / 1000.0;
qpos[2] = pos.z / 1000.0 + RobotHeight*0.5 + WheelRadius*1.1 + BottomHeight;

// getPos: meters -> mm, subtract height offset
x = qpos[0] * 1000.0;
y = qpos[1] * 1000.0;
z = (qpos[2] - RobotHeight*0.5 - WheelRadius*1.1 - BottomHeight) * 1000.0;

// setAngle: yaw -> quaternion about Z axis
qpos[3] = cos(rad/2);  qpos[4] = 0;  qpos[5] = 0;  qpos[6] = sin(rad/2);

// getAngle: yaw from quaternion
yaw = atan2(2*(w*z + x*y), 1 - 2*(y*y + z*z));  // radians
```

---

## Data Flow: Command -> Physics -> Vision -> Network

```
External AI ──UDP──→ Network (readyRead signal, async)
                       │
                       ├── grSim_Packet (legacy port 20011)
                       ├── RobotControl blue (port 10301)
                       └── RobotControl yellow (port 10302)
                              │
                              v
                       Protobuf::handleRobotControl()
                              │ deserializes, per robot:
                              │  setWheelSpeed() or setMoveSpeed()
                              │  kick(), activateRoller()
                              v
                       Robot::setMoveSpeed(vx, vy, vw)
                              │ clamp to limits
                              │ acceleration limiting
                              │ inverse kinematics → 4 wheel speeds
                              v
                       Wheel::setSpeed(desiredSpeed) × 4

                       ════════════ TICK BOUNDARY ════════════

                       Wheel::step() → writes to ctrl[]
                       Field::step() → mj_step(model, data)
                              │
                              v
                       Robot::getPos/getAngle (reads from qpos[])
                              │
                              v
                       Camera::getRobots() + Gaussian noise
                              │
                              v
                       SSL_WrapperPacket (protobuf)
                              │
                              v
                       Network::sendVision() → UDP multicast 224.5.23.2:10020
                              │
                              v
                       External AI receives vision
```

### Inverse Kinematics

Both `PRobot::setMoveSpeed()` and `MJCRobot::setMoveSpeed()` implement identical omni-wheel inverse kinematics:

```
dw_i = (1/r) * (R*vw - vx*sin(alpha_i) + vy*cos(alpha_i))
```

Where `r` = wheel radius, `R` = robot radius, `alpha_i` = wheel angle from config, with acceleration limiting applied first.

---

## Networking Layer

All networking uses **UDP** exclusively. Vision output uses **UDP multicast**; all control/status channels use **unicast UDP**. All payloads are **Protocol Buffers**.

### Socket Architecture

```
Socket (abstract, QObject)
  └── UdpSocket (unicast)

MulticastSocket (abstract)
  └── UdpMulticast (multicast sender)
```

### Channel Map

| Socket | Type | Direction | Port | Purpose |
|---|---|---|---|---|
| `visionSocket` | Multicast | OUT | 10020 | SSL_WrapperPacket vision frames |
| `commandSocket` | Unicast | IN | 20011 | Legacy grSim_Packet commands |
| `simControlSocket` | Unicast | IN+OUT | 10300 | SimulatorCommand / SimulatorResponse |
| `blueControlSocket` | Unicast | IN+OUT | 10301 | RobotControl blue / RobotControlResponse |
| `yellowControlSocket` | Unicast | IN+OUT | 10302 | RobotControl yellow / RobotControlResponse |
| `blueStatusSocket` | Unicast | OUT | 30011 | Blue robot status |
| `yellowStatusSocket` | Unicast | OUT | 30012 | Yellow robot status |

### Protobuf Messages

**Incoming:**
- `grSim_Packet` — legacy protocol (per-robot wheel/velocity/kick + teleport)
- `SimulatorCommand` — SSL sim protocol (teleport, sim speed, config)
- `RobotControl` — SSL sim protocol (per-robot move/kick/dribble commands)

**Outgoing:**
- `SSL_WrapperPacket` — wraps `SSL_DetectionFrame` (robot/ball positions with noise)
- `SimulatorResponse` — error codes for sim control
- `RobotControlResponse` — per-robot `RobotFeedback` (dribbler ball contact)

**Proto files:** All in `lib/proto/` — includes SSL vision, simulation control, robot control/feedback, legacy grSim, and unused synchronous protocol.

---

## Graphics Pipeline

### Renderer Abstraction

```
MainWindow → PreviewWidget → PreviewRenderer (abstract)
                                └── OpenGLRenderer (concrete)
                                      └── OpenGLWidget (QOpenGLWidget)
```

`PreviewWidget::swapRenderer(GraphicsMode)` supports runtime switching, but only `OpenGLRenderer` is currently implemented.

### GObject Hierarchy

```
GObject  (base: holds OpenGLWidget*, pos, angle, color, visible)
  ├── GBall      → holds Ball* (direct pointer to physics)
  ├── GCylinder  → generic cylinder with optional texture
  ├── GBox       → axis-aligned box
  ├── GGround    → textured ground plane + field lines/circles
  ├── GWheel     → holds Wheel* → delegates to GCylinder
  ├── GKicker    → holds Kicker* → delegates to GBox
  ├── GRobot     → holds Robot* → owns GCylinder chassis + GWheel[4] + GKicker
  └── GField     → holds Field* → owns GGround + GBox[] walls
```

### Physics-to-Graphics: Direct Polling

Every `GObject` subclass holds a **raw pointer** to its physics counterpart and polls position/orientation every frame. There is no event system, no copy buffer, no notification mechanism.

```cpp
// GRobot::draw() — every frame
Float3d pos = m_robot->getPos();           // poll physics
chassis->setAngle(m_robot->getOrientation()); // poll physics
chassis->draw();
for (GWheel* wheel : wheels) { wheel->draw(); }
kicker->draw();
```

Units: physics mm → GL meters (divided by 1000). The `Orientation` struct wraps a 4x4 row-major rotation matrix, transposed to column-major for OpenGL in `OpenGLWidget::setTransform()`.

### Draw Sequence

```
OpenGLRenderer::draw()
  ├── gl->initFrame()              (clear buffers, projection, lights)
  ├── ball->draw()                 → Ball::getPos(), Ball::getOrientation()
  ├── robots[32]->draw()           → Robot::getPos(), Robot::getOrientation()
  │     ├── chassis->draw()        → GCylinder with team-colored texture
  │     ├── wheels[4]->draw()      → Wheel::getPos(), Wheel::getOrientation()
  │     └── kicker->draw()         → Kicker::getPos(), Kicker::getOrientation()
  ├── field->draw()                → walls + textured ground
  └── gl->draw()                   → QOpenGLWidget::update()
```

### Textures

Team-colored robot top textures are generated at init time by loading PNGs from Qt resources and pixel-replacing robot-gray `QColor(63,63,63)` with team color (blue `#0000ff`, yellow `#ffff00`). Stored in `OpenGLWidget`'s `QVector<QOpenGLTexture*>`.

### Legacy Graphics (Dead Code)

`CGraphics` / `GLWidget` in `app/include/graphics.h` and `app/include/glwidget.h` are the old ODE-coupled rendering system. Not used by the new `MainWindow` path (connections commented out with `//TODO`).

---

## Robot Data Model

### Core Types (`lib/include/Common.h`)

```cpp
typedef double Float;
struct Float2d { Float x, y; };
struct Float3d { Float x, y, z; };
typedef std::array<Float, 4> Float4d;   // robot formation: {x, y, z, angle}

struct Orientation {
    std::array<Float, 16> angle;         // 4x4 rotation matrix (row-major)
    Orientation(std::array<Float, 4> quat);    // quaternion [w,x,y,z] -> matrix
    Orientation(std::array<Float, 16> angle);  // direct matrix
    Orientation(const Float* angle);           // raw pointer (ODE compatible)
};

enum Team : int { UNKNOWN=0, YELLOW=1, BLUE=2 };
struct RobotID { Team team; int id; };
enum class WheelPosition : uint8_t { FrontLeft=0, FrontRight=1, BackLeft=2, BackRight=3 };
```

### RobotSettings (`lib/include/Config.h`)

```cpp
struct RobotSettings {
    // Geometry
    double RobotCenterFromKicker, RobotRadius, RobotHeight;
    double BottomHeight, KickerZ, KickerThickness, KickerWidth, KickerHeight;
    double WheelRadius, WheelThickness;
    double Wheel1Angle, Wheel2Angle, Wheel3Angle, Wheel4Angle;  // DEGREES

    // Physics
    double BodyMass, WheelMass, KickerMass;
    double KickerDampFactor, RollerTorqueFactor, RollerPerpendicularTorqueFactor;
    double Kicker_Friction, WheelTangentFriction, WheelPerpendicularFriction;
    double Wheel_Motor_FMax;
    double MaxLinearKickSpeed, MaxChipKickSpeed;
    double AccSpeedupAbsoluteMax, AccSpeedupAngularMax;
    double AccBrakeAbsoluteMax, AccBrakeAngularMax;
    double VelAbsoluteMax, VelAngularMax;
};
```

Loaded from `.ini` files in `config/` (e.g. `Parsian.ini`, `ParsianNew.ini`). Three copies: `defaultRobotSettings`, `blueSettings`, `yellowSettings`. Hot-reloadable via Qt signal when team selection changes in config.

### State Representations Across Layers

| Layer | Position units | Angle units | Orientation representation |
|---|---|---|---|
| MuJoCo internal | meters | radians | quaternion [w,x,y,z] in qpos |
| grSim abstract interface | **millimeters** | **radians** | `Orientation` (4x4 matrix) |
| ODE internal | millimeters | varies | ODE dMatrix3 (3x3 rotation) |
| ODE `getAngle()` | - | **degrees** | - |
| MJC `getAngle()` | - | **radians** | - |
| Camera / Vision output | millimeters | radians | scalar angle only |
| Network protobuf (SSL) | meters | radians | - |
| Network protobuf (grSim) | mm (implied) | degrees | - |

---

## Config System

`Config` (`lib/include/Config.h`) uses **VarTypes** (Qt-based hierarchical variable tree). Three top-level groups:

- **Geometry** (`geo_vars`): field dimensions (Div A/B), camera params, ball radius, team names
- **Physics** (`phys_vars`): FPS, DeltaTime, gravity, ball mass/friction, robot dynamics
- **Communication** (`comm_vars`): all UDP ports and multicast addresses, noise/vanishing params

Persisted to `~/.grsim.xml` via `VarXML::write()` on destruction, loaded on construction. Exposed in the GUI via `ConfigWidget` (VarTypes tree view) in a dock panel.

---

## Qt Signals/Slots (Inter-Component Communication)

### Config
- `v_BlueTeam/v_YellowTeam wasEdited → Config::loadRobotsSettings()` (reload robot INI)

### Simulator
- `QTimer::timeout → Simulator::tickAuto()` (drives physics in headless mode)

### MainWindow
- `QTimer::timeout → MainWindow::update()` (drives GUI render + physics tick)
- `PreviewWidget::selectedRobot → RobotWidget::changeSelectedRobot`
- Menu actions for snapshot, pause, fullscreen, formation placement, etc.

### Network
- `UdpSocket::readyRead → Network::grSimCommandRecv/simControlRecv/blueControlRecv/yellowControlRecv`

---

## Known Bugs / Issues

1. **`Protobuf*` never initialized** in `Simulator` constructor → null deref in `sendVision()`
2. **Yellow control socket reads from wrong socket** (`simControlSocket` instead of `yellowControlSocket`) in `Network::yellowControlRecv()`
3. **Double draw per tick** in GUI mode: `OpenGLRenderer::draw()` called explicitly by `MainWindow::update()`, then again via Qt's `paintGL()` callback
4. **ODE returns degrees, MJC returns radians** from `getAngle()` → backend switch would silently break all consumers
5. **Camera confidence bug**: `0.9 + bernoulli(0/1)` → confidence can be 1.9 (should cap at 1.0)
6. **Geometry packets never sent**: `Camera::geometryReady()` hard-returns `false`
7. **Robot status not sent**: `handleGrSimControl` returns empty `QByteArray` for legacy robot status
8. **Synchronous protocol not implemented**: `ssl_simulation_synchronous.proto` exists but no handler wired
9. **Two timers coexist in GUI mode**: `Simulator` has its own `QTimer` (for headless), `MainWindow` has another that calls `sim->tick()` directly. `Simulator::start()` is never called in GUI mode, so only `MainWindow`'s timer fires.

---

## Key File Reference

| File | Role |
|---|---|
| `lib/include/Common.h` | `Float3d`, `Orientation`, `Team`, `WheelPosition` primitives |
| `lib/include/Config.h` | `RobotSettings` struct, all config value declarations |
| `lib/src/Config.cpp` | Default values for all ports/addresses/physics params |
| `lib/include/Simulator.h` | Top-level simulation driver (QObject, owns everything) |
| `lib/src/Simulator.cpp` | `tick()`, `sendVision()`, `connectNetwork()` |
| `lib/include/SimWorld.h` | World state: robots, ball, field, cameras |
| `lib/src/SimWorld.cpp` | `step()`, teleport, halt-on-timeout |
| `lib/include/Network.h` | Qt UDP networking (QObject) |
| `lib/src/Network.cpp` | All socket wiring and receive handlers |
| `lib/include/Protobuf.h` | Protobuf serializer/deserializer interface |
| `lib/src/Protobuf.cpp` | All proto encode/decode logic |
| `lib/include/Camera.h` | Camera struct, CameraBall, CameraRobot |
| `lib/src/Camera.cpp` | Visibility, noise injection, frame generation |
| `lib/include/physics/Physics.h` | Abstract factory for backends |
| `lib/include/physics/Robot.h` | Abstract Robot interface |
| `lib/include/physics/Ball.h` | Abstract Ball interface |
| `lib/include/physics/Wheel.h` | Abstract Wheel interface |
| `lib/include/physics/Kicker.h` | Abstract Kicker interface |
| `lib/include/physics/Field.h` | Abstract Field interface |
| `lib/include/physics/mujoco/MJCTypes.h` | `mjc::handle`, inline accessors, `MM_PER_M` |
| `lib/include/physics/mujoco/MJCPhysics.h` | MuJoCo backend factory |
| `lib/src/physics/mujoco/MJCPhysics.cpp` | `buildModel()`: XML attachment + 224 actuators |
| `lib/include/physics/mujoco/MJCRobot.h` | MuJoCo robot (bodyId, jointId, qposId, qvelId) |
| `lib/src/physics/mujoco/MJCRobot.cpp` | `setPos/getPos` mm<->m, `setMoveSpeed` IK |
| `lib/include/physics/mujoco/MJCBall.h` | MuJoCo ball |
| `lib/include/physics/mujoco/MJCWheel.h` | MuJoCo wheel (actuator control) |
| `lib/include/physics/mujoco/MJCKicker.h` | MuJoCo kicker (3 actuators, countdown kick) |
| `lib/include/physics/mujoco/MJCField.h` | MuJoCo field (calls `mj_step`) |
| `lib/include/physics/ode/ODEPhysics.h` | ODE backend factory |
| `lib/include/physics/ode/PRobot.h` | ODE robot |
| `lib/include/physics/ode/PBall.h` | ODE ball (drives 5x `dWorldStep`) |
| `lib/include/physics/ode/PField.h` | ODE field (no-op step) |
| `app/include/mainwindow.h` | Qt GUI shell |
| `app/src/mainwindow.cpp` | GUI setup, timer, `update()` slot |
| `app/include/PreviewWidget.h` | Renderer abstraction wrapper |
| `app/include/PreviewRenderer.h` | Abstract rendering interface |
| `app/include/OpenGLRenderer.h` | Concrete OpenGL renderer |
| `app/src/OpenGLRenderer.cpp` | `draw()`, texture init, mouse handling |
| `app/include/OpenGLWidget.h` | QOpenGLWidget subclass (drawing primitives) |
| `app/src/OpenGLWidget.cpp` | GL state, `initFrame()`, `drawSphere/Cylinder/Box` |
| `app/include/graphics/gobject.h` | Base GObject class |
| `app/include/graphics/grobot.h` | GRobot (polls Robot*) |
| `app/include/graphics/gball.h` | GBall (polls Ball*) |
| `app/include/graphics/gfield.h` | GField (polls Field*) |
| `app/include/graphics/gwheel.h` | GWheel (polls Wheel*) |
| `app/include/graphics/gkicker.h` | GKicker (polls Kicker*) |
| `app/include/graphics/gcylinder.h` | GCylinder (generic drawable cylinder) |
| `app/include/graphics/gbox.h` | GBox (generic drawable box) |
| `app/include/graphics/gground.h` | GGround (textured ground with lines) |
| `lib/proto/*.proto` | All protobuf message definitions |
| `config/*.ini` | Robot geometry/physics configs |

---

## TUI/CLI Visualization Tools

For visualizing these architectural relationships in the terminal:

| Tool | What it does | Notes |
|---|---|---|
| [clang-uml](https://github.com/bkryza/clang-uml) | Auto-generates UML class/sequence/package diagrams from C++ using Clang AST | Best for this codebase - needs `compile_commands.json`, outputs PlantUML/Mermaid/JSON |
| [Graphviz](https://graphviz.org/) (`dot`) | Renders DAGs/dependency graphs from `.dot` files | CLI tool, can output to terminal via `graph-easy` or to SVG/PNG |
| [Mermaid](https://mermaid.js.org/) | Text-to-diagram (class, sequence, flowchart) | Renders in markdown, GitHub, or CLI via `mmdc` |
| [D2](https://d2lang.com/) | Modern text-to-diagram language with auto-layout | CLI `d2` command, cleaner syntax than Mermaid for architecture diagrams |
| [Swark](https://github.com/swark-io/swark) | LLM-powered auto architecture diagram generation | Generates Mermaid from code using AI |
| [graph-easy](https://metacpan.org/pod/Graph::Easy) | ASCII art graph rendering in terminal | Converts Graphviz `.dot` to ASCII, pure terminal output |

Recommendation: **clang-uml** for generating accurate class hierarchy diagrams from this C++ codebase, piped into **D2** or **Mermaid** for rendering. For quick ASCII visualization in the terminal, **graph-easy** converts `.dot` files to ASCII art.

