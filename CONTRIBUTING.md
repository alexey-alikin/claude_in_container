# Contributing

Thanks for your interest. This is a small repo, so the bar for changes is "does it make the default user experience better, safer, or clearer." A few ground rules:

## Before opening a PR

- **Open an issue first** for anything non-trivial (new feature, behavior change, dependency addition). Quick fixes and typo PRs can skip this.
- **Keep PRs small and focused.** One concern per PR. If you're touching the Dockerfile and writing docs and adding a workflow, that's three PRs.
- **Don't add features beyond what the issue scopes.** No drive-by refactors.

## Local checks

CI runs three things on every PR. Run them locally first so you don't burn a round-trip:

```bash
# Lint both Dockerfiles (matches the CI matrix)
docker run --rm -i hadolint/hadolint < Dockerfile
docker run --rm -i hadolint/hadolint < hardened/Dockerfile

# Validate compose files render
PROJECT=example docker compose config -q
PROJECT=example docker compose -f docker-compose.yml -f docker-compose.hardened.yml config -q
```

The trivy image scan also runs in CI; you don't need to run it locally unless you're touching the Dockerfile or bumping the base image.

Repo-level helpers (install/uninstall of the `cic` launcher, etc.) are surfaced via `make help`.

## Style

- Shell scripts: keep them readable, prefer `set -euo pipefail`, quote variables.
- Compose files: comment any non-obvious option (we already do this for the `egress` network).
- Docs: no emoji, no marketing voice. Short sentences. Show, don't list.

## Security issues

Do **not** open a public issue for security problems. See [SECURITY.md](SECURITY.md) for how to report.

## License

By contributing, you agree your changes are released under the [MIT License](LICENSE).
