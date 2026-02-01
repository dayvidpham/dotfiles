#!/usr/bin/env bash
# Generate OpenClaw secrets securely
# - Secrets never echoed to terminal
# - File encrypted immediately after creation
# - Use `sops <file>` to edit later (decrypts in $EDITOR, re-encrypts on save)
#
# Usage: generate-openclaw-secrets.sh [secrets_file] [instances...]
#   secrets_file: Path to output file (default: secrets/openclaw/secrets.yaml)
#   instances: Space-separated instance names (default: "alpha beta")

set -euo pipefail

SECRETS_FILE="${1:-secrets/openclaw/secrets.yaml}"
INSTANCES="${2:-alpha beta}"

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

# Generate secrets for each instance
generate_instance_secrets() {
  local instance_name="$1"
  cat << EOF
# ${instance_name} instance
${instance_name}_anthropic_api_key: REPLACE_WITH_${instance_name^^}_API_KEY
${instance_name}_instance_token: $(openssl rand -base64 32)
${instance_name}_bridge_signing_key: $(openssl rand -base64 32)
EOF
}

# Generate secrets and pipe directly to sops - plaintext never touches disk
{
  echo "# OpenClaw secrets"
  echo "# Edit with: sops $SECRETS_FILE"
  echo ""
  echo "# Anthropic API keys - one per instance for isolation"
  echo "# If one key is compromised/revoked, other instances keep working"
  for instance in $INSTANCES; do
    echo ""
    generate_instance_secrets "$instance"
  done
  echo ""
  echo "# Shared secret for bridge authentication"
  echo "bridge_shared_secret: $(openssl rand -base64 32)"
} | sops --input-type yaml --output-type yaml -e /dev/stdin > "$SECRETS_FILE"

echo "Created and encrypted: $SECRETS_FILE"
echo "Instances configured: $INSTANCES"
echo ""
echo "⚠️  IMPORTANT: You must replace the placeholder API keys!"
echo "   Run: sops $SECRETS_FILE"
echo "   Replace all REPLACE_WITH_*_API_KEY placeholders with actual Anthropic API keys"
echo ""
echo "Next steps:"
echo "  1. Add your Anthropic API keys: sops $SECRETS_FILE"
echo "  2. Enable secrets in NixOS config and rebuild"
