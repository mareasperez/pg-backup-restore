#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

TARGET_ENV=""
SOURCE_ENV=""  # optional; defaults to TARGET_ENV if not set
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/../backups}"

backup_file=""; metadata_file=""; LIST_ONLY=0; FORCE_LATEST=0


log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --target <dev|prod> [--source <dev|prod>] [--list] [--latest] [--no-progress] [--show-lines]

WARNING:
  Wrapper (tool.sh) restricts destructive operations to DEV (target=dev).
  Direct PROD restore allowed only by running this script manually.

Flags:
  --target <dev|prod>   Destination database environment (required)
  --source <dev|prod>   Backup source environment (optional; defaults to target)
  --list                List backups for source and exit (no restore)
  --latest              Use latest backup without the (y/n) prompt
  --no-progress         Disable progress/ETA display during restore
  --show-lines          Show verbose pg_restore output lines (normally suppressed when progress active)
  -h|--help  Show help

Env vars:
  CONFIG_FILE_PATH  Optional path to target env file
  BACKUP_ROOT       Base backups dir (default: $BACKUP_ROOT)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) shift; TARGET_ENV="${1:-}" ;;
      --source) shift; SOURCE_ENV="${1:-}" ;;
      --list) LIST_ONLY=1 ;;
      --latest) FORCE_LATEST=1 ;;
      --no-progress) NO_PROGRESS=1 ;;
      --show-lines) SHOW_LINES=1 ;;
      -h|--help) usage; exit 0 ;;
      --dev|-d|--prod|-p|--from-prod) error "Deprecated flag: use --target and optional --source instead" ;;
      *) error "Unknown argument: $1" ;;
    esac; shift
  done
  [[ -n "$TARGET_ENV" ]] || error "--target <dev|prod> is required"
  if [[ -z "$SOURCE_ENV" ]]; then SOURCE_ENV="$TARGET_ENV"; fi
  [[ "$TARGET_ENV" =~ ^(dev|prod)$ ]] || error "Invalid --target value: $TARGET_ENV"
  [[ "$SOURCE_ENV" =~ ^(dev|prod)$ ]] || error "Invalid --source value: $SOURCE_ENV"
}

load_config() {
  local cfg_basename="${TARGET_ENV}.env"
  [[ -z "$CONFIG_FILE_PATH" ]] && CONFIG_FILE_PATH="${SCRIPTPATH}/../${cfg_basename}"
  [[ -r "$CONFIG_FILE_PATH" ]] || error "Could not load target config: $CONFIG_FILE_PATH"
  log "Loading target config from: $CONFIG_FILE_PATH"
  set -a; source "$CONFIG_FILE_PATH"; set +a
  log "Target environment: $TARGET_ENV | Source backups: $SOURCE_ENV"
  echo "========================================"
  echo "DB_DATABASE: ${DB_DATABASE:-<not set>}"
  echo "DB_HOST:     ${DB_HOST:-<not set>}"
  echo "DB_USERNAME: ${DB_USERNAME:-<not set>}"
  echo "DB_PASSWORD: ${DB_PASSWORD:+********}"
  echo "DB_PORT:     ${DB_PORT:-<default>}"
  echo "========================================"
}

