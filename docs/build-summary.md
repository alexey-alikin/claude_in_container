# Build summary

Snapshot of the repo at phase 5. Intended for handing context to another AI or onboarding a new human reviewer quickly. For the evolving roadmap, see `PLAN.md`; for the security threat model, see `SECURITY.md`.

## What this repo is

A Docker setup for running Anthropic's Claude Code CLI inside a container with persistent OAuth login, per-project isolation, and an opt-in network egress allowlist. Aimed at developers who want safer Claude usage — especially when Claude processes untrusted input — without giving up subscription-mode login or daily-driver ergonomics.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Dockerfile` | `node:20-slim` + global install of `@anthropic-ai/claude-code` (at `latest`); creates non-root `claudeuser` whose UID matches the host via the `USER_UID` build arg. |
| `docker-compose.yml` | Single parameterized service named `claude`. Bind-mounts `./projects/${PROJECT}:/workspace` (errors if `PROJECT` unset) and `./claude_home:/home/claudeuser`. `cap_drop: ALL`, `no-new-privileges`, `read_only: true` with tmpfs `/tmp`, caps: 2 GB RAM, 1.0 CPU, `pids_limit: 512`, `nofile: 8192/16384`. Joins the named bridge network `egress`. |
| `docker-compose.hardened.yml` | Opt-in overlay. Sets `HTTP_PROXY`/`HTTPS_PROXY` on `claude`, flips `egress` to `internal: true` (no direct internet), adds `egress-proxy` sidecar on both `egress` and a new `internet` network. |
| `hardened/Dockerfile` | `alpine:3.21` + `tinyproxy`. |
| `hardened/tinyproxy.conf` | Listens on `0.0.0.0:8888`, `FilterDefaultDeny Yes`, `ConnectPort 443/563`. |
| `hardened/filter` | Starter allowlist: Anthropic API/OAuth/telemetry, GitHub, npm, PyPI. |
| `claude.sh` | Wrapper script. Subcommands: `new <name>`, `shell <name>`, `run <name> -- <args>`, `list`, `help`. Validates project names against `[a-zA-Z0-9_-]+`. Honors `HARDENED=1` env var to also apply the overlay. |
| `projects/` | Per-project workspaces, bind-mounted into the container. Everything inside is gitignored except `projects/example/` (whitelisted as a placeholder). |
| `claude_home/` | OAuth state, persisted across container restarts. Entirely gitignored. |
| `.env.example` | Template for `CLAUDE_CODE_OAUTH_TOKEN` (headless mode only). Real `.env` is gitignored. |
| `LICENSE` | MIT. |
| `README.md`, `SECURITY.md`, `PLAN.md` | User-facing docs and roadmap. |
| `docs/build-summary.md`, `docs/test-plan.md` | Meta-docs (this file and the test plan). |

## How a user interacts with it

```bash
# First-time setup
git clone <repo>
./claude.sh shell example       # interactive bash in the container
claude                          # then /login (persists to claude_home/)
exit

# Daily use
./claude.sh new my-api          # creates projects/my-api + git init
./claude.sh shell my-api        # shell in that project's container
./claude.sh run my-api -- -p "explain this repo"   # headless one-shot

# Hardened (network-allowlist) mode
HARDENED=1 ./claude.sh shell my-api
```

## Security posture

Enforced by the default compose config:

- non-root container user (UID matched to host)
- `cap_drop: ALL`, `no-new-privileges: true`
- read-only root filesystem + tmpfs at `/tmp`
- resource caps: 2 GB RAM, 1.0 CPU, 512 PIDs, 8192/16384 nofile
- project bind mount is the only host filesystem path the container can write to outside `claude_home/`

Added by `HARDENED=1` overlay:

- `claude` container loses direct internet access (joined to `internal: true` network)
- HTTP/HTTPS routed through `tinyproxy` with hostname allowlist (`hardened/filter`)
- non-HTTP egress (SSH, raw sockets) has no path to the outside

Explicitly NOT protected (see `SECURITY.md` for the full list):

- the project folder itself — Claude's whole job is to edit those files
- OAuth token if other host users can read `claude_home/` (mitigation: `chmod 700 claude_home/`)
- compromise of the Docker daemon or anyone in the host's `docker` group
- supply-chain attacks on claude-code, the base image, or packages Claude installs
- host-kernel exploits — Docker shares the kernel; this is not a VM

## Intentional simplifications

- `@anthropic-ai/claude-code` is not version-pinned (decision: accept `latest` drift, document the manual pin step in README troubleshooting if it ever breaks).
- The hardened-mode allowlist is HTTP/HTTPS-only and hostname-based; `tinyproxy` does not decrypt TLS.
- No CI in repo yet (planned: hadolint, compose lint, trivy scan).
- No `curl`/`wget` in the base image. Network-connectivity tests in `docs/test-plan.md` use a small `node` helper.

## Phase history

Each phase shipped as its own PR. Source of truth is `git log`; this is the elevator version.

1. License, README rewrite, `.env.example`, planning doc.
2. Parameterize compose, ship `claude.sh` wrapper, add `projects/example/` placeholder.
3. Hardening pass: read-only rootfs, tmpfs, pids/fd limits, `chmod` recommendation.
4. `SECURITY.md` threat model.
5. Hardened-mode overlay with `tinyproxy` egress allowlist; `docs/` meta-docs.
