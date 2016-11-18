#!/bin/bash

# Configure NTP
# Incept 2014/01/14
# Author: SDW

# Back up the original NTP file

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

if [[ $PRODUCT == RHEL ]] && [[ $RELEASE == 7 ]]; then
   NTP_DISABLE="/bin/systemctl disable ntpd.service"
   NTP_ENABLE="/bin/systemctl enable ntpd.service"
   NTP_STOP="/bin/systemctl stop ntpd.service"
   NTP_START="/bin/systemctl start ntpd.service"
else
   NTP_DISABLE='sbin/chkconfig ntpd off'
   NTP_ENABLE='sbin/chkconfig ntpd on'
   NTP_STOP='service ntpd stop'
   NTP_START='service ntpd start'
fi

# Disable NTPD on VMs and DMZ servers by default
if [[ "`f_DetectVM`" != "FALSE" ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:Detected Virtual Machine - NTP is being disabled and uninstalled" | $LOG1
   fi
   $NTP_DISABLE 2>&1 | > /dev/null
   $NTP_STOP 2>&1 | > /dev/null
   RELEASE=`f_GetRelease | awk '{print $2}'`
   if [[ -n `rpm -qa ntp` ]]; then
      if [[ $RELEASE == 6 ]] || [[ $RELEASE == 7 ]]; then
         rpm -e ntp
      else
         rpm -e ntp system-config-date system-config-keyboard firstboot
      fi
   fi

   exit 0
fi
if [[ "`f_InDMZ`" == "TRUE" ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:Detected DMZ - NTP is being disabled." | $LOG1
   fi
   $NTP_DISABLE 2>&1 | > /dev/null
   $NTP_STOP 2>&1 | > /dev/null
   exit 0
fi

SSO=/etc/sso
NTPC=/etc/ntp.conf

# Configure NTPD conf file
# Check for ITC network 
ITC=NO
if [[ -s $SSO ]]; then
   ITC=`grep "^ITC=" $SSO | awk -F'=' '{print $2}'`
fi

# Create a backup of the original NTP file
if [[ ! -s ${NTPC}.orig ]]; then
   /bin/cp $NTPC ${NTPC}.orig
fi

# Disable the default server list
sed -i '/^server/s/^/#/g' $NTPC

# Remove exiisting West server entries
sed -i '/server ntp-1.wic.west.com/d' $NTPC
sed -i '/server ntp-2.wic.west.com/d' $NTPC
sed -i '/server ntp-3.wic.west.com/d' $NTPC
sed -i '/server ntp-4.wic.west.com/d' $NTPC
sed -i '/server ntp-5.wic.west.com/d' $NTPC
sed -i '/server ntp-6.wic.west.com/d' $NTPC
sed -i '/server time.icallinc.com/d' $NTPC

# Configure driftfile
if [[ -z `grep "^driftfile" $NTPC` ]]; then
   echo "driftfile /var/lib/ntp/drift" >> $NTPC
else
   sed -i '/^driftfile/s/.*/driftfile \/var\/lib\/ntp\/drift/' $NTPC
fi

# Add servers based on network
if [[ $ITC != YES ]]; then
   echo 'server ntp-1.wic.west.com' >> $NTPC
   echo 'server ntp-2.wic.west.com' >> $NTPC
   echo 'server ntp-3.wic.west.com' >> $NTPC
   echo 'server ntp-4.wic.west.com' >> $NTPC
   echo 'server ntp-5.wic.west.com' >> $NTPC
   echo 'server ntp-6.wic.west.com' >> $NTPC
else
   echo 'server time.icallinc.com' >> $NTPC
fi


# Set dummy driver for backup
if [[ -z `grep "^fudge" $NTPC` ]]; then
   echo "fudge  127.127.1.0 stratum 10" >> $NTPC
else
   sed -i '/^fudge/s/.*/fudge  127.127.1.0 stratum 10/' $NTPC
fi

# Set broadcast delay
if [[ -z `grep "^broadcastdelay" $NTPC` ]]; then
   echo "broadcastdelay  0.008" >> $NTPC
else
   sed -i '/^broadcastdelay/s/.*/broadcastdelay  0.008/' $NTPC
fi

# Set initial time 

$NTP_STOP 2>&1 | > /dev/null


# This negotiation is not intended to be foolproof as it is based on
# only one sample.

best=
besttime=
for s in `grep ^server /etc/ntp.conf | awk '{print $2}'`; do
   # Make sure the server actually responds to ntp requests before making it a candidate
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:   checking $s" | $LOG1
   fi
   if [[ -z `/usr/sbin/ntpdate $s 2>&1 | grep "no server suitable"` ]]; then
      # Collect the average of 4 pings
      time=`ping -q -c4 $s | grep rtt | awk '{print $4}' | awk -F'/' '{print $2}'`
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0:      $s average response $time ms" | $LOG1
      fi
      if [[ -z $besttime ]] || ( [[ -n $time ]] && [[ $time < $besttime ]] ); then
         best=$s
         besttime=$time
      fi
   else
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0:      $s does not answer NTP requests." | $LOG1
      fi
   fi
done

if [[ -z $best ]]; then
   echo "Unable to find a suitable NTP server, please verify a firewall or"
   echo "network issue is not preventing ntp requests."
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:No reachable NTP servers" | $LOG1
   fi
   exit 2
else
   echo "Synchronizing the clock against $best"
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0: Beginning clock sync against [$best] time in logfile may jump" | $LOG1
   fi
   /usr/sbin/ntpdate $best
   $NTP_START 2>&1 | > /dev/null
   $NTP_ENABLE 2>&1 | > /dev/null
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0: Clock sync complete" | $LOG1
   fi
fi

# Final Steps
echo "/sbin/hwclock --systohc" >> /etc/rc.local

