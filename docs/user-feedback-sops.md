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

## Step 3: Generate and Encrypt Secrets

Run the secrets generation script (generates random values and encrypts immediately):

```bash
./scripts/generate-openclaw-secrets.sh
```

This creates `secrets/openclaw/secrets.yaml` with:
- Placeholder API keys for each instance (you must fill these in)
- Auto-generated instance tokens and signing keys
- Immediate encryption (plaintext never visible in terminal)

## Step 4: Add Your API Keys

Edit the encrypted file (decrypts in `$EDITOR`, re-encrypts on save):

```bash
sops secrets/openclaw/secrets.yaml
```

Replace the placeholder API keys with your actual Anthropic API keys:
- `alpha_anthropic_api_key` - API key for alpha instance
- `beta_anthropic_api_key` - API key for beta instance

Using separate keys per instance means if one is compromised, you only revoke that one.

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
