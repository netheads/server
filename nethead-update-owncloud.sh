#!/bin/sh

OWNCLOUD_PATH=$1
OWNCLOUD_USER=$2
OWNCLOUD_GROUP=$3
OWNCLOUD_VERSION=$4

wget http://download.owncloud.org/community/owncloud-$OWNCLOUD_VERSION.tar.bz2

if [ -f owncloud-$OWNCLOUD_VERSION.tar.bz2 ];
then
	tar xvjf owncloud-$OWNCLOUD_VERSION.tar.bz2
	rm -R owncloud/config
	rm -R owncloud/data

	rsync -a owncloud/ $OWNCLOUD_PATH --progress
	rm -R owncloud
	rm owncloud-$OWNCLOUD_VERSION.tar.bz2

	chown -R $OWNCLOUD_USER:$OWNCLOUD_GROUP $OWNCLOUD_PATH
	chmod -R 750 $OWNCLOUD_PATH
	chown root:$OWNCLOUD_GROUP $OWNCLOUD_PATH

	echo "You have to visit the Owncloud website instance to start the update"
	echo "nethead-update-owncloud-fix-permissions.sh has to be executed afterwards"
else
   echo "File owncloud-$OWNCLOUD_VERSION.tar.bz2 dos not exists"
fi
