#!/bin/bash

echo
echo ---
echo postgresql backup

# directory to save backups in, must be rwx by postgres user
BASE_DIR="/var/backup/postgresql"
YMD=$(date "+%Y-%m-%d")
DIR="$BASE_DIR/$YMD"

mkdir $DIR
cd $DIR

# get list of databases in system, exclude template0
DBS=$(psql -At -c "SELECT datname FROM pg_database" | egrep -v 'template0' | awk '{print $1}')

# dump globals (roles and tablespaces) only
echo backup globals
pg_dumpall --globals-only | gzip -9 > "$DIR/globals.gz"

# loop through each individual database and backup
for database in $DBS; do
	echo backup database $database
	pg_dump --create --blobs $database | gzip -9 > $DIR/$database.gz
done

# delete backup files older than 14 days
OLD=$(find $BASE_DIR -type d -mtime +14)
if [ -n "$OLD" ] ; then
	echo deleting old backup files: $OLD
	echo $OLD | xargs rm -rfv
fi

echo ---
