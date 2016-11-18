#!/bin/bash

############################################
# Author: SDW
# Purpose: Configures a RHEL for SNMP
# Author: AJM / DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
# To export the latest version of this file:
#   svn export https://eitsvn.west.com/svn/EIT-post_scripts/trunk/setup_snmp.sh
#############################################


# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

# Set the path to wherever the script lives, ignore where it was launched from
WORKING_DIR=`f_PathOfScript`
cd $WORKING_DIR

#### SET VARIABLES ###
RPM=/bin/rpm
LSOF=/usr/sbin/lsof
#RC=/etc/init.d/snmpd
INFO=/etc/motd.info
if [[ -f /usr/lib/systemd/system/snmpd.service ]] 
then
	RC='/usr/lib/systemd/system/snmpd.service'
	RCSTATUS='systemctl status snmpd.service'
	RCSTOP='systemctl stop snmpd.service'
	RCSTART='systemctl start snmpd.service'
	RCENABLE='systemctl enable snmpd.service'
	REDISABLE='systemctl disable snmpd.service'
	DSTATUS=`$RCSTATUS | grep Active: | cut -d'(' -f2 | cut -d')' -f1`
elif [[ -f /etc/init.d/snmpd ]]
then
	RC='/etc/init.d/snmpd'
	RCSTATUS='service snmpd status'
	RCSTOP='service snmpd stop'
	RCSTART='service snmpd start'
	RCENABLE='chkconfig snmpd on'
	RCDISABLE='chkconfig snmpd off'
	DSTATUS=`$RCSTATUS | awk '{print $NF}'`
else
	echo Unrecognized OS configuration.. exiting..
	exit 99
fi

SNMP_CONF=/etc/snmp/snmpd.conf
SNMP_PORT=161
SNMP_RPMS='net-snmp net-snmp-libs'
SNMP_CONTACT=EITServerOperations@west.com

if [[ -s $INFO ]]; then
   SNMP_LOCATION=`grep -i ^Location $INFO | awk -F':' '{print $2}'`
else
   SNMP_LOCATION=UNSPECIFIED
fi

#### PRE-CONFIGURATION CHECKS ####

PRECHECK=SUCCESS
echo "Performing pre-configuration checks..."

# Verify the script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "   Error: this script must be run as root, please use \`sudo $0\`"
   PRECHECK=FAILURE
fi

# Verify that SNMP is installed on the machine
if [[ $PRECHECK != FAILURE ]]; then
   SNMP_RPMS='net-snmp net-snmp-libs'
   for R in $SNMP_RPMS; do
      if [[ -z `$RPM -qa $R` ]]; then
         echo "   Error: $R does not appear to be installed."
         PRECHECK=FAILURE
      fi
   done
fi

# Verify that the rcscript exists
if [[ $PRECHECK != FAILURE ]]; then
   if [[ ! -s $RC ]]; then
      echo "   Error: $RC not present - please re-install SNMP rpms."
      PRECHECK=FAILURE
   fi
fi

# Ensure that the SNMP daemon is down
if [[ $PRECHECK != FAILURE ]]; then
   if [[ $DSTATUS != stopped ]]; then
      # If the SNMP daemon is already running, stop it.
      echo "Stopping the SNMP daemon."
      $RCSTOP
      if [[ $? -ne 0 ]]; then
         echo "   Error: unable to stop the SNMP daemon, please address this and try again."
         PRECHECK=FAILURE
      fi
   fi
fi

# Verify nothing else is using the port
if [[ $PRECHECK != FAILURE ]]; then
   if [[ -n `$LSOF -ni :$SNMP_PORT` ]]; then
      echo "   Error: the following process(s) are bound to port $SNMP_PORT:"
      $LSOF -ni :$SNMP_PORT | awk '{print $1,$2,$3}' | sed 's/^/      /g'
      echo ""
      echo "   Please shut down and/or move these processes to different ports"
      echo "   and try again."
      PRECHECK=FAILURE
   fi
fi

# If PRECHECK is not set to FAILURE at this point, we're good to move forward.
if [[ $PRECHECK != FAILURE ]]; then
   echo "Pre-checks successful."
else
   echo "One or more pre-checks failed, please address the errors above and try again."
   exit
fi



#### BACKUP the existing SNMP

if [[ -s $SNMP_CONF ]]; then 
   echo "   Moving previous config to ${SNMP_CONF}.${TS}"
   mv $SNMP_CONF ${SNMP_CONF}.${TS}
fi


#### Write/Over-write config file ####

echo "Writing new config..."

cat << EOF > $SNMP_CONF

###########################################################################
#
# snmpd.conf
#
###########################################################################
# SECTION: Access Control Setup
#
# This section defines who is allowed to talk to your running
# snmp agent.

# rocommunity: a SNMPv1/SNMPv2c read-only access community name
# arguments: community [default|hostname|network/bits] [oid]

rocommunity helmet 127.0.0.0/8
rocommunity helmet 10.27.117.0/24
rocommunity helmet 75.78.24.0/23
rocommunity helmet 10.50.217.0/24

# rwcommunity: a SNMPv1/SNMPv2c read-write access community name
# arguments: community [default|hostname|network/bits] [oid]

###########################################################################
# SECTION: Monitor Various Aspects of the Running Host
#
# The following check up on various aspects of a host.

# disk: Check for disk space usage of a partition.
# The agent can check the amount of available disk space, and make
# sure it is above a set limit.
#
# disk PATH [MIN=100000]
#
# PATH: mount path to the disk in question.
# MIN: Disks with space below this value will have the Mib's errorFlag set.
# Can be a raw byte value or a percentage followed by the %
# symbol. Default value = 100000.
#
# The results are reported in the dskTable section of the UCD-SNMP-MIB tree



###########################################################################
# SECTION: System Information Setup
#
# This section defines some of the information reported in
# the "system" mib group in the mibII tree.

# syslocation: The [typically physical] location of the system.
# Note that setting this value here means that when trying to
# perform an snmp SET operation to the sysLocation.0 variable will make
# the agent return the "notWritable" error code. IE, including
# this token in the snmpd.conf file will disable write access to
# the variable.
# arguments: location_string

syslocation "$SNMP_LOCATION"

# syscontact: The contact information for the administrator
# Note that setting this value here means that when trying to
# perform an snmp SET operation to the sysContact.0 variable will make
# the agent return the "notWritable" error code. IE, including
# this token in the snmpd.conf file will disable write access to
# the variable.
# arguments: contact_string

syscontact "$SNMP_CONTACT"


###########################################################################
# SECTION: Trap Destinations
#
# Here we define who the agent will send traps to.

# trap2sink: A SNMPv2c trap receiver
# arguments: host [community] [portnum]

# informsink: A SNMPv2c inform (acknowledged trap) receiver
# arguments: host [community] [portnum]


# trapcommunity: Default trap sink community to use
# arguments: community-string
trapcommunity helmet


# authtrapenable: Should we send traps when authentication failures occur
# arguments: 1 | 2 (1 = yes, 2 = no)

authtrapenable 2


# What do we listen to?
agentaddress $SNMP_PORT,tcp:$SNMP_PORT

EOF

#### Start the SNMP Daemon

echo "Starting the SNMP Daemon..."
$RCSTART
$RCENABLE

exit

