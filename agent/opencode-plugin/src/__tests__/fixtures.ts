/**
 * Shared test fixtures for bash parser and security filter tests.
 *
 * Pattern follows the Python opencode-security/tests/fixtures structure:
 * - Sensitive paths (should be blocked)
 * - Safe paths (should be allowed)
 * - Bash commands with expected path extractions
 */

// =============================================================================
// Sensitive file paths that SHOULD be blocked
// =============================================================================

export const SENSITIVE_PATHS = {
  // SSH keys and config
  ssh: [
    "~/.ssh/id_rsa",
    "~/.ssh/id_ed25519",
    "~/.ssh/config",
    "~/.ssh/known_hosts",
    "~/.ssh/authorized_keys",
  ],

  // Cloud credentials
  cloud: [
    "~/.aws/credentials",
    "~/.aws/config",
    "~/.config/gcloud/credentials.json",
    "~/.config/gcloud/application_default_credentials.json",
    "~/.azure/credentials",
  ],

  // Package manager tokens
  packageManagers: [
    "~/.npmrc",
    "~/.netrc",
    "~/.pypirc",
  ],

  // Environment and secrets
  secrets: [
    ".env",
    ".env.local",
    ".env.production",
    "secrets/api.key",
    "credentials.json",
  ],

  // System files
  system: [
    "/etc/passwd",
    "/etc/shadow",
    "/etc/sudoers",
  ],
}

// All sensitive paths flattened
export const ALL_SENSITIVE_PATHS = Object.values(SENSITIVE_PATHS).flat()

// =============================================================================
// Safe file paths that SHOULD be allowed
// =============================================================================

export const SAFE_PATHS = {
  // Public keys (safe to read)
  publicKeys: [
    "~/.ssh/id_rsa.pub",
    "~/.ssh/id_ed25519.pub",
  ],

  // Project files
  projectFiles: [
    "./src/index.ts",
    "./package.json",
    "./README.md",
    "file1",
    "file2",
    "data.json",
  ],

  // Temporary files
  tempFiles: [
    "/tmp/test.txt",
    "/tmp/output.log",
  ],
}

export const ALL_SAFE_PATHS = Object.values(SAFE_PATHS).flat()

// =============================================================================
// Bash commands with expected path extractions
// =============================================================================

export interface CommandTestCase {
  /** The bash command to parse */
  command: string
  /** Expected file paths extracted */
  expectedPaths: string[]
  /** Description for test output */
  description: string
  /** Category for grouping tests */
  category: "simple" | "pipes" | "subshells" | "substitution" | "logical" | "multi-vector"
  /** Whether this tests a security-critical bypass vector */
  securityCritical?: boolean
}

