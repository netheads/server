#!/bin/bash

set -u

echo
echo ---
echo redis backup

BASE_DIR="/var/backup/redis"
YMD=$(date "+%Y-%m-%d")
DIR="$BASE_DIR/$YMD"

mkdir $DIR
cd $DIR

LASTSAVE=$(docker run --rm --link redis:redis dockerfile/redis bash -c 'redis-cli -h redis lastsave')

echo "Lastsave is:"
echo $LASTSAVE

docker run --rm --link redis:redis dockerfile/redis bash -c 'redis-cli -h redis bgsave'

echo "Wait a few seconds"
sleep 5

CURRENT_LASTSAVE=$(docker run --rm --link redis:redis dockerfile/redis bash -c 'redis-cli -h redis lastsave')

while [ "$LASTSAVE" == "$CURRENT_LASTSAVE" ]
do
	echo "Current lastsave is:"
	echo $CURRENT_LASTSAVE

	echo "Sleep for a minute"
	sleep 60

	CURRENT_LASTSAVE=$(docker run --rm --link redis:redis dockerfile/redis bash -c 'redis-cli -h redis lastsave')
done

mv /srv/redis/dump.rdb $DIR

# delete backup files older than 14 days
OLD=$(find $BASE_DIR -type d -mtime +14)
if [ -n "$OLD" ] ; then
	echo deleting old backup files: $OLD
	echo $OLD | xargs rm -rfv
fi

echo ---
