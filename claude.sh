#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

compose_args=(-f docker-compose.yml)
if [[ "${HARDENED:-0}" == "1" ]]; then
  compose_args+=(-f docker-compose.hardened.yml)
fi

usage() {
  cat <<'EOF'
Usage: ./claude.sh <command> [args]

Commands:
  list                          list all projects
  new   <name>                  create projects/<name> and git init it
  shell <name>                  open a bash shell in the container for <name>
                                (useful for inspecting the environment or
                                running git commands)
  run   <name> [-- <args...>]   run `claude` in the container for <name>;
                                with no args, starts an interactive session;
                                with `-- <args>`, forwards <args> to claude
                                (e.g. `-- -p "..."` for headless mode)
  build [<args>...]             rebuild the container image after editing the
                                Dockerfile; forwards <args> to
                                `docker compose build` (e.g. --no-cache,
                                or a service name like `egress-proxy`)
  help                          show this help

Project names: letters, digits, underscore, hyphen only.

Set HARDENED=1 to also apply docker-compose.hardened.yml (network allowlist).
Set CIC_SKIP_GIT_IDENTITY=1 to skip the first-run copy of your host git
identity into claude_home/.gitconfig.local.

Examples:
  ./claude.sh new my-api
  ./claude.sh shell my-api                       # bash shell in container
  ./claude.sh run my-api                         # interactive Claude session
  ./claude.sh run my-api -- -p "explain this"    # headless one-shot
  ./claude.sh build                              # rebuild after Dockerfile change
  ./claude.sh build --no-cache                   # force full rebuild
  HARDENED=1 ./claude.sh shell my-api
EOF
}

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

require_name() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "error: project name required" >&2
    usage >&2
    exit 1
  fi
  if ! valid_name "$name"; then
    echo "error: invalid project name '$name' (allowed: letters, digits, _, -)" >&2
    exit 1
  fi
}

require_exists() {
  local name="$1"
  if [[ ! -d "projects/$name" ]]; then
    echo "error: projects/$name does not exist. Create it with: ./claude.sh new $name" >&2
    exit 1
  fi
}

# Copy the host's git identity into claude_home/.gitconfig.local on first run
# so that commits inside the container inherit the same author by default.
# Idempotent — does nothing if the file already exists or CIC_SKIP_GIT_IDENTITY=1.
bootstrap_git_identity() {
  local target="claude_home/.gitconfig.local"

  [[ "${CIC_SKIP_GIT_IDENTITY:-0}" == "1" ]] && return 0
  [[ -e "$target" ]] && return 0

  if ! command -v git >/dev/null 2>&1; then
    echo "note: git not found on host; skipping identity bootstrap. Create $target manually with a [user] block before Claude commits." >&2
    return 0
  fi

  local host_name host_email
  host_name=$(git config --global --get user.name 2>/dev/null || true)
  host_email=$(git config --global --get user.email 2>/dev/null || true)

  if [[ -z "$host_name" || -z "$host_email" ]]; then
    echo "note: host git identity not configured ('git config --global user.name/email' is unset)." >&2
    echo "      Set it on the host, or create $target manually with a [user] block, before Claude commits." >&2
    return 0
  fi

  cat > "$target" <<EOF
# Auto-created by claude.sh on first run from your host's
# 'git config --global user.{name,email}'. Edit to use a different identity
# for commits Claude makes inside the container — for example, a marker
# address like you+claude@example.com so 'git log' shows which commits
# were made autonomously.

[user]
    name = $host_name
    email = $host_email
EOF

  cat >&2 <<EOF
First-time setup: copied your host git identity into the container so
Claude can commit on your behalf:

  name  = $host_name
  email = $host_email

  → $target

Edit that file if you want a different identity for commits made inside
the container. This only affects commit authorship — Claude still can't
push from inside the container unless you set GITHUB_TOKEN in .env
(see 'Pushing your work' in README).
EOF
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  list)
    ls -1 projects/ 2>/dev/null || true
    ;;
  new)
    name="${1:-}"
    require_name "$name"
    if [[ -d "projects/$name" ]]; then
      echo "error: projects/$name already exists" >&2
      exit 1
    fi
    bootstrap_git_identity
    mkdir -p "projects/$name"
    (cd "projects/$name" && git init -q)
    echo "created projects/$name (git initialized)"
    ;;
  shell)
    name="${1:-}"
    require_name "$name"
    require_exists "$name"
    bootstrap_git_identity
    PROJECT="$name" docker compose "${compose_args[@]}" run --rm claude
    ;;
  run)
    name="${1:-}"
    require_name "$name"
    shift
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
    require_exists "$name"
    bootstrap_git_identity
    PROJECT="$name" docker compose "${compose_args[@]}" run --rm claude claude "$@"
    ;;
  build)
    # PROJECT must be set for compose to interpolate the volume mount,
    # even though `build` doesn't actually mount anything. Use `example`
    # since projects/example/ is committed to the repo.
    bootstrap_git_identity
    PROJECT=example docker compose "${compose_args[@]}" build "$@"
    ;;
  *)
    echo "error: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
