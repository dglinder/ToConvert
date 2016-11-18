#!/bin/bash
#############################################
# Purpose: Prepares a RHEL instance specifically for the West Cloud.
# Author: DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         This system HAS NOT been configured for the West Cloud."
   exit 1
fi

# Include common_functions.h
SCRIPTDIR1=/maint/scripts

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 5
fi

DIRNAME=$(dirname $0)
echo Running all scripts from: ${DIRNAME}

############### Install West Cloud apps ########################
# Install the Hyperic Agent
echo Installing the Hyperic agent
${DIRNAME}/setup_hyperic.sh

############### FIX FILE and DIR PERMS ########################
# Make the directory structure necessary for West CloudOne data files
# and mount points.
mkdir -p /data
chmod 755 /data
chown root:root /data
mkdir -p /data/westcorp
chmod 775 /data/westcorp
chown root:eitvcacp /data/westcorp

################ Clean up vCM agent files      ###############
rm -rf /opt/CMAgent.pre-*

################ Clean up Hyperic agent files      ###############
service hyperic-agent stop
# Clean out conflicting data files.
rm -rf /opt/hyperic/hyperic-hqee-agent-*/data/*
# Delete any backups of previous configuration files.
rm -rf /opt/hyperic.pre-*

################ Clean up VMWare tools files      ###############
# Per this bug request, need to handle Upstart enabled systems (RHEL 6) differently.
# https://bugzilla.mozilla.org/show_bug.cgi?id=703104
# old: /etc/init.d/vmware-tools {start|stop|status|restart}
# new: /etc/vmware-tools/services.sh {start|stop|status|restart}
# if [[ -e /etc/init.d/vmware-tools ]] ; then RESTART="service vmware-tools restart" ; else RESTART="/sbin/restart vmware-tools" ; fi
service vmware-tools stop

# Make sure the vmware-tools service is setup to auto-start
chkconfig --add vmware-tools
chkconfig vmware-tools on

# Clean out conflicting data files.
rm -f /var/run/vmtoolsd.pid
rm -rf /var/log/vmware-imc

################ Call out to prep the system like other VM ###############
${DIRNAME}/rhelcloneprep.sh

PAUSETIME=10
echo "System will power down in ${PAUSETIME} seconds: (Ctrl+C to abort)"
f_SpinningCountdown ${PAUSETIME}
poweroff

###############################################################

