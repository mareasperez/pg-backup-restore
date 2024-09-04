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
    echo "Loading dev environment"
    config="dev.env"
    folder_name="prod"
}

function list_backups() {
    echo "Available backups:"
    # List all folders in the production backup directory
    available_backups=""
    counter=1

    for folder in ${SCRIPTPATH}/backups/${folder_name}/*; do
        if [ -d "$folder" ]; then
            dump_file="$folder/${folder_name}.dump"
            meta_file="$folder/${folder_name}.meta"

            # Only list folders that contain a .dump file
            if [ -f "$dump_file" ]; then
                if [ -f "$meta_file" ]; then
                    available_backups+="$counter $(basename "$folder")\n"
                else
                    available_backups+="$counter $(basename "$folder")*\n"
                fi
                counter=$((counter + 1))
            fi
        fi
    done

    if [ -z "$available_backups" ]; then
        echo "No valid backups found."
        exit 1
    fi

    # Display the list of available backups with a numeric index (folder names only)
    echo -e "$available_backups"

    # Ask the user to select a backup by number
    while true; do
        echo "Enter the number of the backup you want to restore:"
        read -r selected_number

        # Check if the input is a valid number and corresponds to a valid backup
        if [[ "$selected_number" =~ ^[0-9]+$ ]]; then
            backup_folder_name=$(echo -e "$available_backups" | awk -v num="$selected_number" '$1 == num {print $2}')
            backup_folder_name=$(echo "$backup_folder_name" | sed 's/\*$//')  # Remove asterisk if present
            backup_folder="${SCRIPTPATH}/backups/${folder_name}/$backup_folder_name"
            if [ -n "$backup_folder_name" ]; then
                break  # Exit the loop once a valid selection is made
            fi
        fi
        echo "Invalid selection. Please enter a valid number."
    done

    # Set the backup file and metadata file based on the selected backup
    backup_file="$backup_folder/${folder_name}.dump"
    metadata_file="$backup_folder/${folder_name}.meta"

    if [ ! -f "$backup_file" ]; then
        echo "Backup file missing in the selected folder: $backup_folder"
        exit 1
    fi

    # Show the metadata of the selected backup (if it exists)
    echo "Selected backup: $backup_folder_name"
    if [ -f "$metadata_file" ]; then
        echo "Backup metadata:"
        cat "$metadata_file"
    else
        echo "Missing metadata"
    fi

    # Confirm the restore of the selected backup
    echo "Do you want to restore this backup? (y/n)"
    read -r confirm_restore
    if [ "$confirm_restore" != "y" ]; then
        echo "Restore canceled."
        exit 0
    fi
}

function load_last_backup() {
    echo "Looking for the latest backup in the production folder..."

    # Find the latest backup folder based on timestamp in the folder name
    latest_backup_folder=$(ls -td ${SCRIPTPATH}/backups/${folder_name}/* | head -1)

    if [ -z "$latest_backup_folder" ];then
        echo "No backups found in ${SCRIPTPATH}/backups/${folder_name}/"
        exit 1
    fi

    backup_file="$latest_backup_folder/${folder_name}.dump"
    metadata_file="$latest_backup_folder/${folder_name}.meta"

    if [ ! -f "$backup_file" ]; then
        echo "Backup file missing in the latest backup folder: $latest_backup_folder"
        exit 1
    fi

    # Show metadata information
    echo "Backup found: $(basename "$latest_backup_folder")"
    if [ -f "$metadata_file" ]; then
        echo "Backup metadata:"
        cat "$metadata_file"
    else
        echo "Missing metadata"
    fi

    # Confirm restore
    echo "Do you want to restore the latest backup? (y/n)"
    read -r confirm_restore
    if [ "$confirm_restore" != "y" ]; then
        echo "You chose not to restore the latest backup."
        list_backups  # If user rejects, list all available backups for selection
    fi
}

function restore_db() {
    export PGPASSWORD=$DB_PASSWORD
    now=$(date)
    echo "Starting restore at: $now"
    echo "Connecting to database: $DB_DATABASE"

    if [ ! -f "$backup_file" ]; then
        echo "Restore file not found: $backup_file"
        exit 1
    fi

    # Perform the restore
    pg_restore -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" --clean --verbose -F c "$backup_file"

    if [ $? -eq 0 ]; then
        echo "Restore completed successfully: $(date)"
    else
        echo "Restore failed."
        exit 1
    fi
}

# Start script execution
SECONDS=0
config=""
folder_name=""
SCRIPTPATH=$(cd "${0%/*}" && pwd -P)

# Load the production environment configuration
load_prod_config
load_config

# Load the last production backup and show metadata
load_last_backup

# Start the restore process
restore_db

# Display elapsed time
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
