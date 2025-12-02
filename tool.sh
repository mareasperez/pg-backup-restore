#!/usr/bin/env bash

# Central entry point for pg-backup-restore toolkit
# Routes to: backup.sh, restore_db.sh, drop_all_tables.sh, backup_deps.sh, env_utils.sh

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

# Set TOOL_ROOT for scripts to use
export TOOL_ROOT="$SCRIPTPATH"

BACKUP_SCRIPT="$SCRIPTPATH/scripts/backup.sh"
RESTORE_SCRIPT="$SCRIPTPATH/scripts/restore_db.sh"
DROP_SCRIPT="$SCRIPTPATH/scripts/drop_all_tables.sh"
DEPS_SCRIPT="$SCRIPTPATH/scripts/backup_deps.sh"
ENV_UTILS="$SCRIPTPATH/scripts/env_utils.sh"

# Source environment utilities
source "$ENV_UTILS"

CONFIG_FILE_PATH="${CONFIG_FILE_PATH:-}"
BACKUP_ROOT="${BACKUP_ROOT:-}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { log "ERROR: $*"; exit 1; }

# Runtime guard: Linux/WSL only
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux) ;; # OK: native Linux or WSL
  *)
    error "Unsupported shell/OS. Use Bash on Linux or WSL. On Windows, run via WSL (Ubuntu)."
    ;;
esac

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <command> [options]

Environment Management:
  env list                List all available environments
  env create <name>       Create new environment (interactive or from URL)
  env remove <name>       Remove an environment
  env test <name>         Test database connection for an environment
  env migrate             Migrate old .env files to environments/ directory

Backup Operations:
  backup --env <name>     Backup specified environment
  list --env <name>       List backups for environment

Restore Operations:
  restore --target <env> [--source <env>] [--latest]
                          Restore from backup (interactive or latest)
  sync --source <env> --target <env>
                          Backup source and restore to target (1-step sync)

Maintenance:
  drop --env <name>       Drop all tables (with auto-backup)
  deps --check            Check dependencies
  deps --install          Install dependencies (requires sudo)

Options:
  --config <path>         Override env file path
  --backups <path>        Override backups base dir
  --yes                   Skip confirmations
  --skip-backup           Skip pre-drop backup (DANGEROUS)
  -h | --help             Show this help

Examples:
  $SCRIPT_NAME env list
  $SCRIPT_NAME env create staging
  $SCRIPT_NAME env test prod
  $SCRIPT_NAME backup --env prod
  $SCRIPT_NAME sync --source prod --target dev
  $SCRIPT_NAME restore --target dev --source prod --latest
  $SCRIPT_NAME list --env staging
  $SCRIPT_NAME drop --env dev --yes

Notes:
  - All operations work with any defined environment
  - Use 'env list' to see available environments
  - Create environments with 'env create' before using them
EOF
}

require_script() {
  local f="$1"; [[ -x "$f" ]] || error "Required script not executable: $f"
}

pass_config_env() {
  [[ -n "$CONFIG_FILE_PATH" ]] && export CONFIG_FILE_PATH
  [[ -n "$BACKUP_ROOT" ]] && export BACKUP_ROOT
  export TOOL_ROOT="$SCRIPTPATH"
}

# Environment management commands
cmd_env() {
  local subcmd="${1:-}"
  shift || true
  
  case "$subcmd" in
    list)
      echo "Available environments:"
      list_environments | sed 's/^/  - /' || echo "  (none)"
      ;;
    create)
      local env_name="${1:-}"
      [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME env create <name> [postgres_url]"
      if [[ -n "${2:-}" ]]; then
        create_environment_from_url "$env_name" "$2"
      else
        create_environment_interactive "$env_name"
      fi
      ;;
    remove)
      local env_name="${1:-}"
      [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME env remove <name>"
      remove_environment "$env_name"
      ;;
    test)
      local env_name="${1:-}"
      [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME env test <name>"
      test_environment "$env_name"
      ;;
    migrate)
      cmd_migrate_envs
      ;;
    *)
      echo "Unknown env command: $subcmd"
      echo "Usage: $SCRIPT_NAME env {list|create|remove|test|migrate}"
      exit 1
      ;;
  esac
}

