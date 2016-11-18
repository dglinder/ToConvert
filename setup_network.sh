#!/bin/bash

#############################################
# Purpose: sets up the network for a newly imaged
#          or moved server.
# Author: re-written 2012/06/06 SDW
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

##################VARIABLE DEFINITIONS#############
RETCODE=0
SCRIPTDIR1=/maint/scripts
SCRIPTDIR2=/usr/sbin

# Locate the "Configure Interface" script
#configure_net_interface.sh <Interface> <NEW IPv4 ADDRESS> <NEW IPv4 GATEWAY> <NEW IPv4 NETMASK>
if [[ -s "${SCRIPTDIR1}/configure_net_interface.sh" ]]; then
   CFGINT="${SCRIPTDIR1}/configure_net_interface.sh"
elif [[ -s "${SCRIPTDIR2}/configure_net_interface.sh" ]]; then
   CFGINT="${SCRIPTDIR2}/configure_net_interface.sh"
else
   echo "Critical dependency failure: unable to locate configure_net_interface.sh"
   exit 5
fi


# Locate the "IP Bond script" script
if [[ -s "${SCRIPTDIR1}/setup_ip_bonding.sh" ]]; then
   MKBOND="${SCRIPTDIR1}/setup_ip_bonding.sh"
elif [[ -s "${SCRIPTDIR2}/setup_ip_bonding.sh" ]]; then
   MKBOND="${SCRIPTDIR2}/setup_ip_bonding.sh.sh"
else
   echo "Critical dependency failure: unable to locate setup_ip_bonding.sh"
   exit 5
fi


# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 5
fi


#####################MAIN EXECUTION START###################

# Read current system values

echo "...Gathering information"
echo ""
PHN=`hostname`
PIP=`f_FindPubIP`
if [[ $PIP != FAILURE ]] && [[ -n $PIP ]]; then
   if [[ -n `ifconfig -a | grep $PIP | grep 'Mask:'` ]]; then
      PNM=`ifconfig -a | grep $PIP | awk -F'Mask:' '{print $NF}' | head -1`
   elif [[ -n `ifconfig -a | grep $PIP | grep 'netmask'` ]]; then
      PNM=`ifconfig -a | grep $PIP | awk '{print $4}'`
   fi
   #PGW=`echo $PIP | awk -F'.' '{print $1"."$2"."$3".1"}'`
   PGW=`f_FindDefaultGW`
fi
PUBIF=`f_FindPubIF`
if [[ $PUBIF == FAILURE ]]; then
   unset PUBIF
   export PUBIF=`f_AskPubIF`
fi

# Show current system values before asking if they should be updated
# (This is in preparation to future updates where these values will
#  already be set by the kickstart process.)

if [[ $PIP != FAILURE ]] && [[ -z `echo $PHN | egrep -i 'unnamed|setup000|localhost'` ]]; then
   echo "Existing Network Settings Found."
   echo ""
   echo "         Hostname: $PHN"
   echo "     IPv4 Address: $PIP"
   echo "          Netmask: $PNM"
   echo "          Gateway: $PGW"
   echo ""
   read -p "Do you want to change these? (y/n): " changexist
   if [[ -z `echo $changexist | grep -i "^y"` ]]; then
      # If we had existing settings, maybe we had an existing bond device, but if not...
      if [[ -z `/sbin/ifconfig -a | grep "^bond"` ]]; then
         # Offer to set up a bond interface with the existing settings
         read -p "Do you want to set up bonding with these settings? (y/n): " bondexist
         if [[ -n `echo $bondexist | grep -i "^y"` ]]; then
            if [[ $PUBIF == eth0 ]] || [[ $PUBIF == eth1 ]]; then
               $MKBOND eth0 eth1 bond0
               NEEDSRESTART=TRUE
            elif [[ $PUBIF == eth2 ]] || [[ $PUBIF == eth3 ]]; then
               $MKBOND eth2 eth3 bond0
               NEEDSRESTART=TRUE
            elif [[ $PUBIF == eth4 ]] || [[ $PUBIF == eth5 ]]; then
               $MKBOND eth4 eth5 bond0
               NEEDSRESTART=TRUE
            elif [[ $PUBIF == eth6 ]] || [[ $PUBIF == eth7 ]]; then
               $MKBOND eth6 eth7 bond0
               NEEDSRESTART=TRUE
            elif [[ -n `echo $PUBIF | egrep 'bond|virt'` ]]; then
               echo "Bonding has already been configured."
            else
               echo "Unable to determine proper NIC pair to bond, skipping."
            fi
            if [[ $NEEDSRESTART == TRUE ]]; then
               echo "Restarting the netowrk to activate the bond."
               /etc/init.d/network restart
               modprobe bonding
            fi
        
         fi
      fi
      # Since this is an early exit, but a valid one, let's touch our check file
      touch /etc/setup_net_complete
      exit
   fi
