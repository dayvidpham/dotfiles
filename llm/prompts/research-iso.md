Ideally, I don't want to create a new type or table for each new metric or each new annotation. That would result in an unmaintainable combinatorial explosion. I SHOULD have an entity registry though, that tracks what types of "things" can produce an annotation, ideally this would have less than 10 entries. I SHOULD also have some kind of AnnotationRegistry. Code designs should prefer composition over inheritance: a typical object-oriented approach would be disastrous here: instead take inspiration from a `<verb>able` interface or trait design system. Our database design should be in Boyce-Codd Normal Form (BCNF), just like the rest of our current database.

Let's do another Research wave. Send out 9 Opus Explore agents to further break down and explore these standards, with 3 agents for each standard. Each will be focused on a different axis: A - Entity-Relationship Database Design design decomposition; B - systems design and scalable architecture and principles; C - translation into testing requirements.

I forgot to mention: they should each write to their own llm/research/iso/<document>--<axis>.md file. Let's launch these 9 research agents now.

Once this wave finishes, there should be wave of three Opus researchers sent to read the research document for each standard, on a single axis. So one agent will look at the 3 documents for A, and so on.

Each will be focused on a different axis: A - Entity-Relationship Database Design design decomposition; B - systems design and scalable architecture and principles; C - translation into testing requirements.

The 2nd wave will perform a synthesis, and output their own document at @lm/research/iso/<axis>--synthesis.md .

Once that second wave finishes, send out 3 opus agents to come up with 3 proposals.
