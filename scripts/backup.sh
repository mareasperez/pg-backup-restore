#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; log "ERROR trap: rc=$rc line=$LINENO cmd=$BASH_COMMAND"' ERR
[[ "${BACKUP_DEBUG:-}" == "1" ]] && set -x
# Wrapper: moved from repo root. See README.
# Original content preserved.

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)
PROJECT_ROOT="${TOOL_ROOT:-$SCRIPTPATH/..}"

# Source environment utilities
source "$SCRIPTPATH/env_utils.sh"

ENVIRONMENT=""
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$PROJECT_ROOT/backups}"
LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/backup.log}"
ENV_DIR="${ENV_DIR:-$PROJECT_ROOT/environments}"

_log_to_file() { local msg="$1"; { printf '%s\n' "$msg" >> "$LOG_FILE"; } 2>/dev/null || true; }
log() { local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"; printf '%s\n' "$msg" >&2; _log_to_file "$msg"; }
error() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --env <environment> [--debug]
Flags:
  --env|-e <name>  Environment to backup (required)
  --debug          Verbose trace (or BACKUP_DEBUG=1)
  -h|--help        Show this help

Available environments:
$(list_environments | sed 's/^/  - /')

Env overrides:
  CONFIG_FILE_PATH  custom env file path
  BACKUP_ROOT       custom backups directory
  LOG_FILE          custom log file path
  ENV_DIR           custom environments directory

Dependencies:
  pg_dump, stat, md5sum (optional: crc32)

Examples:
  $SCRIPT_NAME --env prod
  $SCRIPT_NAME --env staging --debug
EOF
}

init_log() { touch "$LOG_FILE" 2>/dev/null || { printf 'WARN: cannot write log file at %s\n' "$LOG_FILE" >&2; return; }; _log_to_file "----------------------------------------"; _log_to_file "New run of $SCRIPT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"; }
require_cmd_or_hint() { local cmd="$1"; command -v "$cmd" >/dev/null 2>&1 || error "Required '$cmd' missing. Use ./scripts/backup_deps.sh --install"; }
ensure_dependencies() { require_cmd_or_hint "pg_dump"; require_cmd_or_hint "stat"; require_cmd_or_hint "md5sum"; command -v crc32 >/dev/null 2>&1 || log "WARN: 'crc32' not found. Setting CRC32 to N/A."; }

set_env() {
  local env_name="$1"
  validate_environment "$env_name"
  log "Selected environment: $env_name"
  ENVIRONMENT="$env_name"
  CONFIG_FILE_PATH=$(get_env_file_path "$env_name")
}

load_config() {
  [[ -r "$CONFIG_FILE_PATH" ]] || error "Could not read config file: $CONFIG_FILE_PATH"
  log "Loading config from: $CONFIG_FILE_PATH"
  set -a
  source "$CONFIG_FILE_PATH"
  set +a
}
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

create_backup_folder() {
  local now="$1"
  local backup_folder="${BACKUP_ROOT}/${ENVIRONMENT}/${now}"
  [[ -d "$backup_folder" ]] || {
    mkdir -p "$backup_folder"
    log "Created backup folder: $backup_folder"
  }
  printf '%s\n' "$backup_folder"
}
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
  local backup_file="${backup_folder}/${ENVIRONMENT}.dump"; local metadata_file="${backup_folder}/${ENVIRONMENT}.meta"; local transfer_file="${PROJECT_ROOT}/transfer.dump"
  log "Starting backup."; log "Database: $DB_DATABASE"; log "Host: $DB_HOST"; log "Backup file: $backup_file"; SECONDS=0
  # Estimar tamaño bruto (no comprimido) para ETA
  local db_estimated_size=0
  if command -v psql >/dev/null 2>&1; then
    db_estimated_size=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "${DB_PORT:-5432}" -t -A -c "SELECT pg_database_size('$DB_DATABASE');" 2>/dev/null || echo 0)
    [[ -n "$db_estimated_size" ]] || db_estimated_size=0
  fi
  if (( db_estimated_size > 0 )); then
    local est_mb=$(awk -v b="$db_estimated_size" 'BEGIN{printf "%.2f", b/1024/1024}')
    log "Estimated raw database size: ${est_mb} MB (custom format will differ)"
  else
    log "Raw size estimate unavailable; ETA will show '-'"
  fi
  export PGPASSWORD="$DB_PASSWORD"
  (
    pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "${DB_PORT:-5432}" -Fc --create -f "$backup_file" 2>&1 | sed 's/^/[pg_dump] /'
  ) &
  local pid=$!
  # Monitorear progreso
  local last_size=0 stall_count=0 max_stalls=10
  local elapsed m s
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$SECONDS
    m=$(( elapsed / 60 ))
    s=$(( elapsed % 60 ))
    local eta="-"
    if [[ -f "$backup_file" ]]; then
      local size_bytes
      size_bytes=$(stat --format="%s" "$backup_file" 2>/dev/null || echo 0)
      local size_mb=$(awk -v b="$size_bytes" 'BEGIN{printf "%.2f", b/1024/1024}')
      local delta=$(( size_bytes - last_size ))
      last_size=$size_bytes
      # actualizar velocidad promedio simple (total/elapsed)
      if (( elapsed > 0 )); then
        avg_speed=$(( size_bytes / elapsed ))
      fi
      if (( db_estimated_size > 0 && avg_speed > 0 && size_bytes < db_estimated_size )); then
        local remaining=$(( db_estimated_size - size_bytes ))
        local eta_sec=$(( remaining / avg_speed ))
        if (( eta_sec >= 0 )); then
          eta=$(printf "%02d:%02d" $(( eta_sec/60 )) $(( eta_sec%60 )))
        fi
      fi
      local delta_kb=$(awk -v d="$delta" 'BEGIN{printf "%.1f", d/1024}')
      printf "Elapsed %02d:%02d | Size %s MB | +%s KB/s | ETA %s\r" "$m" "$s" "$size_mb" "$delta_kb" "$eta"
    else
      printf "Elapsed %02d:%02d | awaiting dump creation...\r" "$m" "$s"
    fi
    sleep 1
  done
  wait "$pid"
  local rc=$?
  printf "\n"
  unset PGPASSWORD
  if (( rc != 0 )); then
    error "pg_dump failed with exit code $rc. See [pg_dump] lines above."
  fi
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
  local env_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env|-e) shift; env_arg="${1:-}" ;;
      --debug) BACKUP_DEBUG=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Invalid argument: '$1'. Use --help for usage." ;;
    esac
    shift || true
  done
  
  if [[ -z "$env_arg" ]]; then
    echo "Error: --env <environment> is required"
    echo
    usage
    exit 1
  fi
  
  set_env "$env_arg"
  load_config
  backup_db
}

main "$@"