cmd_migrate_envs() {
  log "Migrating .env files to environments/ directory..."
  
  local env_files=()
  while IFS= read -r -d '' f; do
    env_files+=("$f")
  done < <(find "$SCRIPTPATH" -maxdepth 1 -name "*.env" -type f -print0 2>/dev/null || true)
  
  if (( ${#env_files[@]} == 0 )); then
    log "No .env files found in root directory"
    return 0
  fi
  
  mkdir -p "$SCRIPTPATH/environments"
  
  for f in "${env_files[@]}"; do
    local basename=$(basename "$f")
    local target="$SCRIPTPATH/environments/$basename"
    
    if [[ -f "$target" ]]; then
      log "SKIP: $basename already exists in environments/"
      continue
    fi
    
    log "Moving $basename to environments/"
    mv "$f" "$target"
    chmod 600 "$target"
  done
  
  log "Migration complete!"
  log "Migrated ${#env_files[@]} environment file(s)"
}

cmd_backup() {
  require_script "$BACKUP_SCRIPT"
  local env_name=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env|-e) shift; env_name="${1:-}" ;;
      --config) shift; CONFIG_FILE_PATH="${1:-}" ;;
      --backups) shift; BACKUP_ROOT="${1:-}" ;;
      *) break ;;
    esac
    shift || true
  done
  
  [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME backup --env <name>"
  pass_config_env
  log "Dispatching: backup --env $env_name"
  "$BACKUP_SCRIPT" --env "$env_name"
}

cmd_list() {
  require_script "$RESTORE_SCRIPT"
  local env_name=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env|-e) shift; env_name="${1:-}" ;;
      --config) shift; CONFIG_FILE_PATH="${1:-}" ;;
      --backups) shift; BACKUP_ROOT="${1:-}" ;;
      *) break ;;
    esac
    shift || true
  done
  
  [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME list --env <name>"
  pass_config_env
  log "Dispatching: list --env $env_name"
  "$RESTORE_SCRIPT" --source "$env_name" --list
}

cmd_restore() {
  require_script "$RESTORE_SCRIPT"
  pass_config_env
  log "Dispatching: restore $*"
  "$RESTORE_SCRIPT" "$@"
}

cmd_sync() {
  require_script "$BACKUP_SCRIPT"
  require_script "$RESTORE_SCRIPT"
  
  local source_env=""
  local target_env=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source|-s) shift; source_env="${1:-}" ;;
      --target|-t) shift; target_env="${1:-}" ;;
      --config) shift; CONFIG_FILE_PATH="${1:-}" ;;
      --backups) shift; BACKUP_ROOT="${1:-}" ;;
      *) break ;;
    esac
    shift || true
  done
  
  [[ -n "$source_env" ]] || error "Usage: $SCRIPT_NAME sync --source <env> --target <env>"
  [[ -n "$target_env" ]] || error "Usage: $SCRIPT_NAME sync --source <env> --target <env>"
  
  # Validate both environments exist
  validate_environment "$source_env"
  validate_environment "$target_env"
  
  pass_config_env
  
  log "Starting sync: $source_env → $target_env"
  echo
  echo "This will:"
  echo "  1. Create a fresh backup of: $source_env"
  echo "  2. Restore that backup into: $target_env"
  echo
  read -r -p "Continue? (y/n): " confirm
  [[ "$confirm" == "y" ]] || { log "Sync cancelled"; exit 0; }
  
  log "Step 1/2: Backing up $source_env..."
  "$BACKUP_SCRIPT" --env "$source_env"
  
  log "Step 2/2: Restoring to $target_env..."
  "$RESTORE_SCRIPT" --target "$target_env" --source "$source_env" --latest
  
  log "Sync complete: $source_env → $target_env"
}

cmd_drop() {
  require_script "$DROP_SCRIPT"
  local env_name=""
  local extra_args=()
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env|-e) shift; env_name="${1:-}" ;;
      --config) shift; CONFIG_FILE_PATH="${1:-}" ;;
      --backups) shift; BACKUP_ROOT="${1:-}" ;;
      --yes|--skip-backup) extra_args+=("$1") ;;
      *) break ;;
    esac
    shift || true
  done
  
  [[ -n "$env_name" ]] || error "Usage: $SCRIPT_NAME drop --env <name>"
  pass_config_env
  log "Dispatching: drop --env $env_name ${extra_args[*]}"
  "$DROP_SCRIPT" --env "$env_name" "${extra_args[@]}"
}

