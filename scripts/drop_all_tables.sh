#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)
PROJECT_ROOT="${TOOL_ROOT:-$SCRIPTPATH/..}"

# Source environment utilities
source "$SCRIPTPATH/env_utils.sh"

ENVIRONMENT=""; ENV_FILE=""; BACKUP_SCRIPT="${BACKUP_SCRIPT:-$SCRIPTPATH/backup.sh}"
AUTO_CONFIRM=0; SKIP_BACKUP=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }
usage() { cat <<EOF
Usage: $SCRIPT_NAME --env <environment> [--yes] [--skip-backup]

Available environments:
$(list_environments | sed 's/^/  - /')

WARNING:
  This will DROP ALL TABLES in the specified environment.
  A backup is created automatically before dropping (unless --skip-backup is used).
  
Options:
  --yes           Skip confirmation prompt
  --skip-backup   Skip pre-drop backup (DANGEROUS)
EOF
}

parse_args() {
  local env_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env|-e) shift; ENVIRONMENT="${1:-}"; env_set=1 ;;
      --yes) AUTO_CONFIRM=1 ;;
      --skip-backup) SKIP_BACKUP=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown argument: $1" ;;
    esac; shift || true
  done
  
  if (( env_set == 0 )); then
    echo "Error: --env <environment> is required"
    echo
    usage
    exit 1
  fi
  
  validate_environment "$ENVIRONMENT"
  ENV_FILE=$(get_env_file_path "$ENVIRONMENT")
}

load_env_file() { [[ -f "$ENV_FILE" && -r "$ENV_FILE" ]] || error "Env file not readable: $ENV_FILE"; log "Environment selected: $ENVIRONMENT"; log "Loading env from: $ENV_FILE"; set -a; source "$ENV_FILE"; set +a; log "Env loaded"; echo "========================================"; echo "DB_DATABASE: ${DB_DATABASE:-<not set>}"; echo "DB_HOST:     ${DB_HOST:-<not set>}"; echo "DB_USERNAME: ${DB_USERNAME:-<not set>}"; echo "DB_PASSWORD: ${DB_PASSWORD:+********}"; echo "DB_PORT:     ${DB_PORT:-<default>}"; echo "========================================"; }
validate_required_env() {
  local missing=()
  for var in DB_DATABASE DB_HOST DB_USERNAME DB_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    error "Missing required env: ${missing[*]}"
  fi
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || error "Required command '$1' not found in PATH."; }

test_connection() {
  require_cmd "psql"
  local port="${DB_PORT:-5432}"
  log "Testing connectivity to $DB_HOST:$port ($DB_DATABASE)"
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "$port" -t -A -c 'SELECT 1;' >/dev/null 2>&1 || error "Connectivity test failed (SELECT 1). Aborting drop operation."
  log "Connectivity OK."
}

confirm_dangerous_operation() {
  (( AUTO_CONFIRM == 1 )) && { log "Auto-confirm enabled (--yes)."; return; }
  echo; echo "!!! DANGER !!!"; echo "You are about to DROP ALL TABLES:"; echo "  Environment = $ENVIRONMENT"; echo "  DB_DATABASE = $DB_DATABASE"; echo "  DB_HOST     = $DB_HOST"; echo "  DB_USERNAME = $DB_USERNAME"; echo; read -r -p "Type the database name ('$DB_DATABASE') to confirm, or anything else to abort: " answer; [[ "$answer" == "$DB_DATABASE" ]] || { log "Confirmation failed. Aborting."; exit 1; }; log "Confirmation accepted."
}

run_backup_script() {
  (( SKIP_BACKUP == 1 )) && { log "WARNING: Skipping backup (--skip-backup)."; return; }
  [[ -x "$BACKUP_SCRIPT" ]] || error "Backup script not executable: $BACKUP_SCRIPT"
  log "Running backup script before dropping tables..."
  CONFIG_FILE_PATH="$ENV_FILE" "$BACKUP_SCRIPT" --env "$ENVIRONMENT"
  local status=$?
  (( status == 0 )) || error "Backup script failed with exit code $status. Aborting drop."
  log "Backup completed successfully."
}

drop_all_tables() {
  validate_required_env; test_connection; confirm_dangerous_operation; run_backup_script
  local port_arg=(); [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")
  log "Dropping all tables in database: $DB_DATABASE"; log "Connecting to host: $DB_HOST"; log "Connecting with user: $DB_USERNAME"
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" "${port_arg[@]}" -v ON_ERROR_STOP=1 -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' || error "Failed to drop/recreate public schema."
  log "All tables dropped and public schema recreated."
}

main() { parse_args "$@"; load_env_file; drop_all_tables; }
main "$@"
