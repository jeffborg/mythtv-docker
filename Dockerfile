ARG UBUNTU_BASE=focal
FROM ubuntu:${UBUNTU_BASE}

# Build arguments
ARG MYTH_VERSION=31
ARG MYTH_PKG_VERSION=2:31.0+fixes.202108081239.5da2523154~ubuntu20.04.1

# Set correct environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_AU.UTF-8
ENV LANGUAGE=en_AU:en
ENV LC_ALL=en_AU.UTF-8
ENV TZ="Australia/Sydney"

# These can be overriden at runtime.
ENV USER_ID=99
ENV GROUP_ID=100
ENV DATABASE_HOST=mysql
ENV DATABASE_PORT=3306
ENV DATABASE_ROOT_FILE=
ENV DATABASE_NAME=mythconverg
ENV DATABASE_USER=mythtv
ENV DATABASE_PWD=mythtv
ENV DATABASE_BACKUP=
ENV SSH_PORT=22
ENV MYTHWEB_PORT=80

# Expose ports (SSH, mythweb, UPNP, mythtvx2)
EXPOSE $SSH_PORT $MYTHWEB_PORT 5000 6543 6544

# set volumes
VOLUME /var/lib/mythtv

# Add files
COPY files /root/

# add repositories
RUN apt-get update -qq && \
	apt-get install -y locales tzdata && \
# chfn workaround - Known issue within Dockers
	ln -s -f /bin/true /usr/bin/chfn && \
# set the locale
	locale-gen ${LANG} && \
# prepare apt 
	apt-get install -y software-properties-common --no-install-recommends && \
	apt-add-repository ppa:mythbuntu/$MYTH_VERSION -y && \
	apt-get update -qq && \
# packages to install
	apt-get install -y --no-install-recommends \
# mythtv backend and utilities (mythweb=${MYTH_PKG_VERSION})
	mythtv-common=${MYTH_PKG_VERSION} mythtv-backend=${MYTH_PKG_VERSION} libmyth-python xmltv mariadb-client \
# ssh and x11 to enable setup
	openssh-server x11-utils xauth xterm sudo && \
# clean up
	apt-get clean && \
	rm -rf /tmp/* /var/tmp/* \
	/usr/share/man /usr/share/groff /usr/share/info \
	/usr/share/lintian /usr/share/linda /var/cache/man && \
	(( find /usr/share/doc -depth -type f ! -name copyright|xargs rm || true )) && \
	(( find /usr/share/doc -empty|xargs rmdir || true ))
	
# create/place required files/folders
RUN	mkdir -p /home/mythtv/.mythtv /var/lib/mythtv /var/log/mythtv && \
# configure user mythtv (set password, login shell, home dir add to required groups)
	echo "mythtv:mythtv" | chpasswd && \ 
	usermod -s /bin/bash -d /home/mythtv -a -G users,mythtv mythtv && \
# setup epg file download script
	mv /root/tv_grab_au_file /usr/bin/ && \
	chmod a+rx /usr/bin/tv_grab_au_file &&\
# enable apache modules
	# a2enmod headers && \
	# a2enmod auth_digest &&\
# hack to stop systemd error msgs from popping up when running mythtv-setup
	mv -f /root/mythtv-setup.sh /usr/share/mythtv/ && \
	chmod a+rx /usr/share/mythtv/mythtv-setup.sh &&\
# set dockerentry script to executable
	chmod +rx /root/dockerentry.sh

CMD ["/root/dockerentry.sh"]