cmd_deps() {
  require_script "$DEPS_SCRIPT"
  log "Dispatching: deps $*"
  "$DEPS_SCRIPT" "$@"
}

main() {
  if (( $# < 1 )); then
    local envs=($(list_environments))
    local num_envs=${#envs[@]}
    
    echo "Select an option:"
    echo "  [Environment Management]"
    echo "    1) List environments"
    echo "    2) Create new environment"
    echo "    3) Test environment connection"
    echo "    4) Remove environment"
    
    if (( num_envs > 0 )); then
      echo "  [Backup Operations]"
      local i=5
      for env in "${envs[@]}"; do
        echo "    $i) Backup $env"
        ((i++))
      done
      
      echo "  [Sync Operations]"
      local sync_start=$i
      if (( num_envs >= 2 )); then
        echo "    $i) Sync between environments"
        ((i++))
      fi
      
      echo "  [List Backups]"
      local list_start=$i
      for env in "${envs[@]}"; do
        echo "    $i) List $env backups"
        ((i++))
      done
      
      echo "  [Restore Operations]"
      local restore_start=$i
      if (( num_envs >= 2 )); then
        echo "    $i) Restore from another environment"
        ((i++))
      fi
    else
      echo "    (No environments configured - create one first)"
    fi
    
    echo "  [Utilities]"
    echo "    98) Check dependencies"
    echo "    99) Install dependencies"
    
    read -r -p "Enter number: " choice
    
    case "$choice" in
      1) cmd_env list ;;
      2) 
        read -r -p "Environment name: " name
        read -r -p "PostgreSQL URL (or press Enter for interactive): " url
        if [[ -n "$url" ]]; then
          cmd_env create "$name" "$url"
        else
          cmd_env create "$name"
        fi
        ;;
      3)
        if (( num_envs == 0 )); then
          echo "No environments available. Create one first."
          exit 1
        fi
        cmd_env list
        read -r -p "Environment name to test: " name
        cmd_env test "$name"
        ;;
      4)
        if (( num_envs == 0 )); then
          echo "No environments available."
          exit 1
        fi
        cmd_env list
        read -r -p "Environment name to remove: " name
        cmd_env remove "$name"
        ;;
      98) cmd_deps --check ;;
      99) cmd_deps --install ;;
      *)
        # Dynamic menu handling
        if (( num_envs == 0 )); then
          echo "Invalid choice"
          exit 1
        fi
        
        # Backup operations (5 to 5+num_envs-1)
        if (( choice >= 5 && choice < 5 + num_envs )); then
          local idx=$((choice - 5))
          cmd_backup --env "${envs[$idx]}"
        
        # Sync operation
        elif (( num_envs >= 2 && choice == sync_start )); then
          echo "Available environments:"
          for env in "${envs[@]}"; do
            echo "  - $env"
          done
          read -r -p "Source environment: " source
          read -r -p "Target environment: " target
          cmd_sync --source "$source" --target "$target"
        
        # List backups (after sync)
        elif (( choice >= list_start && choice < list_start + num_envs )); then
          local idx=$((choice - list_start))
          cmd_list --env "${envs[$idx]}"
        
        # Restore operation
        elif (( num_envs >= 2 && choice == restore_start )); then
          echo "Available environments:"
          for env in "${envs[@]}"; do
            echo "  - $env"
          done
          read -r -p "Source environment (where backup is): " source
          read -r -p "Target environment (where to restore): " target
          cmd_restore --target "$target" --source "$source" --latest
        
        else
          echo "Invalid choice"
          exit 1
        fi
        ;;
    esac
    exit 0
  fi
  
  local command="$1"; shift
  case "$command" in
    env) cmd_env "$@" ;;
    backup) cmd_backup "$@" ;;
    list) cmd_list "$@" ;;
    restore) cmd_restore "$@" ;;
    sync) cmd_sync "$@" ;;
    drop) cmd_drop "$@" ;;
    deps) cmd_deps "$@" ;;
    -h|--help) usage ;;
    *) error "Unknown command: $command. Use --help for usage." ;;
  esac
}

main "$@"