fi


# VC is a flag that says whether we received a valid choice
# It will only be set to true when all questions have been
# answered and validated

VC=FALSE   

while [[ $VC != TRUE ]]; do
   echo "Updating Network Configuration."
   echo ""

   #Temporarily suppress console messages to keep
   #our output clean
   /sbin/sysctl -w kernel.printk="3 4 1 3" 2>&1 | > /dev/null

   #Get the new hostname
   VC1=FALSE   
   # Matches a non-qualified RFC 1035 hostname
   MATCH1='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)$'
   # Matches a fully qualified RFC 1035 hostname
   MATCH2='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$'
   #Check the hostname we got
   while [[ $VC1 != TRUE ]]; do
      read -p "   Enter Host Name: " GNHN

      NHN=`echo $GNHN | tr '[:upper:]' '[:lower:]'`

      if [[ $NHN =~ $MATCH1 ]] || [[ $NHN =~ $MATCH2 ]]; then
         # Valid simple hostname
         VC1=TRUE
      else
         echo "   \"$NHN\" is not a valid RFC 1035 hostname."
         unset NHN
         read -p "   Press Enter to try again, or Ctrl+C to exit." JUNK
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      fi
   done

   #Get the new IPv4 address
   VC2=FALSE
   while [[ $VC2 != TRUE ]]; do
      read -p "   Enter IPv4 Address: " NIP

      # If the format of the input is valid...
      if [[ `f_ValidIPv4 $NIP` == TRUE ]]; then
         unset IPINUSE
         # Check to see if the address is in use
         /sbin/ifconfig $PUBIF up
         sleep 1
         /sbin/arping -q -c 2 -w 3 -D -I $PUBIF $NIP
         IPINUSE=$?

         # If the IP is already in use, ask for a different one
         if [[ $IPINUSE != 0 ]]; then
            echo "   \"$NIP\" is already in use on the network."
            unset NIP
            read -p "   Press Enter to select a different IP." JUNK
            tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
         else
            VC2=TRUE
         fi
      # If the format of the input is NOT valid...
      else
         echo "   \"$NIP\" is not a valid IPv4 address."
         unset NIP
         read -p "   Press Enter to try again." JUNK
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      fi
   done

   #Get the new netmask
   # First make a guess at what the netmask should be
   GNM=255.255.255.0
   VC4=FALSE
   while [[ $VC4 != TRUE ]]; do
      read -p "   Enter IPv4 Netmask [$GNM]: " NNM
      if [[ -z $NNM ]]; then
         NNM=$GNM
         VC4=TRUE
      elif [[ `f_ValidIPv4 $NNM` == TRUE ]]; then
         VC4=TRUE
      else
         echo "   \"$NNM\" is not a valid IPv4 Netmask."
         unset NNM
         read -p "   Press Enter to try again." JUNK
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      fi
   done


   #Get the new gateway
   # First make a guess at what the gateway should be
   GGW=`echo $NIP | awk -F'.' '{print $1"."$2"."$3".1"}'`
   VC3=FALSE
   while [[ $VC3 != TRUE ]]; do
      read -p "   Enter IPv4 Gateway [$GGW]: " NGW
      if [[ -z $NGW ]]; then
         NGW=$GGW
         VC3=TRUE
      elif [[ `f_ValidIPv4 $NGW` == TRUE ]]; then
         VC3=TRUE
      else
         echo "   \"$NGW\" is not a valid IPv4 Gateway."
         unset NGW
         read -p "   Press Enter to try again." JUNK
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      fi
   done

   # Display the results we gathered and ask for final verification
   unset CONFIRM
   #echo -e "\n\n"
   tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
   echo "The following settings are about to be applied to this system."
   echo ""
   echo "       Hostname: $NHN"
   echo "   IPv4 Address: $NIP"
   echo "   IPv4 Gateway: $NGW"
   echo "   IPv4 Netmask: $NNM"
   echo ""
   read -p "Are these settings correct? (y/n): " CONFIRM
   if [[ -n `echo $CONFIRM | grep -i "^y"` ]]; then
      VC=TRUE
   else
      unset NHN NIP NGW NNM
      read -p "New settings rejected.  Press Enter to start over." JUNK
      tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el;
   fi
