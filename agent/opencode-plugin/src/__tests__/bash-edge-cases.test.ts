/**
 * Bash Parser Edge Case Tests
 *
 * Tests security filter behavior for complex bash constructs that could
 * bypass naive string matching. Each test verifies that the AST walker
 * properly finds and checks all command invocations.
 *
 * SECURITY CRITICAL: These patterns represent actual exfiltration vectors.
 */

import { describe, it, expect } from "vitest"
import parse from "bash-parser"
import {
  getCasesByCategory,
  getSecurityCriticalCases,
} from "./fixtures.js"

// Command sets from security-filter.ts
const READ_COMMANDS = new Set([
  "cat", "head", "tail", "less", "more", "bat",
  "grep", "rg", "ag", "ack",
  "source", ".",
  "wc", "file", "stat", "md5sum", "sha256sum",
  "diff", "cmp",
  "jq", "yq", "xq",
])

const WRITE_COMMANDS = new Set(["tee", "touch"])
const COPY_COMMANDS = new Set(["cp", "mv", "rsync", "scp"])
const PATTERN_FIRST_COMMANDS = new Set(["grep", "rg", "ag", "ack"])

/**
 * Extract file paths from a bash AST command node.
 * Mirrors the logic in security-filter.ts.
 */
const extractPathsFromCommand = (cmd: any): string[] => {
  const paths: string[] = []
  const name = cmd.name?.text?.toLowerCase()
  let args = (cmd.suffix || [])
    .map((s: any) => s.text)
    .filter((a: string) => a && !a.startsWith("-"))

  if (!name || args.length === 0) return paths

  // For grep/rg/etc, first arg is the pattern - skip it
  if (PATTERN_FIRST_COMMANDS.has(name) && args.length > 1) {
    args = args.slice(1)
  }

  if (READ_COMMANDS.has(name) || COPY_COMMANDS.has(name)) {
    paths.push(...args)
  } else if (WRITE_COMMANDS.has(name)) {
    const last = args[args.length - 1]
    if (last) paths.push(last)
  }

  return paths
}

/**
 * Recursively walk AST to find all Command nodes.
 * Handles: pipes, subshells, logical expressions, command substitutions.
 */
const walkCommands = (node: any, visitor: (cmd: any) => void) => {
  if (!node) return

  if (node.type === "Command") {
    visitor(node)

    // Check command suffix for expansions
    if (node.suffix) {
      for (const item of node.suffix) {
        if (item.expansion) {
          for (const exp of item.expansion) {
            if (exp.type === "CommandExpansion" && exp.commandAST) {
              walkCommands(exp.commandAST, visitor)
            }
          }
        }
      }
    }

    // Check redirects
    if (node.redirect) {
      for (const redir of node.redirect) {
        if (redir.file?.expansion) {
          for (const exp of redir.file.expansion) {
            if (exp.type === "CommandExpansion" && exp.commandAST) {
              walkCommands(exp.commandAST, visitor)
            }
          }
        }
      }
    }
  }

  // Handle subshells
  if (node.type === "Subshell" && node.list) {
    walkCommands(node.list, visitor)
  }

  // Handle logical operations
  if (node.type === "LogicalExpression") {
    if (node.left) walkCommands(node.left, visitor)
    if (node.right) walkCommands(node.right, visitor)
  }

  // Walk children
  if (node.commands) {
    for (const child of node.commands) {
      walkCommands(child, visitor)
    }
  }
  if (node.then) walkCommands(node.then, visitor)
  if (node.else) walkCommands(node.else, visitor)
  if (node.do) walkCommands(node.do, visitor)
}

const extractAllPaths = (command: string): string[] => {
  const paths: string[] = []
  try {
    const ast = parse(command)
    walkCommands(ast, (cmd) => {
      paths.push(...extractPathsFromCommand(cmd))
    })
  } catch (e) {
    console.error("Parse error:", e)
  }
  return paths
}

describe("Bash Parser Edge Cases", () => {
  describe("Simple Commands", () => {
    for (const testCase of getCasesByCategory("simple")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Pipes", () => {
    for (const testCase of getCasesByCategory("pipes")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Subshells - SECURITY CRITICAL", () => {
    for (const testCase of getCasesByCategory("subshells")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Command Substitution - SECURITY CRITICAL", () => {
    for (const testCase of getCasesByCategory("substitution")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Logical Operators - SECURITY CRITICAL", () => {
    for (const testCase of getCasesByCategory("logical")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Multi-Vector Attacks", () => {
    for (const testCase of getCasesByCategory("multi-vector")) {
      it(testCase.description, () => {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(paths).toContain(expected)
        }
      })
    }
  })

  describe("Security Critical Summary", () => {
    it("all security critical cases should extract correct paths", () => {
      for (const testCase of getSecurityCriticalCases()) {
        const paths = extractAllPaths(testCase.command)
        for (const expected of testCase.expectedPaths) {
          expect(
            paths,
            `Failed for: ${testCase.command} - missing ${expected}`
          ).toContain(expected)
        }
      }
    })
  })

  describe("AST Structure Documentation", () => {
    it("pipes create commands array", () => {
      const ast = parse("cat file1 | grep pattern")
      expect(ast.type).toBe("Script")
      expect(ast.commands).toBeDefined()
    })

    it("subshells have list property", () => {
      const ast = parse("(cat file)")
      expect(ast.commands[0].type).toBe("Subshell")
      expect(ast.commands[0].list).toBeDefined()
    })

    it("logical ops have left/right", () => {
      const ast = parse("cat file1 && cat file2")
      expect(ast.commands[0].type).toBe("LogicalExpression")
      expect(ast.commands[0].left).toBeDefined()
      expect(ast.commands[0].right).toBeDefined()
    })
  })
})
