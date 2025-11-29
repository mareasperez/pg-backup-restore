#!/usr/bin/env bash

# Exit on error, undefined var, and failed pipeline
set -euo pipefail

################################
########### GLOBALS ############
################################

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""          # dev | prod
FOLDER_NAME=""          # dev | prod
CONFIG_BASENAME=""      # dev.env | prod.env
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"          # can be overridden from outside
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/backups}" # can be overridden from outside

# Logging
LOG_FILE="${LOG_FILE:-$SCRIPTPATH/backup.log}"    # log file path

################################
########### LOGGING ############
################################

_log_to_file() {
    local msg="$1"
    {
        printf '%s\n' "$msg" >> "$LOG_FILE"
    } 2>/dev/null || true
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    printf '%s\n' "$msg" >&2
    _log_to_file "$msg"
}

error() {
    log "ERROR: $*"
    exit 1
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME --dev | --prod

Flags:
  --dev, -d     Use dev.env and back up development database
  --prod, -p    Use prod.env and back up production database
  -h, --help    Show this help message

Environment variables:
  CONFIG_FILE_PATH  Optional full path to env file (default: ./dev.env or ./prod.env)
  BACKUP_ROOT       Optional backups directory (default: $SCRIPTPATH/backups)
  LOG_FILE          Optional path for logs (default: $SCRIPTPATH/backup.log)

Dependencies:
  Requires:
    - pg_dump   (usually from package: postgresql-client)
    - stat      (usually from package: coreutils)
    - md5sum    (usually from package: coreutils)
  Optional:
    - crc32     (usually from package: libarchive-zip-perl)

To install/check dependencies on Debian/Ubuntu/WSL you can use:
  ./backup_deps.sh --check
  sudo ./backup_deps.sh --install

Examples:
  $SCRIPT_NAME --dev
  $SCRIPT_NAME --prod
  $SCRIPT_NAME -d
  LOG_FILE=/var/log/db-backup.log $SCRIPT_NAME -p
EOF
}

init_log() {
    touch "$LOG_FILE" 2>/dev/null || {
        printf 'WARN: cannot write log file at %s\n' "$LOG_FILE" >&2
        return
    }
    _log_to_file "----------------------------------------"
    _log_to_file "New run of $SCRIPT_NAME at $(date '+%Y-%m-%d %H:%M:%S')"
}

################################
######## DEPENDENCIES ##########
################################

require_cmd_or_hint() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    error "Required command '$cmd' not found in PATH. \
Please install it manually or run ./backup_deps.sh --install on Debian/Ubuntu/WSL."
}

ensure_dependencies() {
    require_cmd_or_hint "pg_dump"
    require_cmd_or_hint "stat"
    require_cmd_or_hint "md5sum"

    if ! command -v crc32 >/dev/null 2>&1; then
        log "WARN: 'crc32' command not found. CRC32 checksum will be set to N/A."
    fi
}

################################
########### CONFIG #############
################################

set_env_dev() {
    log "Selected environment: DEV"
    ENVIRONMENT="dev"
    FOLDER_NAME="dev"
    CONFIG_BASENAME="dev.env"
}

set_env_prod() {
    log "Selected environment: PROD"
    ENVIRONMENT="prod"
    FOLDER_NAME="prod"
    CONFIG_BASENAME="prod.env"
}

load_config() {
    if [[ -z "$CONFIG_FILE_PATH" ]]; then
        CONFIG_FILE_PATH="${SCRIPTPATH}/${CONFIG_BASENAME}"
    fi

    if [[ ! -r "$CONFIG_FILE_PATH" ]]; then
        error "Could not read config file: $CONFIG_FILE_PATH"
    fi

    log "Loading config from: $CONFIG_FILE_PATH"

    set -a
    # shellcheck disable=SC1090
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

################################
########### HELPERS ############
################################

create_backup_folder() {
    local now="$1"
    local backup_folder="${BACKUP_ROOT}/${FOLDER_NAME}/${now}"

    if [[ ! -d "$backup_folder" ]]; then
        mkdir -p "$backup_folder"
        log "Created backup folder: $backup_folder"
    fi

    printf '%s\n' "$backup_folder"
}

calculate_file_size() {
    stat --format="%s" "$1"
}

calculate_md5() {
    md5sum "$1" | awk '{ print $1 }'
}

calculate_crc32() {
    local file="$1"

    if command -v crc32 >/dev/null 2>&1; then
        crc32 "$file"
    else
        printf 'N/A'
    fi
}

show_elapsed_time() {
    local pid="$1"
    local start_seconds=$SECONDS

    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_seconds ))
        local minutes=$(( elapsed / 60 ))
        local seconds=$(( elapsed % 60 ))
        printf "Time elapsed: %02d:%02d (mm:ss)...\r" "$minutes" "$seconds"
        sleep 1
    done
    printf "\n"
}

################################
########### BACKUP #############
################################

backup_db() {
    validate_required_env
    ensure_dependencies

    local now
    now=$(date +"%Y-%m-%d-%H-%M")
    local backup_folder
    backup_folder=$(create_backup_folder "$now")

    local backup_file="${backup_folder}/${FOLDER_NAME}.dump"
    local metadata_file="${backup_folder}/${FOLDER_NAME}.meta"
    local transfer_file="${SCRIPTPATH}/transfer.dump"

    log "Starting backup."
    log "Database: $DB_DATABASE"
    log "Host: $DB_HOST"
    log "Backup file: $backup_file"

    SECONDS=0

    # Run pg_dump in background inside a subshell with PGPASSWORD
    (
        export PGPASSWORD="$DB_PASSWORD"
        pg_dump \
            -h "$DB_HOST" \
            -U "$DB_USERNAME" \
            -d "$DB_DATABASE" \
            -Fc \
            --create \
            -f "$backup_file"
    ) &
    local pid=$!

    show_elapsed_time "$pid"
    wait "$pid"

    log "pg_dump completed successfully."

    cp -f "$backup_file" "$transfer_file"
    log "Copied backup to: $transfer_file"

    local file_size
    local md5_checksum
    local crc32_checksum

    file_size=$(calculate_file_size "$backup_file")
    md5_checksum=$(calculate_md5 "$backup_file")
    crc32_checksum=$(calculate_crc32 "$backup_file")

    {
        echo "Backup date: $(date)"
        echo "Environment: $ENVIRONMENT"
        echo "Database: $DB_DATABASE"
        echo "Host: $DB_HOST"
        echo "Backup file: $backup_file"
        echo "File size: ${file_size} bytes"
        echo "MD5 checksum: $md5_checksum"
        echo "CRC32 checksum: $crc32_checksum"
        echo "Log file: $LOG_FILE"
    } > "$metadata_file"

    log "Metadata file created: $metadata_file"

    local duration=$SECONDS
    local minutes=$(( duration / 60 ))
    local seconds=$(( duration % 60 ))
    log "Backup finished. Total time: ${minutes}m ${seconds}s"
}

################################
############ MAIN ##############
################################

main() {
    init_log

    if (( $# != 1 )); then
        usage
        exit 1
    fi

    case "$1" in
        --dev|-d)
            set_env_dev
            ;;
        --prod|-p)
            set_env_prod
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Invalid argument: '$1'. Expected '--dev'/'-d' or '--prod'/'-p'."
            ;;
    esac

    load_config
    backup_db
}

main "$@"
