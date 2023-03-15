#!/bin/bash

# Load database parameters from .env file
set -a
source prod.env
set +a

# Set backup file path and name
BACKUP_FILE="backup-file.dump"

# Set PGPASSWORD environment variable to the database password
export PGPASSWORD="$DB_PASSWORD"

# Create backup using pg_dump
pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc --create -f "$BACKUP_FILE"

# Unset PGPASSWORD environment variable
unset PGPASSWORD
