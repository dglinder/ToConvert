#!/bin/bash

# Installs legacy WIC *stuff*

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`
UPDATE=`f_GetRelease | awk '{print $3}'`

# Create the /wic links
ln -s /opt /wic
ln -s /home /wic/home
ln -s /var/log /wic/log
ln -s /usr/local /wic/local

# Create and/or populate /usr/local/man
tar -xzf /maint/scripts/tars/man.tar.gz -C /usr/local
chmod 755 /usr/local/man
cd /usr/local/man
   
# Create /usr/local/bin and populate
tar -xzf /maint/scripts/tars/bin.tar.gz -C /usr/local
chmod -R 755 /usr/local/bin/*
chown root:root /usr/local/bin/killarg
chmod 700 /usr/local/bin/killarg

# Create /opt/sys and populate it
tar -xzf /maint/scripts/tars/sys.tar.gz -C /opt
chmod 777 /opt/sys

# Create SCO-like directory structure for expcfg and syslog
ln -s /bin/touch /usr/bin/touch
if [[ ! -d /usr/eos ]]; then mkdir /usr/eos; fi
chmod 755 /usr/eos
if [[ ! -d /usr/eos/data ]]; then mkdir -p /usr/eos/data; fi
chmod 755 /usr/eos/data

# Set up Logsrv
if [[ $DISTRO == RHEL ]] && [[ $RELEASE == 6 ]]; then

echo << EOF >> /etc/init/logsrv.conf

# Automatically start the logsrv daemon
#

description     "Logsrv upstart daemon"

# Start/Stop conditions
start on started network
stop on network stopping
stop on runlevel [S016]

respawn
respawn limit 15 5
exec /opt/local/bin/logsrv 0 15

EOF
   chmod 644 /etc/init/logsrv.conf

   /sbin/start logsrv
   if [[ -z `grep logsrv.conf /etc/inittab` ]]; then
      echo "# LOGSRV - inittab is deprecated, logsrv is controlled by /etc/init/logsrv.conf" >> /etc/inittab
   fi
elif [[ $DISTRO == RHEL ]] && ( [[ $RELEASE == 5 ]] || [[ $RELEASE == 4 ]] ); then

   # Setting up the new inittab
   /bin/cp /etc/inittab /etc/inittab.install

   if [ `grep -c "lsrv" /etc/inittab` -ge "1" ] ; then
        echo "LOGSRV.......INITTAB ERRORS -- PLEASE UPDATE INITTAB MANUALLY!!"
   else
        echo "# LOGSRV" >> /etc/inittab
        echo "lsrv:2345:respawn:/opt/local/bin/logsrv 0 15" >>/etc/inittab
        /sbin/init q
        sleep 2
   fi
else
   echo "Automation of LOGSRV is not supported on $DISTRO $RELEASE"
fi


