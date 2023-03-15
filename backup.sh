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

function backup_db() {
        export PGPASSWORD=$DB_PASSWORD
        now=$(date)
        echo "Starting backup script: $now"
        echo "Connecting to database: $DB_DATABASE"
        # echo "pg_dump -U $DB_USERNAME -h $DB_HOST -p $DB_PORT $DB_DATABASE >${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.sql"
        # pg_dump --clean -U $DB_USERNAME -h $DB_HOST -p $DB_PORT $DB_DATABASE > "${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.sql" old method
        pg_dump -h "$DB_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc --create -f "${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.dump"
        cp "${SCRIPTPATH}/backups/${folder_name}/${folder_name}-$now.dump" "${SCRIPTPATH}/transfer.dump"
        echo "Backup done: $(date)"
}

# check if the backup is dev or prod
config=""
folder_name=""
SCRIPTPATH=""
if [ "$1" == "dev" ]; then
        load_dev_config
elif [ "$1" == "prod" ]; then
        load_prod_config
else
        echo "ingrese dev o prod"
        exit 1
fi
SECONDS=0
# do some work
load_config
backup_db
# echo "Backup terminado en "
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
