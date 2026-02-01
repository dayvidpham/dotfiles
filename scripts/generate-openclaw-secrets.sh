#!/usr/bin/env bash
# Generate OpenClaw secrets securely
# - Secrets never echoed to terminal
# - File encrypted immediately after creation
# - Use `sops <file>` to edit later (decrypts in $EDITOR, re-encrypts on save)

set -euo pipefail

SECRETS_FILE="${1:-secrets/openclaw/secrets.yaml}"

if [[ -f "$SECRETS_FILE" ]]; then
  echo "Error: $SECRETS_FILE already exists." >&2
  echo "To edit existing secrets: sops $SECRETS_FILE" >&2
  exit 1
fi

# Check dependencies
if ! command -v sops &> /dev/null; then
  echo "Error: sops not found. Install it or run from a nix shell." >&2
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  echo "Error: openssl not found." >&2
  exit 1
fi

mkdir -p "$(dirname "$SECRETS_FILE")"

# umask 077 = new files get permission 600 (rw-------)
# Default umask is usually 022, which gives 644 (rw-r--r--)
# 077 masks out all group/other permissions, so only owner can read/write
# This prevents other users from reading the plaintext secrets file
# during the brief moment before encryption
umask 077

# Generate secrets directly into file - never echoed to terminal
cat > "$SECRETS_FILE" << EOF
# OpenClaw secrets
# Edit with: sops $SECRETS_FILE

# Anthropic API keys - one per instance for isolation
# If one key is compromised/revoked, other instances keep working
alpha_anthropic_api_key: REPLACE_WITH_ALPHA_API_KEY
beta_anthropic_api_key: REPLACE_WITH_BETA_API_KEY

# Instance authentication tokens
alpha_instance_token: $(openssl rand -base64 32)
beta_instance_token: $(openssl rand -base64 32)

# Bridge signing keys (for inter-instance RPC)
alpha_bridge_signing_key: $(openssl rand -base64 32)
beta_bridge_signing_key: $(openssl rand -base64 32)

# Shared secret for bridge authentication
bridge_shared_secret: $(openssl rand -base64 32)
EOF

# Encrypt immediately - plaintext exists only momentarily
sops -e -i "$SECRETS_FILE"

echo "Created and encrypted: $SECRETS_FILE"
echo ""
echo "Next steps:"
echo "  1. Add your Anthropic API key: sops $SECRETS_FILE"
echo "  2. Enable secrets in NixOS config and rebuild"
