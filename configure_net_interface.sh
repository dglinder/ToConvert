#!/bin/bash

#############################################
# Purpose: to update the IP, Gateway, and Netmask of the server
# Author: re-written 2012/06/07 SDW
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

# NOTE - script assumes that basic config files have already been set
###############FUNCTION DEFINITIONS############################

#-----------------
# Function: f_Usage	
#-----------------
# Displays usage information
#-----------------
# Usage: f_Usage
#-----------------
# Returns: <null>
f_Usage () {

   echo "$0"
   echo ""
   echo "   Usage:"
   echo "         $0 <Interface> <NEW IPv4 ADDRESS>"
   echo "            OR"
   echo "         $0 <Interface> <NEW IPv4 ADDRESS> <NEW IPv4 GATEWAY> <NEW IPv4 NETMASK>"
   echo ""

}

# Include common_functions.h
SCRIPTDIR1=/maint/scripts

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi



####################MAIN EXECUTION START########################

#Set some default variables
NETFILE=/etc/sysconfig/network
CONFDIR=/etc/sysconfig/network-scripts

#Check for the proper number of arguments
if [[ $# -ne 4 ]] && [[ $# -ne 2 ]]; then
   echo "Invalid argument count."
   f_Usage
   exit 1
fi

#Check each argument for the correct format
SYNCHECK=PASS

###!!!!FIX THIS!!!!####

for ARG in "$2 $3 $4"; do
   if [[ `f_ValidIPv4 $ARG` != TRUE ]]; then
      SYNCHECK=FAIL
      echo "$ARG is not a valid IPv4 number."
   fi
done

# If any checks failed, abort
if [[ $SYNCHECK != PASS ]]; then
   echo "One or more provided addresses was invalid."
   f_Usage
   exit 1
fi


##################### EVALUATE ARGUMENTS ##########################

UPINT=$1
NADDR=$2
NDGW=$3
NMASK=$4

# Grab a list of network interfaces from the local system
IFLIST=`/sbin/ifconfig -a | egrep -v '^ |^$' | awk '{print $1}' | awk -F':' '{print $1}' | egrep -v 'lo|sit|usb'`

# Verify that the update interface exists on the system
if [[ -z `echo $IFLIST | grep -i $UPINT` ]]; then
   echo "The interface [$UPINT] does not exist."
   exit 2
fi

# Verify that we haven't been asked to add address info to a bond slave
if [[ -s "${CONFDIR}/ifcfg-${UPINT}" ]] && [[ -n `grep -i "^MASTER" "${CONFDIR}/ifcfg-${UPINT}"` ]]; then
   M=`grep -i "^MASTER" "${CONFDIR}/ifcfg-${UPINT}" | awk -F'=' '{print $2}'`
   echo "The interface [$UPINT] is a slave of [$M] and cannot be updated directly."
   exit 3
fi
if [[ -d "/proc/net/bonding" ]]; then
   if [[ -n `grep -i "slave" /proc/net/bonding/* | grep -i $UPINT` ]]; then
      M=$(basename `grep -l "$UPINT" /proc/net/bonding/*`)
      echo "The interface [$UPINT] is a slave of [$M] and cannot be updated directly."
      exit 3
   fi
fi


echo ""
echo "Network settings will be updated for interface: $UPINT"
echo ""

# We're ready to modify network config scripts now, so create some backups

mkdir -p ${CONFDIR}/bak.${TS}
cp -rp ${CONFDIR}/ifcfg-* ${CONFDIR}/bak.${TS}

# If we're changing the gateway address, modify the network file and arp targets
if [[ -n $NDGW ]]; then
   #echo "Gateway is being changed to: $NDGW"
   sed -i.${TS} "s/^GATEWAY=.*$/GATEWAY=$NDGW/" $NETFILE
   if [[ -z `grep "^GATEWAY" ${NETFILE}` ]]; then
      echo GATEWAY=$NDGW >> ${NETFILE}
   fi

   # Arp target settings are deprecated and will be replaced
   # however, for compatibility with older systems this has been left intact
   if [[ -n `echo $UPINT | grep bond` ]]; then
      if [[ -n `grep arp_ip_target ${CONFDIR}/ifcfg-${UPINT}` ]]; then
         sed -i "BONDING_OPTS=\"mode=1 miimon=100\"/" ${CONFDIR}/ifcfg-${UPINT}
      fi
      # Find our modprobe file
      if [[ -f /etc/modprobe.conf ]]; then
         MP_FILE=/etc/modprobe.conf
      elif [[ -d /etc/modprobe.d ]]; then
         MP_FILE=/etc/modprobe.d/bonding.conf
      fi
      # If the options in modprobe have been set for bonding, update the arp target
      # but only do it for the public interface - there may be other bonds
      # with different targets.
      if [[ -n `grep "options $UPINT" $MP_FILE | grep arp_ip_target` ]]; then
         OLDLINE=`grep "options $UPINT" $MP_FILE | grep arp_ip_target`
         NEWLINE=`echo $OLDLINE | sed "s/arp_ip_target=.*$/arp_ip_target=$NDGW/"`
         if [[ -n $NEWLINE ]]; then
            sed -i "s/$OLDLINE/$NEWLINE/" $MP_FILE
         fi
      fi
      
   fi
fi

# Update the appropriate IFCFG

# Announce the operation
#echo "Setting IP $NADDR in ${CONFDIR}/ifcfg-${UPINT}"

# If the needed settings already exist, change them, otherwise, add them

# Set Address
if [[ -n `grep ^IPADDR ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "s/^IPADDR.*=.*$/IPADDR=$NADDR/" ${CONFDIR}/ifcfg-${UPINT}
else
   echo "IPADDR=$NADDR" >> ${CONFDIR}/ifcfg-${UPINT}
fi

# Set ONBOOT
if [[ -n `grep ^ONBOOT ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "s/^ONBOOT=.*$/ONBOOT=yes/" ${CONFDIR}/ifcfg-${UPINT}
else
   echo "ONBOOT=yes" >> ${CONFDIR}/ifcfg-${UPINT}
fi

# Turn off Network Manager control
if [[ -n `grep ^NM_CONTROLLED ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "s/^NM_CONTROLLED=.*$/NM_CONTROLLED=no/" ${CONFDIR}/ifcfg-${UPINT}
else
   echo "NM_CONTROLLED=no" >> ${CONFDIR}/ifcfg-${UPINT}
fi

# Set the interface to static
if [[ -n `grep ^BOOTPROTO ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "s/^BOOTPROTO=.*$/BOOTPROTO=static/" ${CONFDIR}/ifcfg-${UPINT}
else
   echo "BOOTPROTO=static" >> ${CONFDIR}/ifcfg-${UPINT}
fi

# Configure device name
if [[ -n `grep ^DEVICE ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "s/^DEVICE=.*$/DEVICE=${UPINT}/" ${CONFDIR}/ifcfg-${UPINT}
else
   echo "DEVICE=${UPINT}" >> ${CONFDIR}/ifcfg-${UPINT}
fi

# REMOVE

# Remove any gateway definitions from the file
if [[ -n `grep ^GATEWAY ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "/^GATEWAY/d" ${CONFDIR}/ifcfg-${UPINT}
fi

# Remove any prefix data from the file - we'll be using "NETMASK" for compatibility
if [[ -n `grep ^PREFIX ${CONFDIR}/ifcfg-${UPINT}` ]]; then
   sed -i "/^PREFIX/d" ${CONFDIR}/ifcfg-${UPINT}
fi

# The following settings should be removed if they're present
sed -i "s/^DHCP_HOSTNAME=.*$//" ${CONFDIR}/ifcfg-${UPINT}
sed -i "s/^HWADDR=.*$//" ${CONFDIR}/ifcfg-${UPINT}

# Set the netmask if one was provided
if [[ -n $NMASK ]]; then
   #echo "Setting NETMASK $NMASK in ${CONFDIR}/ifcfg-${UPINT}"
   if [[ -n `grep ^NETMASK ${CONFDIR}/ifcfg-${UPINT}` ]]; then
      sed -i "s/^NETMASK=.*$/NETMASK=$NMASK/" ${CONFDIR}/ifcfg-${UPINT}
   else
      echo "NETMASK=$NMASK" >> ${CONFDIR}/ifcfg-${UPINT}
   fi
fi

exit 0

