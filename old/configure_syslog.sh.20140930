#!/bin/bash

# !!!!!!!!!!ATTENTION!!!!!!!!!!!!!
# DO NOT MAKE CHANGES TO THIS SCRIPT
# If you need to change logging behavior,
#  update [/opt/configure_syslog.conf]
#  and re-run this script
# !!!!!!!!!!ATTENTION!!!!!!!!!!!!!










































# This script configures syslog/rsyslog - it is only meant to be run during initial
# setup or when changing sites - it should not be put into cron!

## SCRIPT_VERSION=20140702a


# Make sure we're running as root
if [[ $EUID != 0 ]]; then
   echo "This script must be run with root privileges - try sudo"
   exit
fi

# The octal mode for custom West logfiles
WLF_PERMS=0644


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

cd "`f_PathOfScript`"

###############VARIABLE CONFIGURATIONS###################
TMPFILE=/tmp/slc
DSUFFIX=`date +%Y%m%d`
ROOTCRONTAB=/var/spool/cron/root
OVERRIDECONF=/opt/configure_syslog.conf
LINKSCRIPT=/opt/configure_loglinks.sh
WESTLRSCRIPT=/opt/westlogrotate.sh
LOGROTATECONF=/etc/logrotate.conf
LOGROTATEDIR=/etc/logrotate.d
WESTLOGROTATE=${LOGROTATEDIR}/westsyslog
SYSLOGROTATE=${LOGROTATEDIR}/syslog
OVERRIDEROTATE=${LOGROTATEDIR}/syslog-ovr
CLEANMACHINECONF=/opt/log/clean_machine/clean_machine.cfg

NUMLOGS=14
COMPRESSDELAY=5

# Create a list of standard Linux logfiles
# This will be used to differentiate them from
# West-only logfiles
STANDARD_LOGFILES="
/var/log/messages
/var/log/secure
/var/log/maillog
/var/log/cron
/var/log/spooler
/var/log/boot.log
"


###############VARIABLE CONFIGURATIONS###################

###############OS SPECIFIC SETTINGS######################

DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`
UPDATE=`f_GetRelease | awk '{print $3}'`

USE_RSYSLOG=FALSE

if [[ $DISTRO == RHEL ]]; then
   if [[ $RELEASE -lt 6 ]]; then
      SYSLOG_CONF=/etc/syslog.conf
      SYSLOG_START="/etc/init.d/syslog start"
      SYSLOG_STOP="/etc/init.d/syslog stop"
      SYSLOG_RESTART="/etc/init.d/syslog restart"
      CRON_RESTART="/etc/init.d/crond restart"
      CRON_RELOAD="/etc/init.d/crond reload"
      if [[ -f /etc/rsyslog.conf ]]; then
         USE_RSYSLOG=TRUE
      fi
   fi
   if [[ $RELEASE -eq 6 ]]; then
      SYSLOG_CONF=/etc/rsyslog.conf
      SYSLOG_START="/etc/init.d/rsyslog start"
      SYSLOG_STOP="/etc/init.d/rsyslog stop"
      SYSLOG_RESTART="/etc/init.d/rsyslog restart"
      CRON_RESTART="/etc/init.d/crond restart"
      CRON_RELOAD="/etc/init.d/crond reload"
      USE_RSYSLOG=TRUE
   fi
   if [[ $RELEASE -eq 7 ]]; then
      SYSLOG_CONF=/etc/rsyslog.conf
      SYSLOG_START="/bin/systemctl start rsyslog.service"
      SYSLOG_STOP="/bin/systemctl stop rsyslog.service"
      SYSLOG_RESTART="/bin/systemctl restart rsyslog.service"
      CRON_RESTART="/bin/systemctl restart crond.service"
      CRON_RELOAD="/bin/systemctl restart crond.service"
      USE_RSYSLOG=TRUE
   fi
fi

if [[ -x /usr/bin/find ]]; then
   FIND=/usr/bin/find
elif [[ -x /bin/find ]]; then
   FIND=/bin/find
else
   FIND=`which find 2>&1 | grep -v ' no ' | awk '{print $1}'`
fi
if [[ -z $FIND ]]; then
   echo "Critical dependency failure: unable to locate \`find\`"
   exit
fi


###############OS SPECIFIC SETTINGS######################

################SITE NUMBER###############################

# Newer builds should use the SSO file to record the site number
if [[ -s /etc/sso ]]; then
   SN=`grep "^SITENUM=" /etc/sso | awk -F'=' '{print $2}'`
fi

# Slightly older builds might use /etc/sitenum instead
if [[ -z $SN ]]; then
   if [[ -s /etc/sitenum ]]; then
      SN=`cat /etc/sitenum`
   fi
fi

# Older builds save the info in /usr/eos/data/expcfg
if [[ -z $SN ]]; then
   if [[ -s /usr/eos/data/expcfg ]]; then
      SN=`awk '{print $2}' /usr/eos/data/expcfg`
   fi
fi

################SITE NUMBER###############################

################CONFIG/OVERRIDE FILE######################

if [[ ! -s $OVERRIDECONF ]]; then

cat << EOF > $OVERRIDECONF
# This configuration file allows you to add or override the default
# configuration used by configure_syslog.sh
#
#

#@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@
#@
#@  To apply changes, save your changes to this file, then re-run $0
#@
#@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@@@@[ ATTENTION ]@


# DEBUG STATUS
# Many systems in the environment perform alerting based on log-scraping external
# logs.  When setting up, or debugging a server, you may not want the logs being sent
# externally and triggering alerts.  
# Setting DEBUG to "YES" will prevent external logging.
#
#DEBUG:YES

# ADDITIONAL Logs
# configure_syslog.sh creates a default list of facility->target logging directives.
# If you wish to create additional logfiles to manage with syslog and logrotate
# Use the "ADD" action, in the following format:
#
# ADD:<facility>:<target>:[<port>]
#
# Where "<facility>" and "<target>" are the exact same format used by syslog, and
#    "<port>" is the TCP or UDP target port to send the logs.
#
# Note: use "{SITE}" to use the server's site number as part of the logserver name
# Note2: <port> is only valid for logging targets beginning with "@"(UDP) or "@@"(TCP).
#
# Examples:
#
#ADD:local.14:@logserver{SITE}
#ADD:*.authpriv:@securityserver.net:514
#ADD:*.info;*.authpriv:/var/log/misc

# OVERRIDE Default Logs
# You can change the facility configuration of a default target by using
# the "OVR" action in the following format:
#
# OVR:<facility>:<target>[<port>]
#
# Where "<facility>" is the new configuration you want for the default "<target>"
#    and "<port>" is the TCP or UDP target port for remote logging
#
# Note: use "{SITE}" to use the server's site number as part of the logserver name
#
# Examples:
#
#OVR:*.info;mail.none:/var/log/error/error
#OVR:authpriv.*,*.info:@gniggol.0.west.com:514
#OVR:local19.debug:@apperror{SITE}

# REMOVE Default Logs
# You can prevent specific default logging targets using the following format:
#
# REM:<target>
#
# Where "<target>" is the name of a default target you do not wish to leave active
#
# Note: use "{SITE}" to use the server's site number as part of the logserver name
#
# Examples:
#
#REM:@apperror{SITE}
#REM:/var/log/error/error

# ROTATION Override action
# By default all logs handled by syslog are on a 15 day rotation, and compressed.
# You can override default rotation behavior for a specific logfile by using the "ROR" action
# in the following format:
#
# ROR:<target>:<days>:<compress>
#
# Where: <target> is a valid logging target in syslog
#          <days> is the number of days to retain the log
#      <compress> is either "Y" or "N"
#
# Examples:
#
#ROR:/var/log/error/error:7:Y




EOF
fi


################CONFIG/OVERRIDE FILE######################

################RSYSLOG SETTINGS##########################

if [[ $USE_RSYSLOG == TRUE ]]; then

# NOTE: These directives must appear at the beginning of rsyslog.conf, before
#       any comments or anything else

cat << EOF > $TMPFILE
\$ModLoad imuxsock
\$ModLoad imklog
\$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
\$template sysklogd,"<%PRI%>%TIMESTAMP% %syslogtag%%msg%"

EOF

fi

################RSYSLOG SETTINGS##########################

################SYSLOG CONFIGURATION######################

# Do not make changes to this section unless they are meant
# to apply to every server going forward.  

cat << EOF >> $TMPFILE

# This file was automatically generated by $0 on `date`
# !!!!!!!!!!ATTENTION!!!!!!!!!!!!!
#
# If you want to make changes to logging, edit $OVERRIDECONF and re-run $0
#
# DO NOT edit this file by hand
# DO NOT put $0 in cron (This script should only be run at build and when adding new logs)
# DO NOT rename log files with .MMDDYYYY extensions - that will be done automatically
# DO NOT add these logs to CleanMachine - compression and rotation is done automatically
#
# !!!!!!!!!!ATTENTION!!!!!!!!!!!!!

# External logging
local0.info                                             @error${SN}
local2.debug                                            @apperror${SN}
local3.debug                                            @admin-msg
authpriv.*,*.info                                       @gniggol.0.west.com

# West-Specific logging
local1.debug                                            -/var/log/debug/debug
mail.*                                                  -/var/log/mail/mail
local2.debug                                            -/var/log/app/app
local3.debug                                            -/var/log/admin_msg/admin
*.info                                                  /var/log/error/error

# Standard Syslog Facilities
*.info;mail.none;authpriv.none;cron.none                /var/log/messages
authpriv.*                                              /var/log/secure
cron.*                                                  /var/log/cron
local7.*                                                /var/log/boot.log

EOF


# Process Overrides

# Check for ADD actions

if [[ -n `grep ^ADD: $OVERRIDECONF` ]]; then

   for AL in `grep ^ADD: $OVERRIDECONF`; do
   
      # Break out the ADD line into its parts

      AFAC=`echo $AL | awk -F':' '{print $2}'`
      ATAR=`echo $AL | awk -F':' '{print $3}' | sed "s/{SITE}/$SN/g"`
      APOR=`echo $AL | awk -F':' '{print $4}'`

      if [[ -n $AFAC ]] && [[ -n $ATAR ]]; then

         # Verify the target does not already exist before continuing
         if [[ -z `egrep -v '^$|^#|^\$' $TMPFILE | awk '{print $2}' | grep "^${ATAR}$"` ]]; then
     
            # Add a comment line if necessary 
            if [[ -z `grep '^# Custom/Overridden logging' $TMPFILE` ]]; then
               echo '# Custom/Overridden logging' >> $TMPFILE
            fi
   
            # Add the new log definition
            # W is the default tab-stop for the syslog format
            W=56
   
            # If we happen to add a facility that is longer than the default
            # tab-stop, then increase the tabstop to the facility's length +2
            if [[ `expr length $AFAC` -ge $W ]]; then
               let W=`expr length $AFAC`+2
            fi
   
            # Create a tab-stop format string for awk 
            TSF="%-${W}.${W}s%s\n"

            # Add the port to the target if applicable

            if [[ -n $APOR ]]; then

               # Verify the target is remote
               if [[ -z `echo $ATAR | grep "^@"` ]]; then
                  echo "Error in $OVERRIDECONF: Port numbers are only valid for remote logging targets."
                  echo "         Ignoring port number in line \"${AL}\""
               else
                  # Verify it's a valid port number
                  if [[ -z `echo $APOR | egrep "^[0-9]+$"` ]] || [[ $APOR -lt 1 ]] || [[ $APOR -gt 65534 ]]; then
                     echo "Error in $OVERRIDECONF: Port number provided on line \"${AL}\" is invalid, operation skipped."
                  else
                     # After passing checks, update ATAR variable with the port number before writing it out
                     ATAR="${ATAR}:${APOR}"
                  fi

               fi
            fi

   
            # Write the new log definition
            echo "${AFAC} ${ATAR}" | awk -v format=$TSF '{printf 'format', $1,$2; }' >> $TMPFILE
         else
            echo "Error in $OVERRIDECONF: the target \"${ATAR}\" already exists. "
            echo "   This ADD action will be ignored. If you're trying to alter the"
            echo "   default facilities for \"${ATAR}\" use OVR instead of ADD."
         fi   
      else
         echo "Error in $OVERRIDECONF: the line $AL is not properly formatted, skipping."
      fi
      

   done


fi

# Check for Override actions

if [[ -n `grep ^OVR: $OVERRIDECONF` ]]; then

   for OL in `grep ^OVR: $OVERRIDECONF`; do

      # Break out the ADD line into its parts

      OFAC=`echo $OL | awk -F':' '{print $2}'`
      OTAR=`echo $OL | awk -F':' '{print $3}' | sed "s/{SITE}/$SN/g"`
      OPOR=`echo $OL | awk -F':' '{print $4}'`

      if [[ -n $OFAC ]] && [[ -n $OTAR ]]; then

         # Verify that the target exists in the logfile before trying to override
         if [[ -n `egrep -v '^$|^#|^\$' $TMPFILE | awk '{print $2}' | grep "^${OTAR}$"` ]]; then

            # Add a comment line if necessary
            if [[ -z `grep '^# Custom/Overridden logging' $TMPFILE` ]]; then
               echo '# Custom/Overridden logging' >> $TMPFILE
            fi

            # Remove the original line from the configuration file
            sed -i "/^`egrep -v '^$|^\$|^#' $TMPFILE | awk -v T=$OTAR '{if($2==T) print}' | sed 's/\\//\\\\\//g'`/d" $TMPFILE
          

            # Add the override as a new log definition
            # W is the default tab-stop for the syslog format
            W=56

            # If we happen to add a facility that is longer than the default
            # tab-stop, then increase the tabstop to the facility's length +2
            if [[ `expr length $OFAC` -ge $W ]]; then
               let W=`expr length $OFAC`+2
            fi
   
            # Create a tab-stop format string for awk
            TSF="%-${W}.${W}s%s\n"

            # Add port to target if applicable
            if [[ -n $OPOR ]]; then

               # Verify the target is remote
               if [[ -z `echo $OTAR | grep "^@"` ]]; then
                  echo "Error in $OVERRIDECONF: Port numbers are only valid for remote logging targets."
                  echo "         Ignoring port number in line \"${OL}\""
               else
                  # Verify it's a valid port number
                  if [[ -z `echo $OPOR | egrep "^[0-9]+$"` ]] || [[ $OPOR -lt 1 ]] || [[ $OPOR -gt 65534 ]]; then
                     echo "Error in $OVERRIDECONF: Port number provided on line \"${OL}\" is invalid, operation skipped."
                  else
                     # After passing checks, update ATAR variable with the port number before writing it out
                     OTAR="${OTAR}:${OPOR}"
                  fi

               fi
            fi

   
            # Write the new log definition
            echo "${OFAC} ${OTAR}" | awk -v format=$TSF '{printf 'format', $1,$2; }' >> $TMPFILE
         
         else

            echo "Error in $OVERRIDECONF: "
            echo "   the target \"${OTAR}\" is not a configured target, so there is nothing to override."
            echo "   This OVR will be skipped.  If you wish to add this target, use ADD instead of OVR"

         fi

      else
         echo "Error in $OVERRIDECONF: the line $OL is not properly formatted, skipping."
      fi


   done


fi

# Check for Remove actions

if [[ -n `grep ^REM: $OVERRIDECONF` ]]; then

   for RL in `grep ^REM: $OVERRIDECONF`; do

      # Break out the REM line into its parts

      RTAR=`echo $RL | awk -F':' '{print $2}' | sed "s/{SITE}/$SN/g"`

      if [[ -n $RTAR ]]; then

         # Verify that the target exists in the logfile before trying to remove it
         if [[ -n `egrep -v '^$|^#|^\$' $TMPFILE | awk '{print $2}' | grep "^${RTAR}$"` ]]; then

            # Remove the line from the configuration file
            sed -i "/^`egrep -v '^$|^\$|^#' $TMPFILE | awk -v T=$RTAR '{if($2==T) print}' | sed 's/\\//\\\\\//g'`/d" $TMPFILE

         else

            echo "Error in $OVERRIDECONF: "
            echo "   the target \"${RTAR}\" is not a configured target, so there is nothing to remove."
            echo "   This REM action will be skipped."

         fi

      else
         echo "Error in $OVERRIDECONF: the line $RL is not properly formatted, skipping."
      fi


   done


fi

# Check for debug setting

if [[ -n `grep ^DEBUG: $OVERRIDECONF` ]]; then


   # Check the debug setting

   DS=`grep ^DEBUG: $OVERRIDECONF | awk -F':' '{print $2}' | tr '[:lower:]' '[:upper:]' | awk '{print $1}'`


   if [[ "$DS" == "YES" ]]; then

      # Remove any external logging directives from the TMPFILE

      sed -i -e '/[ \t]@.*$/d; s/# External logging/# External logging\n# Notice: external logging currently disabled by DEBUG mode in \/opt\/configure_syslog.conf/g' $TMPFILE
      
   fi

fi



################SYSLOG CONFIGURATION######################

###################UPDATE REDIRECTS AS NEEDED#############

if [[ $USE_RSYSLOG == TRUE ]]; then

   # append redirects with ";sysklogd" to prevent double-logging the system name
   sed -i '/@/ s/$/;sysklogd/g' $TMPFILE

fi

###################UPDATE REDIRECTS AS NEEDED#############

################UPDATE SYSLOG CONF########################

/bin/cp "$SYSLOG_CONF" "${SYSLOG_CONF}.bak.${TS}"

/bin/mv "$TMPFILE" "$SYSLOG_CONF"

################UPDATE SYSLOG CONF########################

################CREATE WEST LOGDIRS#######################


# Create a variable containing all of the west-only logfiles
unset WESTLOGFILES

for LF in `/bin/cat "$SYSLOG_CONF" | /bin/egrep -v '^#|^$|\\$' | /bin/awk '{print $NF}' | /bin/grep -v '^@' | sed 's/^-//g'`; do
   if [[ -z `echo $STANDARD_LOGFILES | /bin/grep $LF` ]]; then
      WESTLOGFILES="$WESTLOGFILES $LF"
   fi
done

# Create the log directories if they don't already exist
for WLF in $WESTLOGFILES; do
   WLF_BASENAME=`/bin/basename $WLF`
   WLOGDIR=`echo $WLF | sed 's/'"$WLF_BASENAME"'$//g'`
   if [[ ! -d $WLOGDIR ]]; then
      mkdir -p $WLOGDIR
   fi
done

################CREATE WEST LOGDIRS#######################

################CLEAN UP LEGACY###########################

# This section will clean up changes made by ConfigureSyslog.pl
# and previous versions of this script.

# Check to see if we actually need to fix legacy filenaming
WLFRENAME=NO
EDITCLEANMACHINE=YES
for WLF in $WESTLOGFILES; do

   # Get the basename for the west log file
   WLF_BASENAME=`/bin/basename $WLF`

   # Get the directory name for the west log file
   WLOGDIR=`echo $WLF | sed 's/'"$WLF_BASENAME"'$//g'`

   # FAKENAME is the name of logfiles with a path under the symlinked "wic" filesystem.
   FAKENAME=`echo ${WLOGDIR} | sed 's/var/wic/;s/opt/wic/' | sed 's/\/$//'`
   if [[ -s $CLEANMACHINECONF ]]; then
      if [[ -n `/bin/egrep  "${WLOGDIR}|${FAKENAME}" $CLEANMACHINECONF` ]]; then
         EDITCLEANMACHINE=YES
      fi
   else
      EDITCLEANMACHINE=NO
   fi

   # If a west log file exists with the standard date suffix for today's date, and it's not a link
   # Then we're dealing with a system managed by ConfigureSyslog.pl and we need som renaming done

   if ([[ -f "${WLF}.${DSUFFIX}" ]] && [[ ! -L "${WLF}.${DSUFFIX}" ]]) || ([[ -f "${WLF}-${DSUFFIX}" ]] && [[ ! -L "${WLF}-${DSUFFIX}" ]]); then
      WLFRENAME=YES
   fi

   # If there are logfiles with the "-" suffix in the log directory, then a rename is in order
   if [[ -n `ls "${WLOGDIR}" | grep "${WLF_BASENAME}-"` ]]; then
      WLFRENAME=YES
   fi


   
done

# Clean up links called /var/log/messages - this is to address issues caused by earlier versions of this script

for VLM in `$FIND /var/log -type l -name messages*`; do
  /bin/rm $VLM
done

# Remove the date extension from today's log so our new settings 
# won't conflict with it.
if [[ $WLFRENAME == YES ]]; then
 
   # Stop the daemon from writing to the logs while we're changing the names
   $SYSLOG_STOP
   for WLF in $WESTLOGFILES; do

   # Get the basename for the west log file
   WLF_BASENAME=`/bin/basename $WLF`

   # Get the directory name for the west log file
   WLOGDIR=`echo $WLF | sed 's/'"$WLF_BASENAME"'$//g'`

      
      # If a logfile exists with today's date and it's NOT a symlink
      if ([[ -f "${WLF}.${DSUFFIX}" ]] && [[ ! -L "${WLF}.${DSUFFIX}" ]]) || ([[ -f "${WLF}-${DSUFFIX}" ]] && [[ ! -L "${WLF}-${DSUFFIX}" ]]) || [[ -n `ls "${WLOGDIR}" | grep "${WLF_BASENAME}\."` ]]; then

         # If there is no existing logfile without today's date as a suffix, then
         # simply remove the extension from the one with the suffix.
         if [[ ! -f "${WLF}" ]]; then
            if [[ -f "${WLF}.${DSUFFIX}" ]] && [[ ! -L "${WLF}.${DSUFFIX}" ]]; then
               /bin/mv "${WLF}.${DSUFFIX}" "${WLF}"
            fi
            if [[ -f "${WLF}-${DSUFFIX}" ]] && [[ ! -L "${WLF}-${DSUFFIX}" ]]; then
               /bin/mv "${WLF}-${DSUFFIX}" "${WLF}"
            fi
         else
            # If we have both a logfile without a suffix AND a logfile with
            # with TODAY's date, then we first need to merge them then, we rename the old file
            # The one without a suffix should be the newest one so it is appended to the older
            # to keep consistent log flow.

            # One set of instructions for "." suffixes
            if [[ -f "${WLF}.${DSUFFIX}" ]] && [[ ! -L "${WLF}.${DSUFFIX}" ]]; then
               cat "${WLF}" >> "${WLF}.${DSUFFIX}"
               /bin/rm "${WLF}"
               /bin/mv "${WLF}.${DSUFFIX}" "${WLF}"
            fi

            # One set of instructions for "-" suffixes
            if [[ -f "${WLF}-${DSUFFIX}" ]] && [[ ! -L "${WLF}-${DSUFFIX}" ]]; then
               cat "${WLF}" >> "${WLF}-${DSUFFIX}"
               /bin/rm "${WLF}"
               /bin/mv "${WLF}-${DSUFFIX}" "${WLF}"
            fi
         fi
      fi

      # Re-name any log files in the directory with "-" delimiters to "." delimeters
      for EF in `ls "${WLOGDIR}" | grep "${WLF_BASENAME}-"`; do
         EFNN=`echo $EF | sed "s/${WLF_BASENAME}-/${WLF_BASENAME}\./"`
         /bin/mv "${WLOGDIR}/$EF" "${WLOGDIR}/$EFNN"
      done

      # Set permissions for West Logfiles
      touch "$WLF"
      chmod $WLF_PERMS "$WLF"
      
   done
   # Restart the syslog daemon
   $SYSLOG_START
fi

# The RHEL5 version of logrotate doesn't support using "." as a delimiter. For compatibility
# we're switching everything over to - for the delimiter.  

# This section will re-name files in the directory found using the . delimiter
# There is also the possibility that a bad log rotate has caused there to be both a file with today's date
# and a file without a date.  


# Remove ConfigureSyslog.pl from cron if necessary
if [[ -s $ROOTCRONTAB ]] && [[ -n `/bin/egrep 'configure_rsyslog.sh|link_syslog.sh|ConfigureSyslog.pl|CONFIG SYSLOG' $ROOTCRONTAB` ]]; then

   /bin/cp $ROOTCRONTAB /var/spool/cron.root.${TS}
   /bin/sed -i '/configure_rsyslog.sh/d;/link_syslog.sh/d;/ConfigureSyslog.pl/d;/CONFIG SYSLOG/d' $ROOTCRONTAB
   $CRON_RELOAD

fi

# Remove log rotation from cleanmachine for the logs now handled by logrotate
if [[ $EDITCLEANMACHINE == YES ]]; then
   /bin/cp ${CLEANMACHINECONF} ${CLEANMACHINECONF}.${TS}
   for WLF in $WESTLOGFILES; do
      WLF_BASENAME=`/bin/basename $WLF`
      WLOGDIR=`echo $WLF | sed 's/'"$WLF_BASENAME"'$//g'`
      FAKENAME=`echo ${WLOGDIR} | sed 's/var/wic/;s/opt/wic/' | sed 's/\/$//'`
      /bin/cat $CLEANMACHINECONF | /bin/egrep -v "${WLF}|${FAKENAME}" >> $CLEANMACHINECONF.tmp
      /bin/mv $CLEANMACHINECONF.tmp $CLEANMACHINECONF
   done
   /bin/chmod 600 $CLEANMACHINECONF
fi



################CLEAN UP LEGACY###########################

################CONFIGURE LINKSCRIPT######################
# 20130729 - SDW the linkscript is being replaced with "westlogrotate.sh"

if [[ -f $LINKSCRIPT ]]; then
   /bin/rm $LINKSCRIPT
fi


#cat << EOF > $LINKSCRIPT
#
##!/bin/bash
#
## DO NOT EDIT THIS SCRIPT - it is auto-generated by $0
## This script creates and removes links to West-only logfiles and should
## only be executed from the $WESTLOGROTATE script, and only by the 
## logrotate daemon.
## 
## Ordinarily the current day's log file will not have a date
## extension.  This adds a link with a date extension to the current
## day's logfile.
##
## Links are removed just prior to log rotation to prevent filename
## conflicts.
#
#
#MODE=\$1
#
#
#f_linkSuffix () {
#
#  FN=\$1
#  SFX=\$2
#
#   if [[ -f \$FN ]]; then
#      ln -s \$FN \${FN}-\${SFX}
#   fi
#
#}
#
#DSUFFIX=\`date +%Y%m%d\`
#TODAY=\`date +%s\`
#let TOMORROW=\$TODAY+86400
#TSUFFIX=\`date --date=@\$TOMORROW +%Y%m%d\`
#LOGFILES="$WESTLOGFILES"
#
#if [[ ! -s /etc/sitenum ]]; then
#
#   if [[ -f /usr/eos/data/expcfg ]]; then
#      cat /usr/eos/data/expcfg | awk '{print \$2}' > /etc/sitenum
#   fi
#fi
#
#if [[ -s /etc/sitenum ]]; then
#   SN=\`cat /etc/sitenum\`
#fi
#
##Create symlinks to "Today's" log
#
#if [[ \$MODE == PRE ]]; then
#
#   # Remove old links
#   for lf in \$LOGFILES; do
#      lfb=\`basename \$lf\`
#      ld=\`echo \$lf | sed 's/'"\$lfb"'$//g'\`
#      for l in \`find \$ld -type l | grep \${lf}- \`; do
#         /bin/rm \$l
#      done
#   done
#
#elif [[ \$MODE == POST ]]; then
#
#   for lf in \$LOGFILES; do
#      # If this is being run at a minute to midnight
#      # then it's probably being run by cron so use tomorrow's 
#      # date as the link name.
#      if [[ \`date +%H%M\` == 2359 ]]; then
#         f_linkSuffix \$lf \$TSUFFIX
#      else
#         f_linkSuffix \$lf \$DSUFFIX
#      fi
#   done
#
#fi
#
#EOF
#chmod 700 $LINKSCRIPT

################CONFIGURE LINKSCRIPT######################

################CONFIGURE WESTLRSCRIPT####################

cat << EOF > $WESTLRSCRIPT
#!/bin/bash

# DO NOT EDIT THIS SCRIPT - it is auto-generated by $0
#  and any changes will be overwritten. If you need to make changes
#  to the way system logging is handled, make them in $OVERRIDECONF
#  then re-run $0 to apply them. 
#



















# Get our date information
TODAY=\`date +%s\`
let YESTERDAY=\$TODAY-86400
TODAYSUFFIX=\`date +%Y%m%d\`
YESTERDAYSUFFIX=\`date --date=@\$YESTERDAY +%Y%m%d\`

MAXFILES=$NUMLOGS
COMPRESS=Y
COMPRESSDELAY=$COMPRESSDELAY
PERMS=$WLF_PERMS
OWNER=root
GROUP=root

LOGFILES="$WESTLOGFILES"
let CAGE=\$COMPRESSDELAY*86400

# Rotate West-Specific logfiles
for lf in \$LOGFILES; do
   # Get the basename for the logfile
   lfb=\`basename \$lf\`

   # Get the directory for the logfile
   ld=\`echo \$lf | sed 's/'"\$lfb"'$//g'\`

   # Set maxfiles and compression to default
   THIS_MAXFILES=\$MAXFILES
   THIS_COMPRESS=\$COMPRESS

   # Check for age and compression overrides
   if [[ -n \`grep ^ROR: $OVERRIDECONF | egrep ":-\${lf}:|:\${lf}:"\` ]]; then
      # Pull the number of logs to rotate from the config file.
      THIS_MAXFILES=\`grep ^ROR: $OVERRIDECONF | egrep ":-\${lf}:|:\${lf}:" | head -1 | awk -F':' '{print \$3}'\`     
      
      # If the value pulled is not numeric, fall back to the default
      if [[ -z \`echo \$MAXFILES | egrep "^[0-9]+$"\` ]]; then
         THIS_MAXFILES=\$MAXFILES
      fi
      
      # If the value pulled is not "Y" or "N" then fall back to the default   
      THIS_COMPRESS=\`grep ^ROR: $OVERRIDECONF | egrep ":-\${lf}:|:\${lf}:" | head -1 | awk -F':' '{print \$4}'\`     
      if [[ -z \`echo $THIS_COMPRESS | egrep 'y|Y|n|N'\` ]]; then
         THIS_COMPRESS=\$COMPRESS
      fi
      
   fi

   # Determine whether the logfile needs to be rotated

   # If there are no log files with yesterday's date OR the one with yesterday's date is a link
   # then we need to rotate
   # NOTE: the first time this script is run it will ALWAYS rotate the logfile
   if [[ ! -f "\${lf}.\${YESTERDAYSUFFIX}" ]] || [[ -L "\${lf}.\${YESTERDAYSUFFIX}" ]]; then
      # ROTATE!

      # Remove any symlinks pointing at the logfile
      for l in \`find \$ld -type l | grep \${lf}. \`; do
         /bin/rm \$l
      done
      for l in \`find \$ld -type l | grep \${lf}- \`; do
         /bin/rm \$l
      done

      # Drop old files until we're down to one below MAXFILES
      while [[ \`ls -lsa \$ld | egrep "\${lfb}." | grep -v '\->' | awk -F"\$lfb." '{print \$2}' | sed 's/.gz$//g' | wc -l \` -ge \$THIS_MAXFILES ]]; do
         # Grab the oldest date found on a rotated file
         OLDEST=\`ls -lsa \$ld | egrep "\${lfb}." | grep -v '\->' | awk -F"\$lfb." '{print \$2}' | sed 's/.gz$//g' | sort -n | head -1\`

         # Find the full filename corresponding with that date
         #OLDESTF=\`ls \$ld | grep "\${lfb}.\${OLDEST}"\`
         OLDESTF=\`ls \$ld | egrep "\${lfb}.\${OLDEST}\$|\${lfb}.\${OLDEST}.gz"\`

         # Log the pruning operation
         logger -t \$0 "logfile \$OLDESTF has reached max age of \$MAXFILES and is being pruned."
         # Remove the oldest file
         /bin/rm "\${ld}/\${OLDESTF}"
      done

      # Apply compression - look for all previously rotated logfiles that aren't already compressed
      if [[ "\$THIS_COMPRESS" == "Y" ]] || [[ "\$THIS_COMPRESS" == "y" ]]; then
         for lfpr in \`ls -lsa \$ld | egrep "\${lfb}." | egrep -v '\->|.gz$' | awk -F"\$lfb." '{print \$2}'\`; do
            # Determine the create time (by date of the logfile)
            LFS=\`date --date="\$lfpr" +%s\`
   
            # Determine the age of the logfile in seconds by subtracting create time from now
            let LFA=\$TODAY-\$LFS
   
            # If the age is greater than the compression age, then compress
            if [[ \$LFA -ge \$CAGE ]]; then
               # Compress
               gzip -9 "\${lf}.\${lfpr}"
            fi
   
         done
      fi

      # Apply permissions and ownership
      chmod \$PERMS "\$lf"
      chown "\${OWNER}:\${GROUP}" "\$lf"

      # Rotate the current file to yesterday's date
      /bin/cp -p "\$lf" "\${lf}.\${YESTERDAYSUFFIX}"

      # If the rotated file is not empty (or if the original file was) then it is
      # safe to erase the original file
      if [[ -s "\${lf}.\${YESTERDAYSUFFIX}" ]] || [[ ! -s "\${lf}" ]]; then
         # Erase the current logfile
         echo > "\$lf"

         # Bounce syslog to make sure it picks up the changes
         /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true

         # Create a symlink to today's logfile with today's date
         ln -s "\$lf" "\${lf}.\${TODAYSUFFIX}"

      else
         logger -s -t \$0 "FATAL - failed to rotate \$lf, exiting before we cause any damage."
      fi

   else
      echo "Rotation not needed for \$lf."

   fi

done



EOF

chmod 700 $WESTLRSCRIPT

# Install in the system's crontab to run at midnight
CTSTRING="00 0 * * * root $WESTLRSCRIPT"
if [[ -z `grep "$CTSTRING" /etc/crontab` ]]; then
   if [[ -n `grep "$WESTLRSCRIPT" /etc/crontab` ]]; then
      WLRSB=`basename $WESTLRSCRIPT`
      sed -i "/$WLRSB/d" /etc/crontab
   fi
   echo "$CTSTRING" >> /etc/crontab
fi

$CRON_RESTART


################CONFIGURE WESTLRSCRIPT####################

################CREATE INITIAL LINKS######################

# When a system is initially set up, it will not have the
# symlinks for today's date going back to the West logfiles
# These links aren't ordinarily available until after the first
# logrotation operation.
# This section will add those links if they don't exist
for WLF in $WESTLOGFILES; do
   if [[ ! -f "${WLF}.${DSUFFIX}" ]] && [[ ! -L "${WLF}.${DSUFFIX}" ]]; then
      ln -s "$WLF" "${WLF}.${DSUFFIX}"
   fi
done

################CREATE INITIAL LINKS######################


################CONFIGURE LOGROTATE#######################

# Check for Rotate Overrides and process them first

if [[ -n `grep ^ROR: $OVERRIDECONF` ]]; then

   # Remove the OVERRIDEROTATE file if it exists to make sure we're starting fresh
   if [[ -f $OVERRIDEROTATE ]]; then
      /bin/rm $OVERRIDEROTATE
   fi

   for TL in `grep ^ROR: $OVERRIDECONF`; do

      # Break out the ROR line into its parts

      TTAR=`echo $TL | awk -F':' '{print $2}' | sed "s/{SITE}/$SN/g"`
      TDAY=`echo $TL | awk -F':' '{print $3}'`
      TCOM=`echo $TL | awk -F':' '{print $4}' | tr '[:lower:]' '[:upper:]'`

      # Check input to ensure format is valid
      VALID=TRUE

      # Make sure we got all three fields
      if [[ -z $TTAR ]] || [[ -z $TDAY ]] || [[ -z $TCOM ]]; then
         VALID=FALSE
      fi

      # Make sure TTAR actually exists in the syslog config
      if [[ $VALID == TRUE ]] && [[ -z `egrep -v '^$|^#|^\$' $SYSLOG_CONF | awk '{print $2}' | grep -v '@' | grep "^${TTAR}$"` ]]; then
         VALID=FALSE
         echo "Error in $OVERRIDECONF: "
         echo "   the target \"${TTAR}\" is not a configured target, there is no log rotation to override."
         echo "   This ROR action will be skipped."
      fi

      # Make sure TDAY is an integer
      if [[ $VALID == TRUE ]] && [[ ! $TDAY =~ ^[0-9]+$ ]]; then
         VALID=FALSE
         echo "Error in $OVERRIDECONF: "
         echo "   \"$TDAY\" is not a valid entry for number of days to rotate."
         echo "   \"${RTAR}\" will be processed with the default $NUMLOGS days"
         echo "   This ROR action will be skipped."
      fi

      # Make sure TCOM is either Y or N
      if [[ $VALID == TRUE ]] && [[ $TCOM != Y ]] && [[ $TCOM != N ]]; then
         VALID=FALSE
         echo "Error in $OVERRIDECONF: "
         echo "   \"$TCOM\" is not a valid setting for compression."
         echo "   Acceptible settings are \"Y\" or \"N\""
         echo "   \"${RTAR}\" will be compressed by default."
         echo "   This ROR action will be skipped."
      fi
      
      # Create a list of the overridden log files so we can filter them from the standard
      # ones later. 
      if [[ $VALID == TRUE ]]; then
         if [[ -z $ROTATE_OVERRIDES ]]; then
            ROTATE_OVERRIDES=$TTAR
         else
            ROTATE_OVERRIDES="$ROTATE_OVERRIDES $TTAR"
         fi

         # Create an entry for this "west" logfile in the override rotate
         echo "" >> $OVERRIDEROTATE
         echo "$TTAR" >> $OVERRIDEROTATE
         echo "{" >> $OVERRIDEROTATE

         # Add compression directives if specified
         if [[ $TCOM == Y ]]; then
            echo "compress" >> $OVERRIDEROTATE
            echo "delaycompress" >> $OVERRIDEROTATE
         else
            echo "nocompress" >> $OVERRIDEROTATE
         fi

# 20130729 SDW - deprecated logrotate for west logfiles
#         # Handle differently based on whether this is a standard or a west custom log file         
#         if [[ -z `echo $STANDARD_LOGFILES | egrep "^$TTAR$|^$TTAR | $TTAR |$TTAR$"` ]]; then
#            # West log options
#            echo "daily" >> $OVERRIDEROTATE
#            echo "create $WLF_PERMS root root" >> $OVERRIDEROTATE
#            echo "rotate $TDAY" >> $OVERRIDEROTATE
#            echo "prerotate" >> $OVERRIDEROTATE
#            echo "    $LINKSCRIPT PRE 2> /dev/null || true" >> $OVERRIDEROTATE
#            echo "endscript" >> $OVERRIDEROTATE
#            echo "postrotate" >> $OVERRIDEROTATE
#            echo "    /bin/kill -HUP \`/bin/cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true" >> $OVERRIDEROTATE
#            echo "    $LINKSCRIPT POST 2> /dev/null || true" >> $OVERRIDEROTATE
#            echo "endscript" >> $OVERRIDEROTATE
#         else
#            # Standard log options
#            echo "prerotate" >> $OVERRIDEROTATE
#            echo "    /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true" >> $OVERRIDEROTATE
#            echo "endscript" >> $OVERRIDEROTATE
#         fi
         
         if [[ -n `echo $STANDARD_LOGFILES | egrep "^$TTAR$|^$TTAR | $TTAR |$TTAR$"` ]]; then
            echo "prerotate" >> $OVERRIDEROTATE
            echo "    /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true" >> $OVERRIDEROTATE
            echo "endscript" >> $OVERRIDEROTATE
         fi

         echo "" >> $OVERRIDEROTATE
         echo "}" >> $OVERRIDEROTATE
         
      else
         echo "Error in $OVERRIDECONF: the line $RL is not properly formatted, skipping."
      fi


   done


fi



# Generate the logrotate directive for Linux standard logfiles

echo > $SYSLOGROTATE

for SLF in $STANDARD_LOGFILES; do
   # If the logfile has not been overridden, add it to the list
   if [[ -z `echo $ROTATE_OVERRIDES | egrep "^$SLF$|^$SLF | $SLF |$SLF$"` ]]; then
      echo $SLF >> $SYSLOGROTATE
   fi
done

cat << EOF >> $SYSLOGROTATE
{
    sharedscripts
    postrotate
        /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

# Generate the logrotate directive for west-only logfiles

# 20130729 - SDW - removing logrotate handling for West syslog files because the expected
#                  formatting turns out not to be compatible with logrotate:
#                  - Logrotate appends the date of rotation which is a day after the events in the log
#                  - RHEL 5 logrotate doesn't support using "." as a delimiter in date extensions

if [[ -f "$WESTLOGROTATE" ]]; then
   /bin/rm $WESTLOGROTATE
fi

#echo > $WESTLOGROTATE
#
#for WLF in $WESTLOGFILES; do
#   # if the logfile has not been overridden add it to the list
#   if [[ -z `echo $ROTATE_OVERRIDES | egrep "^$WLF$|^$WLF | $WLF |$WLF$"` ]]; then
#      echo $WLF >> $WESTLOGROTATE
#   fi
#done
#
#cat << EOF >> $WESTLOGROTATE
#{
#    compress
#    delaycompress
#    daily
#    create $WLF_PERMS root root
#    rotate $NUMLOGS
#    sharedscripts
#    prerotate
#        $LINKSCRIPT PRE 2> /dev/null || true
#    endscript
#    postrotate
#        /bin/kill -HUP \`/bin/cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true
#        $LINKSCRIPT POST 2> /dev/null || true
#    endscript
#}
#
#EOF

# Update logrotate.conf

cat << EOF > $LOGROTATECONF

# see "man logrotate" for details
# rotate log files weekly
weekly

# keep 4 weeks worth of backlogs
rotate 4

# create new (empty) log files after rotating old ones
create

# use date as a suffix of the rotated file
#dateext

EOF

#if [[ $DISTRO == RHEL ]] && [[ $RELEASE -ge 6 ]]; then
#   echo "dateformat .%Y%m%d" >> $LOGROTATECONF
#fi

cat << EOF >> $LOGROTATECONF

# uncomment this if you want your log files compressed
#compress

# RPM packages drop log rotation information into this directory
include /etc/logrotate.d

# no packages own wtmp and btmp -- we'll rotate them here
/var/log/wtmp {
    rotate 5
    size 50M
    create 0664 root utmp
    compress
}

/var/log/btmp {
    missingok
    monthly
    create 0600 root utmp
    rotate 1
}

# system-specific logs may be also be configured here

EOF

# 20130729 - SDW - see previous note about logrotate and west logfiles

# This is just to clean up old scripts

if [[ -f "/etc/cron.midnight/logrotate" ]]; then
   if [[ ! -f "/etc/cron.daily/logrotate" ]]; then
      /bin/mv "/etc/cron.midnight/logrotate" "/etc/cron.daily/logrotate"
      /bin/rm -rf /etc/cron.midnight/
   else
      /bin/rm -rf /etc/cron.midnight/
   fi
fi

if [[ -n `grep cron.midnight /etc/crontab` ]]; then
   sed -i '/\/etc\/cron.midnight$/d' /etc/crontab
fi


### Ensure that logrotate is run at midnight ##
#
## Create a new cron directory
#if [[ ! -d /etc/cron.midnight ]]; then
#   mkdir -p /etc/cron.midnight
#fi
#
## Move any existing logrotate scripts from /etc/cron.daily to
## the new cron.midnight.  This will prevent cron.daily from
## triggering it.  Also, if a current copy exists in cron.midnight
## it will be overwritten by any new ones that appear in cron.daily
## This is done to accomodate potential changes if the system's
## version of logrotate is updated.
#
#if [[ -f /etc/cron.daily/logrotate ]]; then
#   /bin/mv /etc/cron.daily/logrotate /etc/cron.midnight/logrotate
#fi
#
## Ensure that cron.midnight exists in the system crontab
#
#RPSTRING='59 23 * * * root run-parts /etc/cron.midnight'
#
## If the run-parts string for cron.midnight already exists and is correct
## Then we don't need to do anything, if not, we'll remove any that does
## exist and then add the correct one.
#if [[ -z `grep "$RPSTRING" /etc/crontab` ]]; then
#   if [[ -n `grep cron.midnight /etc/crontab` ]]; then
#      sed -i '/\/etc\/cron.midnight$/d' /etc/crontab
#   fi
#   echo "$RPSTRING" >> /etc/crontab
#fi
#


################CONFIGURE LOGROTATE#######################

################BOUNCE THE SYSLOG DAEMON##################
#$LINKSCRIPT PRE
$SYSLOG_RESTART
#$LINKSCRIPT POST
################BOUNCE THE SYSLOG DAEMON##################



