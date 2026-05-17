# Plan: open-sourcing & hardening `claude_in_container`

This is a planning doc, not implementation. Each item below is a concrete change to make before/after publishing the repo. Items are grouped by goal and tagged with rough effort: **S** (small, <1h), **M** (medium, half-day), **L** (large, day+).

---

## 1. Goals

1. **Easy for strangers to use.** A new user with Docker installed should be able to clone, run one command, log in once, and start using Claude Code in an isolated workspace. Multi-project workflow should be obvious.
2. **Safer than running Claude on the host.** Reduce blast radius of a compromised/prompt-injected session: container can't escape to host, can't reach arbitrary network targets, can't burn unlimited resources, and only sees the files for the one project it's working on.
3. **Honest about limits.** Document what the container does NOT protect against (the project files themselves, the OAuth token in `claude_home`, etc.) rather than overselling.

---

## 2. Open-source readiness

### 2.1 Licensing & meta files
- **LICENSE** (S) — pick one. MIT is the lowest-friction default; Apache 2.0 if you care about an explicit patent grant. **Decision needed.**
- **SECURITY.md** (S) — short threat model + how to report issues (a contact email or GitHub security advisories link). See §3.7 for content.
- **CONTRIBUTING.md** (S, optional) — one paragraph: "open an issue first, keep PRs small, run `hadolint Dockerfile` and `docker compose config` before submitting."
- **`.env.example`** (S) — committed template showing `CLAUDE_CODE_OAUTH_TOKEN=` with a comment pointing at `claude setup-token`. The real `.env` stays gitignored (already is).

### 2.2 README rewrite
Replace the current 2-line README with sections in this order. (Detail in §5.)

1. What this is / who it's for (2–3 sentences).
2. Prerequisites — link to <https://docs.docker.com/engine/install/> and note Linux/macOS/Windows-WSL2 support. Mention `docker compose` v2.
3. Quick start (clone → first run → log in → use).
4. Daily usage — opening a shell, running one-off `claude -p "..."` commands.
5. Multi-project workflow — how to add a second, third, Nth project; each gets its own git repo inside `projects/<name>/`, gitignored from this repo.
6. Authentication modes — subscription (interactive login that persists in `claude_home/`) vs. headless via `CLAUDE_CODE_OAUTH_TOKEN` for `claude -p`.
7. Security model — what the container protects, what it doesn't (link to SECURITY.md).
8. Troubleshooting — UID mismatch on Linux, permission errors on `claude_home`, token expiry, etc.
9. License.

### 2.3 Multi-project ergonomics
The current `docker-compose.yml` hardcodes `project-a`. Two viable patterns — **decision needed**:

- **(A) Parameterized single service.** One service named `claude`, mount `./projects/${PROJECT}:/workspace`, run with `PROJECT=my-app docker compose run --rm claude`. Plus a thin wrapper script (`./claude.sh my-app` or a `Makefile`) so users don't memorize that. Cleaner repo, one source of truth, easy to add projects (just `mkdir projects/foo`).
- **(B) One service per project.** User copies a service block in `docker-compose.yml` for each project. More boilerplate, but lets you `docker compose up` several at once.

Recommend **(A)** with a wrapper script — it's what most users will want, and (B) is just `docker compose run` in two terminals.

Wrapper script outline (`./claude.sh`, ~20 lines of bash):
- `./claude.sh new <name>` → `mkdir projects/<name>`, optional `git init` inside it.
- `./claude.sh shell <name>` → `docker compose run --rm -e PROJECT=<name> claude bash`.
- `./claude.sh run <name> -- <args...>` → `docker compose run --rm -e PROJECT=<name> claude claude <args>`.
- `./claude.sh list` → `ls projects/`.

### 2.4 Example project
Ship a `projects/example/` (NOT gitignored) containing a `README.md` that says "delete me and put your code here." Makes the multi-project pattern visible without forcing the user to read docs first. The existing `projects/.gitignore` would need to whitelist `example/`.

