# Running in a sandboxed container

You are running inside the `claude_in_container` Docker sandbox, not on the user's host.

- **Writable paths:** only `/workspace` (your current directory, bind-mounted to the host project) and `/tmp` (in-memory, wiped on container exit). The rest of the filesystem is read-only.
- **No root, no capabilities:** you cannot `sudo`, install system packages (`apt`, `apk`, etc.), or modify anything outside the writable paths.
- **Network:** unrestricted by default, but in hardened mode (`HARDENED=1`) outbound traffic is allowlisted to a small set of hosts (`api.anthropic.com`, `github.com`, `registry.npmjs.org`, …). Unexpected DNS or TLS failures usually mean the host isn't on the allowlist.
- **Need a missing tool** (e.g., `python3`, `make`, `go`, a linter)? Don't try to install it — it will fail. Instead, tell the user to add it to the `Dockerfile` on the host (typically the `apt-get install` line) and rebuild with `docker compose build`, then restart the session.
- **Don't try to use `docker` itself from inside the container.** Giving the sandbox Docker access would defeat the whole sandbox; if the user needs container builds, they run them on the host.
