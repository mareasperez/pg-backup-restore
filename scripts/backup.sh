#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; log "ERROR trap: rc=$rc line=$LINENO cmd=$BASH_COMMAND"' ERR
[[ "${BACKUP_DEBUG:-}" == "1" ]] && set -x
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
Usage: $SCRIPT_NAME --dev | --prod [--debug]
Flags:
  --dev|-d         Backup dev
  --prod|-p        Backup prod
  --debug          Verbose trace (or BACKUP_DEBUG=1)
Env overrides:
  CONFIG_FILE_PATH  custom env file path
  BACKUP_ROOT       custom backups directory
  LOG_FILE          custom log file path
Dependencies:
  pg_dump, stat, md5sum (optional: crc32)
EOF
}

init_log() { touch "$LOG_FILE" 2>/dev/null || { printf 'WARN: cannot write log file at %s\n' "$LOG_FILE" >&2; return; }; _log_to_file "----------------------------------------"; _log_to_file "New run of $SCRIPT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"; }
require_cmd_or_hint() { local cmd="$1"; command -v "$cmd" >/dev/null 2>&1 || error "Required '$cmd' missing. Use ./scripts/backup_deps.sh --install"; }
ensure_dependencies() { require_cmd_or_hint "pg_dump"; require_cmd_or_hint "stat"; require_cmd_or_hint "md5sum"; command -v crc32 >/dev/null 2>&1 || log "WARN: 'crc32' not found. Setting CRC32 to N/A."; }

set_env_dev() { log "Selected environment: DEV"; ENVIRONMENT="dev"; FOLDER_NAME="dev"; CONFIG_BASENAME="dev.env"; }
set_env_prod() { log "Selected environment: PROD"; ENVIRONMENT="prod"; FOLDER_NAME="prod"; CONFIG_BASENAME="prod.env"; }

load_config() { [[ -z "$CONFIG_FILE_PATH" ]] && CONFIG_FILE_PATH="${SCRIPTPATH}/../${CONFIG_BASENAME}"; [[ -r "$CONFIG_FILE_PATH" ]] || error "Could not read config file: $CONFIG_FILE_PATH"; log "Loading config from: $CONFIG_FILE_PATH"; set -a; source "$CONFIG_FILE_PATH"; set +a; }
validate_required_env() {
  local missing=()
  for var in DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    error "Missing required environment variables: ${missing[*]}"
  fi
}

create_backup_folder() { local now="$1"; local backup_folder="${BACKUP_ROOT}/${FOLDER_NAME}/${now}"; [[ -d "$backup_folder" ]] || { mkdir -p "$backup_folder"; log "Created backup folder: $backup_folder"; }; printf '%s\n' "$backup_folder"; }
calculate_file_size() { stat --format="%s" "$1"; }
calculate_md5() { md5sum "$1" | awk '{ print $1 }'; }
calculate_crc32() { local file="$1"; command -v crc32 >/dev/null 2>&1 && crc32 "$file" || printf 'N/A'; }
show_elapsed_time() { local pid="$1"; local start_seconds=$SECONDS; while kill -0 "$pid" 2>/dev/null; do local elapsed=$(( SECONDS - start_seconds )); printf "Time elapsed: %02d:%02d (mm:ss)...\r" $((elapsed/60)) $((elapsed%60)); sleep 1; done; printf "\n"; }

test_connection() {
  log "Testing connectivity (SELECT 1)..."
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "${DB_PORT:-5432}" -t -A -c 'SELECT 1;' >/dev/null 2>&1 || error "Database connectivity test failed (psql SELECT 1). Check host/port/network/VPN/firewall."
  log "Connectivity OK."
}

backup_db() {
  validate_required_env; ensure_dependencies; test_connection
  local now; now=$(date +"%Y-%m-%d-%H-%M"); local backup_folder; backup_folder=$(create_backup_folder "$now")
  local backup_file="${backup_folder}/${FOLDER_NAME}.dump"; local metadata_file="${backup_folder}/${FOLDER_NAME}.meta"; local transfer_file="${SCRIPTPATH}/../transfer.dump"
  log "Starting backup."; log "Database: $DB_DATABASE"; log "Host: $DB_HOST"; log "Backup file: $backup_file"; SECONDS=0
  export PGPASSWORD="$DB_PASSWORD"
  # Run pg_dump in foreground to capture immediate failure status
  if ! pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "${DB_PORT:-5432}" -Fc --create -f "$backup_file" 2>&1 | sed 's/^/[pg_dump] /'; then
    error "pg_dump failed. See preceding [pg_dump] lines for context."
  fi
  unset PGPASSWORD
  log "pg_dump completed successfully."
  cp -f "$backup_file" "$transfer_file" || error "Failed to copy to transfer.dump"
  log "Copied backup to: $transfer_file"
  local file_size md5_checksum crc32_checksum; file_size=$(calculate_file_size "$backup_file"); md5_checksum=$(calculate_md5 "$backup_file"); crc32_checksum=$(calculate_crc32 "$backup_file")
  {
    echo "Backup date: $(date)"; echo "Environment: $ENVIRONMENT"; echo "Database: $DB_DATABASE"; echo "Host: $DB_HOST"; echo "Backup file: $backup_file"; echo "File size: ${file_size} bytes"; echo "MD5 checksum: $md5_checksum"; echo "CRC32 checksum: $crc32_checksum"; echo "Log file: $LOG_FILE"
  } > "$metadata_file" || error "Failed writing metadata file"
  log "Metadata file created: $metadata_file"; local duration=$SECONDS; log "Backup finished. Total time: $((duration/60))m $((duration%60))s"
}

main() {
  init_log
  local debug_flag=0
  local env_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev|-d) env_arg="dev" ;;
      --prod|-p) env_arg="prod" ;;
      --debug) BACKUP_DEBUG=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Invalid argument: '$1'" ;;
    esac; shift
  done
  [[ -n "$env_arg" ]] || { usage; exit 1; }
  case "$env_arg" in dev) set_env_dev ;; prod) set_env_prod ;; esac
  load_config
  backup_db
}

main "$@"
