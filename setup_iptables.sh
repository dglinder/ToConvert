#!/bin/bash

#############################################
# Purpose: Configure IPtables firewall
# Author: SDW / DGL
# Incept 2014/01/09
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
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi


# Define Variables
IPTABLES=/sbin/iptables
RPM=/bin/rpm
SERVICE=/sbin/service
EGREP=/bin/egrep

# Verify that IPTables is installed and running
if [[ -z `$RPM -qa iptables` ]]; then
   echo "$0:FAILURE: IPTables not installed."
   exit 1
fi

# If the service isn't running, attempt to start it
if [[ -n `$SERVICE iptables status | $EGREP -i "not running|stopped"` ]]; then
   $SERVICE iptables start 2>&1 | >> /dev/null
   if [[ -n `$SERVICE iptables status | $EGREP -i "not running|stopped"` ]]; then
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0:FAILURE - unable to start the iptables daemon" | $LOG1
      fi  
      exit 2
   fi
fi

ISNETUP=`f_IsNetUp`

if [[ $ISNETUP == NO ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:FAILURE - network is not reachable, unable to determine correct settings" | $LOG1
   fi
   echo "   FAILURE: network is not set up or not working."
   echo "            Please set up the network and ensure"
   echo "            it is working, then run this script again."
   exit 3
fi



# If the server is in the DMZ or fails the "At West" check, then
# use the more restrictive settings.

# Make sure IPTables doesn't interfere with our ability to determine
# location in the network
$IPTABLES -F 2>&1 | >> /dev/null


echo "Checking environment."
echo "   West Internal Network Visible?: `f_AtWest`"
echo "                             DMZ?: `f_InDMZ`"
ATWEST=`f_AtWest`
DMZ=`f_InDMZ`

# Make sure to reload the existing ruies before continuing
$SERVICE iptables restart 2>&1 | >> /dev/null

# If we're not "at West" OR we are in the DMZ, then use the more restrictive settings
# Otherwise, use the more relxed settings.
if [[ $ATWEST != TRUE ]] || [[ $DMZ != FALSE ]]; then
   # Configuring "restrictive" settings - basically only allows SSH and ping
   
   echo "Using DMZ/Pre-Prod/Vaulted Firewall settings"
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:ATWEST=$ATWEST, DMZ=$DMZ - Using DMZ/Pre-Prod/Vaulted Firewall settings" | $LOG1
   fi

   #################################
   ##### Configure INPUT chain #####
   #################################

   # Clean up stuff that might be left from previous usage of this script
   $IPTABLES -D INPUT -j REJECT --reject-with icmp-port-unreachable 2>&1 | > /dev/null
   $IPTABLES -D INPUT -j REJECT --reject-with icmp-host-prohibited 2>&1 | > /dev/null
   $IPTABLES -D INPUT -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 21 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 23 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 512 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 513 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 514 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 1022 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -p tcp --dport 1023 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D OUTPUT -p tcp --dport 1022 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D OUTPUT -p tcp --dport 1023 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D OUTPUT -p tcp --dport 514 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D OUTPUT -p tcp --dport 513 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -D OUTPUT -p tcp --dport 512 -j REJECT 2>&1 | > /dev/null

   # Accept anything from loopback
   $IPTABLES -D INPUT -i lo -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -i lo -j ACCEPT

   # Accept all related or established traffic
   $IPTABLES -D INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

   # Allow ping
   $IPTABLES -D INPUT -p icmp -m icmp --icmp-type any -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p icmp -m icmp --icmp-type any -j ACCEPT

   # Allow Intranet addresses to SSH
   $IPTABLES -D INPUT -s 10.0.0.0/8 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -s 10.0.0.0/8 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT

   # Allow DMZ addresses to SSH
   $IPTABLES -D INPUT -s 75.78.0.0/16 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -s 75.78.0.0/16 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT

   # Allow Legacy Intranet addresses to SSH
   $IPTABLES -D INPUT -s 172.16.0.0/12 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -s 172.16.0.0/12 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT

   # Allow Legacy DMZ addresses to SSH
   $IPTABLES -D INPUT -s 216.57.96.0/20 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -s 216.57.96.0/20 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT

   # Reject anything not matching above
   # 15/05/08-DGL - Really should look at using "iptables -P INPUT REJECT" instead of
   #                appending to the end of the chain - makes adding additional rules
   #                more challenging. http://wiki.centos.org/HowTos/Network/IPTables#head-724ed81dbcd2b82b5fd3f648142796f3ce60c730
   $IPTABLES -D INPUT -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -j REJECT

   ##################################
   ##### Configure OUTPUT chain #####
   ##################################

   # Allow all outgoing traffic
   # 15/05/08-DGL - Really should look at using "iptables -P OUTPUT ACCEPT" instead of
   #                appending to the end of the chain - makes adding additional rules
   #                more challenging. http://wiki.centos.org/HowTos/Network/IPTables#head-724ed81dbcd2b82b5fd3f648142796f3ce60c730
   $IPTABLES -D OUTPUT -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -j ACCEPT 

else

   # Configuring relaxed "internal" settings - allows anything except known insecure protocols.
   echo "Using Standard Internal Firewall Settings"
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:ATWEST=$ATWEST, DMZ=$DMZ - Using Standard Internal Firewall Settings" | $LOG1
   fi

   # Cleanup
   $IPTABLES -D INPUT -s 10.0.0.0/8 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -s 75.78.0.0/16 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -s 172.16.0.0/12 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -s 216.57.96.0/20 -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -D INPUT -j REJECT --reject-with icmp-port-unreachable 2>&1 | > /dev/null
   $IPTABLES -D INPUT -j REJECT --reject-with icmp-host-prohibited 2>&1 | > /dev/null
   $IPTABLES -D INPUT -j REJECT 2>&1 | > /dev/null

   #################################
   ##### Configure INPUT chain #####
   #################################

   # Accept anything from loopback
   $IPTABLES -D INPUT -i lo -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -i lo -j ACCEPT

   # Accept all related or established traffic
   $IPTABLES -D INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

   # Block known insecure or dangerous protocols
   $IPTABLES -D INPUT -p tcp --dport 21 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 21 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 23 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 23 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 512 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 512 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 513 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 513 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 514 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 514 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 1022 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 1022 -j REJECT

   $IPTABLES -D INPUT -p tcp --dport 1023 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -p tcp --dport 1023 -j REJECT


   # Accept all other traffic by default
   # 15/05/08-DGL - Really should look at using "iptables -P INPUT ACCEPT" instead of
   #                appending to the end of the chain - makes adding additional rules
   #                more challenging. http://wiki.centos.org/HowTos/Network/IPTables#head-724ed81dbcd2b82b5fd3f648142796f3ce60c730
   $IPTABLES -D INPUT -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A INPUT -j ACCEPT

   ##################################
   ##### Configure OUTPUT chain #####
   ##################################

   # Prevent outgoing insecure or known dangerous protocols
   $IPTABLES -D OUTPUT -p tcp --dport 1022 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -p tcp --dport 1022 -j REJECT

   $IPTABLES -D OUTPUT -p tcp --dport 1023 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -p tcp --dport 1023 -j REJECT

   $IPTABLES -D OUTPUT -p tcp --dport 514 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -p tcp --dport 514 -j REJECT

   $IPTABLES -D OUTPUT -p tcp --dport 513 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -p tcp --dport 513 -j REJECT

   $IPTABLES -D OUTPUT -p tcp --dport 512 -j REJECT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -p tcp --dport 512 -j REJECT

   # Allow all other outgoing traffic
   # 15/05/08-DGL - Really should look at using "iptables -P OUTPUT ACCEPT" instead of
   #                appending to the end of the chain - makes adding additional rules
   #                more challenging. http://wiki.centos.org/HowTos/Network/IPTables#head-724ed81dbcd2b82b5fd3f648142796f3ce60c730
   $IPTABLES -D OUTPUT -j ACCEPT 2>&1 | > /dev/null
   $IPTABLES -A OUTPUT -j ACCEPT

fi

# Set DSCP/QoS settings - universal


# TSM Rules
$IPTABLES -t mangle -D POSTROUTING -p tcp --dport 1500:1530 -j DSCP --set-dscp-class AF13 2>&1 | > /dev/null
$IPTABLES -t mangle -A POSTROUTING -p tcp --dport 1500:1530 -j DSCP --set-dscp-class AF13

# NBU Rules
$IPTABLES -t mangle -D POSTROUTING -p tcp --dport 13782 -j DSCP --set-dscp-class AF13 2>&1 | > /dev/null
$IPTABLES -t mangle -A POSTROUTING -p tcp --dport 13782 -j DSCP --set-dscp-class AF13

# Make changes permanent

iptables-save > /etc/sysconfig/iptables

exit

