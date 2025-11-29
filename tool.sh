#!/usr/bin/env bash

# Central entry point for pg-backup-restore toolkit
# Routes to: backup.sh, restore_db.sh, drop_all_tables.sh, backup_deps.sh

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

BACKUP_SCRIPT="$SCRIPTPATH/scripts/backup.sh"
RESTORE_SCRIPT="$SCRIPTPATH/scripts/restore_db.sh"
DROP_SCRIPT="$SCRIPTPATH/scripts/drop_all_tables.sh"
DEPS_SCRIPT="$SCRIPTPATH/scripts/backup_deps.sh"

ENV_ARG=""           # --dev | --prod
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"  # optional override passthrough
BACKUP_ROOT="${BACKUP_ROOT:-}"           # optional override passthrough

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <command> [--dev|--prod] [options]

Commands (most common first):
  Commands (grouped, common first):
    [Prod -> Dev]
      sync-dev          Fresh PROD backup then restore into DEV (1-step)
      refresh-dev       Use latest existing PROD backup to update DEV
      restore-prod      Choose a specific PROD backup → DEV
    [Dev Restore]
      restore           Choose a DEV backup → DEV
      restore-latest    Restore latest DEV backup (less common; hidden from menu)
      drop              Drop & recreate public schema (DEV only)
    [Backups]
      backup            Backup selected env (dev or prod)
      list              List backups for env
    [Utilities]
      deps              Check/install dependencies

Environment selection (required for backup/drop):
  --dev | -d      Use dev.env
  --prod | -p     Use prod.env (non-destructive operations only)

Options:
  --config <path> Override env file path (passthrough to scripts)
  --backups <path> Override backups base dir (passthrough)
  --yes           Pass through to destructive commands where supported
  --skip-backup   Pass through to drop to skip pre-drop backup (DANGEROUS)
  -h | --help     Show this help message

Examples:
  $SCRIPT_NAME sync-dev --dev             # Fresh prod backup then restore to dev
  $SCRIPT_NAME refresh-dev --dev          # Latest existing prod -> dev
  $SCRIPT_NAME restore-prod --dev         # Choose prod backup -> dev
  $SCRIPT_NAME restore --dev              # Choose dev backup -> dev
  $SCRIPT_NAME backup --prod              # Backup prod
  $SCRIPT_NAME list --prod                # List prod backups
  $SCRIPT_NAME drop --dev --yes           # Reset dev schema

 Notes:
 - Destructive operations (restore, drop) restricted to target DEV only.
 - Primary workflows (Prod -> Dev): 'sync-dev' (fresh), 'refresh-dev' (latest existing), 'restore-prod' (choose).
 - 'restore-latest' is available via CLI but omitted from menu for simplicity.
cmd_sync_dev() {
  require_script "$BACKUP_SCRIPT"
  require_script "$RESTORE_SCRIPT"
  pass_config_env
  log "Dispatching: sync-dev (fresh prod backup -> dev restore)"
  # 1. Fresh PROD backup
  "$BACKUP_SCRIPT" --prod
  # 2. Restore latest PROD backup into DEV
  "$RESTORE_SCRIPT" --target dev --source prod --latest
}

cmd_restore_prod() {
  require_script "$RESTORE_SCRIPT"
  pass_config_env
  log "Dispatching: restore-prod (choose prod backup -> dev)"
  "$RESTORE_SCRIPT" --target dev --source prod
}
- To perform these on PROD you must manually invoke the underlying script, e.g.:
  scripts/restore_db.sh --prod
  scripts/drop_all_tables.sh --prod
- This wrapper enforces the same safety prompts as underlying scripts.
- Use --config to point at a custom env file when needed.
EOF
}

require_script() {
  local f="$1"; [[ -x "$f" ]] || error "Required script not executable: $f"
}

parse_common_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev|-d) ENV_ARG="--dev";;
      --prod|-p) ENV_ARG="--prod";;
      --config) shift; CONFIG_FILE_PATH="${1:-}" || true;;
      --backups) shift; BACKUP_ROOT="${1:-}" || true;;
      -h|--help) usage; exit 0;;
      *) break;;
    esac
    shift || true
  done
  # Remaining args are returned as list
  echo "$ENV_ARG" "$CONFIG_FILE_PATH" "$BACKUP_ROOT" "$@"
}

pass_config_env() {
  if [[ -n "$CONFIG_FILE_PATH" ]]; then
    export CONFIG_FILE_PATH
  fi
  if [[ -n "$BACKUP_ROOT" ]]; then
    export BACKUP_ROOT
  fi
}

