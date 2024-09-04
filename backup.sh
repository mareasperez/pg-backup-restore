#!/bin/bash

###########################
####### LOAD CONFIG #######
###########################
function load_config() {
    if [ -z "$CONFIG_FILE_PATH" ]; then
        SCRIPTPATH=$(cd "${0%/*}" && pwd -P)
        CONFIG_FILE_PATH="${SCRIPTPATH}/${config}"
    fi

    if [ ! -r "${CONFIG_FILE_PATH}" ]; then
        echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
        exit 1
    fi
    source "${CONFIG_FILE_PATH}"
}

function load_prod_config() {
    echo "Backup prod"
    config="prod.env"
    folder_name="prod"
}

function load_dev_config() {
    echo "Backup dev"
    config="dev.env"
    folder_name="dev"
}

function create_backup_folder() {
    backup_folder="${SCRIPTPATH}/backups/${folder_name}/${now}"
    if [ ! -d "$backup_folder" ]; then
        mkdir -p "$backup_folder"
        echo "Created backup folder: $backup_folder"
    fi
}

function calculate_file_size() {
    stat --format="%s" "$1"
}

function calculate_md5() {
    md5sum "$1" | awk '{ print $1 }'
}

function calculate_crc32() {
    if command -v crc32 > /dev/null; then
        crc32 "$1"
    else
        echo "CRC32 not available, skipping CRC32 checksum."
    fi
}

function show_elapsed_time() {
    SECONDS=0
    while kill -0 $1 2> /dev/null; do
        elapsed=$SECONDS
        echo -ne "Time elapsed: $(($elapsed / 60)) minutes and $(($elapsed % 60)) seconds...\r"
        sleep 1
    done
    echo ""
}

function backup_db() {
    export PGPASSWORD=$DB_PASSWORD
    now=$(date +"%Y-%m-%d-%H-%M")
    echo "Starting backup script: $(date)"
    echo "Connecting to database: $DB_DATABASE"

    create_backup_folder

    # Perform the database backup in the background
    backup_file="${backup_folder}/${folder_name}.dump"
    pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc --create -f "$backup_file" &

    # Capture the process ID of the pg_dump command
    pid=$!

    # Show real-time elapsed time while pg_dump is running
    show_elapsed_time $pid

    # Wait for pg_dump to finish
    wait $pid
    if [ $? -ne 0 ]; then
        echo "pg_dump failed."
        exit 1
    fi

    # Copy the dump to transfer.dump
    cp "$backup_file" "${SCRIPTPATH}/transfer.dump"

    # Calculate file size and checksums
    file_size=$(calculate_file_size "$backup_file")
    md5_checksum=$(calculate_md5 "$backup_file")
    crc32_checksum=$(calculate_crc32 "$backup_file")

    # Create a metadata file with backup details
    metadata_file="${backup_folder}/${folder_name}.meta"
    echo "Backup date: $(date)" > "$metadata_file"
    echo "Database: $DB_DATABASE" >> "$metadata_file"
    echo "Host: $DB_HOST" >> "$metadata_file"
    echo "Backup file: $backup_file" >> "$metadata_file"
    echo "File size: $file_size bytes" >> "$metadata_file"
    echo "MD5 checksum: $md5_checksum" >> "$metadata_file"
    echo "CRC32 checksum: $crc32_checksum" >> "$metadata_file"

    echo "Metadata file created: $metadata_file"
    echo "Backup done: $(date)"
}

# Check if the backup is dev or prod
config=""
folder_name=""
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

if [ "$1" == "dev" ]; then
    load_dev_config
elif [ "$1" == "prod" ]; then
    load_prod_config
else
    echo "Please specify 'dev' or 'prod'"
    exit 1
fi

SECONDS=0
load_config
backup_db
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
