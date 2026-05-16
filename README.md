# claude_in_container

Run [Claude Code](https://docs.anthropic.com/claude-code) inside a Docker container with persistent login. Your OAuth credentials live in `./claude_home/`, so a Claude.ai Pro/Team subscription only has to log in once and survives container restarts. Each project gets its own isolated `/workspace`, so a misbehaving (or prompt-injected) session can't reach anything outside that folder.

## Prerequisites

- Docker Engine and Compose v2 — install instructions at https://docs.docker.com/engine/install/
- On Linux, your user must be in the `docker` group (or use rootless Docker)

## Quick start

```bash
git clone https://github.com/alexey-alikin/claude_in_container.git
cd claude_in_container

# First run: opens a shell inside the container.
docker compose run --rm project-a

# Inside the container, log in once:
claude        # then run /login and follow the prompts
```

Credentials are written to `./claude_home/` on the host and reused by every later run.

## Daily usage

Open an interactive shell in the project:

```bash
docker compose run --rm project-a
```

Run a one-shot Claude command (headless mode, requires `CLAUDE_CODE_OAUTH_TOKEN` — see Authentication):

```bash
docker compose run --rm project-a claude -p "explain the files in this repo"
```

The container's `/workspace` is bind-mounted to `./projects/project-a/` on your host. Put your code there; edits sync both ways instantly.

## Authentication

Two modes, pick whichever you need:

**Subscription (interactive).** Run `claude` inside the container, type `/login`, complete the browser flow. Credentials persist in `./claude_home/`. No `.env` file needed.

**Headless (`claude -p "..."`).** Requires an OAuth token in a `.env` file:

```bash
cp .env.example .env
# Then generate a token from inside an interactive session:
#   docker compose run --rm project-a claude setup-token
# Paste the token into .env as CLAUDE_CODE_OAUTH_TOKEN=...
```

## Keep your secrets out of git

Two files in this repo contain credentials that grant access to your Claude account. Both are already gitignored — keep them that way and never share them.

- **`.env`** — holds `CLAUDE_CODE_OAUTH_TOKEN`. Ignored by `.gitignore` at the repo root.
- **`claude_home/`** — holds the OAuth credentials saved by `/login`. Ignored by `claude_home/.gitignore` (everything inside the folder is excluded).

A leaked token lets anyone use your Claude.ai subscription, so:

- Don't remove those `.gitignore` entries.
- Don't paste these files into chat tools, screenshots, gists, or pastebins.
- If you fork or copy this repo, double-check the `.gitignore` files came along.
- If you accidentally commit a token, rotate it immediately by deleting `claude_home/` and re-running `/login` (and revoke any leaked `CLAUDE_CODE_OAUTH_TOKEN` from your Anthropic account).

If you initialize your own git repo inside `projects/<name>/`, treat it as a separate project and make sure secrets for that project also stay out of its history.

## Multiple projects

Each project is a folder under `projects/` mounted into its own container. The contents of `projects/*` are gitignored from this repo, so each project can have its own independent git history.

Right now the compose file defines a single service named `project-a`. To add a second project, copy the `project-a` block in `docker-compose.yml`, rename it, and point its volume at the new folder:

```yaml
  project-b:
    build:
      context: .
      args:
        USER_UID: ${UID:-1000}
    stdin_open: true
    tty: true
    env_file:
      - path: .env
        required: false
    volumes:
      - ./projects/project-b:/workspace
      - ./claude_home:/home/claudeuser
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 2g
    cpus: 1.0
```

Then `docker compose run --rm project-b`. A wrapper script that removes this boilerplate is planned (see `PLAN.md`).

## Security model (short version)

What the container protects against:

- Code run by Claude touching files outside `./projects/<name>/` on your host
- Privilege escalation to root inside the container (no capabilities, `no-new-privileges`)
- Unbounded resource use (memory and CPU are capped per service)

What it does NOT protect against:

- Anything Claude does to files inside the mounted project folder — that's the point of the tool
- Theft of the OAuth token in `./claude_home/` if other users on your host can read it
- Network exfiltration: the container currently has full outbound internet access
- Compromise of the Docker daemon or anyone in the `docker` group on the host

A stricter network-allowlist overlay and a full `SECURITY.md` are on the roadmap.

## Troubleshooting

**Permission errors on `./claude_home/` or `./projects/` (Linux).** The container's user UID must match your host UID. Rebuild with your UID baked in:

```bash
UID=$(id -u) docker compose build
```

**Claude Code update broke the container.** The Dockerfile installs `@anthropic-ai/claude-code` at `latest`. If a new release breaks things, pin a known-good version: edit `Dockerfile` line 4 to read

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@<version>
```

then `docker compose build` again.

**Login stopped working.** Delete the contents of `./claude_home/` and run `claude` → `/login` again.

## License

MIT — see [LICENSE](LICENSE).
