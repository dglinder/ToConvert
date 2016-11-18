#!/bin/bash

#############################################
# Purpose: Reads current network information and 
#          creates a bonded interface from two
#          NICs
# Author: re-written 20120605 SDW
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

##################SETTINGS ###############################
# Change script behavior by modifying these settings
IF1=eth0
IF2=eth1
BOND=bond0
NETMASK=255.255.255.0

##################COMMAND LINE OVERRIDES#################
# If 3 arguments are passed to the script, it will use
# those instead of the settings listed above

if [[ $# -eq 3 ]]; then
   IF1=$1
   IF2=$2
   BOND=$3
elif [[ $# -ne 0 ]] && [[ $# -ne 3 ]]; then
   echo "Invalid arguments $@"
   f_Usage
   exit
fi

##################GENERATE VARIABLES #####################
export TS=`date +%Y%m%d%H%M%S`
CONFIG_DIR=/etc/sysconfig/network-scripts
#CONFIG_DIR=/tmp/sysconfig/network-scripts
IF1_FILE=ifcfg-${IF1}
IF2_FILE=ifcfg-${IF2}
BOND_FILE=ifcfg-${BOND}

##################FUNCTION DEFINITIONS####################

#-----------------
# Function: f_Usage
#-----------------
# Prints Usage Information
f_Usage () {

   echo "$0"
   echo "   Usage: $0"
   echo "      OR"
   echo "          $0 <slave1> <slave2> <bond>"
   echo ""
   echo "      ex: $0 eth0 eth1 bond0"
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


#########################MAIN EXECUTION START##############

#Don't attempt bonding if we're on a virtual machine

if [[ `f_DetectVM` == TRUE ]]; then
   echo "Detected virtual machine.  Bonding will be skipped."
   exit 4
fi

# echo some description
echo "Attempting to make $IF1 and $IF2 slaves of $BOND."

# Check our interfaces to make sure they exist
echo "   checking interfaces..."
for j in $IF1 $IF2; do

   RESULT=`f_CheckIF $j`

   case $RESULT in

      FAILURE ) echo "      FAILURE: The device $j does not exist, aborting."
                exit 255
               ;;
      SUCCESS ) echo "      The device $j appears to be valid."
               ;;
       NOLINK ) echo "      WARNING: The device $j does not have a link and may not work."
               ;;
             *) echo "      FAILURE: the function f_CheckIF returned the unexpected result $RESULT."
                exit 90
               ;; 
   esac

done

# Compare our interfaces to see if they both have IP addresses
# (In which case we don't want to set up bonding because it won't work
#  and it'll break the server)
echo "   ensuring there is only one IP between the slaves"
if [[ `f_IPforIF $IF1` != NONE ]] && [[ `f_IPforIF $IF2` != NONE ]]; then
   echo "      FAILURE: $IF1 has `f_IPforIF $IF1` and $IF2 has `f_IPforIF $IF2`."
   echo "               Bonding would kill one or both network connections."
   echo "               Aborting."
   exit
fi



# Find our modprobe file
if [[ -f /etc/modprobe.conf ]]; then 
   MP_FILE=/etc/modprobe.conf
elif [[ -d /etc/modprobe.d ]]; then
   MP_FILE=/etc/modprobe.d/bonding.conf
fi

# Get the IP
echo "   getting the IP for this machine..."
IP=`f_FindPubIP`

if [[ $IP == FAILURE ]]; then
   echo "      FAILURE: unable to determine the IP for this machine."
   exit
else
   echo "      the IPv4 address that will be used for this machine is $IP."
fi

# Find our default gateway for arping purposes
echo "   getting the gateway for this machine..."
GW=`f_FindDefaultGW`
if [[ $GW == FAILURE ]]; then
   echo "     FAILURE: There is no default gateway set up for this machine!"
   echo "              please set up the gateway and try again."
   exit
else
   echo "      the IPv4 gateway that will be used for this machine is $GW."
fi


#Usage: f_CreateBondMaster <IP> <DEVNAME> <NETMASK> <FILE>
#Usage: f_CreateBondSlave <DEV> <MASTER> <FILE> 

# Create the master config file

#echo "   creating master config for $BOND at ${CONFIG_DIR}/${BOND_FILE}"
echo "   creating master config for $BOND" 
if [[ `f_CreateBondMaster $IP $BOND $NETMASK ${CONFIG_DIR}/${BOND_FILE}` != FAILURE ]]; then
   echo "      success."
else
   echo "      failure, aborting operation."
   exit
fi

# Create the slaves

#echo "   creating slave config for $IF1 at ${CONFIG_DIR}/${IF1_FILE}"
echo "   creating slave config for $IF1"
if [[ `f_CreateBondSlave $IF1 $BOND ${CONFIG_DIR}/${IF1_FILE}` != FAILURE ]]; then
   echo "      success."
else
   echo "      failure, aborting operation."
   exit
fi

#echo "   creating slave config for $IF2 at ${CONFIG_DIR}/${IF2_FILE}"
echo "   creating slave config for $IF2"
if [[ `f_CreateBondSlave $IF2 $BOND ${CONFIG_DIR}/${IF2_FILE}` != FAILURE ]]; then
   echo "      success."
else
   echo "      failure, aborting operation."
   exit
fi

# Add an alias for our bond interface
#echo "  adding an alias for the bonding driver to $MP_FILE"
echo "  adding an alias for the bonding driver to modprobe"
if [[ -f $MP_FILE ]]; then
   cp ${MP_FILE} /etc/modprobe_backup.${TS}
else
   touch $MP_FILE
fi

if [[ -z `grep "alias $BOND bonding" $MP_FILE` ]]; then
   echo "alias $BOND bonding" >> $MP_FILE
fi

# Add bonding options based on release
# If we're dealing with RHEL 5 or newer these get added to the
# ifcfg bond files, otherwise they're added to modprobe

DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`

if [[ $DISTRO == RHEL ]] && [[ $RELEASE -ge 5 ]]; then
   echo "   detected $DISTRO ${RELEASE}.X,"
   echo "       adding bonding opts to ${BOND_FILE}"
   #echo "BONDING_OPTS=\"mode=1 primary=${IF1} arp_interval=1000 arp_ip_target=${GW}\"" >> ${CONFIG_DIR}/${BOND_FILE}
   echo "BONDING_OPTS=\"mode=1 miimon=100\"" >> ${CONFIG_DIR}/${BOND_FILE}
else
   echo "   detected $DISTRO ${RELEASE}.X,"
   echo "      adding bonding opts to modprobe."
   if [[ -n `grep "options $BOND" $MP_FILE` ]]; then
      grep -v "options $BOND" $MP_FILE > ${MP_FILE}.tmp
      /bin/mv ${MP_FILE}.tmp $MP_FILE
   fi
   #echo "options $BOND primary=${IF1} mode=1 arp_interval=1000 arp_ip_target=${GW}" >> $MP_FILE
   echo "options $BOND primary=${IF1} mode=1 miimon=100" >> $MP_FILE
fi


# load the bonding module, so the next time the network is restarted, it can be envoked
if [[ -z `lsmod | grep bonding` ]]; then
   modprobe bonding 2>&1 >/dev/null
fi
echo ""
echo "Bonding configuration has been completed."
echo "The network subsystem needs to be restarted to"
echo "complete the changes."
echo ""
echo "If the network restart is unsuccessful, "
echo "you can either reload the nic drivers or reboot."
exit

