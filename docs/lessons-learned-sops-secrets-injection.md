# LESSON LEARNED: Secrets Injection with sops-nix

**Date**: 2026-02-01
**Context**: OpenClaw Home Manager module (modules/home-manager/services/openclaw/)
**Commit**: 5ea01fb

## Problem
Application (openclaw) required secrets in config file `~/.openclaw/openclaw.json`:
```json
{
  "gateway": {
    "mode": "local",
    "auth": { "token": "secret-here" }
  }
}
```

Upstream module created **empty config** `{}` in Nix store.

## ❌ WRONG APPROACH: Systemd Environment Variables

**What we tried:**
```nix
systemd.user.services.openclaw-gateway.Service.Environment = [
  "MOLTBOT_CONFIG_PATH=/path/to/sops-config"
];
```

**Why it FAILED:**
1. Environment variables in Home Manager's `systemd.user.services` often don't reach the running process
2. Service file shows env vars, but `cat /proc/$PID/environ` shows they're missing
3. Fighting with upstream module's config management is futile
4. Debugging nightmare - vars appear in unit file but not in process

## ✅ CORRECT APPROACH: Direct Config File Replacement

**Use `sops.templates` to write config directly where app expects it:**

```nix
{
  # 1. Declare secret
  sops.secrets."app/token" = {
    sopsFile = ./secrets.yaml;
    key = "token_key";
  };

  # 2. Generate config with injected secret
  sops.templates."app-config.json" = {
    content = builtins.toJSON {
      setting = config.sops.placeholder."app/token";
    };
    path = "${stateDir}/config.json";  # Direct path where app reads it
    mode = "0400";
  };
}
```

**Why this WORKS:**
- sops.templates writes file with actual secret at activation time
- File goes directly where application expects it
- No systemd environment variable indirection
- sops-nix handles symlink management automatically
- Simple, direct, debuggable

## KEY PRINCIPLE

**When application needs secrets in config file:**
1. ✅ Use `sops.templates` with `path = "..."` to write config directly
2. ✅ Let application read its config file normally
3. ❌ NEVER try to override config paths via environment variables
4. ❌ NEVER fight with upstream modules' config management
5. ❌ NEVER add indirection layers (env vars, wrapper scripts, etc.)

## Debugging

Check the actual config file:
```bash
cat ~/.openclaw/openclaw.json  # Should show config with secrets
ls -la ~/.openclaw/openclaw.json  # Should be symlink to sops-rendered file
```

If file is empty `{}`, your `sops.templates` config is wrong.

## References
- Commit: 5ea01fb fix(openclaw): use sops template to inject gateway token into config
- Module: modules/home-manager/services/openclaw/default.nix
- Issue: systemd "Unknown section 'serviceConfig'" + "gateway.mode=local (current: unset)"