### 2.5 Versioning
- Pin `@anthropic-ai/claude-code` to a specific version in the Dockerfile (M). Currently `npm install -g @anthropic-ai/claude-code` picks `latest` at build time — non-reproducible and means rebuilds can break for users without warning. Either pin a version and document how to bump, or accept the drift and call it out in README.
- Optional: pin base image by digest (`node:20-slim@sha256:…`) for full reproducibility (S). Trade-off: requires manual bumps for security updates.

---

## 3. Hardening

The current setup already does the right basics: non-root user, `cap_drop: ALL`, `no-new-privileges`, memory/cpu caps. The items below close remaining gaps.

### 3.1 Network egress allowlist (M, biggest single win)
Today the container can talk to anything on the internet. A prompt-injected Claude could exfiltrate `/workspace` contents to an attacker-controlled host. Two approaches:

- **Lightweight:** add a tiny sidecar (e.g. `tinyproxy` or a squid container) on a private compose network, deny direct internet, allowlist `api.anthropic.com`, `github.com`, `registry.npmjs.org`, `pypi.org`, etc. The claude container gets `HTTP_PROXY`/`HTTPS_PROXY` env vars.
- **Heavier:** the reference Anthropic devcontainer uses iptables init + DNS allowlist inside the container; requires `NET_ADMIN` cap during init then dropped. More moving parts.

Recommend the sidecar proxy — fewer privileges, easier to audit, easier for users to extend the allowlist for their own dev needs. **Decision needed**: ship it on by default, or as an opt-in `docker-compose.hardened.yml` overlay?

### 3.2 Read-only root filesystem (S)
Add `read_only: true` and `tmpfs: [/tmp]` to the compose service. `/workspace` and `/home/claudeuser` are bind mounts and stay writable. Prevents tampering with installed binaries / system files even if something inside the container is compromised.

### 3.3 PID and file-descriptor limits (S)
Add `pids_limit: 512` and `ulimits: { nofile: 4096 }`. Cheap defense against fork bombs / fd exhaustion.

### 3.4 Token file permissions (S)
After first login, document `chmod 600 claude_home/.claude/.credentials.json` (or whatever the actual filename is — verify). The OAuth token is the most sensitive thing on disk; default umask may leave it group-readable.

### 3.5 Don't bring host secrets into the container (doc-only, S)
README should explicitly warn: do NOT mount `~/.ssh`, `~/.aws`, `~/.gnupg`, etc. into the container. If a project needs git push access, document per-project deploy keys stored *inside* `projects/<name>/` and treated as project-scoped.

### 3.6 Per-project container = per-project blast radius (doc-only, S)
The architecture already enforces this (one mount, one project). Just call it out in SECURITY.md so users understand why they shouldn't symlink in their home dir.

### 3.7 Threat model — write it down (SECURITY.md, S)
**What the container protects against:**
- Claude (or a prompt injection) running arbitrary code that touches the host outside the project dir.
- Privilege escalation to root on host.
- Resource exhaustion taking down the host.
- (With §3.1) silent exfiltration to arbitrary endpoints.

**What it does NOT protect against:**
- Modification/deletion of files inside the mounted project dir — that's the whole point of the tool.
- Theft of the Claude OAuth token if `claude_home/` is readable to other users on the host.
- Anything that compromises the Docker daemon itself.
- Anyone with `docker` group membership on the host (equivalent to root).
- Supply chain attacks on `@anthropic-ai/claude-code`, base image, or any package Claude installs into the project.