cmd_backup() {
  require_script "$BACKUP_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod"
  pass_config_env
  log "Dispatching: backup $ENV_ARG"
  "$BACKUP_SCRIPT" "$ENV_ARG"
}

cmd_restore() {
  require_script "$RESTORE_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod (dev required for target)"
  if [[ "$ENV_ARG" != "--dev" ]]; then error "Wrapper restore limited to target dev."; fi
  pass_config_env
  log "Dispatching: restore target=dev source=dev"
  "$RESTORE_SCRIPT" --target dev
}

cmd_restore_latest() {
  require_script "$RESTORE_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod (dev required for target)"
  if [[ "$ENV_ARG" != "--dev" ]]; then error "Wrapper restore limited to target dev."; fi
  pass_config_env
  log "Dispatching: restore-latest target=dev source=dev"
  "$RESTORE_SCRIPT" --target dev --latest
}

cmd_refresh_dev() {
  require_script "$RESTORE_SCRIPT"
  pass_config_env
  log "Dispatching: refresh-dev source=prod target=dev"
  "$RESTORE_SCRIPT" --target dev --source prod --latest
}

cmd_list() {
  require_script "$RESTORE_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod"
  pass_config_env
  log "Dispatching: list $ENV_ARG"
  "$RESTORE_SCRIPT" "$ENV_ARG" --list
}

cmd_drop() {
  require_script "$DROP_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod"
  if [[ "$ENV_ARG" == "--prod" ]]; then
    error "Prod drop disabled in tool wrapper. Run scripts/drop_all_tables.sh manually if absolutely required."
  fi
  pass_config_env
  # Forward extra flags like --yes and --skip-backup
  log "Dispatching: drop (dev only) $ENV_ARG $REST"
  "$DROP_SCRIPT" "$ENV_ARG" $REST
}

cmd_deps() {
  require_script "$DEPS_SCRIPT"
  # deps supports --check or --install
  log "Dispatching: deps $*"
  "$DEPS_SCRIPT" "$@"
}

main() {
  if (( $# < 1 )); then
    echo "Select an option (prod destructive ops disabled):"
    echo "  [Prod -> Dev]"
    echo "    1) Sync DEV (fresh PROD backup -> restore)"
    echo "    2) Refresh DEV from latest PROD"
    echo "    3) Restore DEV from chosen PROD backup"
    echo "  [Dev Restore / Maintenance]"
    echo "    4) Restore DEV from chosen DEV backup"
    echo "    5) Drop --dev"
    echo "  [Backups]"
    echo "    6) Backup --prod"
    echo "    7) Backup --dev"
    echo "    8) List backups --prod"
    echo "    9) List backups --dev"
    echo "  [Utilities]"
    echo "   10) Deps --check"
    echo "   11) Deps --install"
    echo "   12) Settings (set --config / --backups)"
    read -r -p "Enter number: " choice
    case "$choice" in
      1) cmd_sync_dev ;;
      2) cmd_refresh_dev ;;
      3) cmd_restore_prod ;;
      4) cmd_restore --dev ;;
      5) cmd_drop --dev ;;
      6) cmd_backup --prod ;;
      7) cmd_backup --dev ;;
      8) cmd_list --prod ;;
      9) cmd_list --dev ;;
         10) cmd_deps --check ;;
         11) cmd_deps --install ;;
         12)
        echo "Current overrides:"
        echo "  CONFIG_FILE_PATH = ${CONFIG_FILE_PATH:-<none>}"
        echo "  BACKUP_ROOT      = ${BACKUP_ROOT:-<none>}"
        read -r -p "Set CONFIG_FILE_PATH (leave empty to skip): " cfg
        if [[ -n "$cfg" ]]; then CONFIG_FILE_PATH="$cfg"; fi
        read -r -p "Set BACKUP_ROOT (leave empty to skip): " broot
        if [[ -n "$broot" ]]; then BACKUP_ROOT="$broot"; fi
        echo "Settings updated."
        exit 0
        ;;
      *) usage; exit 1 ;;
    esac
    exit 0
  fi
  local command="$1"; shift
  case "$command" in
    backup)  cmd_backup "$@" ;;
    restore) cmd_restore "$@" ;;
    drop)    cmd_drop "$@" ;;
    list)    cmd_list "$@" ;;
    deps)    cmd_deps "$@" ;;
    -h|--help) usage ;;
    *) error "Unknown command: $command" ;;
  esac
}

main "$@"