export const COMMAND_TEST_CASES: CommandTestCase[] = [
  // Simple commands
  {
    command: "cat ~/.ssh/id_rsa",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "extracts path from cat command",
    category: "simple",
  },
  {
    command: "cat file1 file2",
    expectedPaths: ["file1", "file2"],
    description: "extracts multiple bare filenames",
    category: "simple",
  },
  {
    command: "cat -n ~/.ssh/id_rsa",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "filters out flags",
    category: "simple",
  },
  {
    command: "head -n 10 /etc/passwd",
    expectedPaths: ["/etc/passwd"],
    description: "extracts path from head command",
    category: "simple",
  },

  // Pipes
  {
    command: "cat ~/.ssh/id_rsa | grep BEGIN",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "finds commands in pipe chains",
    category: "pipes",
  },
  {
    command: "cat file1 | grep pattern | tee file2",
    expectedPaths: ["file1", "file2"],
    description: "finds all commands in multi-stage pipes",
    category: "pipes",
  },

  // Subshells - SECURITY CRITICAL
  {
    command: "(cat ~/.netrc)",
    expectedPaths: ["~/.netrc"],
    description: "finds commands in subshells",
    category: "subshells",
    securityCritical: true,
  },
  {
    command: "((cat ~/.ssh/id_rsa))",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "finds commands in nested subshells",
    category: "subshells",
    securityCritical: true,
  },
  {
    command: "(cat ~/.ssh/id_rsa | base64)",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "finds commands in subshell with pipes",
    category: "subshells",
    securityCritical: true,
  },

  // Command substitution - SECURITY CRITICAL
  {
    command: "echo $(cat ~/.aws/credentials)",
    expectedPaths: ["~/.aws/credentials"],
    description: "finds commands in $()",
    category: "substitution",
    securityCritical: true,
  },
  {
    command: 'grep "$(cat ~/.netrc)" /dev/null',
    expectedPaths: ["~/.netrc", "/dev/null"],
    description: "grep with command substitution pattern (exfiltration vector)",
    category: "substitution",
    securityCritical: true,
  },

  // Logical operators - SECURITY CRITICAL
  {
    command: "cat ~/.ssh/id_rsa && echo done",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "finds commands in && chains",
    category: "logical",
    securityCritical: true,
  },
  {
    command: "cat file1 || cat ~/.netrc",
    expectedPaths: ["file1", "~/.netrc"],
    description: "finds commands in || chains",
    category: "logical",
    securityCritical: true,
  },
  {
    command: "cat file1 && cat file2 || cat file3",
    expectedPaths: ["file1", "file2", "file3"],
    description: "finds commands in mixed && || chains",
    category: "logical",
    securityCritical: true,
  },

  // Grep exfiltration vectors
  {
    command: "grep . ~/.ssh/id_rsa",
    expectedPaths: ["~/.ssh/id_rsa"],
    description: "grep . outputs entire file",
    category: "simple",
  },
  {
    command: "rg pattern ~/.aws/credentials",
    expectedPaths: ["~/.aws/credentials"],
    description: "rg with path argument",
    category: "simple",
  },

  // Multi-vector attacks
  {
    command: "cat file1 | grep $(cat file2) | tee file3",
    expectedPaths: ["file1", "file2", "file3"],
    description: "handles nested pipes and substitutions",
    category: "multi-vector",
    securityCritical: true,
  },
  {
    command: "(grep . ~/.ssh/id_rsa | base64) && cat ~/.netrc",
    expectedPaths: ["~/.ssh/id_rsa", "~/.netrc"],
    description: "multi-vector exfiltration attempt",
    category: "multi-vector",
    securityCritical: true,
  },
]

// Filter helpers
export const getSecurityCriticalCases = () =>
  COMMAND_TEST_CASES.filter((c) => c.securityCritical)

export const getCasesByCategory = (category: CommandTestCase["category"]) =>
  COMMAND_TEST_CASES.filter((c) => c.category === category)

// =============================================================================
// Search pattern test cases
// Note: Pattern blocking is handled by the Python CLI which has comprehensive
// rules for sensitive filenames (id_rsa, id_ed25519, credential, password, etc.)
// =============================================================================

export interface SearchPatternTestCase {
  /** The bash command with a search pattern */
  command: string
  /** Expected search patterns extracted */
  expectedPatterns: string[]
  /** Whether the pattern should be blocked (by Python CLI) */
  shouldBlock: boolean
  /** Description for test output */
  description: string
}

export const SEARCH_PATTERN_TEST_CASES: SearchPatternTestCase[] = [
  // Sensitive patterns that SHOULD be blocked (by Python CLI)
  {
    command: "ls -al | grep -e 'id_ed25519'",
    expectedPatterns: ["id_ed25519"],
    shouldBlock: true,
    description: "blocks grep for SSH key filename",
  },
  {
    command: "grep id_rsa .",
    expectedPatterns: ["id_rsa"],
    shouldBlock: true,
    description: "blocks grep for id_rsa",
  },
  {
    command: "grep 'credential' .",
    expectedPatterns: ["credential"],
    shouldBlock: true,
    description: "blocks grep for credential",
  },
  {
    command: "rg password /var/log",
    expectedPatterns: ["password"],
    shouldBlock: true,
    description: "blocks rg for password",
  },

  // Safe patterns that SHOULD be allowed
  {
    command: "grep TODO src/",
    expectedPatterns: ["TODO"],
    shouldBlock: false,
    description: "allows grep for TODO",
  },
  {
    command: "rg 'function' .",
    expectedPatterns: ["function"],
    shouldBlock: false,
    description: "allows rg for function keyword",
  },
  {
    command: "grep -r 'import' src/",
    expectedPatterns: ["import"],
    shouldBlock: false,
    description: "allows grep for import statements",
  },
]

export const getBlockedPatternCases = () =>
  SEARCH_PATTERN_TEST_CASES.filter((c) => c.shouldBlock)

export const getAllowedPatternCases = () =>
  SEARCH_PATTERN_TEST_CASES.filter((c) => !c.shouldBlock)
