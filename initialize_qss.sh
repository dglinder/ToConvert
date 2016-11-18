#!/bin/bash
##############################
# configures the Query Servicedesk Summary executable
# 20140226 - SDW


# Include common_functions.h
SCRIPTDIR=/maint/scripts
RPMDIR=${SCRIPTDIR}/rpms/freetds
TARBALL=${SCRIPTDIR}/tars/qss.tar.gz


## Dependency checks

# Run as root
if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         This system HAS NOT been configured for LDAP."
   exit 4
fi

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

if [[ -z `/bin/rpm -qa unixODBC` ]]; then
   echo "Critical dependency failure: unixODBC is not installed."
   exit 5
fi



####################MAIN EXECUTION START########################

DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`

if [[ $DISTRO != RHEL ]]; then
   echo "Unable to configure QSS - \"$DISTRO\" is an unsupported distro."
   exit 2
fi

# Different RHEL versions have different library dependencies
if [[ $RELEASE == 6 ]]; then
   TDSRPM=freetds-0.91-2.el6.x86_64.rpm
   QSSBIN=qss.rhel6
elif [[ $RELEASE == 5 ]]; then
   TDSRPM=freetds-0.91-2.el5.i386.rpm
   QSSBIN=qss.rhel5
else 
   echo "Unable to configure QSS - \"$DISTRO $RELEASE\" is not supported."
   exit 3
fi

# Install Free TDS
if [[ -z `/bin/rpm -qa freetds` ]]; then
   /bin/rpm -Uvh ${RPMDIR}/${TDSRPM}
   RETVAL=$?

   if [[ $RETVAL != 0 ]]; then
     echo "Unable to configure QSS - FreeTDS driver installation failed."
     exit $RETVAL
   fi
fi

## Configure ODBC
# extract the config
/bin/tar -C /tmp -xf $TARBALL tds.odbc.template
RETVAL=$?
if [[ $RETVAL != 0 ]]; then
  echo "Unable to configure QSS - ODBC template could not be extracted."
  exit $RETVAL
fi

# install the config
if [[ -z `/usr/bin/odbcinst -q -d | grep -i FreeTDS` ]]; then
   /usr/bin/odbcinst -i -d -f /tmp/tds.odbc.template
   RETVAL=$?
   /bin/rm /tmp/tds.odbc.template
   if [[ $RETVAL != 0 ]]; then
     echo "Unable to configure QSS - ODBC template could not be installed."
     exit $RETVAL
   fi
fi

# Install the binary
/bin/tar -O -xf $TARBALL $QSSBIN > /opt/qss
/bin/tar -C /opt -xf $TARBALL qss.conf
chmod 700 /opt/qss.conf
chmod +x /opt/qss


exit 0

