#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)
PROJECT_ROOT="${TOOL_ROOT:-$SCRIPTPATH/..}"

# Source environment utilities
source "$SCRIPTPATH/env_utils.sh"

# Global config (non-secret) file path (override with GLOBAL_CONFIG_FILE)
GLOBAL_CONFIG_FILE="${GLOBAL_CONFIG_FILE:-$PROJECT_ROOT/config.ini}"

TARGET_ENV=""
SOURCE_ENV=""
CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-}"
ENV_DIR="${ENV_DIR:-}"

NO_PROGRESS=0
SHOW_LINES=0
LATEST=0

# Global variables for backup file paths (set by latest_or_select_backup)
backup_file=""
metadata_file=""


LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/backup.log}"

log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>&1; }
error(){ printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; log "ERROR: $*"; exit 1; }


require_cmd(){ command -v "$1" >/dev/null 2>&1 || error "Missing required command: $1"; }

load_settings(){
  local file="$GLOBAL_CONFIG_FILE"
  [[ -r "$file" ]] || return 0
  while IFS='=' read -r k v; do
    local key="$(echo "$k" | sed 's/[[:space:]]//g')"
    [[ -z "$key" ]] && continue
    # Skip comments starting with # or ;
    case "$key" in
      \#*|\;*) continue ;;
    esac
    # Skip section headers like [paths]
    case "$key" in
      \[*\]) continue ;;
    esac
    local val="$(echo "$v" | sed 's/^ *//;s/ *$//;s/\r$//')"
    case "$key" in
      BACKUP_ROOT) [[ -z "$BACKUP_ROOT" ]] && BACKUP_ROOT="$val" ;;
      ENV_DIR) [[ -z "$ENV_DIR" ]] && ENV_DIR="$val" ;;
    esac
  done < "$file"
}



load_target_config(){
  [[ -n "$TARGET_ENV" ]] || error "Target env not set"
  validate_environment "$TARGET_ENV"
  local cfg=$(get_env_file_path "$TARGET_ENV")
  [[ -r "$cfg" ]] || error "Cannot read env file: $cfg"
  log "Loading target env from: $cfg"
  set -a
  source "$cfg"
  set +a
  for var in DB_DATABASE DB_HOST DB_USERNAME DB_PASSWORD; do
    [[ -n "${!var:-}" ]] || error "Missing required env var: $var"
  done
}

