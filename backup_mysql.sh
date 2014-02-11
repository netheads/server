#!/bin/bash

echo
echo ---
echo mysql backup

# directory to save backups in, must be rwx by mysql user
BASE_DIR="/var/backup/mysql"
YMD=$(date "+%Y-%m-%d")
DIR="$BASE_DIR/$YMD"
ROOTUSER=root
ROOTPASSWORD=PASSWORD

mkdir $DIR
cd $DIR

# backup grants additionally for easier restoring
echo backup grants
mysql --user=$ROOTUSER --password=$ROOTPASSWORD --batch --skip-column-names --execute="SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS query FROM mysql.user" | \
	mysql --user=$ROOTUSER --password=$ROOTPASSWORD | \
	sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' | \
	gzip -9 > $DIR/grants.gz

# get list of databases in system, exclude information_schema
DBS=$(mysql --user=$ROOTUSER --password=$ROOTPASSWORD -Bse 'show databases' | egrep -v 'information_schema' | awk '{print $1}')

# loop through each individual database and backup
for database in $DBS; do
	echo backup database $database
	mysqldump --user=$ROOTUSER --password=$ROOTPASSWORD --databases --single-transaction --compatible=ansi --flush-logs $database | gzip -9 > $DIR/$database.gz
done

# delete backup files older than 14 days
OLD=$(find $BASE_DIR -type d -mtime +14)
if [ -n "$OLD" ] ; then
	echo deleting old backup files: $OLD
	echo $OLD | xargs rm -rfv
fi

echo ---
