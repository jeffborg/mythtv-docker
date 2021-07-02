#!/bin/bash

# Internal constants
MYTH_USER_HOME=/home/mythtv
MYTH_APP_HOME=$MYTH_USER_HOME/.mythtv
MYTH_VOLUME=/var/lib/mythtv

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
echo "Update mythtv user and group ids"
groupmod -g $GROUPID users
usermod -u $USERID -g $GROUPID mythtv

mkdir -p $MYTH_APP_HOME
chown -R mythtv:mythtv $MYTH_USER_HOME

# Fix the config
if [ -f "$MYTH_VOLUME/.mythtv/config.xml" ]; then
  echo "Copying config file that was set in home"
  cp $MYTH_VOLUME/.mythtv/config.xml $MYTH_APP_HOME/config.xml
else
  echo "Setting config from environment variables"
  cat << EOF > $MYTH_APP_HOME/config.xml
<Configuration>
  <Database>
    <PingHost>1</PingHost>
    <Host>${DATABASE_HOST}</Host>
    <UserName>${DATABASE_USER}</UserName>
    <Password>${DATABASE_PWD}</Password>
    <DatabaseName>${DATABASE_NAME}</DatabaseName>
    <Port>${DATABASE_PORT}</Port>
  </Database>
  <WakeOnLAN>
    <Enabled>0</Enabled>
    <SQLReconnectWaitTime>0</SQLReconnectWaitTime>
    <SQLConnectRetry>5</SQLConnectRetry>
    <Command>echo 'WOLsqlServerCommand not set'</Command>
  </WakeOnLAN>
</Configuration>
EOF
fi

cp $MYTH_APP_HOME/config.xml /usr/share/mythtv/config.xml

for f in $MYTH_VOLUME/.mythtv/*.xmltv; do
    [ -e "$f" ] && echo "Copying XMLTV config file that was set in home" && 
    cp $MYTH_VOLUME/.mythtv/*.xmltv $MYTH_HOME/
    break
done

if [ -d "$MYTH_VOLUME/recordings" ]; then
  echo "mythtv folders appear to be set"
else
  mkdir -p $MYTH_VOLUME/banners $MYTH_VOLUME/channels $MYTH_VOLUME/coverart  $MYTH_VOLUME/db_backups  $MYTH_VOLUME/fanart  $MYTH_VOLUME/livetv  $MYTH_VOLUME/recordings  $MYTH_VOLUME/screenshots  $MYTH_VOLUME/streaming  $MYTH_VOLUME/trailers  $MYTH_VOLUME/videos
fi

# set permissions for files/folders
chown -R mythtv:users $MYTH_VOLUME /var/log/mythtv

#persist the channel icons in the external volume
su mythtv -c "ln -s $MYTH_VOLUME/channels/ $MYTH_HOME/"

#database connection and configuration
echo "Waiting for database to be online..."
while : ; do
  mysqladmin -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u${DATABASE_USER} -p${DATABASE_PWD} ping
  [[ $? -eq 0 ]] && break
  echo "Connection to $DATABASE_HOST:$DATABASE_PORT timed out. Retrying..."
  sleep 2s
done
#If DATABASE_ROOT_FILE is set AND credential file exists, check if we need to create the mythtv database
if [[ ! -z "$DATABASE_ROOT_FILE" && -f "$DATABASE_ROOT_FILE" ]]; then
	echo "Database root credentials provided. Checking if we need to create the $DATABASE_NAME database..."
  read -d '\n' db_rt_user db_rt_pswd < $DATABASE_ROOT_FILE
	output=$(mysql -s -N -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '${DATABASE_NAME}'" information_schema)
	[[ $? -ne 0 ]] && echo "Database call returned an error. Check stderr for details. Unable to continue. Exiting." && exit 1
  echo "  Query result = ${output}"
	if [[ -z "${output}" ]]; then
	  echo "$DATABASE_NAME not found. Creating an empty one with supplied user credentials."
	  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME}"
	  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "CREATE USER '${DATABASE_USER}' IDENTIFIED BY '${DATABASE_PWD}'"
	  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "GRANT ALL ON ${DATABASE_NAME}.* TO '${DATABASE_USER}' IDENTIFIED BY '${DATABASE_PWD}'"
	  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "GRANT CREATE TEMPORARY TABLES ON ${DATABASE_NAME}.* TO '${DATABASE_USER}' IDENTIFIED BY '${DATABASE_PWD}'"
	  mysql -h ${DATABASE_HOST} -P ${DATABASE_PORT} -u ${db_rt_user} -p${db_rt_pswd} -e "ALTER DATABASE ${DATABASE_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci"
	else
  	echo "Database already exists. FOR BETTER SECURITY, PLEASE REMOVE THE DATABASE ROOT CREDENTIALS FILE!"
	fi
else #DATABASE_ROOT_FILE is NOT set, let's validate that the mythtv database exists and we can access it ok 
  echo "Testing connection to mythtv database with supplied credentials."
  output=$(mysql -s -N -h $DATABASE_HOST -P $DATABASE_PORT -u $DATABASE_USER -p$DATABASE_PWD -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '$DATABASE_NAME'" information_schema)
  [[ $? -ne 0 ]] && echo "Database call returned an error. Check stderr for details. Unable to continue. Exiting." && exit 1
  echo "  Query result = ${output}"
  if [[ -z "${output}" ]]; then
    echo "$DATABASE_NAME not found. Please provide database admin credentials and restart container to create one.Unable to continue. Exiting."
    exit 1
  fi
fi

# setup mythweb
echo "Setting up mythweb configuration"
sed -i -e "s/Listen 80/Listen $MYTHWEB_PORT/" /etc/apache2/ports.conf
sed -i "s/setenv db_server.*/setenv db_server ${DATABASE_HOST}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_name.*/setenv db_name ${DATABASE_NAME}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_login.*/setenv db_login ${DATABASE_USER}/" /etc/apache2/sites-available/mythweb.conf
sed -i "s/setenv db_password.*/setenv db_password ${DATABASE_PWD}/" /etc/apache2/sites-available/mythweb.conf
echo "starting mythweb"
/usr/sbin/apache2ctl start

#Setup db backup job and start cron if requested. $DBBACKUP env var specifies the backup schedule in cron syntax
if [ ! -z "$DBBACKUP" ]; then
  echo "Database backup schedule spcified. Inserting cron job and starting cron."
  echo "$DBBACKUP    root    /usr/share/mythtv/mythconverg_backup.pl" >> /etc/crontab
  cron
fi

# setup SSH
sed -i -e "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config

#Bring up the backend

for retry in $(seq 1 10); do
  while killall -0 mythtv-setup; do sleep 5; done
  su mythtv -c /usr/bin/mythbackend || echo Unexpected exit retry=$retry
  sleep 60
done