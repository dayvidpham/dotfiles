❯ Make a new revision, then once it's completed, spawn another cohort of Reviewers. While they review, we
  should "bake the cake recipe and slice it up", meaning we use the @scripts/launch-parallel.py script to spawn
   a supervisor instance that reads in your current proposal via `bd show ...` and creates an implementation
  plan. They should be decomposing the proposal into a horizontal layer-cake set of tasks, then cut up the cake
   along end-to-end vertical slices. They should be minimizing for synchronization points across the vertical
  slices, but this will be unavoidable. At the synchronization points, the workers should stop work and allow
  the supervisor to agent-commit the work.

/aura:supervisor Should NOT implement changes yourself. MUST run parallel workers to make changes. Let's "bake the cake and slice it up". Plan the tasks out, horizontal layer cakes of tasks, and then end-to-end vertical slices. Each vertical slice should be allocated to a Haiku subagent, with minimal synchronization points between vertical slices. Should commit each horizontal layer.

❯ The questions should not be general: "exactly matches feedback, mostly matches feedback, requires revisions, ..." . Questions should be about examples of how the requirements were met using various abstractions in the
  possible software engineering design space. These questions should be multiSelect, because the user can choose multiple tradeoffs/design choices. For example, "Should this be statically-allocated, allocated at runtime, ...?"
   Or which of these variants we chose are appropriate, and why

Launch a new team of agents to fix the remaining issues with test fixtures and consolidation, taking into account the lessons learned from UAT-2. These tasks should be topologically sorted and planned in a horizontal layer-cake style. However, when performing task allocation, this should cut the cake into end-to-end vertical slices one agent (or a subteam of agents) can be responsible for. Agents are allowed to modify the same file, but this must occur in a way where they are not modifying the same file during the same phase. Workers MUST validate their own changes and have it independently reviewed by a Haiku worker before declaring their phase done. Haiku worker would focus on alignment to user requirements and the correcet wiring of components and integration. Once this implementation plan is complete, launch a team of parallel agents to implement the plan. Do not create one teammate for each phase: create two teammates for each slice. One worker, and one reviewer. Worker should be Sonnet model, reviewer should be Haiku model. We should be creating a new team PER PHASE, one worker-reviewer pair for each slice, and shutting the team down once they complete their phase. Commit and review occurs, then new team startup for next phase.