done


#Changing the network settings according to user input

#/usr/sbin/chgnet.sh $NIP $NGW $NNM
#$CHGNET $NIP $NGW $NNM
$CFGINT $PUBIF $NIP $NGW $NNM
RETCODE=$?
if [[ $RETCODE != 0 ]]; then
   echo "FAILURE: the command:"
   echo "   \`$CFGINT $PUBIF $NIP $NGW $NNM\`"
   echo "   has failed.  Please investigate and try again."
   exit $RETCODE
fi

#echo ""
#echo "Network settings have been changed. The network needs to be re-started "
#echo "for the changes to take effect.  If you are connecting via SSH, you will"
#echo "need to re-connect to $NIP when the network is restarted."
#echo ""
echo "Network will restart in 5 seconds: (Ctrl+C to abort)"
f_SpinningCountdown 5
/etc/init.d/network restart
RETCODE=$?

if [[ $RETCODE != 0 ]]; then
   echo "FAILURE: Error Restarting Network"
   exit $RETCODE
fi


#Changing the hostname

# If this is a new name and new IP for a new machine, then simply add the "self" address.
if [[ -z `egrep "$NHN|$NIP" /etc/hosts` ]]; then
   echo "$NIP   $NHN $NHN.wic.west.com" >> /etc/hosts
fi

OHN=`hostname`

# Update the hostname 
f_RHELChangeHostname $OHN $NHN

if [[ `f_DetectVM` == FALSE ]]; then
   #Configure bonding for physical servers
   NEEDSRESTART=
   if [[ $PUBIF == eth0 ]] || [[ $PUBIF == eth1 ]]; then
      $MKBOND eth0 eth1 bond0
      NEEDSRESTART=TRUE
   elif [[ $PUBIF == eth2 ]] || [[ $PUBIF == eth3 ]]; then
      $MKBOND eth2 eth3 bond0
      NEEDSRESTART=TRUE
   elif [[ $PUBIF == eth4 ]] || [[ $PUBIF == eth5 ]]; then
      $MKBOND eth4 eth5 bond0
      NEEDSRESTART=TRUE
   elif [[ $PUBIF == eth6 ]] || [[ $PUBIF == eth7 ]]; then
      $MKBOND eth6 eth7 bond0
      NEEDSRESTART=TRUE
   elif [[ -n `echo $PUBIF | egrep 'bond|virt'` ]]; then
      echo "Bonding has already been configured."
   else
      echo "Unable to determine proper NIC pair to bond, skipping."
   fi
   if [[ $NEEDSRESTART == TRUE ]]; then
      echo "The network will be restarted to activate bonding"
      echo ""
      echo "Network will restart in 5 seconds: (Ctrl+C to abort)"
      f_SpinningCountdown 5
      /etc/init.d/network restart
      RETCODE=$?
   fi
fi

#Drop a stop file in /etc/ to indicate that the network was successfully set up
#This will prevent the "fix_profile" script from removing the directives from
#root's profile if something went wrong.
if [[ $RETCODE == 0 ]]; then
   touch /etc/setup_net_complete
   #echo "Network setup is complete."
else
   exit $RETCODE
fi
