#!/usr/bin/env bash

# Exit on error, undefined var, and failed pipeline
set -euo pipefail

################################
########### GLOBALS ############
################################

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""          # dev | prod
FOLDER_NAME=""          # dev | prod (used in backup folder and file names)
CONFIG_BASENAME=""      # dev.env | prod.env
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"          # optional override
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/backups}" # base backups directory

backup_file=""
metadata_file=""

# Max allowed backup age in seconds (30 minutes)
MAX_BACKUP_AGE_SECONDS=$((30 * 60))

################################
########### LOGGING ############
################################

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--dev | -d | --prod | -p]

Environment selection (required, one of):
  --dev,  -d   Use dev.env and restore from backups/dev/...
  --prod, -p   Use prod.env and restore from backups/prod/...

Environment variables:
  CONFIG_FILE_PATH  Optional full path to env file
  BACKUP_ROOT       Optional base directory for backups (default: $BACKUP_ROOT)

Backup layout expected:
  \$BACKUP_ROOT/<env>/<timestamp>/<env>.dump
  \$BACKUP_ROOT/<env>/<timestamp>/<env>.meta (optional)

Safety rules:
  - Restore requires TWO confirmations:
      1) Answer 'yes' to a confirmation question
      2) Type the database name exactly
  - Restore is ONLY allowed if the selected backup file is <= 30 minutes old.

Examples:
  $SCRIPT_NAME --dev
  $SCRIPT_NAME --prod
  CONFIG_FILE_PATH=/etc/myapp/prod.env BACKUP_ROOT=/mnt/backups $SCRIPT_NAME --prod

EOF
}

################################
########## ARG PARSING #########
################################

parse_args() {
    local env_set=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dev|-d)
                ENVIRONMENT="dev"
                FOLDER_NAME="dev"
                CONFIG_BASENAME="dev.env"
                env_set=1
                ;;
            --prod|-p)
                ENVIRONMENT="prod"
                FOLDER_NAME="prod"
                CONFIG_BASENAME="prod.env"
                env_set=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
        shift
    done

    if (( env_set == 0 )); then
        error "You must specify one environment: --dev/-d or --prod/-p"
    fi
}

################################
########### CONFIG #############
################################

load_config() {
    if [[ -z "$CONFIG_FILE_PATH" ]]; then
        CONFIG_FILE_PATH="${SCRIPTPATH}/${CONFIG_BASENAME}"
    fi

    if [[ ! -r "$CONFIG_FILE_PATH" ]]; then
        error "Could not load config file from: $CONFIG_FILE_PATH"
    fi

    log "Loading config from: $CONFIG_FILE_PATH"

    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE_PATH"
    set +a

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
        error "Missing required environment variables: ${missing[*]}"
    fi
}

################################
########## BACKUP LIST #########
################################

