# Test plan

Manual smoke tests for the repo. Two parts: **basic mode** (default) and **hardened mode** (`HARDENED=1`). All commands are run from the repo root on your host. Mark each step PASS or FAIL when reporting results.

## Assumptions

- Docker Engine + Compose v2 are installed and your user can run `docker`.
- You have cloned the repo and `cd`'d into it.
- A Claude.ai account is available for the login step. Headless tests that need an OAuth token are clearly marked optional.

## Fresh-clone smoke test (release sanity check)

Run this when you want to verify the repo works for a brand-new user — fresh clone, no cached image layers, no leftover state from your dev work. Skip if you're just iterating locally.

```bash
# Clone fresh into a scratch dir outside your working copy.
cd /tmp && rm -rf cic-smoke && mkdir cic-smoke && cd cic-smoke
git clone https://github.com/alexey-alikin/claude_in_container.git
cd claude_in_container

# Force a rebuild from scratch (no layer cache reuse).
PROJECT=example docker compose build --no-cache claude

# First start — should land you in /workspace as claudeuser.
./claude.sh shell example
```

**Expected:** `--no-cache` build runs every Dockerfile step from scratch (no `CACHED` markers); the shell opens and `id -un` returns `claudeuser`. From here, walk through Part 1 below.

For hardened mode, additionally:

```bash
PROJECT=example docker compose -f docker-compose.yml -f docker-compose.hardened.yml \
  build --no-cache egress-proxy
HARDENED=1 ./claude.sh shell example
```

Then walk through Part 2.

## The `node` helper for connectivity tests

The base image ships with `node` but not `curl`/`wget`. This helper uses Node's built-in `fetch` and routes through the proxy when `HTTPS_PROXY` is set (i.e. in hardened mode). Define it once at the start of any in-container shell:

```bash
test_url() {
  node -e "
    const url = process.argv[1];
    const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
    const opts = {};
    if (proxy) {
      const { ProxyAgent } = require('undici');
      opts.dispatcher = new ProxyAgent(proxy);
    }
    fetch(url, opts)
      .then(r => console.log(url, '->', r.status))
      .catch(e => console.error(url, '-> FAIL:', e.message));
  " "$1"
}
```

