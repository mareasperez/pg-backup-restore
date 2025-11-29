#!/usr/bin/env bash

# Exit on error, undefined var, and failed pipeline
set -euo pipefail

################################
########### GLOBALS ############
################################

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""          # dev | prod
ENV_FILE=""             # dev.env | prod.env (resolved based on ENVIRONMENT)
ENV_FLAG=""             # --dev or --prod (to pass to backup.sh)

# External scripts
BACKUP_SCRIPT="${BACKUP_SCRIPT:-$SCRIPTPATH/backup.sh}"

# Flags
AUTO_CONFIRM=0      # set to 1 when --yes is used
SKIP_BACKUP=0       # set to 1 when --skip-backup is used (DANGEROUS)

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
Usage: $SCRIPT_NAME [--dev | -d | --prod | -p] [--yes] [--skip-backup]

Environment selection (required, one of):
  --dev,  -d   Use dev.env, target development database
  --prod, -p   Use prod.env, target production database

Options:
  --yes            Skip confirmation prompt (DANGEROUS)
  --skip-backup    Skip calling backup.sh before dropping (VERY DANGEROUS, NOT RECOMMENDED)
  -h, --help       Show this help message

External script:
  BACKUP_SCRIPT   Path to backup script (default: $BACKUP_SCRIPT)

Expected env files (relative to script path):
  dev.env, prod.env
  Each must define:
    DB_DATABASE, DB_HOST, DB_USERNAME, DB_PASSWORD
    (optional: DB_PORT)

Examples:
  $SCRIPT_NAME --dev
  $SCRIPT_NAME -d --yes
  BACKUP_SCRIPT=/opt/tools/backup.sh $SCRIPT_NAME --prod

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
                ENV_FILE="$SCRIPTPATH/dev.env"
                ENV_FLAG="--dev"
                env_set=1
                ;;
            --prod|-p)
                ENVIRONMENT="prod"
                ENV_FILE="$SCRIPTPATH/prod.env"
                ENV_FLAG="--prod"
                env_set=1
                ;;
            --yes)
                AUTO_CONFIRM=1
                ;;
            --skip-backup)
                SKIP_BACKUP=1
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

load_env_file() {
    if [[ -z "$ENV_FILE" ]]; then
        error "ENV_FILE not set. Internal error."
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        error "Env file not found: $ENV_FILE"
    fi

    if [[ ! -r "$ENV_FILE" ]]; then
        error "Env file is not readable: $ENV_FILE"
    fi

    log "Environment selected: $ENVIRONMENT"
    log "Loading environment variables from: $ENV_FILE"

    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a

    log "Environment variables loaded:"
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
########### SAFETY #############
################################

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/devnull 2>&1; then
        error "Required command '$cmd' not found in PATH."
    fi
}

confirm_dangerous_operation() {
    if (( AUTO_CONFIRM == 1 )); then
        log "Auto-confirm enabled (--yes). Skipping interactive prompt."
        return 0
    fi

    echo
    echo "!!! DANGER !!!"
    echo "You are about to DROP ALL TABLES in database:"
    echo "  Environment = $ENVIRONMENT"
    echo "  DB_DATABASE = $DB_DATABASE"
    echo "  DB_HOST     = $DB_HOST"
    echo "  DB_USERNAME = $DB_USERNAME"
    echo
    read -r -p "Type the database name ('$DB_DATABASE') to confirm, or anything else to abort: " answer

    if [[ "$answer" != "$DB_DATABASE" ]]; then
        log "Confirmation failed. Aborting."
        exit 1
    fi

    log "Confirmation accepted. Proceeding."
}

################################
########## BACKUP CALL #########
################################

run_backup_script() {
    if (( SKIP_BACKUP == 1 )); then
        log "WARNING: Backup step skipped (--skip-backup)."
        return 0
    fi

    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        error "Backup script not found or not executable: $BACKUP_SCRIPT"
    fi

    log "Running backup script before dropping tables..."
    log "Backup command: $BACKUP_SCRIPT $ENV_FLAG (CONFIG_FILE_PATH=$ENV_FILE)"

    # Pasamos el archivo de config al backup y dejamos que él haga lo suyo.
    CONFIG_FILE_PATH="$ENV_FILE" "$BACKUP_SCRIPT" "$ENV_FLAG"
    local status=$?

    if (( status != 0 )); then
        error "Backup script failed with exit code $status. Aborting drop."
    fi

    log "Backup completed successfully."
}

################################
########### ACTION #############
################################

drop_all_tables() {
    validate_required_env
    require_cmd "psql"

    confirm_dangerous_operation
    run_backup_script

    local port_arg=()
    if [[ -n "${DB_PORT:-}" ]]; then
        port_arg=(-p "$DB_PORT")
    fi

    log "Dropping all tables in database: $DB_DATABASE"
    log "Connecting to host: $DB_HOST"
    log "Connecting with user: $DB_USERNAME"

    PGPASSWORD="$DB_PASSWORD" \
    psql \
        -h "$DB_HOST" \
        -U "$DB_USERNAME" \
        -d "$DB_DATABASE" \
        "${port_arg[@]}" \
        -v ON_ERROR_STOP=1 \
        -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' || \
        error "Failed to drop/recreate public schema."

    log "All tables dropped and public schema recreated."
}

################################
############ MAIN ##############
################################

main() {
    parse_args "$@"
    load_env_file
    drop_all_tables
}
 
main "$@"
