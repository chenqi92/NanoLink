#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
task_root="$script_dir/tasks"

usage() {
  cat <<'EOF'
Usage: ./scripts/nanoops.sh [action] [options]

Actions:
  menu             Open the interactive project console (default).
  start            Start the development environment.
  stop             Stop the development environment.
  deploy           Deploy Server to production after confirmation.
  deploy-dry-run   Validate and package without touching the server.
  version VERSION  Update the project semantic version.
  install-hooks    Install the repository Git hooks.
  remove-bom       Scan source files and remove UTF-8 BOM.

Deployment options are passed through, including --allow-dirty,
--skip-checks, --config PATH, and --dry-run. Use --yes only for intentional
non-interactive production automation.
EOF
}

run_task() {
  local name=$1
  shift
  local task="$task_root/$name"
  [[ -f $task ]] || { echo "Internal task not found: $task" >&2; return 1; }
  bash "$task" "$@"
}

confirm_deploy() {
  local answer
  printf 'This will build and deploy NanoOps Server to production.\n'
  read -r -p 'Type DEPLOY to continue: ' answer
  [[ $answer == DEPLOY ]]
}

run_action() {
  local action=$1
  shift
  cd "$repo_root"
  case "$action" in
    start)
      run_task start-dev.sh "$@"
      ;;
    stop)
      run_task stop-dev.sh "$@"
      ;;
    deploy)
      local assume_yes=0
      local deploy_args=()
      while (( $# > 0 )); do
        if [[ $1 == --yes ]]; then
          assume_yes=1
        else
          deploy_args+=("$1")
        fi
        shift
      done
      if (( ! assume_yes )) && ! confirm_deploy; then
        echo 'Deployment cancelled.'
        return 0
      fi
      run_task deploy-server.sh "${deploy_args[@]}"
      ;;
    deploy-dry-run)
      run_task deploy-server.sh --dry-run "$@"
      ;;
    version)
      local new_version=${1-}
      if [[ -z $new_version ]]; then
        read -r -p 'New semantic version (for example 0.5.0): ' new_version
      fi
      [[ -n $new_version ]] || { echo 'A version is required.' >&2; return 1; }
      run_task bump-version.sh "$new_version"
      ;;
    install-hooks)
      run_task install-hooks.sh
      ;;
    remove-bom)
      run_task remove-bom.sh "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Unknown action: $action" >&2
      usage >&2
      return 1
      ;;
  esac
}

show_menu() {
  local choice action
  while true; do
    printf '\nNanoOps Project Console\n'
    printf '  1. Start development environment\n'
    printf '  2. Stop development environment\n'
    printf '  3. Deploy Server to production\n'
    printf '  4. Validate deployment (DryRun)\n'
    printf '  5. Bump project version\n'
    printf '  6. Install Git hooks\n'
    printf '  7. Scan and remove BOM\n'
    printf '  0. Exit\n'
    read -r -p 'Select: ' choice
    case "$choice" in
      1) action=start ;;
      2) action=stop ;;
      3) action=deploy ;;
      4) action=deploy-dry-run ;;
      5) action=version ;;
      6) action=install-hooks ;;
      7) action=remove-bom ;;
      0) return 0 ;;
      *) echo 'Invalid selection.'; continue ;;
    esac
    run_action "$action" || true
    read -r -p 'Press Enter to return to the menu' _
  done
}

action=${1:-menu}
if (( $# > 0 )); then shift; fi
if [[ $action == menu ]]; then
  show_menu
else
  run_action "$action" "$@"
fi
