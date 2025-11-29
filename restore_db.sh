#!/usr/bin/env bash
# DEPRECATED: use scripts/restore_db.sh via tool.sh
set -euo pipefail

################################
########### GLOBALS ############
################################

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""          
FOLDER_NAME=""          
CONFIG_BASENAME=""      
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPTPATH/backups}"

backup_file=""
metadata_file=""

# Only enforce backup age limit in PROD
MAX_BACKUP_AGE_SECONDS=$((30 * 60))

################################
########### LOGGING ############
################################

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--dev | -d | --prod | -p]

Environments:
  --dev,  -d   Restore from dev backups (no strict safety rules)
  --prod, -p   Restore from prod backups (STRICT safety rules enabled)

Strict safety rules (ONLY for --prod):
  - Backup MUST be <= 30 minutes old
  - TWO confirmations required:
         1) Confirm with 'yes'
         2) Type the exact database name

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
                usage; exit 0;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
        shift
    done

    if (( env_set == 0 )); then
        error "You must specify --dev/-d or --prod/-p"
    fi
}

################################
########### CONFIG #############
################################

load_config() {
    if [[ -z "$CONFIG_FILE_PATH" ]]; then
        CONFIG_FILE_PATH="$SCRIPTPATH/$CONFIG_BASENAME"
    fi

    if [[ ! -r "$CONFIG_FILE_PATH" ]]; then
        error "Cannot read config file: $CONFIG_FILE_PATH"
    fi

    log "Loading environment from: $CONFIG_FILE_PATH"

    set -a
    # shellcheck disable=SC1090
    source "$CONFIG_FILE_PATH"
    set +a

    log "Environment selected: $ENVIRONMENT"
}

validate_required_env() {
    for var in DB_DATABASE DB_HOST DB_USERNAME DB_PASSWORD; do
        [[ -z "${!var:-}" ]] && error "Missing required env var: $var"
    done
}

################################
######## BACKUP SELECTION ######
################################

list_backups_and_select() {
    local base="${BACKUP_ROOT}/${FOLDER_NAME}"

    [[ -d "$base" ]] || error "Backup directory not found: $base"

    local -a dirs=()
    while IFS= read -r -d '' d; do dirs+=("$d"); done \
        < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    (( ${#dirs[@]} > 0 )) || error "No backups found."

    echo "Available backups:"
    local idx=1
    for d in "${dirs[@]}"; do
        [[ -f "$d/$FOLDER_NAME.dump" ]] && echo "  $idx) $(basename "$d")" && ((idx++))
    done

    (( idx > 1 )) || error "No valid backups with dump file."

    while true; do
        read -r -p "Select backup number: " n
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n < idx )); then
            local chosen="${dirs[n-1]}"
            backup_file="$chosen/$FOLDER_NAME.dump"
            metadata_file="$chosen/$FOLDER_NAME.meta"
            break
        fi
        echo "Invalid selection."
    done
}

load_latest_backup_or_select() {
    local base="${BACKUP_ROOT}/${FOLDER_NAME}"

    [[ -d "$base" ]] || error "Backup directory does not exist: $base"

    local latest
    latest=$(ls -td "$base"/* 2>/dev/null | head -n 1 || true)

    if [[ -z "$latest" || ! -f "$latest/$FOLDER_NAME.dump" ]]; then
        echo "No valid latest backup found."
        list_backups_and_select
        return
    fi

    backup_file="$latest/$FOLDER_NAME.dump"
    metadata_file="$latest/$FOLDER_NAME.meta"

    echo "Latest backup: $(basename "$latest")"
    [[ -f "$metadata_file" ]] && cat "$metadata_file"

    read -r -p "Restore this backup? (y/n) " ans
    [[ "$ans" == "y" ]] || list_backups_and_select
}

################################
########### SAFETY #############
################################

check_backup_age_prod_only() {
    if [[ "$ENVIRONMENT" == "dev" ]]; then
        return 0  # NO strict rule for dev
    fi

    log "Checking backup age (prod strict mode)..."

    local mtime now age
    mtime=$(stat -c %Y "$backup_file")
    now=$(date +%s)
    age=$(( now - mtime ))

    if (( age > MAX_BACKUP_AGE_SECONDS )); then
        error "Backup is older than 30 minutes. Restore blocked for safety."
    fi

    log "Backup age OK (<= 30 minutes)."
}

double_confirmation_prod_only() {
    if [[ "$ENVIRONMENT" == "dev" ]]; then
        return 0  # No double confirmation for dev
    fi

    echo
    read -r -p "First confirmation: Are you absolutely sure? (yes/no) " ans
    [[ "$ans" == "yes" ]] || error "First confirmation denied."

    read -r -p "Second confirmation: Type the database name ('$DB_DATABASE') to confirm: " ans2
    [[ "$ans2" == "$DB_DATABASE" ]] || error "Second confirmation failed."

    log "Double confirmation passed."
}

################################
########### RESTORE ############
################################

restore_db() {
    validate_required_env
    [[ -f "$backup_file" ]] || error "Backup file missing: $backup_file"

    check_backup_age_prod_only
    double_confirmation_prod_only

    local port_arg=()
    [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")

    log "Starting restore..."
    PGPASSWORD="$DB_PASSWORD" pg_restore \
        -h "$DB_HOST" \
        -U "$DB_USERNAME" \
        -d "$DB_DATABASE" \
        "${port_arg[@]}" \
        --clean \
        --verbose \
        -F c \
        "$backup_file"

    log "Restore completed successfully."
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
    printf "Elapsed time: %d min %d sec\n" "$((SECONDS/60))" "$((SECONDS%60))"
}

main "$@"
