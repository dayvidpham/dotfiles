❯ Make a new revision, then once it's completed, spawn another cohort of Reviewers. While they review, we
  should "bake the cake recipe and slice it up", meaning we use the @scripts/launch-parallel.py script to spawn
   a supervisor instance that reads in your current proposal via `bd show ...` and creates an implementation
  plan. They should be decomposing the proposal into a horizontal layer-cake set of tasks, then cut up the cake
   along end-to-end vertical slices. They should be minimizing for synchronization points across the vertical
  slices, but this will be unavoidable. At the synchronization points, the workers should stop work and allow
  the supervisor to agent-commit the work.


❯ The questions should not be general: "exactly matches feedback, mostly matches feedback, requires revisions, ..." . Questions should be about examples of how the requirements were met using various abstractions in the
  possible software engineering design space. These questions should be multiSelect, because the user can choose multiple tradeoffs/design choices. For example, "Should this be statically-allocated, allocated at runtime, ...?"
   Or which of these variants we chose are appropriate, and why

