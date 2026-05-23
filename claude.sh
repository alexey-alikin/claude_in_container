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
    mkdir -p "projects/$name"
    (cd "projects/$name" && git init -q)
    echo "created projects/$name (git initialized)"
    ;;
  shell)
    name="${1:-}"
    require_name "$name"
    require_exists "$name"
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
    PROJECT="$name" docker compose "${compose_args[@]}" run --rm claude claude "$@"
    ;;
  build)
    # PROJECT must be set for compose to interpolate the volume mount,
    # even though `build` doesn't actually mount anything. Use `example`
    # since projects/example/ is committed to the repo.
    PROJECT=example docker compose "${compose_args[@]}" build "$@"
    ;;
  *)
    echo "error: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
