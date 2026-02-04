import type { Plugin } from "@opencode-ai/plugin"
import { readFileSync, existsSync } from "fs"
import { homedir } from "os"
import { join } from "path"

/**
 * BD Prime Plugin
 * 
 * Injects beads workflow context on:
 * - Session creation (equivalent to Claude's SessionStart hook)
 * - Session compaction (equivalent to Claude's PreCompact hook)
 */
export const BdPrimePlugin: Plugin = async ({ client, directory }) => {
  const bdPrimePath = join(homedir(), ".aura", "hooks", "bd-prime.md")
  
  // Check if bd-prime.md exists
  if (!existsSync(bdPrimePath)) {
    client.app.log({
      service: "bd-prime",
      level: "warn",
      message: `bd-prime.md not found at ${bdPrimePath}`,
    }).catch(() => {})  // Fire-and-forget, don't block
    return {}
  }
  
  // Read the content once at plugin init
  let bdPrimeContent: string
  try {
    bdPrimeContent = readFileSync(bdPrimePath, "utf-8")
  } catch (err) {
    client.app.log({
      service: "bd-prime",
      level: "error",
      message: `Failed to read bd-prime.md: ${err}`,
    }).catch(() => {})  // Fire-and-forget, don't block
    return {}
  }
  
  // Check if this is a beads-enabled project (has .beads directory)
  const beadsDir = join(directory, ".beads")
  const isBeadsProject = existsSync(beadsDir)
  
  if (!isBeadsProject) {
    client.app.log({
      service: "bd-prime",
      level: "debug",
      message: "Not a beads project (no .beads directory), plugin inactive",
    }).catch(() => {})  // Fire-and-forget, don't block
    return {}
  }

  client.app.log({
    service: "bd-prime",
    level: "info",
    message: "BD Prime plugin initialized for beads project",
  }).catch(() => {})  // Fire-and-forget, don't block
  
  return {
    // Inject on session creation
    event: async ({ event }) => {
      if (event.type === "session.created") {
        // Inject bd-prime context into the new session
        try {
          await client.session.prompt({
            path: { id: event.properties.info.id },
            body: {
              noReply: true,
              parts: [{ 
                type: "text", 
                text: `<system-context source="bd-prime.md">\n${bdPrimeContent}\n</system-context>` 
              }],
            },
          })
          client.app.log({
            service: "bd-prime",
            level: "info",
            message: `Injected bd-prime context into session ${event.properties.info.id}`,
          }).catch(() => {})
        } catch (err) {
          client.app.log({
            service: "bd-prime",
            level: "error",
            message: `Failed to inject bd-prime context: ${err}`,
          }).catch(() => {})
        }
      }
    },
    
    // Inject on compaction
    "experimental.session.compacting": async (input, output) => {
      output.context.push(`
## Beads Workflow Context (from bd-prime.md)

${bdPrimeContent}
`)
    },
  }
}
