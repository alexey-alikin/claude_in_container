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
./claude.sh build --no-cache

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

The base image ships with `node` and `curl` (but not `wget`). This helper uses Node's built-in `fetch` so it stays self-contained regardless of which HTTP tools are installed, and routes through the proxy when `HTTPS_PROXY` is set (i.e. in hardened mode). Define it once at the start of any in-container shell:

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

### 1.5a Python is available and usable via a venv

Inside `./claude.sh shell example`:

```bash
python3 --version                                          # prints a 3.x version
python3 -m venv /workspace/.venv                           # OK (/workspace is writable)
. /workspace/.venv/bin/activate && pip --version           # OK inside the venv
deactivate
rm -rf /workspace/.venv
pip install --break-system-packages requests               # FAILS (read-only rootfs)
```

**Expected:** `python3 --version` prints `Python 3.x`; the venv is created and `pip --version` works inside it; the final global `pip install` fails with a read-only filesystem error (and/or a PEP 668 externally-managed-environment notice). Confirms Python works while global installs stay blocked by design.

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

If you have a fine-grained PAT (see README → Pushing your work to a remote, Option B), additionally verify the shipped `claude_home/.gitconfig` auto-rewrites SSH GitHub URLs to HTTPS and supplies the token from the env var. Replace the placeholder with the value from `.env`, then inside the container:

```bash
git ls-remote git@github.com:<you>/<your-private-repo>.git | head -3
```

**Expected:** prints refs and exits 0, with no SSH error and without you having to construct a token URL. This proves both the `url.insteadOf` rewrite and the credential helper are wired up. A 401/403 means the token scope is too narrow or expired, not a container bug.

Then verify the helper fails closed rather than silently when the token is missing:

```bash
GITHUB_TOKEN= git ls-remote git@github.com:<you>/<your-private-repo>.git
```

**Expected:** exits non-zero with `fatal: Authentication failed` (or similar HTTP 401 message). It must NOT hang waiting for input and must NOT succeed — a regression where the helper silently outputs empty credentials would let unrelated code paths look like they're working when they aren't.

### 1.13 First-run bootstraps git identity from the host

On the host, with a clean `claude_home/`:

```bash
rm -f claude_home/.gitconfig.local
./claude.sh build
```

**Expected:**

- the wrapper prints a `First-time setup:` message naming the `name` / `email` it read from `git config --global user.{name,email}`
- `cat claude_home/.gitconfig.local` shows a `[user]` block with that name and email
- a second `./claude.sh build` is silent (the file already exists; bootstrap is idempotent)

Sanity-check the include path actually reaches the container:

```bash
./claude.sh shell example
# inside the container:
git config --get user.email     # should print the host email
exit
```

Fallback when the host has no identity (run only if you don't mind temporarily clearing your global git config — back it up first):

```bash
rm -f claude_home/.gitconfig.local
git config --global --unset user.name 2>/dev/null || true
git config --global --unset user.email 2>/dev/null || true
./claude.sh build
# restore your host identity afterwards
```

**Expected:** wrapper prints a `note:` line saying host identity is not configured and points at `claude_home/.gitconfig.local`. No file is created; subsequent runs print the same note until the user fixes it on the host or creates the file by hand.

Opt-out:

```bash
rm -f claude_home/.gitconfig.local
CIC_SKIP_GIT_IDENTITY=1 ./claude.sh build
ls claude_home/.gitconfig.local 2>&1 || echo "(not created — correct)"
```

**Expected:** no `First-time setup:` message, no file created. Re-running without the env var on a host with identity configured creates the file as in the happy path above.

### 1.14 Headless mode — optional, requires OAuth token

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

### 2.3a Hostname-spoofing bypass attempts are blocked

The allowlist relies on anchored regexes (`^github\.com$`) with `FilterDefaultDeny Yes`. This step proves the anchors actually hold, so an allowed token embedded in a hostile hostname can't slip through. It also guards against a future edit to `hardened/filter` that drops an anchor.

```bash
test_url https://github.com.evil.com         # suffix after an allowed host
test_url https://notgithub.com               # allowed host as a prefix
test_url https://evil.github.com             # subdomain of an allowed host
test_url https://api.anthropic.com.evil.com  # suffix after a second allowed host
```

**Expected:** all four return a 4xx (`tinyproxy` block page), exactly as in 2.3. None reach a real upstream. If any returns a real status line, an allowlist entry is under-anchored — check `hardened/filter` for a missing `^` or `$`.

### 2.4 Direct (non-proxy) egress is impossible

```bash
node -e "fetch('https://api.anthropic.com').then(r => console.log(r.status)).catch(e => console.error('FAIL:', e.message))"
```

(This call deliberately does NOT use the proxy.)

**Expected:** `FAIL: …` with a network error (`getaddrinfo ENOTFOUND`, `Connect Timeout`, or similar). The `claude` container is on an `internal: true` network and has no path to the outside without the proxy.

Now repeat against a raw public IP, which bypasses DNS entirely:

```bash
node -e "fetch('https://1.1.1.1').then(r => console.log(r.status)).catch(e => console.error('FAIL:', e.message))"
```

**Expected:** `FAIL: …` with a connect/timeout error (not `ENOTFOUND` — there is no name to resolve here). This is the stronger check: a pass on the first call alone could just mean DNS didn't resolve, whereas Docker's embedded resolver may still answer on an `internal` network. A timeout to a known-routable IP proves there is genuinely **no route** to the internet, not merely a missing name.

### 2.4a CONNECT to non-standard ports is refused

`tinyproxy.conf` allows the HTTPS CONNECT method only to ports 443 and 563. This step confirms an allowed *hostname* on a disallowed *port* is still refused.

```bash
node -e "
  const { ProxyAgent } = require('undici');
  fetch('https://github.com:8443', { dispatcher: new ProxyAgent(process.env.HTTPS_PROXY) })
    .then(r => console.log('status', r.status))
    .catch(e => console.error('FAIL:', e.message));
"
```

**Expected:** the proxy refuses the CONNECT — a 4xx status or a connection error from the proxy. You should NOT get a real response from `github.com:8443`. (Note: `github.com` does not serve TLS on 8443 anyway; the point is that the *proxy* rejects the tunnel before any upstream connection, regardless of whether the port is open.)

### 2.4b Proxy sidecar is itself locked down — optional

The hardened overlay drops all capabilities, sets `no-new-privileges`, and mounts the proxy's root filesystem read-only. Verify from the host:

```bash
PROJECT=example docker compose -f docker-compose.yml -f docker-compose.hardened.yml \
  exec egress-proxy sh -c 'touch /probe 2>&1; grep CapEff /proc/1/status'
```

**Expected:** `touch /probe` fails with `Read-only file system`, and `CapEff` reads `0000000000000000` (all capabilities dropped). Confirms the sidecar can't be tampered with or escalated even if `tinyproxy` were compromised.

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
