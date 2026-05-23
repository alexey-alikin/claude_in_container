# claude_in_container

Run [Claude Code](https://docs.anthropic.com/claude-code) inside a Docker container with persistent login. Your OAuth credentials live in `./claude_home/`, so a Claude.ai Pro/Team subscription only has to log in once and survives container restarts. Each project gets its own isolated `/workspace`, so a misbehaving (or prompt-injected) session can't reach anything outside that folder.

## Prerequisites

- Docker Engine and Compose v2 — install instructions at https://docs.docker.com/engine/install/
- On Linux, your user must be in the `docker` group (or use rootless Docker). To add yourself: `sudo usermod -aG docker $USER`, then log out and back in (or run `newgrp docker` in the current shell).

## Quick start

```bash
git clone https://github.com/alexey-alikin/claude_in_container.git
cd claude_in_container

# First run: opens a shell inside the example project's container.
./claude.sh shell example

# Inside the container, log in once:
claude        # first run prompts you for login (theme + browser auth link)
```

Credentials are written to `./claude_home/` on the host and reused by every later run. On later runs, you can skip the shell step and start an interactive Claude session in one go: `./claude.sh run example`.

## Wrapper commands

| Command | What it does |
| --- | --- |
| `./claude.sh list` | List all projects under `projects/` |
| `./claude.sh new <name>` | Create `projects/<name>/` and `git init` inside it |
| `./claude.sh shell <name>` | Open a bash shell in the container for `<name>` (use this to inspect the environment, run git, or debug) |
| `./claude.sh run <name>` | Start an interactive Claude session in the container for `<name>` — one-step alternative to `shell` + typing `claude` |
| `./claude.sh run <name> -- <args>` | Forward `<args>` to `claude` inside the container — e.g. `-- -p "..."` for headless one-shots |
| `./claude.sh build [<args>]` | Rebuild the container image after editing the `Dockerfile`; forwards `<args>` to `docker compose build` (e.g. `--no-cache`, or a service name like `egress-proxy`) |
| `./claude.sh help` | Show usage |

The `--` in `run` is optional: omit it to start an interactive Claude session, or include it to forward flags to `claude` (e.g. `./claude.sh run my-api -- -p "summarize this repo"` runs `claude -p "summarize this repo"`). Project names must match `[a-zA-Z0-9_-]+`.

## Install (optional)

To call the wrapper from any directory as `cic` instead of `./claude.sh`:

```bash
make install      # installs ~/.local/bin/cic, a small launcher that execs this repo's claude.sh
make uninstall    # removes ~/.local/bin/cic (only if it points to this repo)
```

Both targets run on your **host** machine — `~/.local/bin/cic` is created in your host home directory, not inside the container. The launcher is just a 3-line bash script that execs this checkout's `claude.sh`, which in turn drives `docker compose`. Nothing about the container image or `claude_home/` changes.

After install you can run `cic shell example`, `cic new my-api`, etc. from anywhere. If `~/.local/bin` is not on your `PATH`, `make install` prints a warning telling you to add it to your shell rc — see the walkthrough below. The launcher hardcodes the absolute path to this checkout, so if you move the repo, re-run `make install`.

<details>
<summary>Add <code>~/.local/bin</code> to your PATH (click to expand)</summary>

If `cic` prints `command not found` after `make install`, your shell can't see `~/.local/bin` yet. The install itself worked — you just need to put that directory on your `PATH`.

1. Check which shell you're using:

   ```bash
   echo $SHELL
   ```

   - `/bin/bash` (or `/usr/bin/bash`) → edit `~/.bashrc`
   - `/bin/zsh` (or `/usr/bin/zsh`) — common on modern macOS — → edit `~/.zshrc`

2. Append the line `make install` told you to the right rc file. For bash:

   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   ```

   For zsh, swap `~/.bashrc` for `~/.zshrc`.

3. Reload the rc file in your current terminal (or just open a new one):

   ```bash
   source ~/.bashrc    # or: source ~/.zshrc
   ```

4. Verify:

   ```bash
   which cic
   ```

   Should print `/home/<you>/.local/bin/cic` on Linux, or `/Users/<you>/.local/bin/cic` on macOS. Once that resolves, `cic shell example` will work from any directory.

</details>

## Daily usage

Start an interactive Claude session directly in a project (one step):

```bash
./claude.sh run my-project
```

Open a bash shell in the container instead — useful for running `git`, inspecting `/workspace`, or debugging. From inside that shell you can also run `claude` to start an interactive session:

```bash
./claude.sh shell my-project
```

Run a one-shot Claude command (headless mode, requires `CLAUDE_CODE_OAUTH_TOKEN` — see Authentication):

```bash
./claude.sh run my-project -- -p "explain the files in this repo"
```

The container's `/workspace` is bind-mounted to `./projects/my-project/` on your host. Put your code there; edits sync both ways instantly.

Other wrapper commands: `./claude.sh list` shows all projects, `./claude.sh help` shows full usage.

## Pushing your work to a remote

The container has `git` installed, so `git init`, `git add`, and `git commit` work inside it with no extra setup. **Pushing** to GitHub is where you choose how much you want to trust Claude with your credentials.

**Option A — push from the host (recommended).** No credentials enter the container, so a prompt-injected session cannot push anywhere.

1. Ask Claude to do the work on a feature branch (not `main`):

   > "Create a branch `feat/add-login`, make the changes, commit them with a clear message. Do not push."

   Claude commits locally inside the container; because `/workspace` is bind-mounted, those commits are immediately visible on the host.

2. On the host, open a second terminal and finish the workflow yourself:

   ```bash
   cd projects/my-project
   git push -u origin feat/add-login
   # …review on GitHub, merge the PR…
   git checkout main && git pull
   git branch -d feat/add-login
   ```

This works with your existing host setup — whatever SSH key, agent, or `gh` login you already use. Nothing about it is container-aware.

**Option B — let Claude read or write directly (more convenient, narrower trust).** Requires a token in `.env`. With `GITHUB_TOKEN` set, Claude can also `git clone` and `fetch` private repos using the same `https://x-access-token:${GITHUB_TOKEN}@github.com/owner/repo` URL pattern, scoped to whatever permissions you granted the token.

1. Create a fine-grained GitHub PAT scoped to a single repo with `Contents: Read & write` (add `Pull requests: Read & write` if Claude should open PRs) and a 30–90 day expiry.

   <details>
   <summary>Step-by-step walkthrough on github.com (click to expand)</summary>

   1. Open <https://github.com/settings/tokens?type=beta> (or GitHub → your avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**).
   2. Click **Generate new token**.
   3. **Token name:** something descriptive, e.g. `claude_in_container — my-project`.
   4. **Expiration:** 30–90 days. Short expiries mean a leaked token self-heals.
   5. **Resource owner:** your user (or the org that owns the repo).
   6. **Repository access:** **Only select repositories** → pick the single repo Claude will push to. Do **not** pick `All repositories`.
   7. **Repository permissions:** set `Contents` to **Read and write**. If you also want Claude to open PRs, set `Pull requests` to **Read and write** too. Leave everything else as `No access`. `Metadata: Read-only` is granted automatically — that's fine.
   8. Click **Generate token** and copy the value immediately (GitHub only shows it once). It looks like `github_pat_…` (fine-grained) or `ghp_…` (classic).

   </details>

2. Add it to `.env`:

   ```
   GITHUB_TOKEN=github_pat_xxxxxxxxxxxxxxxxxxxx
   ```
3. Inside the container, point the remote at an HTTPS URL that uses the token, then push as normal:

   ```bash
   git remote add origin https://x-access-token:${GITHUB_TOKEN}@github.com/you/my-project.git
   git push -u origin feat/add-login
   ```

A prompt-injected session can use this token within its scope (one repo, the permissions you granted). Keep the scope narrow and rotate or revoke from GitHub Settings if anything looks off. See [SECURITY.md](SECURITY.md#giving-git-access-to-the-container) for the full trade-off and why mounting `~/.ssh` is not recommended.

## Authentication

Two modes, pick whichever you need:

**Subscription (interactive).** Run `claude` inside the container. On first start it prompts you through login (theme picker, then a browser auth link; exact UX varies by version). Credentials persist in `./claude_home/`, so later runs skip the flow. No `.env` file needed.

**Headless (`claude -p "..."`).** Requires an OAuth token in a `.env` file:

```bash
cp .env.example .env
# Then generate a token from inside an interactive session:
#   ./claude.sh run example -- setup-token
# Paste the token into .env as CLAUDE_CODE_OAUTH_TOKEN=...
```

## Keep your secrets out of git

Two paths in this repo can hold credentials. Both are already gitignored — keep them that way and never share them.

- **`.env`** — holds `CLAUDE_CODE_OAUTH_TOKEN` (Claude headless mode) and optionally `GITHUB_TOKEN` (if you use [Option B](#pushing-your-work-to-a-remote) for pushing). Ignored by `.gitignore` at the repo root.
- **`claude_home/`** — holds the OAuth credentials saved during interactive login. Ignored by `claude_home/.gitignore` (everything inside the folder is excluded).

A leaked Claude credential lets anyone use your Claude.ai subscription. A leaked `GITHUB_TOKEN` lets anyone push to (and read from) whatever repo you scoped it to. Treat both like passwords:

- Don't remove those `.gitignore` entries.
- Don't paste these files into chat tools, screenshots, gists, or pastebins.
- If you fork or copy this repo, double-check the `.gitignore` files came along.
- If you accidentally commit a `CLAUDE_CODE_OAUTH_TOKEN` or `claude_home/` contents, rotate by deleting `claude_home/` and re-running `claude` to redo the login flow; also revoke any leaked `CLAUDE_CODE_OAUTH_TOKEN` from your Anthropic account.
- If you accidentally commit a `GITHUB_TOKEN`, revoke it at GitHub → Settings → Developer settings → Personal access tokens, then generate a new one and update `.env`.

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

## Extending the container (advanced)

The `Dockerfile` ships with a deliberately minimal toolset: `git`, `node`, and `@anthropic-ai/claude-code`. If your project needs more — `python3`, `make`, `go`, a specific linter — add it to the `apt-get install` line (or a new `RUN` step) and rebuild:

```bash
./claude.sh build
```

The next `./claude.sh shell <project>` or `./claude.sh run <project>` will pick up the new image. The default user inside the container is unprivileged, the filesystem is read-only, and no Linux capabilities are granted — so install everything at build time; runtime `sudo` / `apt install` will fail by design.

**Don't add Docker access** (`docker.sock` mount, `dind`, `--privileged`). It looks convenient but effectively gives anything inside the sandbox root on your host, which defeats the entire reason this repo exists. If you need Claude to build container images, run those builds on the host outside the sandbox.

**Claude is already aware of these constraints.** `claude_home/.claude/CLAUDE.md` is loaded automatically at the start of every session and tells the model about the writable paths, network restrictions, and how to ask you to add a missing tool rather than trying to install it itself. You can edit it to layer your own preferences on top.

## Security model (short version)

What the container protects against:

- Code run by Claude touching files outside `./projects/<name>/` on your host
- Privilege escalation to root inside the container (no capabilities, `no-new-privileges`)
- Tampering with installed system binaries — the container's root filesystem is read-only; only `/workspace`, `/home/claudeuser`, and `/tmp` (an in-memory tmpfs) are writable
- Unbounded resource use (memory, CPU, processes, and open file descriptors are all capped per container)

What it does NOT protect against:

- Anything Claude does to files inside the mounted project folder — that's the point of the tool
- Theft of the OAuth token in `./claude_home/` if other users on your host can read it (see [Keep your secrets out of git](#keep-your-secrets-out-of-git) for the `chmod` recommendation)
- Network exfiltration: in default mode the container has full outbound internet access (see [Hardened mode](#hardened-mode-network-allowlist) for an opt-in egress allowlist)
- Compromise of the Docker daemon or anyone in the `docker` group on the host

For the full threat model — including what's _not_ protected and how to harden further — see [SECURITY.md](SECURITY.md).

## Hardened mode (network allowlist)

By default the container has unrestricted internet access. The repo ships an opt-in overlay that locks egress to a small allowlist of domains via a `tinyproxy` sidecar — Anthropic's API, GitHub, npm, and PyPI by default.

Enable it by setting `HARDENED=1`:

```bash
HARDENED=1 ./claude.sh shell my-project
HARDENED=1 ./claude.sh run my-project -- -p "explain this repo"
```

In hardened mode the `claude` container is moved onto an internal-only Docker network and can only reach the outside world by going through the proxy. Direct connections to anything not on the allowlist will fail.

The allowlist lives in [`hardened/filter`](hardened/filter) — edit it to add hosts your projects need (e.g. `^crates\.io$` for Rust, `^rubygems\.org$` for Ruby), then rebuild the proxy:

```bash
HARDENED=1 ./claude.sh build egress-proxy
```

Notes and limitations:

- Only HTTP and HTTPS (`CONNECT` method) are filtered. Other protocols (SSH, raw sockets) just fail outright in hardened mode — no direct egress is possible.
- Hostname matching only: `tinyproxy` does not decrypt TLS, so it cannot filter by URL path inside HTTPS requests. Anything served from an allowed host is reachable.
- Tools that ignore the `HTTP_PROXY`/`HTTPS_PROXY` env vars will fail to reach the internet. For Claude Code and most package managers this is the intended behavior.

## Troubleshooting

**Permission errors on `./claude_home/` or `./projects/` (Linux).** The container's user UID must match your host UID. Rebuild with your UID baked in:

```bash
UID=$(id -u) ./claude.sh build
```

**Claude Code update broke the container.** The Dockerfile installs `@anthropic-ai/claude-code` at `latest`. If a new release breaks things, pin a known-good version: edit `Dockerfile` line 4 to read

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@<version>
```

then `./claude.sh build` again.

**Login stopped working.** Delete the contents of `./claude_home/` and run `claude` again — the next start re-prompts for login.

## License

MIT — see [LICENSE](LICENSE).
