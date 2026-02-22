## Redaction Pipeline Stage

In this refactor, we will also need to spec out the security and privacy redaction pipeline. The redactions will be implemented in parallel to the v2 implementation. The concern is that the warnings_json, subagents_json and metadata_json blobs will need to be transformed by the redaction step. Wait acutally: the redaction stage would occur before we store the metadata or the transcripts in the database, before computation of metrics. This shouldn't affect the actual computation of the metrics since this they are independent stages, but they would cause some metrics to vary: that is intended, and so the blobs here will *already* be redacted, upon insertion into the database. A reference for how we should implement the redactions is in @~/codebases/agentwatch-review/ . I also have an example of an ACP-compliant Claude Code transcript parser and filtering project at @~/codebases/dayvidpham/agentfilter/ .

## SessionEntry, session_entries

The next thing is: the database design for session_entries, and the design of the interface code is going to be tricky. These will inherently be dealing with many variants, each with their own schema for their transcripts, entries, tool calls, etc. This problem has a few steps.

1. Part of this is a literature research task: I put a reference paper that deals with how to deal with variant-rich software environments in @llm/research/variant-rich-paper. Find its references and related works, and determine what architectures or solutions the software engineering research community has developed to deal with this problem. We are in a variant-rich software environment because our ingestion pipeline must account for (MANY model harnsesses which may have MANY configurations, plugins and also interface with MANY models).

2. There is another research task: we need a standardized, stable, uniform interface that we can use to adapt the transcript entries into. This is essentially the purpose of the Agent Context Protocol (ACP), which has been officially merged into the Agent2Agent Protocol (A2A). These have also been officially donated to the Linux Foundation. These protocols integrate and extend the Model Context Protocol (MCP).
   * ACP: (https://agentcommunicationprotocol.dev/introduction/welcome) and its official OpenAPI spec (https://raw.githubusercontent.com/i-am-bee/acp/refs/heads/main/docs/spec/openapi.yaml)
   * A2A: official v1.0 spec (https://a2a-protocol.org/latest/definitions/) ; official A2A Go SDK (https://github.com/a2aproject/a2a-go) ; 
   * MCP: official spec at (https://modelcontextprotocol.io/specification/2025-11-25) and specified as TypeScript (https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/refs/heads/main/schema/2025-11-25/schema.ts)
We should define a database schema and design that is compliant with the A2A and MCP schema. When researching, use these links provided as the official, single source of truth. I have an example of an ACP-compliant Claude Code transcript parser and filtering project at @~/codebases/dayvidpham/agentfilter/ .
We will not need to worry about the ENTIRE A2A or ACP spec; we should prioritize the relevant portions of these specs, and how they will relate to our generalized transcript parsing, storage, and metrics computation. These will be the prime motivator.

## Model Name ID Refactor

Let's also use the database of models at https://github.com/anomalyco/models.dev , since we need a stable model name identifier.



