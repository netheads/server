#!/bin/sh

chmod 4755 /usr/sbin/suexec2
umask 0027

chmod 750 /etc/ssl/private/
chown root:SSL /etc/ssl/private/

service apache2 restart
/root/prefetch-websites.pl

chmod 644 /srv/www/vhost/*/logs/access_log*
chown root:root /srv/www/vhost/*/logs/access_log*
chmod 644 /srv/www/vhost/*/logs/error_log*
chown root:root /srv/www/vhost/*/logs/error_log*

service apache2 status