test_connection() {
  require_cmd "psql"
  local port="${DB_PORT:-5432}"
  log "Testing connectivity to $DB_HOST:$port ($DB_DATABASE)"
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "$port" -t -A -c 'SELECT 1;' >/dev/null 2>&1 || error "Connectivity test failed (SELECT 1). Verify host/port/network or credentials."
  log "Connectivity OK."
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

estimate_total_items() {
  # Count TOC entries (exclude comments/blank lines). Fallback to 0 on error.
  local count
  count=$(pg_restore -l "$backup_file" 2>/dev/null | grep -vE '^(;|$)' | wc -l | tr -d ' ' || echo 0)
  echo "$count"
}

list_backups() {
  local base_dir="${BACKUP_ROOT}/${SOURCE_ENV}"
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
  local base_dir="${BACKUP_ROOT}/${SOURCE_ENV}"; local selection=""; local i=1; local -a valid_dirs=()
  while IFS= read -r -d '' dir; do [[ -f "${dir}/${SOURCE_ENV}.dump" ]] && valid_dirs+=("$dir"); done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  while true; do
    read -r -p "Enter the number of the backup you want to restore: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#valid_dirs[@]} )); then
      local chosen_dir="${valid_dirs[$((selection-1))]}"
      backup_file="${chosen_dir}/${SOURCE_ENV}.dump"; metadata_file="${chosen_dir}/${SOURCE_ENV}.meta"
      log "Selected backup: $(basename "$chosen_dir")"
      if [[ -f "$metadata_file" ]]; then echo "Backup metadata:"; cat "$metadata_file"; else echo "Backup metadata: <missing>"; fi
      break
    fi
    echo "Invalid selection. Please enter a valid number."
  done
}

load_latest_backup_or_select() {
  local base_dir="${BACKUP_ROOT}/${SOURCE_ENV}"; [[ -d "$base_dir" ]] || error "Backup directory does not exist: $base_dir"
  log "Looking for the latest backup in: $base_dir"
  local latest_backup_dir; latest_backup_dir=$(ls -td "${base_dir}"/* 2>/dev/null | head -n 1 || true)
  if [[ -z "$latest_backup_dir" ]]; then echo "No backups found in $base_dir"; list_backups_and_select; return; fi
  backup_file="${latest_backup_dir}/${SOURCE_ENV}.dump"; metadata_file="${latest_backup_dir}/${SOURCE_ENV}.meta"
  if [[ ! -f "$backup_file" ]]; then echo "Latest backup folder does not contain a .dump file: $latest_backup_dir"; list_backups_and_select; return; fi
  echo "Latest backup found: $(basename "$latest_backup_dir")"; [[ -f "$metadata_file" ]] && { echo "Backup metadata:"; cat "$metadata_file"; } || echo "Backup metadata: <missing>"
  if (( FORCE_LATEST == 0 )); then
    read -r -p "Do you want to restore this latest backup? (y/n) " confirm_restore
    if [[ "$confirm_restore" != "y" ]]; then echo "You chose not to restore the latest backup."; list_backups_and_select; fi
  fi
}

confirm_restore() {
  echo; echo "You are about to RESTORE database:"; echo "  Target environment = $TARGET_ENV"; echo "  Source backup env  = $SOURCE_ENV"; echo "  DB_DATABASE        = $DB_DATABASE"; echo "  DB_HOST            = $DB_HOST"; echo "  DB_USERNAME        = $DB_USERNAME"; echo "  Backup file        = $backup_file"; echo
  read -r -p "Type the database name ('$DB_DATABASE') to confirm restore, or anything else to abort: " answer
  [[ "$answer" == "$DB_DATABASE" ]] || { log "Confirmation failed. Aborting."; exit 1; }
  log "Confirmation accepted. Proceeding with restore."
}

restore_db() {
  validate_required_env; require_cmd "pg_restore"; [[ -n "$backup_file" && -f "$backup_file" ]] || error "Backup file not set or missing: $backup_file"
  confirm_restore
  local port_arg=(); [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")
  log "Starting restore at: $(date)"; log "Connecting to target database: $DB_DATABASE on $DB_HOST (source backups: $SOURCE_ENV)"

  if (( NO_PROGRESS == 1 )); then
    PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" "${port_arg[@]}" --clean --verbose -F c "$backup_file"
    log "Restore completed successfully at: $(date)"; return
  fi

  local total_items processed_items eta_display last_line
  total_items=$(estimate_total_items)
  if (( total_items > 0 )); then
    log "Total TOC items: $total_items"
  else
    log "Total TOC items unknown (ETA may be unavailable)."
  fi

  local tmp_log
  tmp_log=$(mktemp)
  SECONDS=0
  # Run pg_restore in background, capturing stderr to tmp_log
  (
    PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" "${port_arg[@]}" --clean --verbose -F c "$backup_file" 2>"$tmp_log" 1>&2
  ) &
  local pid=$!
  processed_items=0
  local prev_processed=0
  while kill -0 "$pid" 2>/dev/null; do
    local elapsed=$SECONDS
    local m=$(( elapsed / 60 ))
    local s=$(( elapsed % 60 ))
    # Count lines indicating creation/processing
    if (( total_items > 0 )); then
      # Use grep -c for a stable integer count; fallback to 0
      processed_items=$(grep -cE '^pg_restore: (creating|processing|restoring|setting)' "$tmp_log" 2>/dev/null || echo 0)
    else
      processed_items=$(grep -cE '^pg_restore:' "$tmp_log" 2>/dev/null || echo 0)
    fi
    # Sanitize to integer (handle rare formatting anomalies)
    [[ "$processed_items" =~ ^[0-9]+$ ]] || processed_items=0
    [[ "$m" =~ ^[0-9]+$ ]] || m=0
    [[ "$s" =~ ^[0-9]+$ ]] || s=0
    local speed=0
    if (( elapsed > 5 && processed_items > 0 )); then
      speed=$(( processed_items / elapsed ))
    fi
    eta_display="-"
    if (( total_items > 0 && speed > 0 && processed_items < total_items )); then
      local remaining=$(( total_items - processed_items ))
      local eta_sec=$(( remaining / speed ))
      if (( eta_sec >= 0 && eta_sec < 43200 )); then
        local eh=$(( eta_sec / 3600 ))
        local em=$(( (eta_sec % 3600) / 60 ))
        local es=$(( eta_sec % 60 ))
        [[ "$eh" =~ ^[0-9]+$ ]] || eh=0; [[ "$em" =~ ^[0-9]+$ ]] || em=0; [[ "$es" =~ ^[0-9]+$ ]] || es=0
        if (( eh > 0 )); then
          eta_display=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es")
        else
          eta_display=$(printf "%02d:%02d" "$em" "$es")
        fi
      fi
    fi
    if (( SHOW_LINES == 1 )); then
      last_line=$(tail -n 1 "$tmp_log" 2>/dev/null || echo "")
    else
      last_line=""
    fi
    if [[ -n "$last_line" ]]; then
      printf "Elapsed %02d:%02d | Items %d/%d | ETA %s | %s\r" "$m" "$s" "$processed_items" "$total_items" "$eta_display" "$last_line"
    else
      printf "Elapsed %02d:%02d | Items %d/%d | ETA %s\r" "$m" "$s" "$processed_items" "$total_items" "$eta_display"
    fi
    sleep 1
  done
  wait "$pid"
  local rc=$?
  printf "\n"
  if (( rc != 0 )); then
    log "Restore failed with exit code $rc. Last lines:"; tail -n 10 "$tmp_log" >&2; rm -f "$tmp_log"; error "pg_restore finished with errors"
  fi
  rm -f "$tmp_log"
  log "Restore completed successfully at: $(date)"
}

main() {
  SECONDS=0
  NO_PROGRESS=0
  SHOW_LINES=0
  parse_args "$@"
  load_config
  test_connection
  if (( LIST_ONLY == 1 )); then list_backups; exit 0; fi
  load_latest_backup_or_select
  restore_db
  printf "Total time: %d minutes and %d seconds elapsed.\n" "$((SECONDS/60))" "$((SECONDS%60))"
}

main "$@"
