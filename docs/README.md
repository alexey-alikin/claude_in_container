# Contributor and maintenance docs

This folder is for people working **on** the repo, not for people using it. If you're looking for how to run Claude Code in a container, the top-level [README](../README.md) is the place to start.

## What's in here

| File | Purpose |
| --- | --- |
| [build-summary.md](build-summary.md) | One-page snapshot of the repo: layout, security posture, intentional simplifications. Read this first when onboarding to the codebase. |
| [design-decisions.md](design-decisions.md) | Planning history and locked decisions for each phase. Explains the *why* behind the current setup. |
| [test-plan.md](test-plan.md) | Manual smoke tests for the basic and hardened modes. Run before tagging a release or after touching the Dockerfile, wrapper, or hardened overlay. |

## Related files outside this folder

- [CONTRIBUTING.md](../CONTRIBUTING.md) — how to open PRs and the local commands that mirror CI.
- [SECURITY.md](../SECURITY.md) — threat model and how to report vulnerabilities.
- [.github/workflows/ci.yml](../.github/workflows/ci.yml) — the CI pipeline (hadolint, compose lint, trivy).
