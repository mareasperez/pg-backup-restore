#!/usr/bin/env bash
# Environment management utilities
# Provides functions for listing, validating, creating, and managing database environments

set -euo pipefail

SCRIPT_DIR=$(cd "${0%/*}" && pwd -P)
PROJECT_ROOT="${TOOL_ROOT:-$SCRIPT_DIR/..}"
ENV_DIR="${ENV_DIR:-$PROJECT_ROOT/environments}"
LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/backup.log}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>&1; }
error() { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; log "ERROR: $*"; exit 1; }

# Windows-compatible read function to prevent cursor freezing
safe_read() {
  local prompt="$1"
  local var_name="$2"
  local flags="${3:-}"
  # Print prompt and flush
  printf "%s" "$prompt"
  sync 2>/dev/null || true
  # Read input with optional flags (like -s for password)
  if [[ "$flags" == "-s" ]]; then
    read -r -s "$var_name"
  else
    read -r "$var_name"
  fi
  sync 2>/dev/null || true
}


# List all available environments
list_environments() {
  [[ -d "$ENV_DIR" ]] || return 0
  find "$ENV_DIR" -maxdepth 1 -name "*.env" -type f 2>/dev/null | \
    grep -v "example.env" | \
    sed 's|.*/||; s|\.env$||' | \
    sort
}

# Validate that an environment exists
validate_environment() {
  local env_name="$1"
  local env_file="$ENV_DIR/${env_name}.env"
  [[ -f "$env_file" ]] || error "Environment '$env_name' not found. Available: $(list_environments | tr '\n' ' ')"
}

# Get the path to an environment file
get_env_file_path() {
  local env_name="$1"
  validate_environment "$env_name"
  echo "$ENV_DIR/${env_name}.env"
}

