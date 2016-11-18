#!/bin/bash
#############################################
# Purpose: Add directories and links, copy prepared files, and modify some existing ones
# Author: ??? / SDW / DGL
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
   exit 1
fi

# Get information about the version of linux we're using
FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`
ECHOA=abcdef/ghijklm.nopqrstuvwxyz
ECHOB=zyxwvuts+rqponmlk.jihgf2edcba

# Configure /maint/scripts
chmod 755 /maint
chmod 755 /maint/scripts

cd /maint/scripts

chown -R root *
chmod 744 *.sh
#chmod 744 chg*
#chmod 744 mem.info

# Move scripts beginning with "chg" to the /usr/sbin directory
#mv chg* /usr/sbin

# Checking links
echo "`$VTS` : Checking links..." | $LOG2

if [[ -d /opt/local ]]; then
   if [[ ! -L /opt/local ]]; then
      echo "`$VTS` : FAILURE: /opt/local should be a symbolic link to /usr/local, but appears to be a directory, aborting" | $LOG1
      exit 2
   else
      if [[ -z `file /opt/local 2>&1 | grep /usr/local` ]]; then
         echo "`$VTS` : FAILURE: /opt/local should be a symbolic link to /usr/local but has the wrong target, aborting" | $LOG1
         exit 3
      fi
   fi
else
   ln -s /usr/local /opt/local
fi

if [[ -d /opt/log ]]; then
   if [[ ! -L /opt/log ]]; then
      echo "`$VTS` : FAILURE: /opt/log should be a symbolic link to /var/log, but appears to be a directory, aborting" | $LOG1
      exit
   else
      if [[ -z `file /opt/log 2>&1 | grep /var/log` ]]; then
         echo "`$VTS` :FAILURE: /opt/log should be a symbolic link to /var/log but has the wrong target, aborting" | $LOG1
         exit
      fi
   fi
else
   ln -s /var/log /opt/log
fi

if [[ -d /usr/log ]]; then
   if [[ ! -L /usr/log ]]; then
      echo "`$VTS` : FAILURE: /usr/log should be a symbolic link to /var/log, but appears to be a directory, aborting" | $LOG1
      exit
   else
      if [[ -z `file /opt/log 2>&1 | grep /var/log` ]]; then
         echo "`$VTS` :FAILURE: /usr/log should be a symbolic link to /var/log but has the wrong target, aborting" | $LOG1
         exit
      fi
   fi
else
   ln -s /var/log /usr/log
fi


# Only install the WIC stuff if this is a WIC server or if forced with -W
#INSTALL_WIC_LEGACY=FALSE
#if [[ -s /etc/sso ]] && [[ "`grep "^BU=" /etc/sso | awk -F'=' '{print $2}'`" == "wic" ]]; then
#   INSTALL_WIC_LEGACY=TRUE
#elif [[ -n $1 ]] && [[ -n `echo $1 | grep -i "\-W"` ]]; then
#   INSTALL_WIC_LEGACY=TRUE
#fi
#
#
#if [[ $INSTALL_WIC_LEGACY != FALSE ]]; then
#   /maint/scripts/setup_legacy_wic.sh
#fi

# Copy config files to /etc
cd /etc
if [[ $DISTRO == RHEL ]] && [[ $RELEASE == 6 ]]; then
   /bin/rm /etc/sudoers
else
   cp /etc/sudoers /etc/sudoers.old
fi

# Populate /var/log with clean machine settings
tar -C /var -xzf /maint/scripts/tars/log.tar.gz
chown root:root /var/log/clean_machine/clean_machine.cfg

# Copy "configure" and "cos" scripts to /opt
cd /opt
cp -rp /maint/scripts/configure_syslog.sh .
cd /maint/
#mv /maint/scripts/cos* .
#mv /maint/scripts/unix_crypt.cfg .

# Fix perl pathing
ln -s /usr/bin/perl /usr/local/bin/perl

C1=tikkgtmi+khgh
C2=tvgxt+khghmvjfr2
S1=tlklv
S1B=lklv
S2=t+huh_hvx
S2B=+huh_hvx
L2=twv2.gh
L2B=wv2.gh

for CIP in $C1 $C2; do

   echo -n > `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
   chmod 0000 `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
   chown 4294967294:4294967294 `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
   # Leaving in chattr for two key files until they can be monitored externally.
   chattr +ui `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`

done

# Make files which should not be changed immutable
# Removed chattr per request in SDR6310213
#SFLIST="/etc/passwd /etc/shadow /etc/group /etc/security/access.conf"
#for SF in $SFLIST; do
#   chattr +ui $SF
#done


# Add newline to the end of /etc/issue and issue.net
echo >> /etc/issue
echo >> /etc/issue.net

#  RHEL 6 is moving to a modular take on limits and this will override the standard limits.conf.  Removing to clear up the issue
if [[ $DISTRO == RHEL ]] && [[ $RELEASE == 6 ]]; then
   rm -f /etc/security/limits.d/90-nproc.conf
fi

#if [[ $DISTRO == RHEL ]] && [[ $RELEASE -lt 5 ]]; then
#   # Populate .rhosts for root
#   echo -en "ops1a root\nibmn root\n" >> /root/.rhosts
#
#   # Add COS master to /etc/hosts
#   echo "172.30.8.125      linux245 linux245.wic.west.com" >> /etc/hosts
##else
##   echo "Omitting legacy configurations"
#fi


# Legacy rc.local steps
#cp /maint/scripts/rc.local.1 /etc/rc.d/rc.local

