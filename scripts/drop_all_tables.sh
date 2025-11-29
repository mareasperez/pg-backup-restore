#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

ENVIRONMENT=""; ENV_FILE=""; ENV_FLAG=""; BACKUP_SCRIPT="${BACKUP_SCRIPT:-$SCRIPTPATH/backup.sh}"
AUTO_CONFIRM=0; SKIP_BACKUP=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }
usage() { cat <<EOF
Usage: $SCRIPT_NAME [--dev|-d|--prod|-p] [--yes] [--skip-backup]
EOF
}

parse_args() {
  local env_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev|-d) ENVIRONMENT="dev"; ENV_FILE="$SCRIPTPATH/../dev.env"; ENV_FLAG="--dev"; env_set=1 ;;
      --prod|-p) ENVIRONMENT="prod"; ENV_FILE="$SCRIPTPATH/../prod.env"; ENV_FLAG="--prod"; env_set=1 ;;
      --yes) AUTO_CONFIRM=1 ;;
      --skip-backup) SKIP_BACKUP=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown argument: $1" ;;
    esac; shift
  done
  (( env_set == 1 )) || error "You must specify one environment: --dev/-d or --prod/-p"
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

confirm_dangerous_operation() {
  (( AUTO_CONFIRM == 1 )) && { log "Auto-confirm enabled (--yes)."; return; }
  echo; echo "!!! DANGER !!!"; echo "You are about to DROP ALL TABLES:"; echo "  Environment = $ENVIRONMENT"; echo "  DB_DATABASE = $DB_DATABASE"; echo "  DB_HOST     = $DB_HOST"; echo "  DB_USERNAME = $DB_USERNAME"; echo; read -r -p "Type the database name ('$DB_DATABASE') to confirm, or anything else to abort: " answer; [[ "$answer" == "$DB_DATABASE" ]] || { log "Confirmation failed. Aborting."; exit 1; }; log "Confirmation accepted."
}

run_backup_script() {
  (( SKIP_BACKUP == 1 )) && { log "WARNING: Skipping backup (--skip-backup)."; return; }
  [[ -x "$BACKUP_SCRIPT" ]] || error "Backup script not executable: $BACKUP_SCRIPT"
  log "Running backup script before dropping tables..."
  CONFIG_FILE_PATH="$ENV_FILE" "$BACKUP_SCRIPT" "$ENV_FLAG"; local status=$?; (( status == 0 )) || error "Backup script failed with exit code $status. Aborting drop."
  log "Backup completed successfully."
}

drop_all_tables() {
  validate_required_env; require_cmd "psql"; confirm_dangerous_operation; run_backup_script
  local port_arg=(); [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")
  log "Dropping all tables in database: $DB_DATABASE"; log "Connecting to host: $DB_HOST"; log "Connecting with user: $DB_USERNAME"
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" "${port_arg[@]}" -v ON_ERROR_STOP=1 -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' || error "Failed to drop/recreate public schema."
  log "All tables dropped and public schema recreated."
}

main() { parse_args "$@"; load_env_file; drop_all_tables; }
main "$@"
