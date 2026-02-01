# Setting Up sops-nix Secrets for OpenClaw

This guide walks you through enabling encrypted secrets management for the OpenClaw module.

## Prerequisites

- NixOS with the openclaw module enabled
- `age` and `sops` CLI tools (included in shared utils)

## Step 1: Generate an Age Key

The openclaw module creates `/var/lib/sops-nix` with proper permissions. After enabling the module and rebuilding once, generate your age keypair:

```bash
sudo age-keygen -o /var/lib/sops-nix/keys.txt
```

Note the public key output (starts with `age1...`). You'll need this for the next step.

## Step 2: Configure sops

Edit `secrets/.sops.yaml` and replace the placeholder with your public key:

```yaml
creation_rules:
  - path_regex: openclaw/.*\.yaml$
    key_groups:
      - age:
          - age1your_actual_public_key_here

  - path_regex: .*\.yaml$
    key_groups:
      - age:
          - age1your_actual_public_key_here
```

## Step 3: Create the Secrets File

Copy the example and fill in your actual values:

```bash
cp secrets/openclaw/secrets.yaml.example secrets/openclaw/secrets.yaml
```

Edit `secrets/openclaw/secrets.yaml` with your real secrets:

```yaml
# Anthropic API key
anthropic_api_key: sk-ant-api03-YOUR_REAL_KEY

# Instance tokens (generate random values)
alpha_instance_token: $(openssl rand -base64 32)
beta_instance_token: $(openssl rand -base64 32)

# Bridge signing keys (generate random values)
alpha_bridge_signing_key: $(openssl rand -base64 32)
beta_bridge_signing_key: $(openssl rand -base64 32)

# Shared bridge secret
bridge_shared_secret: $(openssl rand -base64 32)
```

Generate random values with:
```bash
openssl rand -base64 32
```

## Step 4: Encrypt the Secrets File

```bash
cd secrets/openclaw
sops -e -i secrets.yaml
```

The file is now encrypted. You can verify by viewing it:
```bash
cat secrets.yaml  # Should show encrypted YAML
sops secrets.yaml  # Opens decrypted in $EDITOR
```

## Step 5: Enable Secrets in NixOS Configuration

Edit `hosts/desktop/configuration.nix`:

```nix
CUSTOM.virtualisation.openclaw = {
  enable = true;

  secrets = {
    enable = true;
    sopsFile = ../../secrets/openclaw/secrets.yaml;
    ageKeyFile = "/var/lib/sops-nix/keys.txt";
  };

  # ... rest of config
};
```

## Step 6: Rebuild and Verify

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Verify secrets are deployed:
```bash
# Secrets should exist in /run/secrets
ls -la /run/secrets/openclaw/
```

## Troubleshooting

### "Failed to decrypt" errors

- Ensure the age key in `/var/lib/sops-nix/keys.txt` matches the public key in `.sops.yaml`
- Re-encrypt the secrets file: `sops updatekeys secrets/openclaw/secrets.yaml`

### "File not found" errors

- Ensure `secrets/openclaw/secrets.yaml` is tracked in git: `git add secrets/openclaw/secrets.yaml`
- The encrypted file must be committed for Nix to see it

### Rotating Secrets

To update a secret:
```bash
sops secrets/openclaw/secrets.yaml  # Edit in $EDITOR
git add secrets/openclaw/secrets.yaml
git commit -m "chore: rotate openclaw secrets"
sudo nixos-rebuild switch --flake .#desktop
```

## Security Notes

- Never commit unencrypted secrets
- The age private key (`/var/lib/sops-nix/keys.txt`) should only exist on the target host
- Secrets are decrypted to `/run/secrets` (tmpfs) at boot - they never touch disk
- Each instance gets its own secret paths with restricted permissions
