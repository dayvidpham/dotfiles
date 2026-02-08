❯ Make a new revision, then once it's completed, spawn another cohort of Reviewers. While they review, we
  should "bake the cake recipe and slice it up", meaning we use the @scripts/launch-parallel.py script to spawn
   a supervisor instance that reads in your current proposal via `bd show ...` and creates an implementation
  plan. They should be decomposing the proposal into a horizontal layer-cake set of tasks, then cut up the cake
   along end-to-end vertical slices. They should be minimizing for synchronization points across the vertical
  slices, but this will be unavoidable. At the synchronization points, the workers should stop work and allow
  the supervisor to agent-commit the work.

/aura:supervisor Should NOT implement changes yourself. MUST run parallel workers to make changes. Let's "bake the cake and slice it up". Plan the tasks out, horizontal layer cakes of tasks, and then end-to-end vertical slices. Each vertical slice should be allocated to a Haiku subagent, with minimal synchronization points between vertical slices. Should commit each horizontal layer.

---

❯ The questions should not be general: "exactly matches feedback, mostly matches feedback, requires revisions, ..." . Questions should be about examples of how the requirements were met using various abstractions in the
  possible software engineering design space. These questions should be multiSelect, because the user can choose multiple tradeoffs/design choices. For example, "Should this be statically-allocated, allocated at runtime, ...?"
   Or which of these variants we chose are appropriate, and why


The idea here is: the plan and the implementation MUST match with the user's end vision for the project.
The architect should also plan out several MVP milestones, in order to reach the user's vision.

The questions should not be general.
<bad-example>
BAD example:
"exactly matches feedback, mostly matches feedback, requires revisions, ..." . Questions should be about examples of how the requirements were met using various abstractions in the
</bad-example>

The questions should address critical decisions in the software engineering design space.
User should be prompted with multiSelect, because the user can choose multiple tradeoffs/design choices.
</good-example>
GOOD example:
"Should this be statically-allocated, allocated at runtime, ...?"
"Which of these variants we chose are appropriate, and why? Variant 1, main tradeoffs: ...; Variant N, ...."
</good-example>

The user should NOT be prompted with all questions at once, about all components. The user MUST be shown snippets of the definition, the implementation, and a motivating example. Then they should be asked several critical questions about one component at a time.

---

WARN message is uninformative. Need to know: what failed, WHY it failed, what it MEANS for the end-user, and what they can DO about it. also, the issue is that there is no difference between `watch --verbose` and `watch` with no verbose flag. I thought we were also going to show the daemon events and state changes on verbose.

---


Launch a new team of agents to fix the remaining issues with test fixtures and consolidation, taking into account the lessons learned from UAT-2. These tasks should be topologically sorted and planned in a horizontal layer-cake style. However, when performing task allocation, this should cut the cake into end-to-end vertical slices one agent (or a subteam of agents) can be responsible for. Agents are allowed to modify the same file, but this must occur in a way where they are not modifying the same file during the same phase. Workers MUST validate their own changes and have it independently reviewed by a Haiku worker before declaring their phase done. Haiku worker would focus on alignment to user requirements and the correcet wiring of components and integration. Once this implementation plan is complete, launch a team of parallel agents to implement the plan. Do not create one teammate for each phase: create two teammates for each slice. One worker, and one reviewer. Worker should be Sonnet model, reviewer should be Haiku model. We should be creating a new team PER PHASE, one worker-reviewer pair for each slice, and shutting the team down once they complete their phase. Commit and review occurs, then new team startup for next phase.

--- 

Common failure mode: end of line commands require semi-colon

● Bash(bd show aura-ksy3 2>&1 | head -10
      echo "==="
      bd show aura-7aj7 2>&1 | head -5
      echo "==="
      bd show aura-a0km 2>&1 | head -5
      echo "==="
      bd show aura-g9x 2>&1 | head -5
      echo "==="
      bd show aura-qfr 2>&1 | head -5
      echo "==="
      bd show aura-uvc 2>&1 | head -5
      echo "==="
      bd show aura-dtf 2>&1 | head -5
      echo "==="
      bd show aura-qjc0 2>&1 | head -5)
  ⎿  head: cannot open 'echo' for reading: No such file or directory
     head: cannot open '===' for reading: No such file or directory
     head: cannot open 'bd' for reading: No such file or directory
     head: cannot open 'show' for reading: No such file or directory
     head: cannot open 'aura-qjc0' for reading: No such file or directory
