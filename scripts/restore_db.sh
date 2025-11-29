#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""
FOLDER_NAME=""
CONFIG_BASENAME=""
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/../backups}"

backup_file=""; metadata_file=""; LIST_ONLY=0; FORCE_LATEST=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--dev|-d|--prod|-p] [--list]

Flags:
  --dev|-d   Select dev environment
  --prod|-p  Select prod environment
  --list     List backups for env and exit (no restore)
  --latest   Use latest backup without the (y/n) prompt
  -h|--help  Show help

Env vars:
  CONFIG_FILE_PATH  Optional path to env file
  BACKUP_ROOT       Base backups dir (default: $BACKUP_ROOT)
EOF
}

parse_args() {
  local env_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev|-d) ENVIRONMENT="dev"; FOLDER_NAME="dev"; CONFIG_BASENAME="dev.env"; env_set=1 ;;
      --prod|-p) ENVIRONMENT="prod"; FOLDER_NAME="prod"; CONFIG_BASENAME="prod.env"; env_set=1 ;;
      --list) LIST_ONLY=1 ;;
      --latest) FORCE_LATEST=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown argument: $1" ;;
    esac; shift
  done
  (( env_set == 1 )) || error "Specify --dev/-d or --prod/-p"
}

load_config() {
  [[ -z "$CONFIG_FILE_PATH" ]] && CONFIG_FILE_PATH="${SCRIPTPATH}/../${CONFIG_BASENAME}"
  [[ -r "$CONFIG_FILE_PATH" ]] || error "Could not load config: $CONFIG_FILE_PATH"
  log "Loading config from: $CONFIG_FILE_PATH"
  set -a; source "$CONFIG_FILE_PATH"; set +a
  log "Environment: $ENVIRONMENT"
  echo "========================================"
  echo "DB_DATABASE: ${DB_DATABASE:-<not set>}"
  echo "DB_HOST:     ${DB_HOST:-<not set>}"
  echo "DB_USERNAME: ${DB_USERNAME:-<not set>}"
  echo "DB_PASSWORD: ${DB_PASSWORD:+********}"
  echo "DB_PORT:     ${DB_PORT:-<default>}"
  echo "========================================"
}

validate_required_env() {
  local missing=()
  for var in DB_DATABASE DB_HOST DB_USERNAME DB_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    error "Missing env vars: ${missing[*]}"
  fi
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || error "Required command '$1' not found"; }

list_backups() {
  local base_dir="${BACKUP_ROOT}/${FOLDER_NAME}"
  [[ -d "$base_dir" ]] || error "Backup directory does not exist: $base_dir"
  log "Listing backups under: $base_dir"
  local -a backup_dirs=(); while IFS= read -r -d '' dir; do backup_dirs+=("$dir"); done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  (( ${#backup_dirs[@]} > 0 )) || error "No backup directories found in $base_dir"
  echo "Available backups:"; local i=1
  for d in "${backup_dirs[@]}"; do
    local dump_file="${d}/${FOLDER_NAME}.dump"; local meta_file="${d}/${FOLDER_NAME}.meta"; local name; name=$(basename "$d")
    if [[ -f "$dump_file" ]]; then
      if [[ -f "$meta_file" ]]; then printf "  %2d) %s\n" "$i" "$name"; else printf "  %2d) %s * (missing .meta)\n" "$i" "$name"; fi; ((i++))
    fi
  done
  (( i > 1 )) || error "No valid backups (with .dump) found in $base_dir"
}

list_backups_and_select() {
  list_backups
  local base_dir="${BACKUP_ROOT}/${FOLDER_NAME}"; local selection=""; local i=1; local -a valid_dirs=()
  while IFS= read -r -d '' dir; do [[ -f "${dir}/${FOLDER_NAME}.dump" ]] && valid_dirs+=("$dir"); done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  while true; do
    read -r -p "Enter the number of the backup you want to restore: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#valid_dirs[@]} )); then
      local chosen_dir="${valid_dirs[$((selection-1))]}"
      backup_file="${chosen_dir}/${FOLDER_NAME}.dump"; metadata_file="${chosen_dir}/${FOLDER_NAME}.meta"
      log "Selected backup: $(basename "$chosen_dir")"
      if [[ -f "$metadata_file" ]]; then echo "Backup metadata:"; cat "$metadata_file"; else echo "Backup metadata: <missing>"; fi
      break
    fi
    echo "Invalid selection. Please enter a valid number."
  done
}

load_latest_backup_or_select() {
  local base_dir="${BACKUP_ROOT}/${FOLDER_NAME}"; [[ -d "$base_dir" ]] || error "Backup directory does not exist: $base_dir"
  log "Looking for the latest backup in: $base_dir"
  local latest_backup_dir; latest_backup_dir=$(ls -td "${base_dir}"/* 2>/dev/null | head -n 1 || true)
  if [[ -z "$latest_backup_dir" ]]; then echo "No backups found in $base_dir"; list_backups_and_select; return; fi
  backup_file="${latest_backup_dir}/${FOLDER_NAME}.dump"; metadata_file="${latest_backup_dir}/${FOLDER_NAME}.meta"
  if [[ ! -f "$backup_file" ]]; then echo "Latest backup folder does not contain a .dump file: $latest_backup_dir"; list_backups_and_select; return; fi
  echo "Latest backup found: $(basename "$latest_backup_dir")"; [[ -f "$metadata_file" ]] && { echo "Backup metadata:"; cat "$metadata_file"; } || echo "Backup metadata: <missing>"
  if (( FORCE_LATEST == 0 )); then
    read -r -p "Do you want to restore this latest backup? (y/n) " confirm_restore
    if [[ "$confirm_restore" != "y" ]]; then echo "You chose not to restore the latest backup."; list_backups_and_select; fi
  fi
}

confirm_restore() {
  echo; echo "You are about to RESTORE database:"; echo "  Environment = $ENVIRONMENT"; echo "  DB_DATABASE = $DB_DATABASE"; echo "  DB_HOST     = $DB_HOST"; echo "  DB_USERNAME = $DB_USERNAME"; echo "  Backup file = $backup_file"; echo
  read -r -p "Type the database name ('$DB_DATABASE') to confirm restore, or anything else to abort: " answer
  [[ "$answer" == "$DB_DATABASE" ]] || { log "Confirmation failed. Aborting."; exit 1; }
  log "Confirmation accepted. Proceeding with restore."
}

restore_db() {
  validate_required_env; require_cmd "pg_restore"; [[ -n "$backup_file" && -f "$backup_file" ]] || error "Backup file not set or missing: $backup_file"
  confirm_restore
  local port_arg=(); [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")
  log "Starting restore at: $(date)"; log "Connecting to database: $DB_DATABASE on $DB_HOST"
  PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" "${port_arg[@]}" --clean --verbose -F c "$backup_file"
  log "Restore completed successfully at: $(date)"
}

main() {
  SECONDS=0; parse_args "$@"; load_config; if (( LIST_ONLY == 1 )); then list_backups; exit 0; fi; load_latest_backup_or_select; restore_db; printf "Total time: %d minutes and %d seconds elapsed.\n" "$((SECONDS/60))" "$((SECONDS%60))"
}

main "$@"
