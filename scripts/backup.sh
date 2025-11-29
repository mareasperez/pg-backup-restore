#!/usr/bin/env bash
set -euo pipefail
# Wrapper: moved from repo root. See README.
# Original content preserved.

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""
FOLDER_NAME=""
CONFIG_BASENAME=""
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/../backups}"
LOG_FILE="${LOG_FILE:-$SCRIPTPATH/../backup.log}"

_log_to_file() { local msg="$1"; { printf '%s\n' "$msg" >> "$LOG_FILE"; } 2>/dev/null || true; }
log() { local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"; printf '%s\n' "$msg" >&2; _log_to_file "$msg"; }
error() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --dev | --prod
Flags: --dev/-d, --prod/-p
Env: CONFIG_FILE_PATH, BACKUP_ROOT, LOG_FILE
Deps: pg_dump, stat, md5sum (optional: crc32)
EOF
}

init_log() { touch "$LOG_FILE" 2>/dev/null || { printf 'WARN: cannot write log file at %s\n' "$LOG_FILE" >&2; return; }; _log_to_file "----------------------------------------"; _log_to_file "New run of $SCRIPT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"; }
require_cmd_or_hint() { local cmd="$1"; command -v "$cmd" >/dev/null 2>&1 || error "Required '$cmd' missing. Use ./scripts/backup_deps.sh --install"; }
ensure_dependencies() { require_cmd_or_hint "pg_dump"; require_cmd_or_hint "stat"; require_cmd_or_hint "md5sum"; command -v crc32 >/dev/null 2>&1 || log "WARN: 'crc32' not found. Setting CRC32 to N/A."; }

set_env_dev() { log "Selected environment: DEV"; ENVIRONMENT="dev"; FOLDER_NAME="dev"; CONFIG_BASENAME="dev.env"; }
set_env_prod() { log "Selected environment: PROD"; ENVIRONMENT="prod"; FOLDER_NAME="prod"; CONFIG_BASENAME="prod.env"; }

load_config() { [[ -z "$CONFIG_FILE_PATH" ]] && CONFIG_FILE_PATH="${SCRIPTPATH}/../${CONFIG_BASENAME}"; [[ -r "$CONFIG_FILE_PATH" ]] || error "Could not read config file: $CONFIG_FILE_PATH"; log "Loading config from: $CONFIG_FILE_PATH"; set -a; source "$CONFIG_FILE_PATH"; set +a; }
validate_required_env() { local missing=(); for var in DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE; do [[ -z "${!var:-}" ]] && missing+=("$var"); done; (( ${#missing[@]} > 0 )) && error "Missing required environment variables: ${missing[*]}"; }

create_backup_folder() { local now="$1"; local backup_folder="${BACKUP_ROOT}/${FOLDER_NAME}/${now}"; [[ -d "$backup_folder" ]] || { mkdir -p "$backup_folder"; log "Created backup folder: $backup_folder"; }; printf '%s\n' "$backup_folder"; }
calculate_file_size() { stat --format="%s" "$1"; }
calculate_md5() { md5sum "$1" | awk '{ print $1 }'; }
calculate_crc32() { local file="$1"; command -v crc32 >/dev/null 2>&1 && crc32 "$file" || printf 'N/A'; }
show_elapsed_time() { local pid="$1"; local start_seconds=$SECONDS; while kill -0 "$pid" 2>/dev/null; do local elapsed=$(( SECONDS - start_seconds )); printf "Time elapsed: %02d:%02d (mm:ss)...\r" $((elapsed/60)) $((elapsed%60)); sleep 1; done; printf "\n"; }

backup_db() {
  validate_required_env; ensure_dependencies
  local now; now=$(date +"%Y-%m-%d-%H-%M"); local backup_folder; backup_folder=$(create_backup_folder "$now")
  local backup_file="${backup_folder}/${FOLDER_NAME}.dump"; local metadata_file="${backup_folder}/${FOLDER_NAME}.meta"; local transfer_file="${SCRIPTPATH}/../transfer.dump"
  log "Starting backup."; log "Database: $DB_DATABASE"; log "Host: $DB_HOST"; log "Backup file: $backup_file"; SECONDS=0
  (
    export PGPASSWORD="$DB_PASSWORD"
    pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc --create -f "$backup_file"
  ) & local pid=$!; show_elapsed_time "$pid"; wait "$pid"; log "pg_dump completed successfully."
  cp -f "$backup_file" "$transfer_file"; log "Copied backup to: $transfer_file"
  local file_size md5_checksum crc32_checksum; file_size=$(calculate_file_size "$backup_file"); md5_checksum=$(calculate_md5 "$backup_file"); crc32_checksum=$(calculate_crc32 "$backup_file")
  {
    echo "Backup date: $(date)"; echo "Environment: $ENVIRONMENT"; echo "Database: $DB_DATABASE"; echo "Host: $DB_HOST"; echo "Backup file: $backup_file"; echo "File size: ${file_size} bytes"; echo "MD5 checksum: $md5_checksum"; echo "CRC32 checksum: $crc32_checksum"; echo "Log file: $LOG_FILE"
  } > "$metadata_file"; log "Metadata file created: $metadata_file"; local duration=$SECONDS; log "Backup finished. Total time: $((duration/60))m $((duration%60))s"
}

main() {
  init_log; (( $# != 1 )) && { usage; exit 1; }
  case "$1" in --dev|-d) set_env_dev ;; --prod|-p) set_env_prod ;; -h|--help) usage; exit 0 ;; *) error "Invalid argument: '$1'" ;; esac
  load_config; backup_db
}

main "$@"