### 3.8 Optional / "nice to have" (defer unless asked)
- **userns-remap** — strong UID isolation, but global Docker daemon config; awkward for a clone-and-run repo. Mention in SECURITY.md as "advanced users can enable."
- **AppArmor/SELinux profile** — distro-specific, high friction. Default Docker profile is fine for v1.
- **Image signing / SBOM** — useful if you publish prebuilt images to a registry; skip while users build locally.
- ~~**CI:** hadolint on Dockerfile, `docker compose config` validation, trivy scan on built image.~~ *(done in PR #6.)*

---

## 4. Suggested order of work

Ship in this order so each step is independently useful. **All six phases have shipped**; entries below are kept as historical context.

1. **Foundation (half-day):** LICENSE, `.env.example`, pin claude-code version, expand README to cover quick start + auth + daily usage. → Repo is now usable by a stranger. *(shipped: PR #1)*
2. **Multi-project (half-day):** parameterize compose, add `claude.sh` wrapper, add `projects/example/`, update README §5. → Multi-project workflow is obvious. *(shipped: PR #2)*
3. **Hardening pass 1 (1–2h):** read-only rootfs, tmpfs, pids_limit, ulimits, token chmod doc. All zero-risk additions. → Tighter defaults, no behavior change for users. *(shipped: PR #3)*
4. **SECURITY.md + threat model (1h):** write it down. → Sets expectations honestly. *(shipped: PR #4)*
5. **Network egress allowlist (half-day):** sidecar proxy + compose overlay. → The big security win. Shipped as opt-in `HARDENED=1`. *(shipped: PR #5)*
6. **CI + polish:** hadolint, compose lint, trivy, CONTRIBUTING.md, issue templates. Also adds `apt-get upgrade` in the Dockerfile to pull Debian security patches, plus `.hadolint.yaml` and `.trivyignore` for documented exceptions. *(shipped: PR #6)*

---

## 5. README outline (concrete sections)

```
# claude_in_container
<1-paragraph pitch: what + why>

## Prerequisites
- Docker Engine + Compose v2 — https://docs.docker.com/engine/install/
- (Linux) your user in the `docker` group, or use rootless Docker

## Quick start
1. git clone …
2. cp .env.example .env   # optional, only needed for `claude -p` headless mode
3. docker compose run --rm claude   # first run: interactive login, persists to ./claude_home
4. you're in the container at /workspace

## Daily usage
- Open a shell:  ./claude.sh shell <project>
- One-shot:      ./claude.sh run <project> -- -p "explain this repo"
- New project:   ./claude.sh new <project>

## Multiple projects
Each subdir of `projects/` is its own isolated workspace with its own Claude
context. Initialize a git repo inside it as normal — `projects/*` is gitignored
from THIS repo, so your project history stays separate.

Example:
  ./claude.sh new my-api
  cd projects/my-api && git init && …
  cd ../.. && ./claude.sh shell my-api

## Authentication
- Subscription (Pro/Team): first run logs you in interactively; credentials
  persist in `./claude_home/` and survive container restarts.
- Headless (`claude -p`): put `CLAUDE_CODE_OAUTH_TOKEN=…` in `.env`. Generate
  one with `claude setup-token` in an interactive session.

## Security model
Short summary + link to SECURITY.md. Highlight: container, not VM; mount only
the project dir; don't share `claude_home/` across users.

## Troubleshooting
- "Permission denied" on claude_home → UID mismatch, rebuild with `UID=$(id -u) docker compose build`
- Token expired → delete `claude_home/.claude/.credentials.json` and re-login
- …

## License
```

---

## 6. Locked decisions

1. **License:** MIT.
2. **Multi-project pattern:** parameterized single service named `claude` + `./claude.sh` wrapper script.
3. **Network allowlist:** ship as opt-in `docker-compose.hardened.yml` overlay; default behavior unchanged in v1.
4. **claude-code version:** keep `latest` in the Dockerfile. Add a README note: "if an update breaks the container, pin a known-good version by editing Dockerfile line 4 to `npm install -g @anthropic-ai/claude-code@<version>`."
5. **Example project:** ship `projects/example/` with a placeholder README; whitelist it in `projects/.gitignore`.