# Test database connection for an environment
test_environment() {
  local env_name="$1"
  validate_environment "$env_name"
  
  local env_file=$(get_env_file_path "$env_name")
  
  log "Testing connection for environment: $env_name"
  log "Loading configuration from: $env_file"
  
  # Load environment variables
  set -a
  source "$env_file"
  set +a
  
  # Validate required variables
  local missing=()
  for var in DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  
  if (( ${#missing[@]} > 0 )); then
    error "Missing required variables in $env_file: ${missing[*]}"
  fi
  
  local port="${DB_PORT:-5432}"
  
  echo "Connection details:"
  echo "  Host:     $DB_HOST"
  echo "  Port:     $port"
  echo "  Database: $DB_DATABASE"
  echo "  Username: $DB_USERNAME"
  echo
  
  # Check if psql is available
  if ! command -v psql >/dev/null 2>&1; then
    error "psql command not found. Install postgresql-client to test connections."
  fi
  
  log "Attempting connection..."
  
  # Test connection with SELECT 1
  if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -p "$port" -t -A -c 'SELECT 1;' >/dev/null 2>&1; then
    echo "✅ Connection successful!"
    log "Database connection test passed for environment: $env_name"
    return 0
  else
    echo "❌ Connection failed!"
    log "Database connection test failed for environment: $env_name"
    echo
    echo "Possible issues:"
    echo "  - Incorrect host, port, or database name"
    echo "  - Invalid username or password"
    echo "  - Database server is not running or not accessible"
    echo "  - Firewall blocking connection"
    echo "  - Network/VPN issues"
    return 1
  fi
}

# Parse PostgreSQL connection URL
# Format: postgresql://[user[:password]@][host][:port][/database][?param=value]
parse_postgres_url() {
  local url="$1"
  
  # Remove protocol prefix
  url="${url#postgresql://}"
  url="${url#postgres://}"
  
  # Extract user:password if present
  local userpass=""
  local hostpart="$url"
  if [[ "$url" =~ @ ]]; then
    userpass="${url%%@*}"
    hostpart="${url#*@}"
  fi
  
  local user="${userpass%%:*}"
  local password=""
  if [[ "$userpass" =~ : ]]; then
    password="${userpass#*:}"
  fi
  
  # Extract host:port/database
  local host_port_db="$hostpart"
  
  # Extract database (after /)
  local database=""
  if [[ "$host_port_db" =~ / ]]; then
    database="${host_port_db#*/}"
    database="${database%%\?*}"  # Remove query params
    host_port_db="${host_port_db%%/*}"
  fi
  
  # Extract host and port
  local host="${host_port_db%%:*}"
  local port="5432"
  if [[ "$host_port_db" =~ : ]]; then
    port="${host_port_db#*:}"
  fi
  
  # Set defaults
  [[ -z "$user" ]] && user="postgres"
  [[ -z "$host" ]] && host="localhost"
  [[ -z "$database" ]] && database="postgres"
  
  # Export for caller
  export PARSED_DB_HOST="$host"
  export PARSED_DB_PORT="$port"
  export PARSED_DB_USERNAME="$user"
  export PARSED_DB_PASSWORD="$password"
  export PARSED_DB_DATABASE="$database"
}

# Create a new environment interactively
create_environment_interactive() {
  local env_name="$1"
  
  echo "Creating new environment: $env_name"
  echo "Enter database connection details:"
  echo
  
  safe_read "Database host [localhost]: " db_host
  db_host="${db_host:-localhost}"
  
  safe_read "Database port [5432]: " db_port
  db_port="${db_port:-5432}"
  
  safe_read "Database name: " db_database
  [[ -n "$db_database" ]] || error "Database name is required"
  
  safe_read "Database username [postgres]: " db_username
  db_username="${db_username:-postgres}"
  
  # Retry password input up to 3 times
  local db_password=""
  local attempts=0
  local max_attempts=3
  
  while (( attempts < max_attempts )); do
    safe_read "Database password: " db_password "-s"
    echo
    
    if [[ -n "$db_password" ]]; then
      break
    fi
    
    ((attempts++))
    if (( attempts < max_attempts )); then
      echo "Password cannot be empty. Please try again. (Attempt $((attempts + 1))/$max_attempts)"
    fi
  done
  
  if [[ -z "$db_password" ]]; then
    error "Database password is required. Failed after $max_attempts attempts."
  fi
  
  create_env_file "$env_name" "$db_host" "$db_port" "$db_database" "$db_username" "$db_password"
}

# Create environment from PostgreSQL URL
create_environment_from_url() {
  local env_name="$1"
  local url="$2"
  
  log "Parsing PostgreSQL connection URL..."
  parse_postgres_url "$url"
  
  echo "Detected connection details:"
  echo "  Host:     $PARSED_DB_HOST"
  echo "  Port:     $PARSED_DB_PORT"
  echo "  Database: $PARSED_DB_DATABASE"
  echo "  Username: $PARSED_DB_USERNAME"
  echo "  Password: ${PARSED_DB_PASSWORD:+********}"
  echo
  
  safe_read "Create environment with these settings? (y/n): " confirm
  [[ "$confirm" == "y" ]] || error "Environment creation cancelled"
  
  create_env_file "$env_name" "$PARSED_DB_HOST" "$PARSED_DB_PORT" \
    "$PARSED_DB_DATABASE" "$PARSED_DB_USERNAME" "$PARSED_DB_PASSWORD"
}

# Create the .env file
create_env_file() {
  local env_name="$1"
  local db_host="$2"
  local db_port="$3"
  local db_database="$4"
  local db_username="$5"
  local db_password="$6"
  
  local env_file="$ENV_DIR/${env_name}.env"
  
  # Check if environment already exists
  if [[ -f "$env_file" ]]; then
    safe_read "Environment '$env_name' already exists. Overwrite? (y/n): " overwrite
    [[ "$overwrite" == "y" ]] || error "Environment creation cancelled"
  fi
  
  # Create environments directory if it doesn't exist
  mkdir -p "$ENV_DIR"
  
  # Write environment file
  cat > "$env_file" <<EOF
# Environment: $env_name
# Created: $(date '+%Y-%m-%d %H:%M:%S')

DB_DATABASE=$db_database
DB_HOST=$db_host
DB_USERNAME=$db_username
DB_PASSWORD=$db_password
DB_PORT=$db_port
EOF
  
  chmod 600 "$env_file"  # Secure permissions
  log "Environment '$env_name' created successfully at: $env_file"
  log "Backup directory will be: $PROJECT_ROOT/backups/$env_name/"
}

# Remove an environment
remove_environment() {
  local env_name="$1"
  
  validate_environment "$env_name"
  
  echo "WARNING: This will delete the environment configuration for '$env_name'"
  echo "Backups in backups/$env_name/ will NOT be deleted."
  echo
  safe_read "Type the environment name to confirm deletion: " confirm
  
  [[ "$confirm" == "$env_name" ]] || error "Confirmation failed. Environment not deleted."
  
  local env_file="$ENV_DIR/${env_name}.env"
  rm -f "$env_file"
  log "Environment '$env_name' deleted successfully"
}

# Main function for standalone usage
main() {
  case "${1:-}" in
    list)
      list_environments
      ;;
    create)
      [[ -n "${2:-}" ]] || error "Usage: $0 create <env_name> [postgres_url]"
      local env_name="$2"
      if [[ -n "${3:-}" ]]; then
        create_environment_from_url "$env_name" "$3"
      else
        create_environment_interactive "$env_name"
      fi
      ;;
    remove)
      [[ -n "${2:-}" ]] || error "Usage: $0 remove <env_name>"
      remove_environment "$2"
      ;;
    validate)
      [[ -n "${2:-}" ]] || error "Usage: $0 validate <env_name>"
      validate_environment "$2"
      echo "Environment '$2' is valid"
      ;;
    test)
      [[ -n "${2:-}" ]] || error "Usage: $0 test <env_name>"
      test_environment "$2"
      ;;
    *)
      echo "Usage: $0 {list|create|remove|validate|test} [args...]"
      exit 1
      ;;
  esac
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