latest_or_select_backup(){
  [[ -n "$SOURCE_ENV" ]] || error "Source env not set"
  : "${BACKUP_ROOT:=$PROJECT_ROOT/backups}"
  local base="$BACKUP_ROOT/$SOURCE_ENV"
  if [[ ! -d "$base" ]]; then
    log "DEBUG: PROJECT_ROOT=$PROJECT_ROOT"
    log "DEBUG: BACKUP_ROOT=$BACKUP_ROOT"
    log "DEBUG: base=$base"
    error "Backup directory not found: $base"
  fi

  local latest
  latest=$(ls -td "$base"/* 2>/dev/null | head -n 1 || true)

  if (( LATEST == 1 )) && [[ -n "$latest" && -f "$latest/$SOURCE_ENV.dump" ]]; then
    backup_file="$latest/$SOURCE_ENV.dump"
    metadata_file="$latest/$SOURCE_ENV.meta"
    echo "Latest backup: $(basename "$latest")"
    [[ -f "$metadata_file" ]] && cat "$metadata_file"
    return
  fi

  if [[ -z "$latest" || ! -f "$latest/$SOURCE_ENV.dump" ]]; then
    echo "No valid latest backup found. Listing all available:";
  else
    echo "Latest backup: $(basename "$latest")"
    [[ -f "$latest/$SOURCE_ENV.meta" ]] && cat "$latest/$SOURCE_ENV.meta"
    read -r -p "Use latest? (y/n) " ans
    if [[ "$ans" == "y" ]]; then
      backup_file="$latest/$SOURCE_ENV.dump"
      metadata_file="$latest/$SOURCE_ENV.meta"
      return
    fi
  fi

  local -a dirs=()
  while IFS= read -r -d '' d; do dirs+=("$d"); done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  (( ${#dirs[@]} > 0 )) || error "No backups found in: $base"
  echo "Available backups:"; local i=1
  for d in "${dirs[@]}"; do
    [[ -f "$d/$SOURCE_ENV.dump" ]] && echo "  $i) $(basename "$d")" && ((i++))
  done
  (( i > 1 )) || error "No valid backups with dump file."
  while true; do
    read -r -p "Select backup number: " n
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n < i )); then
      local chosen="${dirs[n-1]}"
      backup_file="$chosen/$SOURCE_ENV.dump"
      metadata_file="$chosen/$SOURCE_ENV.meta"
      break
    fi
    echo "Invalid selection."
  done
}

confirm_restore(){
  echo
  echo "About to restore into target DB: $DB_DATABASE on $DB_HOST"
  [[ -f "$metadata_file" ]] && { echo "Source backup metadata:"; cat "$metadata_file"; }
  read -r -p "Type the database name ('$DB_DATABASE') to confirm: " ans
  [[ "$ans" == "$DB_DATABASE" ]] || error "Confirmation failed."
}

estimate_total_items(){
  [[ -n "$backup_file" ]] || { echo 0; return; }
  PGPASSWORD="$DB_PASSWORD" pg_restore -l "$backup_file" 2>/dev/null | grep -c . || echo 0
}

restore_with_progress(){
  local port_arg=(); [[ -n "${DB_PORT:-}" ]] && port_arg=(-p "$DB_PORT")
  log "Starting restore at: $(date)"
  log "Target: $DB_DATABASE@$DB_HOST | Source env: $SOURCE_ENV"

  if (( NO_PROGRESS == 1 )); then
    PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" \
      "${port_arg[@]}" --clean --verbose -F c "$backup_file"
    log "Restore completed successfully at: $(date)"; return
  fi

  local total_items processed_items eta_display last_line tmp_log
  total_items=$(estimate_total_items); tmp_log=$(mktemp); SECONDS=0
  (
    PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" \
      "${port_arg[@]}" --clean --verbose -F c "$backup_file" 2>"$tmp_log" 1>&2
  ) & local pid=$!; processed_items=0; echo ""

  # Simple line-by-line output - no terminal manipulation
  local use_tput=0
  
  local elapsed m s last_update=0
  echo "Progress updates (every 10 seconds):"
  
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$SECONDS; m=$((elapsed/60)); s=$((elapsed%60))
    
    # Only print update every 10 seconds to avoid spam
    if (( elapsed - last_update >= 10 )); then
      if (( total_items > 0 )); then
        processed_items=$(grep -cE '^pg_restore: (creating|processing|restoring|setting)' "$tmp_log" 2>/dev/null || echo 0)
      else
        processed_items=$(grep -cE '^pg_restore:' "$tmp_log" 2>/dev/null || echo 0)
      fi
      [[ "$processed_items" =~ ^[0-9]+$ ]] || processed_items=0; [[ "$m" =~ ^[0-9]+$ ]] || m=0; [[ "$s" =~ ^[0-9]+$ ]] || s=0
      local speed=0; if (( elapsed > 5 && processed_items > 0 )); then speed=$(( processed_items / elapsed )); fi
      eta_display="-"; if (( total_items > 0 && speed > 0 && processed_items < total_items )); then
        local remaining=$(( total_items - processed_items ))
        local eta_sec=$(( remaining / speed ))
        if (( eta_sec >= 0 && eta_sec < 43200 )); then
          local eh=$(( eta_sec / 3600 )) em=$(( (eta_sec % 3600) / 60 )) es=$(( eta_sec % 60 ))
          [[ "$eh" =~ ^[0-9]+$ ]] || eh=0; [[ "$em" =~ ^[0-9]+$ ]] || em=0; [[ "$es" =~ ^[0-9]+$ ]] || es=0
          if (( eh > 0 )); then eta_display=$(printf "%02d:%02d:%02d" "$eh" "$em" "$es"); else eta_display=$(printf "%02d:%02d" "$em" "$es"); fi
        fi
      fi
      
      # Print progress line
      printf "[%02d:%02d] Processed %d/%d items | ETA: %s\n" "$m" "$s" "$processed_items" "$total_items" "$eta_display"
      
      # Optionally show last line if requested
      if (( SHOW_LINES == 1 )); then 
        last_line=$(tail -n 1 "$tmp_log" 2>/dev/null || echo "")
        [[ -n "$last_line" ]] && echo "  └─ $last_line"
      fi
      
      last_update=$elapsed
    fi
    
    sleep 2
  done
  wait "$pid"; local rc=$?; echo ""
  if (( rc != 0 )); then log "Restore failed with exit code $rc. Last lines:"; tail -n 10 "$tmp_log" >&2; rm -f "$tmp_log"; error "pg_restore finished with errors"; fi
  rm -f "$tmp_log"; log "Restore completed successfully at: $(date)"
}

usage(){ cat <<EOF
Usage: $SCRIPT_NAME --target <env> [--source <env>] [--latest] [--no-progress] [--show-lines] [--list]

Available environments:
$(list_environments | sed 's/^/  - /')

Examples:
  $SCRIPT_NAME --target dev --source prod --latest    # Refresh dev from latest prod
  $SCRIPT_NAME --target dev --source prod             # Choose a prod backup
  $SCRIPT_NAME --target dev                           # Choose a dev backup
  $SCRIPT_NAME --target dev --latest                  # Latest dev backup
EOF
}

main(){
  load_settings
  : "${BACKUP_ROOT:=$PROJECT_ROOT/backups}"
  # If BACKUP_ROOT from config.ini is relative, normalize it to project root
  case "$BACKUP_ROOT" in
    /*|[A-Za-z]:*) ;; # absolute (Linux or Windows path)
    *) BACKUP_ROOT="$PROJECT_ROOT/$BACKUP_ROOT" ;;
  esac

  local LIST_ONLY=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) shift; TARGET_ENV="${1:-}" ;;
      --source) shift; SOURCE_ENV="${1:-}" ;;
      --latest) LATEST=1 ;;
      --no-progress) NO_PROGRESS=1 ;;
      --show-lines) SHOW_LINES=1 ;;
      --list) LIST_ONLY=1 ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown arg: $1" ;;
    esac; shift || true
  done

  if (( LIST_ONLY == 1 )); then
    [[ -n "$SOURCE_ENV" ]] || error "--source <env> required for list mode"
    validate_environment "$SOURCE_ENV"
    : "${BACKUP_ROOT:=$PROJECT_ROOT/backups}"
    # Ensure BACKUP_ROOT normalization (absolute or relative to project root)
    case "$BACKUP_ROOT" in
      /*|[A-Za-z]:*) ;; 
      *) BACKUP_ROOT="$PROJECT_ROOT/${BACKUP_ROOT#./}" ;;
    esac
    local base="$BACKUP_ROOT/$SOURCE_ENV"
    if [[ ! -d "$base" ]]; then
      log "No backups directory found at: $base"
      log "Hint: ensure '$SOURCE_ENV' subfolder exists under '$BACKUP_ROOT'"
      exit 0
    fi
    ls -1 "$base" | sed 's/^/  - /'
    exit 0
  fi

  [[ -n "$TARGET_ENV" ]] || error "--target <env> required"
  [[ -n "$SOURCE_ENV" ]] || SOURCE_ENV="$TARGET_ENV"

  load_target_config
  latest_or_select_backup
  
  # Add confirmation unless --latest flag is used (automated mode)
  if (( LATEST == 0 )); then
    confirm_restore
  fi
  
  # Test connection before attempting restore
  echo ""
  echo "🔍 Testing connection to target database..."
  test_environment "$TARGET_ENV"
  
  echo ""
  echo "📦 Backup file: $backup_file"
  echo "📊 Backup size: $(du -h "$backup_file" 2>/dev/null | cut -f1 || echo 'unknown')"
  echo ""
  echo "🚀 Starting restore process..."
  echo "⏳ This may take several minutes depending on database size."
  echo ""
  
  restore_with_progress
}

main "$@"