list_backups_and_select() {
    local base_dir="${BACKUP_ROOT}/${FOLDER_NAME}"

    if [[ ! -d "$base_dir" ]]; then
        error "Backup directory does not exist: $base_dir"
    fi

    log "Listing available backups under: $base_dir"

    local -a backup_dirs=()
    local dir
    while IFS= read -r -d '' dir; do
        backup_dirs+=("$dir")
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    if (( ${#backup_dirs[@]} == 0 )); then
        error "No backup directories found in $base_dir"
    fi

    echo "Available backups:"
    local i=1
    for d in "${backup_dirs[@]}"; do
        local dump_file="${d}/${FOLDER_NAME}.dump"
        local meta_file="${d}/${FOLDER_NAME}.meta"
        local name
        name=$(basename "$d")

        if [[ -f "$dump_file" ]]; then
            if [[ -f "$meta_file" ]]; then
                printf "  %2d) %s\n" "$i" "$name"
            else
                printf "  %2d) %s * (missing .meta)\n" "$i" "$name"
            fi
            ((i++))
        fi
    done

    if (( i == 1 )); then
        error "No valid backups (with .dump) found in $base_dir"
    fi

    local selection=""
    while true; do
        read -r -p "Enter the number of the backup you want to restore: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection < i )); then
            local idx=$((selection - 1))
            local chosen_dir=""
            local n=0
            for d in "${backup_dirs[@]}"; do
                local dump_file="${d}/${FOLDER_NAME}.dump"
                if [[ -f "$dump_file" ]]; then
                    if (( n == idx )); then
                        chosen_dir="$d"
                        break
                    fi
                    ((n++))
                fi
            done

            if [[ -n "$chosen_dir" ]]; then
                backup_file="${chosen_dir}/${FOLDER_NAME}.dump"
                metadata_file="${chosen_dir}/${FOLDER_NAME}.meta"
                log "Selected backup: $(basename "$chosen_dir")"
                if [[ -f "$metadata_file" ]]; then
                    echo "Backup metadata:"
                    cat "$metadata_file"
                else
                    echo "Backup metadata: <missing>"
                fi
                break
            fi
        fi
        echo "Invalid selection. Please enter a valid number."
    done
}

load_latest_backup_or_select() {
    local base_dir="${BACKUP_ROOT}/${FOLDER_NAME}"

    if [[ ! -d "$base_dir" ]]; then
        error "Backup directory does not exist: $base_dir"
    fi

    log "Looking for the latest backup in: $base_dir"

    local latest_backup_dir
    latest_backup_dir=$(ls -td "${base_dir}"/* 2>/dev/null | head -n 1 || true)

    if [[ -z "$latest_backup_dir" ]]; then
        echo "No backups found in $base_dir"
        list_backups_and_select
        return
    fi

    backup_file="${latest_backup_dir}/${FOLDER_NAME}.dump"
    metadata_file="${latest_backup_dir}/${FOLDER_NAME}.meta"

    if [[ ! -f "$backup_file" ]]; then
        echo "Latest backup folder does not contain a .dump file: $latest_backup_dir"
        list_backups_and_select
        return
    fi

    echo "Latest backup found: $(basename "$latest_backup_dir")"
    if [[ -f "$metadata_file" ]]; then
        echo "Backup metadata:"
        cat "$metadata_file"
    else
        echo "Backup metadata: <missing>"
    fi

    read -r -p "Do you want to restore this latest backup? (y/n) " confirm_restore
    if [[ "$confirm_restore" != "y" ]]; then
        echo "You chose not to restore the latest backup."
        list_backups_and_select
    fi
}

################################
########### SAFETY #############
################################

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command '$cmd' not found in PATH."
    fi
}

check_backup_age() {
    require_cmd "stat"

    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        error "Backup file not set or does not exist: $backup_file"
    fi

    # Get backup file modification time (epoch seconds)
    local backup_mtime
    backup_mtime=$(stat -c %Y "$backup_file")

    local now
    now=$(date +%s)

    local age=$(( now - backup_mtime ))

    if (( age < 0 )); then
        log "WARN: backup file appears to be from the future (clock issue?)."
    fi

    if (( age > MAX_BACKUP_AGE_SECONDS )); then
        local minutes=$(( MAX_BACKUP_AGE_SECONDS / 60 ))
        error "Selected backup is older than ${minutes} minutes. Restore is not allowed for safety."
    fi

    local age_min=$(( age / 60 ))
    local age_sec=$(( age % 60 ))
    log "Backup age: ${age_min} minutes and ${age_sec} seconds (within allowed window)."
}

confirm_restore() {
    echo
    echo "You are about to RESTORE database:"
    echo "  Environment = $ENVIRONMENT"
    echo "  DB_DATABASE = $DB_DATABASE"
    echo "  DB_HOST     = $DB_HOST"
    echo "  DB_USERNAME = $DB_USERNAME"
    echo "  Backup file = $backup_file"
    echo

    # First confirmation
    local ans
    read -r -p "First confirmation: Are you absolutely sure you want to restore this backup? (yes/no) " ans
    if [[ "$ans" != "yes" ]]; then
        log "First confirmation denied. Aborting restore."
        exit 1
    fi

    # Second confirmation: type DB name
    read -r -p "Second confirmation: Type the database name ('$DB_DATABASE') to confirm restore: " answer
    if [[ "$answer" != "$DB_DATABASE" ]]; then
        log "Second confirmation failed (database name mismatch). Aborting restore."
        exit 1
    fi

    log "Double confirmation accepted. Proceeding with restore."
}

################################
########### RESTORE ############
################################

restore_db() {
    validate_required_env
    require_cmd "pg_restore"

    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        error "Backup file not set or does not exist: $backup_file"
    fi

    # Security: ensure backup is recent enough
    check_backup_age

    # Double confirmation
    confirm_restore

    local port_arg=()
    if [[ -n "${DB_PORT:-}" ]]; then
        port_arg=(-p "$DB_PORT")
    fi

    log "Starting restore at: $(date)"
    log "Connecting to database: $DB_DATABASE on $DB_HOST"

    PGPASSWORD="$DB_PASSWORD" \
    pg_restore \
        -h "$DB_HOST" \
        -U "$DB_USERNAME" \
        -d "$DB_DATABASE" \
        "${port_arg[@]}" \
        --clean \
        --verbose \
        -F c \
        "$backup_file"

    log "Restore completed successfully at: $(date)"
}

################################
############ MAIN ##############
################################

main() {
    SECONDS=0
    parse_args "$@"
    load_config
    load_latest_backup_or_select
    restore_db
    local duration=$SECONDS
    printf "Total time: %d minutes and %d seconds elapsed.\n" "$((duration / 60))" "$((duration % 60))"
}

main "$@"
