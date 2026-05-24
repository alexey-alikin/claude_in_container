# Security

## Reporting a vulnerability

Please report security issues privately via [GitHub Security Advisories](https://github.com/alexey-alikin/claude_in_container/security/advisories/new) rather than opening a public issue. For non-sensitive feedback, a regular issue or PR is fine.

## Threat model

This repo runs Claude Code in a Docker container as a non-root user with stripped Linux capabilities, a read-only root filesystem, capped resources, and per-project bind mounts. The goal is to make it safer than running Claude directly on your host, _especially_ when Claude is acting on instructions or inputs you don't fully trust — prompt injection from a fetched web page, a dependency's README, a file in the repo, etc.

It is **not** a replacement for a VM or a hardened sandbox. Docker shares the host kernel.

### What the container protects against

- **Filesystem access outside the project.** Claude can only read and write inside the bind-mounted `./projects/<name>/` folder and the credential bind mount `./claude_home/`. Other host files are invisible to the container.
- **Privilege escalation inside the container.** `cap_drop: ALL` removes all Linux capabilities, `security_opt: no-new-privileges` blocks `setuid` escalation, and the container runs as the unprivileged `claudeuser` (UID matches your host UID via the `USER_UID` build arg).
- **Tampering with installed system files.** `read_only: true` makes the container's root filesystem immutable at runtime. Only the two bind mounts and an in-memory `tmpfs` at `/tmp` are writable. A compromised session cannot backdoor the installed `claude-code` binary — a restart yields a clean container.
- **Resource exhaustion.** Memory (`mem_limit: 2g`), CPU (`cpus: 1.0`), process count (`pids_limit: 512`), and open file descriptors (`ulimits.nofile: 8192`/`16384`) are all capped. A fork bomb or runaway script inside the container cannot take down your host.

### What it does NOT protect against

- **The mounted project folder.** Claude's entire job is to edit files in `./projects/<name>/`. A compromised or prompt-injected session can corrupt or delete anything in there. Keep the project under version control and push often.
- **OAuth-token theft via filesystem.** The OAuth credentials saved during login are stored under `./claude_home/`. Anyone with read access to that folder on your host (other user accounts, a backup with weak ACLs, a synced cloud folder) can use your Claude.ai subscription. See [Hardening recommendations](#hardening-recommendations) below for `chmod`.
- **Network exfiltration (default mode).** In default mode the container has full outbound internet access. A prompt-injected Claude could `curl` your project files to an attacker-controlled endpoint. Use [hardened mode](#use-hardened-mode-network-allowlist) below for an opt-in egress allowlist that mitigates this.
- **Compromise of the Docker daemon or anyone in the `docker` group.** On Linux, anyone in the `docker` group has root-equivalent access to the host. The container cannot defend against that.
- **Supply-chain attacks.** A compromised release of `@anthropic-ai/claude-code`, the `node:20-slim` base image, or any package Claude installs into your project can bypass everything here. Pinning reduces but does not eliminate this risk.
- **Host-level compromise.** This is a container, not a VM. If your host kernel is exploited or the Docker daemon itself is compromised, the container's protections do not apply.

## Hardening recommendations

Opt-in steps beyond the repo's defaults.

### Use hardened mode (network allowlist)

> ⚠️ **Work in progress — not yet tested.** Hardened mode is implemented but has not been verified end-to-end (see [test plan](docs/test-plan.md), Part 2). Until those tests have been run and pass, treat the allowlist as best-effort and do not rely on it as a security boundary for untrusted code.

```bash
HARDENED=1 ./claude.sh shell <project>
```

This applies the `docker-compose.hardened.yml` overlay, which moves the `claude` container onto an internal-only Docker network and routes outbound HTTP/HTTPS through a `tinyproxy` sidecar that enforces a domain allowlist (see [`hardened/filter`](hardened/filter)). Hosts not on the list are blocked. Non-HTTP traffic (SSH, raw sockets) has no path to the outside at all.

Caveats:

- Hostname matching only — `tinyproxy` does not decrypt TLS, so any path on an allowed host is reachable. The allowlist is a strong defense against arbitrary exfiltration, not a content filter.
- Tools that ignore `HTTP_PROXY`/`HTTPS_PROXY` cannot reach the internet in hardened mode. For Claude Code and standard package managers this is what you want.
- Edit `hardened/filter` and rebuild the proxy (`HARDENED=1 ./claude.sh build egress-proxy`) when you need to add a host.

### Giving git access to the container

The container ships with `git` installed but no credentials. Two ways to handle pushing to a remote, in order of safety:

- **Host-side push (recommended).** Have Claude commit to a feature branch inside the container, then `git push` from a terminal on your host. No credentials ever enter the container, so a prompt-injected session has no path to push anywhere. See [README → Pushing your work to a remote](README.md#pushing-your-work-to-a-remote) for the step-by-step.
- **Fine-grained PAT in `.env`.** If you want Claude to read private repos or push directly, set `GITHUB_TOKEN` to a [GitHub fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to a single repo with the minimum permissions (`Contents: Read & write`, plus `Pull requests: Read & write` only if Claude should open PRs). Set a 30–90 day expiry. A prompt-injected session can still use the token, but only within its narrow scope; rotate or revoke from GitHub Settings if anything looks off. The shipped `claude_home/.gitconfig` rewrites SSH GitHub URLs to HTTPS and supplies the token from the env var at request time, so the token is never written into `.git/config` or any other persisted file — even though every git operation against `github.com` still works transparently.

What **not** to do: avoid bind-mounting your host's `~/.ssh` directory or your global `~/.gitconfig` into the container. Your usual SSH key typically authenticates as you to every git host you've used (personal GitHub, work GitLab, internal Gitea, …) — a leak from a single prompt-injected session breaks all of them at once. A global `~/.gitconfig` can also pull in `[includeIf]` paths, signing-key references, and `[url] insteadOf` rewrites you didn't intend to expose.

### Lock down the OAuth credentials

```bash
chmod 700 claude_home/
```

The token in `claude_home/` is the highest-value secret in this setup. Restrict directory permissions so other users on the host cannot read it. Do not put `claude_home/` inside a synced folder (Dropbox, iCloud, etc.) — the credentials will end up on every device the folder syncs to.

### Pin the `@anthropic-ai/claude-code` version

The `Dockerfile` installs `latest`, which means rebuilds are not reproducible and a future release could ship a change you did not review. To pin, edit `Dockerfile`:

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@<version>
```

Then rebuild with `./claude.sh build`.

### Pin the base image by digest

Same idea for the base image. Replace `FROM node:20-slim` with the digest form (`FROM node:20-slim@sha256:…`). You will need to bump it manually when you want security updates.

### Use rootless Docker

If your distro supports it, run Docker without root privileges. This further limits what a Docker daemon compromise can do. See <https://docs.docker.com/engine/security/rootless/>.

### Enable userns-remap

The Docker daemon can remap container UIDs to a separate range on the host (`/etc/docker/daemon.json` → `"userns-remap": "default"`). This is stronger isolation, but it is a global daemon setting and changes how all your containers behave — understand the implications before turning it on.

## Future improvements

See `docs/design-decisions.md` for the full planning history. As of this writing, the planned phases (foundation, multi-project, hardening, threat model, network allowlist, CI) have all shipped — improvements from here are issue-driven.
