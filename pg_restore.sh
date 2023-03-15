#!/bin/bash

# Load environment variables from .env file
set -o allexport
source dev.env
set +o allexport
export PGPASSWORD="$DB_PASSWORD"
# Terminate all active connections to the database
echo "Terminating active connections to ${DB_DATABASE}..."
psql -h ${DB_HOST} -U ${DB_USERNAME} -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_DATABASE}';"

# Drop the database
echo "Dropping database ${DB_DATABASE}..."
psql -h ${DB_HOST} -U ${DB_USERNAME} -c "DROP DATABASE IF EXISTS ${DB_DATABASE};"

# Recreate the database
echo "Creating database ${DB_DATABASE}..."
psql -h ${DB_HOST} -U ${DB_USERNAME} -c "CREATE DATABASE ${DB_DATABASE};"

# Restore the database from backup
echo "Restoring database ${DB_DATABASE} from backup file ${BACKUP_FILE}..."
pg_restore -h ${DB_HOST} -U ${DB_USERNAME} -d ${DB_DATABASE} --clean --verbose -F c ${BACKUP_FILE}

# echo "Restoring database ${DB_DATABASE} from backup file ${BACKUP_FILE}..."
# pg_restore -h ${DB_HOST} -U ${DB_USERNAME} -d ${DB_DATABASE} --clean --verbose -F c --use-list=restore_order.txt ${BACKUP_FILE}

echo "Database ${DB_DATABASE} restored successfully!"
unset PGPASSWORD
