# Headless and graphical credential stores on Linux/NixOS

Research date: 2026-10-17. Documentation research only; no credentials inspected or configuration changed. Adoption descriptions are qualitative, not measured market share. Six core documentation families are supplemented by narrowly scoped integration READMEs.

## 1. What should own SSH/GPG keys versus GitHub tokens?

### Takeaway
Keep the existing gpg-agent and terminal pinentry for SSH/GPG. For reliable terminal-first GitHub access, prefer password-store plus explicitly supplied `GH_TOKEN`; a desktop Secret Service is a separate convenience, not a prerequisite.

### Cited Findings
- **gpg-agent:** supports OpenSSH's agent protocol, configurable pinentry, and separate normal/SSH cache lifetimes. Defaults: normal cache 600 seconds, SSH 1,800 seconds, maximum 7,200 seconds for each. These are agent-memory caches, not reboot-persistent password storage. SSH cannot communicate its calling terminal; upstream documents `gpg-connect-agent updatestartuptty /bye` for updating the prompt destination. — [GnuPG agent options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- **gh:** normally stores login tokens in the system credential store and can fall back to plaintext if that fails. `GH_TOKEN` precedes `GITHUB_TOKEN` and stored credentials for github.com; Enterprise Server uses `GH_ENTERPRISE_TOKEN`. Environment tokens are officially recommended for headless use. — [Login](https://cli.github.com/manual/gh_auth_login), [environment](https://cli.github.com/manual/gh_help_environment)
- **Not interchangeable:** `gh auth setup-git` makes **Git use gh** as its helper; it does not make gh use arbitrary Git helpers. gh's authentication implementation reads environment/config and its keyring, not `credential.helper`. — [setup-git](https://cli.github.com/manual/gh_auth_setup-git), [authentication source](https://github.com/cli/cli/blob/trunk/internal/config/config.go)
- **Important diagnostic exception:** current `gh auth status` checks stored users through `TokenForUser`, even after checking the environment-selected active token. `--active` skips that enumeration; restrict `--hostname github.com` too. Thus simply setting `GH_TOKEN` does not guarantee that unrestricted `auth status` avoids the broken keyring. — [status implementation](https://github.com/cli/cli/blob/trunk/pkg/cmd/auth/status/status.go)

### Inferences
- The reported hang is consistent with a locked Secret Service needing unavailable GUI interaction, not broken SSH authentication. SSH Git transport still does not replace the token needed for GitHub API operations.
- Prefer agent caching over persisting the GPG passphrase unless reboot persistence is a deliberate requirement.

### Gaps
- Installed gh version and its `--active` support were not inspected. No claims about this machine's actual cache configuration or secrets.

## 2. Which established solutions actually support both GUI and headless workflows?

### Takeaway
**pass + QtPass** is the strongest terminal-first/Qt combination. **KeePassXC** is attractive for desktop Secret Service plus independent CLI retrieval. **KWallet** best matches KDE-native desktop UX, but neither desktop provider automatically solves locked-vault access without a display.

### Cited Findings
- **pass/password-store:** each secret is a GPG-encrypted file; CLI retrieval uses gpg-agent. Its official site documents Git synchronization, distro packaging, and QtPass as a compatible GUI. This is an established ecosystem, unlike assuming every small bridge has equal adoption. **pass itself is not a Secret Service provider.** — [password-store](https://www.passwordstore.org/)
- **Git integration:** `cassava/git-credential-pass` is a separate third-party helper with explicit Git configuration and a specified store layout; `pass-git-helper` is another implementation linked by password-store. These serve HTTPS Git, not gh's token store. — [git-credential-pass README](https://github.com/cassava/git-credential-pass), [password-store clients](https://www.passwordstore.org/#other)
- **KeePassXC:** its running GUI can expose a chosen database group through Secret Service, optionally requesting access confirmation. Only one provider can own the service on a bus. Separately, `keepassxc-cli show` and interactive `open` access databases from a terminal. The CLI's documented commands do **not** provide a headless Secret Service daemon or unlock the running GUI's database for it. — [Secret Service documentation](https://github.com/keepassxreboot/keepassxc/blob/develop/docs/topics/SecretService.adoc), [CLI manual](https://github.com/keepassxreboot/keepassxc/blob/develop/docs/man/keepassxc-cli.1.adoc)
- **KWallet:** current upstream separates `ksecretd` (Secret Service storage) from `kwalletd` (legacy KWallet API bridge, also capable of using another Secret Service). Older package versions differ. The normal locked-wallet workflow requests a graphical password dialog. It is an established KDE component, but the cited docs do not establish a general curses/stdin unlock path. — [KWallet README](https://github.com/KDE/kwallet), [user documentation](https://docs.kde.org/stable_kf6/en/kwalletmanager/kwalletmanager/kwallet-using.html)
- **GNOME Keyring:** `--unlock` reads a password from stdin and specifically unlocks/creates the **login keyring**. It is not an arbitrary named-collection unlock interface. `--login` is PAM-oriented and requires later initialization with `--start`. Consequently, unlocking login alone does not establish that another collection behind the default alias is unlocked. — [upstream daemon manual](https://github.com/GNOME/gnome-keyring/blob/master/docs/gnome-keyring-daemon.xml)

### Inferences
- For pass, use a fail-closed wrapper: decrypt the designated token entry, check decryption succeeded and the token is nonempty, select its first line, then supply `GH_TOKEN` only to the invoked gh process. Do not globally export it or use `gh auth login --with-token` expecting pass-backed storage.
- Decryption moves protection from encrypted disk storage to plaintext process memory/environment. Descendants inherit the token; debugging, authorized process inspection, traces, and logs can expose it. Avoid shell tracing and broad environment propagation; scope/expire the PAT. An environment variable is a transport, not an additional vault.
- KeePassXC CLI retrieval can similarly feed gh headlessly, but needs independent database authentication. PAM/pre-unlocking can make desktop providers usable headlessly **while already unlocked**; that is different from offering terminal unlocking on demand.

### Gaps
- Exact NixOS package versions, build features, PAM integration and deployment options were not checked. No adoption statistics or blanket promise of concurrent database-file access safety.

## 3. Is there a genuinely headless Secret Service, and what can deadlock?

### Takeaway
Yes: GPG-backed Secret Service bridges exist, but classify them as niche integrations requiring evaluation, not mainstream replacements with proven equivalent compatibility. Avoid circular passphrase recovery.

### Cited Findings
- **Rust `grimsteel/pass-secret-service`:** provides `org.freedesktop.secrets` over pass, daemon/systemd/D-Bus activation files, and optional agent-cache clearing on lock. Its README explicitly warns that attributes are unencrypted. Distinct **Python `mdellweg/pass_secret_service`** also exposes pass through Secret Service. — [Rust project](https://github.com/grimsteel/pass-secret-service), [Python project](https://github.com/mdellweg/pass_secret_service)
- **gopass integration exists:** third-party `nikicat/gopass-secret-service` uses GoPass as its backend without GNOME/KDE dependencies. It is not evidence that core gopass itself supplies Secret Service. Its README explicitly documents startup deadlock when pinentry queries the very service waiting for GPG decryption. — [project README](https://github.com/nikicat/gopass-secret-service)
- GnuPG's `no-allow-external-cache` advises pinentry against external passphrase caching, leaving internal agent caching available. KWallet also documents this option for GPG-encrypted wallets. Persistence depends on pinentry/provider integration, not installing a wallet alone. — [GnuPG](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html), [KWallet](https://github.com/KDE/kwallet)

### Inferences
- Headless still needs a reachable session D-Bus and an independently bootstrappable GPG unlock: terminal pinentry with correct TTY, pre-unlocked agent, or deliberate provisioning. No bridge removes this requirement.
- For niri versus private-runtime/private-bus Sway, choose provider and unlock policy **per bus**. Sharing one GUI provider makes headless availability depend on that GUI session. Private D-Bus is routing separation, not strong isolation from other processes of the same Unix user.
- Never store the sole recovery passphrase for a GPG-encrypted store inside that same store, including through a Secret Service bridge. Keep external caching disabled for this dependency chain.

### Gaps
- These bridge READMEs do not establish broad adoption, independent security audits, complete API compatibility, or tested NixOS multi-session behavior. Pilot before replacing a mainstream provider; direct pass-to-gh avoids this extra daemon entirely.
