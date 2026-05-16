# claude_in_container

Run [Claude Code](https://docs.anthropic.com/claude-code) inside a Docker container with persistent login. Your OAuth credentials live in `./claude_home/`, so a Claude.ai Pro/Team subscription only has to log in once and survives container restarts. Each project gets its own isolated `/workspace`, so a misbehaving (or prompt-injected) session can't reach anything outside that folder.

## Prerequisites

- Docker Engine and Compose v2 — install instructions at https://docs.docker.com/engine/install/
- On Linux, your user must be in the `docker` group (or use rootless Docker)

## Quick start

```bash
git clone https://github.com/alexey-alikin/claude_in_container.git
cd claude_in_container

# First run: opens a shell inside the example project's container.
./claude.sh shell example

# Inside the container, log in once:
claude        # then run /login and follow the prompts
```

Credentials are written to `./claude_home/` on the host and reused by every later run.

## Wrapper commands

| Command | What it does |
| --- | --- |
| `./claude.sh list` | List all projects under `projects/` |
| `./claude.sh new <name>` | Create `projects/<name>/` and `git init` inside it |
| `./claude.sh shell <name>` | Open a bash shell in the container for `<name>` |
| `./claude.sh run <name> -- <args>` | Run `claude <args>` in the container for `<name>` |
| `./claude.sh help` | Show usage |

In `run`, the `--` separates wrapper arguments from arguments forwarded to `claude`. For example, `./claude.sh run my-api -- -p "summarize this repo"` runs `claude -p "summarize this repo"` inside the container for `my-api`. Project names must match `[a-zA-Z0-9_-]+`.

## Daily usage

Open an interactive shell in a project:

```bash
./claude.sh shell my-project
```

Run a one-shot Claude command (headless mode, requires `CLAUDE_CODE_OAUTH_TOKEN` — see Authentication):

```bash
./claude.sh run my-project -- -p "explain the files in this repo"
```

The container's `/workspace` is bind-mounted to `./projects/my-project/` on your host. Put your code there; edits sync both ways instantly.

Other wrapper commands: `./claude.sh list` shows all projects, `./claude.sh help` shows full usage.

## Authentication

Two modes, pick whichever you need:

**Subscription (interactive).** Run `claude` inside the container, type `/login`, complete the browser flow. Credentials persist in `./claude_home/`. No `.env` file needed.

**Headless (`claude -p "..."`).** Requires an OAuth token in a `.env` file:

```bash
cp .env.example .env
# Then generate a token from inside an interactive session:
#   ./claude.sh run example -- setup-token
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

On a shared host (laptop with multiple user accounts, dev server, etc.), also restrict filesystem permissions on `claude_home/` so other users on the same machine can't read your OAuth credentials:

```bash
chmod 700 claude_home/
```

Git-ignoring isn't enough on its own — anyone with shell access to your host can read the file otherwise.

If you initialize your own git repo inside `projects/<name>/`, treat it as a separate project and make sure secrets for that project also stay out of its history.

## Multiple projects

Each subfolder of `projects/` is its own workspace with its own Claude session. Manage them with the wrapper:

```bash
./claude.sh new my-api      # create projects/my-api and git init it
./claude.sh new other-app   # second project, fully independent
./claude.sh list            # show all projects
./claude.sh shell my-api    # open a shell in the my-api container
```

You can freely `git init`, `git remote add`, and `git push` inside any project folder — `projects/*` is gitignored from this repo (except the `example/` placeholder), so each project keeps its own git history completely separate from this one.

The compose file still works directly if you prefer: `PROJECT=my-api docker compose run --rm claude`. The wrapper is just sugar on top.

## Security model (short version)

What the container protects against:

- Code run by Claude touching files outside `./projects/<name>/` on your host
- Privilege escalation to root inside the container (no capabilities, `no-new-privileges`)
- Tampering with installed system binaries — the container's root filesystem is read-only; only `/workspace`, `/home/claudeuser`, and `/tmp` (an in-memory tmpfs) are writable
- Unbounded resource use (memory, CPU, processes, and open file descriptors are all capped per container)

What it does NOT protect against:

- Anything Claude does to files inside the mounted project folder — that's the point of the tool
- Theft of the OAuth token in `./claude_home/` if other users on your host can read it (see [Keep your secrets out of git](#keep-your-secrets-out-of-git) for the `chmod` recommendation)
- Network exfiltration: the container currently has full outbound internet access
- Compromise of the Docker daemon or anyone in the `docker` group on the host

For the full threat model — including what's _not_ protected and how to harden further — see [SECURITY.md](SECURITY.md). A stricter network-egress allowlist is still on the roadmap.

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
