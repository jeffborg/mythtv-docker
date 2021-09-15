#!/bin/bash

# Internal constants
# MYTH_USER_HOME=/home/mythtv
# MYTH_APP_HOME=$MYTH_USER_HOME/.mythtv
# MYTH_VOLUME=/var/lib/mythtv

# Set timezone
echo "Set correct timezone"
echo "TZ = $TZ"
if [[ $(cat /etc/timezone) != $TZ ]] ; then
  echo "Update timezone"
  echo $TZ > /etc/timezone && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && dpkg-reconfigure -f noninteractive tzdata
else
  echo "Timezone is already correct"
fi

# update Mythtv user and group ids
# echo "Update mythtv user and group ids"
# groupmod -g $GROUP_ID users
# usermod -u $USER_ID -g $GROUP_ID mythtv

# mkdir -p $MYTH_APP_HOME
# chown -R mythtv:mythtv $MYTH_USER_HOME

# set permissions for files/folders
# chown -R mythtv:users $MYTH_VOLUME /var/log/mythtv

#persist the channel icons in the external volume
# su mythtv -c "ln -s $MYTH_VOLUME/channels/ $MYTH_APP_HOME/"

# setup mythweb
echo "Setting up mythweb configuration"
sed -i -e "s/Listen 80/Listen $MYTHWEB_PORT/" /etc/apache2/ports.conf
sed -i "s/setenv db_server.*/setenv db_server ${DATABASE_HOST}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_name.*/setenv db_name ${DATABASE_NAME}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_login.*/setenv db_login ${DATABASE_USER}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_password.*/setenv db_password ${DATABASE_PWD}/" /etc/apache2/sites-available/mythweb.conf
echo "starting mythweb"

ln -sf /proc/$$/fd/1 /var/log/apache2/access.log
ln -sf /proc/$$/fd/2 /var/log/apache2/error.log

/usr/sbin/apache2ctl -DFOREGROUND
