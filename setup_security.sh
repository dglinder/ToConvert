#!/bin/bash

#############################################
# Purpose: Apply security settings to systems
# Author: DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   # Attempt to download common functions from linux157

   echo "...common_functions.h not found, attempting to download it."

   IMGSRV=linux157
   STATICIP=172.30.113.167

   # First, _try_ to use DNS
   IMGSRVIP=`getent hosts $IMGSRV | awk '{print $1}'`

   if [[ -z $IMGSRVIP ]]; then
      IMGSRVIP=$STATICIP
   fi

   wget -q http://${IMGSRVIP}/post_scripts/common_functions.h -O /maint/scripts/common_functions.h

   if [[ -s /maint/scripts/common_functions.h ]]; then
      source /maint/scripts/common_functions.h
   else
      echo "Critical dependency failure: unable to locate common_functions.h"
      exit
   fi
fi

##############################
# Added per discussions with InfoSec regarding Nexpose scan.
# - 2015-05-08 - DGLinder
SYSCTL="/etc/sysctl.conf"

echo "Fixing: net.ipv4.conf.all.accept_redirects=0"
f_replace_or_add "net.ipv4.conf.all.accept_redirects.*=.*" \
		"net.ipv4.conf.all.accept_redirects = 0" \
		${SYSCTL}

echo "Fixing: net.ipv4.conf.default.accept_redirects=0"
f_replace_or_add "net.ipv4.conf.default.accept_redirects.*=.*" \
		"net.ipv4.conf.default.accept_redirects = 0" \
		${SYSCTL}

echo "Fixing: net.ipv4.conf.all.secure_redirects=0"
f_replace_or_add "net.ipv4.conf.all.secure_redirects.*=.*" \
		"net.ipv4.conf.all.secure_redirects = 0" \
		${SYSCTL}

echo "Fixing: net.ipv4.conf.default.secure_redirects=0"
f_replace_or_add "net.ipv4.conf.default.secure_redirects.*=.*" \
		"net.ipv4.conf.default.secure_redirects = 0" \
		${SYSCTL}

# Disable ICMP timestamp responses on Linux
#iptables -I input -p icmp --icmp-type timestamp-request -j DROP
#iptables -I output -p icmp --icmp-type timestamp-reply -j DROP
#service iptables save
# -> This is handled in the setup_iptables.script