`test_url https://example.com` will print `https://example.com -> 200` on success, or `-> FAIL: <reason>` on a network error. For proxy-blocked requests in hardened mode it prints a 4xx status (the proxy's block page).

---

## Part 1 — basic mode

### 1.1 Wrapper script exists and parses

```bash
./claude.sh help
```

**Expected:** prints usage with subcommands `list`, `new`, `shell`, `run`, `help`; exits 0.

### 1.2 First container start

```bash
./claude.sh shell example
```

**Expected:**

- container image builds if not already (first run only)
- you land at a bash prompt as user `claudeuser`
- `pwd` shows `/workspace`
- `ls /workspace` shows the contents of `./projects/example/` on your host
- `id -un` returns `claudeuser`

### 1.3 First login

Inside the container (still in the shell from 1.2):

```bash
claude
# on first run, claude prompts you through login automatically:
#   - pick a theme
#   - open the printed auth link on your host, complete the flow, paste the code back
# (exact prompts may vary by claude-code version)
/exit
```

Then on the **host** (outside the container):

```bash
ls -la claude_home/.claude/
```

**Expected:** `.credentials.json` is listed (it starts with a dot, so plain `ls` would hide it).

### 1.4 Login persists across restarts

Exit the container, then on the host:

```bash
./claude.sh shell example
```

Inside the new shell:

```bash
claude
```

**Expected:** Claude starts without prompting for login — the credentials from 1.3 are reused. Type `/exit` to return to the shell.

### 1.5 Filesystem isolation (read-only rootfs)

Inside `./claude.sh shell example`:

```bash
touch /workspace/probe && rm /workspace/probe              # OK (bind mount)
touch /home/claudeuser/probe && rm /home/claudeuser/probe  # OK (bind mount)
touch /tmp/probe && rm /tmp/probe                          # OK (tmpfs)
touch /usr/probe                                            # FAILS
touch /etc/probe                                            # FAILS
```

**Expected:** first three commands succeed silently. Last two fail with `Read-only file system`.

### 1.6 Project creation and listing

```bash
./claude.sh new test-proj
./claude.sh list
ls projects/test-proj/.git    # confirm git init happened
rm -rf projects/test-proj
```

**Expected:** `list` shows `example` and `test-proj`; `.git/` exists in the new project.

### 1.7 Invalid project names are rejected

```bash
./claude.sh new 'bad name'         # space
./claude.sh new ../escape          # path component
./claude.sh shell does-not-exist
```

**Expected:**

- first two fail with `error: invalid project name`
- third fails with `error: projects/does-not-exist does not exist`
- script exits non-zero in each case

### 1.8 Network is unrestricted in basic mode

Inside `./claude.sh shell example`, define `test_url` (see top of file), then:

```bash
test_url https://api.anthropic.com
test_url https://github.com
test_url https://example.com
```

**Expected:** all three print a real status line from the upstream server (e.g. `-> 200`, `-> 301`, `-> 404`). None print `FAIL`. A 404 from `api.anthropic.com` is fine — it means the request reached the upstream, which is what this step verifies.

### 1.9 `make install` puts a working `cic` launcher on the host

On the host (not inside the container):

```bash
make install
ls -la ~/.local/bin/cic
cat ~/.local/bin/cic
```

**Expected:**

- `~/.local/bin/cic` exists, is executable, and its body is a 3-line bash script that ends with `exec "<absolute path to this repo>/claude.sh" "$@"`.
- If `~/.local/bin` is not already in `PATH`, `make install` prints a warning with the `export PATH=...` line to add.

Then verify the launcher actually invokes the wrapper from a different working directory:

```bash
cd /tmp
PATH="$HOME/.local/bin:$PATH" cic help | head -3
PATH="$HOME/.local/bin:$PATH" cic list
```

**Expected:** `cic help` prints the wrapper's `Usage: ./claude.sh ...` banner; `cic list` prints the same project list as `./claude.sh list` would from the repo root (at minimum `example`). The `PATH=` prefix is only needed for this test if `~/.local/bin` is not already on your `PATH`.

### 1.10 `make uninstall` removes the launcher safely

Happy path:

```bash
make uninstall
ls ~/.local/bin/cic 2>&1 || echo "(gone)"
```

**Expected:** prints `removed ~/.local/bin/cic`; the file is gone. A second `make uninstall` prints `not installed; nothing to do` and exits 0.

Refusal path — the launcher must not delete a file it didn't install:

```bash
make install
# corrupt the launcher so it points at a fake path:
printf '%s\n' '#!/usr/bin/env bash' 'exec "/elsewhere/claude.sh" "$@"' > ~/.local/bin/cic
chmod +x ~/.local/bin/cic
make uninstall ; echo "exit=$?"
ls ~/.local/bin/cic    # still there
```

**Expected:** `make uninstall` prints `error: ... does not reference <repo>/claude.sh; refusing to remove` and exits non-zero; the file is still present. Clean up afterward with `rm ~/.local/bin/cic`.

### 1.11 Git HTTPS to GitHub works (no credentials)

Inside `./claude.sh shell example`:

```bash
git ls-remote https://github.com/octocat/Hello-World.git | head -3
```

**Expected:** prints the first few refs (`HEAD`, `refs/heads/master`, …) and exits 0. No `server certificate verification failed. CAfile: none CRLfile: none` error. This verifies the `ca-certificates` bundle is installed and trusted, so git can validate GitHub's TLS cert without falling back to `GIT_SSL_NO_VERIFY=1`.

### 1.12 `GITHUB_TOKEN` reaches the container when set in `.env` — optional

Back up your `.env` first if it has real values. Then on the host:

```bash
printf 'GITHUB_TOKEN=test-token-123\n' >> .env
./claude.sh shell example
```

Inside the container:

```bash
printenv GITHUB_TOKEN     # → test-token-123
```

**Expected:** the value matches what was in `.env`. Exit the shell and remove the line from `.env` afterward.

If you have a fine-grained PAT (see README → Pushing your work to a remote, Option B), additionally verify the URL-embedded token works for a private repo you own:

```bash
git ls-remote https://x-access-token:${GITHUB_TOKEN}@github.com/<you>/<your-private-repo>.git | head -3
```

**Expected:** prints refs and exits 0. A 401/403 means the token scope is too narrow or expired, not a container bug.

### 1.13 Headless mode — optional, requires OAuth token

```bash
# On the host, generate the token from an interactive shell first:
./claude.sh shell example
claude setup-token
# copy the token, exit the container, paste into .env as
#   CLAUDE_CODE_OAUTH_TOKEN=...

./claude.sh run example -- -p "say hello"
```

**Expected:** Claude responds with a greeting; the command exits 0.

---

## Part 2 — hardened mode

### 2.1 First hardened start builds the proxy

```bash
HARDENED=1 ./claude.sh shell example
```

**Expected:**

- on first run, Compose builds the `egress-proxy` image from `hardened/Dockerfile` (~30 s, downloading Alpine + `tinyproxy`)
- both containers start: `claude` and `egress-proxy`
- you land at a bash prompt in the `claude` container as before
- `env | grep -i proxy` shows `HTTP_PROXY=http://egress-proxy:8888` and similar for HTTPS / lowercase variants

### 2.2 Allowed hosts work through the proxy

Inside the hardened container, define `test_url` (see top of file), then:

```bash
test_url https://api.anthropic.com
test_url https://github.com
test_url https://registry.npmjs.org
```

**Expected:** all three print a real status line from the upstream server (e.g. `-> 200`, `-> 301`, `-> 404`). None print `FAIL`.

### 2.3 Disallowed hosts are blocked by the proxy

```bash
test_url https://example.com
test_url https://www.google.com
```

**Expected:** both return a 4xx status — `tinyproxy` serves its block page. The exact status is typically `403`. You should NOT see content from the real upstream.

### 2.4 Direct (non-proxy) egress is impossible

```bash
node -e "fetch('https://api.anthropic.com').then(r => console.log(r.status)).catch(e => console.error('FAIL:', e.message))"
```

(This call deliberately does NOT use the proxy.)

**Expected:** `FAIL: …` with a network error (`getaddrinfo ENOTFOUND`, `Connect Timeout`, or similar). The `claude` container is on an `internal: true` network and has no path to the outside without the proxy.

### 2.5 Claude itself works in hardened mode

Exit the shell from 2.1, then on the host:

```bash
HARDENED=1 ./claude.sh run example -- -p "say hello"
```

**Expected:** Claude responds normally. `api.anthropic.com` is on the allowlist.

### 2.6 Allowlist is editable

On the host:

```bash
echo '^example\.com$' >> hardened/filter
docker compose -f docker-compose.yml -f docker-compose.hardened.yml build egress-proxy
HARDENED=1 ./claude.sh shell example
```

Inside the rebuilt hardened container:

```bash
test_url https://example.com
```

**Expected:** prints `-> 200` (or another real status from `example.com`). Revert `hardened/filter` afterward if you don't want to keep the entry.

### 2.7 Basic mode is unaffected by the hardened overlay

```bash
./claude.sh shell example      # WITHOUT HARDENED=1
```

Inside (with `test_url` defined):

```bash
test_url https://example.com
```

**Expected:** `-> 200`. No allowlist applies, identical to Part 1.8.

---

## Reporting results

When sharing results, include:

- OS and Docker version (`docker version`, `docker compose version`)
- which step (e.g. `2.3`) failed and the exact output
- whether the failure is reproducible
- whether you modified `hardened/filter` and forgot to revert
