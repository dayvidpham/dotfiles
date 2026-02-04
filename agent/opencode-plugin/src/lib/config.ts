import * as os from "node:os";
import * as path from "node:path";

const HOME = os.homedir();

/**
 * Paths that are always trusted - bypass all other checks.
 * Files in these directories are always allowed to be read.
 */
export const TRUSTED_PATHS: string[] = [
  path.join(HOME, "dotfiles"),
  path.join(HOME, "codebases"),
];

/**
 * Glob patterns for files that should NEVER be read by agents.
 * These take precedence over everything except trusted paths.
 */
export const BLOCKED_PATTERNS: string[] = [
  // Environment files
  "**/*.env",
  "**/*.env.*",
  "**/.env",
  "**/.env.*",

  // SSH keys and config
  `${HOME}/.ssh/*`,
  `${HOME}/.ssh/**/*`,

  // GPG keys
  `${HOME}/.gnupg/*`,
  `${HOME}/.gnupg/**/*`,

  // Cloud provider credentials
  `${HOME}/.aws/*`,
  `${HOME}/.aws/**/*`,
  `${HOME}/.config/gcloud/*`,
  `${HOME}/.config/gcloud/**/*`,
  `${HOME}/.azure/*`,
  `${HOME}/.azure/**/*`,

  // Other sensitive files
  `${HOME}/.netrc`,
  "**/*credentials*",
  "**/*password*",
  "**/secrets/**",
  "**/.secrets/**",

  // Private keys (but NOT public keys)
  "**/*.key",
  "**/id_rsa",
  "**/id_ecdsa",
  "**/id_ed25519",
  "**/id_dsa",
  // Note: *.pem and *.pub are intentionally NOT blocked
];

/**
 * Commands that read files and should be subject to permission checks.
 * When these commands are used, we extract file paths from their arguments.
 */
export const FILE_READ_COMMANDS: string[] = [
  "cat",
  "head",
  "tail",
  "less",
  "more",
  "grep",
  "rg",
  "ag",
  "ack",
  "sed",
  "awk",
  "cut",
  "sort",
  "uniq",
  "wc",
  "file",
  "stat",
  "xxd",
  "hexdump",
  "strings",
  "od",
];

export interface SecurityConfig {
  trustedPaths: string[];
  blockedPatterns: string[];
  fileReadCommands: string[];
}

export function getConfig(): SecurityConfig {
  return {
    trustedPaths: TRUSTED_PATHS,
    blockedPatterns: BLOCKED_PATTERNS,
    fileReadCommands: FILE_READ_COMMANDS,
  };
}
