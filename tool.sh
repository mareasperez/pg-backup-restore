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

Commands:
  backup          Run a backup for selected env
  restore         Restore from latest (or pick) backup
  restore-latest  Restore latest directly (still confirms DB name)
  drop            Drop all tables (auto-backup first)
  list            Show backups for env (no restore)
  deps            Check/install dependencies

Environment selection (required for backup/restore/drop):
  --dev | -d      Use dev.env
  --prod | -p     Use prod.env

Options:
  --config <path> Override env file path (passthrough to scripts)
  --backups <path> Override backups base dir (passthrough)
  --yes           Pass through to destructive commands where supported
  --skip-backup   Pass through to drop to skip pre-drop backup (DANGEROUS)
  -h | --help     Show this help message

Examples:
  $SCRIPT_NAME backup --dev
  $SCRIPT_NAME restore --prod
  $SCRIPT_NAME restore-latest --prod
  $SCRIPT_NAME drop --dev --yes
  $SCRIPT_NAME list --dev
  $SCRIPT_NAME deps --check
  $SCRIPT_NAME deps --install

Notes:
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
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod"
  pass_config_env
  log "Dispatching: restore $ENV_ARG"
  "$RESTORE_SCRIPT" "$ENV_ARG"
}

cmd_restore_latest() {
  require_script "$RESTORE_SCRIPT"
  read -r ENV_ARG CONFIG_FILE_PATH BACKUP_ROOT REST <<< "$(parse_common_flags "$@")"
  [[ -n "$ENV_ARG" ]] || error "Select environment with --dev or --prod"
  pass_config_env
  log "Dispatching: restore-latest $ENV_ARG"
  "$RESTORE_SCRIPT" "$ENV_ARG" --latest
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
  pass_config_env
  # Forward extra flags like --yes and --skip-backup
  log "Dispatching: drop $ENV_ARG $REST"
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
    echo "Select an option:"
    echo "  1) Backup --dev"
    echo "  2) Backup --prod"
    echo "  3) Restore --dev"
    echo "  4) Restore --prod"
    echo "  5) Restore latest --dev"
    echo "  6) Restore latest --prod"
    echo "  7) List backups --dev"
    echo "  8) List backups --prod"
    echo "  9) Drop --dev"
    echo " 10) Drop --prod"
    echo " 11) Deps --check"
    echo " 12) Deps --install"
    echo " 11) Settings (set --config / --backups)"
    read -r -p "Enter number: " choice
    case "$choice" in
      1) cmd_backup --dev ;;
      2) cmd_backup --prod ;;
      3) cmd_restore --dev ;;
      4) cmd_restore --prod ;;
      5) cmd_restore_latest --dev ;;
      6) cmd_restore_latest --prod ;;
      7) cmd_list --dev ;;
      8) cmd_list --prod ;;
      9) cmd_drop --dev ;;
      10) cmd_drop --prod ;;
      11) cmd_deps --check ;;
      12) cmd_deps --install ;;
      13)
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
