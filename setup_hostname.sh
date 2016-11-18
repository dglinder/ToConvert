#!/bin/bash 


# The hostname is set up by the "setup_network.sh" script
# but it is defaulted to wic.west.com there.  This will
# change the domain name if necessary.  Otherwise it does 
# nothing.  All it does for now is change the domain for Intercall.

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

# Reference statement of origin
SSO=/etc/sso
UPDATE_NEEDED=NO


# Set the domain name to icallinc.com

if [[ -n `grep "^ITC" $SSO | grep "YES"` ]]; then
   UPDATE_NEEDED=YES
fi


if [[ $UPDATE_NEEDED == YES ]]; then

   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0: Setting domain name to icallinc.com" | $LOG1
   fi
 
   # Get current "short" hostname
   SHN=`hostname | awk -F'.' '{print $1}'`

   # Find the current "long" hostname
   # First try the built-in function
   if [[ "`hostname -f`" != "localhost" ]] && [[ -n `hostname -f | grep '\.'` ]]; then
      LHN=`hostname -f`
   fi

   # If we still don't have it, then try to pull it out of /etc/hosts
   if [[ -z $LHN ]]; then
      for w in `grep "${SHN}\." /etc/hosts`; do 
         if [[ -n `echo $w | grep "${SHN}\."` ]]; then 
            LHN=$w 
         fi
      done
   fi
   # If we still don't have it, try to pull it out of /etc/sysconfig/network
   if [[ -z $LHN ]]; then
      for w in `grep "${SHN}\." /etc/sysconfig/network | awk -F'=' '{print $2}'`; do
         if [[ -n `echo $w | grep "${SHN}\."` ]]; then
            LHN=$w
         fi
      done
   fi

   # If we STILL don't have it, then give up and just use the SHN as the same thing
   if [[ -z $LHN ]]; then
      LHN=`hostname`
   fi


   NHN="${SHN}.icallinc.com"
   IP=`f_FindPubIP`
   if [[ $IP == FAILURE ]]; then
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0:ERROR - unable to determine IP address, no way to modify /etc/hosts correctly" | $LOG1
         exit 2
      fi
   fi

 
  # Update /etc/hosts
   if [[ -z `egrep "$SHN|$LHN|$IP" /etc/hosts` ]]; then
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0:WARNING - hostname [$LHN or $SHN] and/or IP [$IP] not defined in /etc/hosts - adding entry" | $LOG2
         /bin/cp /etc/hosts /etc/hosts.${TS}
         echo "$IP		$SHN	$NHN" >> /etc/hosts
      fi
   else
      /bin/cp /etc/hosts /etc/hosts.${TS}
      # If the IP is already defined, then re-write the line
      if [[ -n `grep "^${IP}[ \t]" /etc/hosts` ]]; then
         sed -i "/^${IP}[ \t]/s/^${IP}[ \t].*/${IP}\t${SHN}\t${NHN}/" /etc/hosts
      fi

##20150513 - Alex
#This section seems to replace 127.0.0.1   localhost.localdomain localhost
#this is not a desireable behavior.  This step also seems un-necessary.
#      # If the old FQDN is still defined in the hosts file somewhere, replace it
#      sed -i "s/${LHN}/${NHN}/g" /etc/hosts
#/20150513
      
   fi
 
   # Update /etc/sysconfig/network
   cp /etc/sysconfig/network /etc/sysconfig/network.${TS}
   if [[ -n `grep "^HOSTNAME=" /etc/sysconfig/network` ]]; then
      sed -i "s/^HOSTNAME=.*/HOSTNAME=$NHN/" /etc/sysconfig/network
   else
      echo "`$VTS`:$0:WARNING - hostname not defined in /etc/sysconfig/network - adding entry" | $LOG2
      echo "HOSTNAME=$NHN" >> /etc/sysconfig/network
   fi
 
   # Set hostname for running system
   hostname $NHN


fi

