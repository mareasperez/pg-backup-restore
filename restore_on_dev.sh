#!/bin/bash
###########################
####### LOAD CONFIG #######
###########################
function load_config() {
        if [ -z $CONFIG_FILE_PATH ]; then
                SCRIPTPATH=$(cd ${0%/*} && pwd -P)
                CONFIG_FILE_PATH="${SCRIPTPATH}/${config}"
        fi

        if [ ! -r ${CONFIG_FILE_PATH} ]; then
                echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
                exit 1
        fi
        source "${CONFIG_FILE_PATH}"
}
function load_dev_config() {
        echo "Backup dev"
        config="dev.env"
        folder_name="dev"
}

function backup_db() {
        export PGPASSWORD=$DB_PASSWORD
        now=$(date)
        echo "Starting backup script: $now"
        echo "Connecting to database: $DB_DATABASE"
        # echo "pg_dump -U $DB_USERNAME -h $DB_HOST -p $DB_PORT $DB_DATABASE >${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.sql"
        # pg_dump -U $DB_USERNAME -h $DB_HOST -p $DB_PORT $DB_DATABASE >"${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.sql"
        pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc --create -f "${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.dump"
        echo "Backup done: $(date)"
}

function restore_db() {
        export PGPASSWORD=$DB_PASSWORD
        now=$(date)
        echo "Starting restore script: $now"
        echo "Connecting to database: $DB_DATABASE"
        echo "pg_restore -h ${DB_HOST} -U ${DB_USERNAME} -d ${DB_DATABASE} --clean --verbose -F c "${SCRIPTPATH}/transfer.dump""
        # psql -U $DB_USERNAME -h $DB_HOST -p $DB_PORT $DB_DATABASE -f"${SCRIPTPATH}/transfer.sql"
        pg_restore -h ${DB_HOST} -U ${DB_USERNAME} -d ${DB_DATABASE} --clean --verbose -F c "${SCRIPTPATH}/transfer.dump"

        echo "restore terminado"
}
function confim_backup() {
        echo "Confirma backup? (y/n)"
        read confirma
        if [ "$confirma" = "y" ]; then
                echo "Backup confirmado"
                backup_db
        else
                echo "Backup cancelado"
                echo ""
                echo ""
        fi
}
SECONDS=0
config=""
folder_name=""
SCRIPTPATH=""
load_dev_config
load_config
confim_backup
restore_db
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
