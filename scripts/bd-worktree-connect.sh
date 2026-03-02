#!/usr/bin/env bash
# bd-worktree-connect.sh — Connect a worktree's beads DB to the dotfiles Dolt server
#
# Problem: Git worktrees (e.g. feat-annotations-mvp) have their own .beads/
# metadata.json with a default port (3307), but the actual Dolt server runs
# from ~/dotfiles on a different port. This script detects the running server
# and configures the current project's beads to connect to it.
#
# Usage:
#   cd ~/dev/agent-data-leverage/feat-annotations-mvp
#   ~/dotfiles/scripts/bd-worktree-connect.sh
#
# Or from any project directory:
#   ~/dotfiles/scripts/bd-worktree-connect.sh [project-dir]

set -euo pipefail

DOTFILES_DIR="${HOME}/dotfiles"
PROJECT_DIR="${1:-$(pwd)}"

# Step 1: Ensure the Dolt server is running at ~/dotfiles
echo "Checking Dolt server at ${DOTFILES_DIR}..."
SERVER_STATUS=$(cd "${DOTFILES_DIR}" && bd dolt status 2>&1) || true

if echo "${SERVER_STATUS}" | grep -q "not running"; then
    echo "Dolt server not running. Starting..."
    (cd "${DOTFILES_DIR}" && bd dolt start)
    SERVER_STATUS=$(cd "${DOTFILES_DIR}" && bd dolt status 2>&1)
fi

# Step 2: Extract the running port
RUNNING_PORT=$(echo "${SERVER_STATUS}" | grep "Port:" | awk '{print $2}')
if [ -z "${RUNNING_PORT}" ]; then
    echo "ERROR: Could not detect running Dolt server port"
    echo "Server status: ${SERVER_STATUS}"
    exit 1
fi
echo "Dolt server running on port ${RUNNING_PORT}"

# Step 3: Configure the project's beads to use that port
echo "Configuring beads in ${PROJECT_DIR} to use port ${RUNNING_PORT}..."
(cd "${PROJECT_DIR}" && bd dolt set port "${RUNNING_PORT}")

# Step 4: Verify connection
echo "Testing connection..."
(cd "${PROJECT_DIR}" && bd dolt test)

echo "Done. Beads in ${PROJECT_DIR} now connected to Dolt server at port ${RUNNING_PORT}."
