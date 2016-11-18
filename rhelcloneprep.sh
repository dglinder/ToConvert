#!/bin/bash
#############################################
# Purpose: Prepares a RHEL instance to be converted into a VM template
# Author: SDW / DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         This system HAS NOT been prepped for virtualization."
   exit 2
fi

# Include the common functions for additional logging flexibility.
if [[ -s /maint/scripts/common_functions.h ]]; then
  source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
  source common_functions.h
else
  echo "Critical dependency failure: unable to locate common_functions.h"
  exit
fi

############### REMOVE PERSISTENT NET RULES ###################
PRF=/etc/udev/rules.d/70-persistent-net.rules
if [[ -f $PRF ]]; then
   echo > $PRF
fi

###############################################################

############### REMOVE SSH HOST KEYS # ########################
echo Removing SSH host key files from template.
HOSTIDFILES="
/etc/ssh/ssh_host_dsa_key.pub
/etc/ssh/ssh_host_key.pub
/etc/ssh/ssh_host_key
/etc/ssh/ssh_host_rsa_key
/etc/ssh/ssh_host_rsa_key.pub
/etc/ssh/ssh_host_dsa_key
"

for HIDF in $HOSTIDFILES; do
   if [[ -f $HIDF ]]; then
      echo "   Removing $HIDF"
      /bin/rm $HIDF
   fi
done
###############################################################

############### CLEAR HOME DIRECTORES #########################
echo Removing non-standard home directories.
HOMEDIRS=$(ls -1 /home/ | egrep -v '^bbuser$|^lost.found$|^zadmin$|^eitcmdbp$|^eitscanp$|^eithprcp$')
for HD in $HOMEDIRS; do
	echo "   Deleting /home/$HD"
	rm -rf /home/$HD
done
echo "    Left these home directories:"
ls -1 /home | cat -n

############ CLEAR SOURCECODE REPO FILES ######################
echo Removing EIT sourcecode repository files
echo "   Removing /maint/scripts/den06cloudnfs01"
rm -rf /maint/scripts/den06cloudnfs01
echo "   Removing /maint/scripts/WestCloud_scripts"
rm -rf /maint/scripts/WestCloud_scripts
echo "   Removing /root/.subversion"
rm -rf /root/.subversion
SVNDIRS=$(find / -type d -name \.svn)
for SD in $SVNDIRS; do
	echo "   Removing $SD"
	rm -rf $SD
done

############### CLEAR LOG and HISTORY #########################
echo Removing root history log files.
HISTFILES="
$(ls -1 /root/*history* /root/.*history* 2>/dev/null)
"
for HF in $HISTFILES; do
   if [[ -f $HF ]]; then
      echo "   Removing $HF"
      > $HF 2>&1
      rm -f $HF 2>&1
   fi
done

############### CLEAN MISC FILES AND DIRS ########################
echo Cleaning up misc file and directory issues
# Update this list as necessary.  Handy method to find extra files is to
# run:
#    comm -13 <(rpm -qla | sort) <(find / -type f | sort) 
#
MISCLIST="
/root/.setup_linux.sh.*
/etc/rsyslog.conf.bak.*
/etc/syslog.conf.bak.*
/etc/hosts.2*
/etc/resolv.conf.2*
/etc/sysconfig/network.2*
/etc/sudoers.old
/tmp/*
/var/tmp/*
/var/log/clean_machine/clean_machine.cfg.2*
/etc/mail/sendmail.cf.*
/etc/ssh/sshd_config.{*
/etc/sysconfig/network-scripts/bak.2*
$(ls -1 /tmp/ | egrep -v lost.found | sed 's#^#/tmp/#g')
"
for ML in $MISCLIST; do
	echo "   Removing $ML"
	rm -rf $ML
done

############### CLEAN /var/log DIR ########################
echo Cleaning up /var/log files except for clean_machine files.
find /var/log/ -type f -exec echo rm -f {} \; | egrep -v 'clean_machine' | sh

########## CLEAN RPMNEW UPDATED FILES  DIR ###################
echo Cleaning up any RPMNEW updated files.
find / -type f -name \*.rpmnew -exec rm -f {} \;

############### FIX FILE and DIR PERMS ########################
echo Fixing ownership issues
OBJLIST="
/var/log
/var/log/tmp
/var/log/clean_machine
/var/log/clean_machine/tmp
"

for OBJ in $OBJLIST; do
	echo "   Fixing perms on $OBJ"
	chown root $OBJ
done

################ Shut down syslog to begin removal ###############
echo Stopping syslog daemon for clone prep
if [[ -f /etc/init.d/rsyslog ]]; then
   SLD=/etc/init.d/rsyslog
else
   SLD=/etc/init.d/syslog
fi

$SLD stop

############### Remove log and non-standard files ###############
echo Removing log and non-standard user files
LOGFILES="
/var/log/debug/debug
/var/log/mail/mail
/var/log/app/app
/var/log/admin_msg/admin
/var/log/error/error
/var/log/messages
/var/log/secure
/var/log/cron
/var/log/boot.log
/var/log/wtmp
"

for LF in $LOGFILES; do
   if [[ -f $LF ]]; then
      /bin/rm -f ${LF}* 2>&1
   fi
done


###############################################################

################ CREATE CLONECHECK RC SCRIPT ##################

echo Creating the CloneCheck rc script.
# Create the RC script
RCN=clonecheckd
RCP=/etc/init.d
RCSCRIPT=${RCP}/${RCN}

cat << EOF > $RCSCRIPT
#!/bin/sh

# the following is the LSB init header
#
### BEGIN INIT INFO
# Provides: clonecheck
# Required-Start: \$network
# Required-Stop: \$network
# Default-Start: 3 4 5
# Default-Stop: 0 1 2 6
# Short-Description: runs post-clone steps as appropriate
# Description: This script checks to see if this OS is a clone, then runs post-cloning tasks
#              This file is built from the "rhelcloneprep.sh" script and must be updated there.
### END INIT INFO

# the following is chkconfig init header
#
# clonecheck: run post in case of clone
#
# chkconfig: 345 99 01
# description:  This is a script for running post-cloning actions
#

LDAP_SEARCH="/usr/bin/ldapsearch -x -ZZ"


f_Usage() {

   echo "Usage: \$0 [start]"

}


f_Start () {

   echo "Starting \$0"

   # Read some values for comparison

   # Get the recorded and current serial numbers
   RECSERIAL=\`grep "^SERIAL=" /etc/sso | sed 's/^SERIAL=//;s/^ //;s/ $//'i\`
   CURSERIAL=\`dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Serial Number" | awk -F':' '{print \$NF}' | sed 's/^ //;s/ $//'\`
   if [[ -z \$CURSERIAL ]]; then
      logger -t clonecheck -s "FAILURE: error reading Serial/UUID, clonecheck aborted."
      exit 1
   fi

   # Get the recorded and current hostname
   RECHN=\`grep "^NAME=" /etc/sso | sed 's/^NAME=//;s/^ //;s/ $//'i\`
   CURHN=\`hostname -s\`

   if [[ "\$RECSERIAL" != "\$CURSERIAL" ]]; then
      logger -t clonecheck -s "NOTICE: I think I'm a clone now!"

      # Disable LDAP logins to prevent authentication via "borrowed" machine netgroup

      logger -t clonecheck -s "NOTICE: Disabling LDAP logins to prevent authentication via borrowed machine netgroup"

      ESA=/etc/security/access.conf
      # Removed chattr armor per request in SDR6310213
      chattr -i \$ESA
      sed -i '/^+:@/d' \$ESA

      # Make sure the hostname has also been changed before we do anything
      if [[ "\$RECHN" == "\$CURHN" ]]; then
         logger -t clonecheck -s "FAILURE: server serial number has changed but hostname has not, LDAP logins will not work until the hostname is updated"
         exit 2
      elif [[ -n \`hostname | grep -i "RHEL" | grep -i "Template"\` ]]; then
         logger -t clonecheck -s "FAILURE: The hostname [\`hostname\`] is not allowed.  Aborting post-clone."
         exit 3
      else
         # Re-run the setup_ldap.sh script to reconfigure and re-enable
         /maint/scripts/setup_ldap.sh -ua 2>&1 | tee -a /var/log/install/setup_ldap.log
         if [[ \$? != 0 ]]; then
            logger -t clonecheck -s "FAILURE: setup_ldap.sh exited non-zero, please see /var/log/install/setup_ldap.log"
            exit 4
         fi

         ## Define LDAP parameters
         NG_BASE=\`\$LDAP_SEARCH '(ou=Netgroups)' | grep "dn: ou" | awk '{print \$2}'\`
         MNG=\`hostname -s\`_machine


         # Validate that setup_ldap.sh successfully configured the directory and server

         MNG_PRESENT=FALSE
         if [[ -n \$NG_BASE ]]; then
            if [[ -n \`\$LDAP_SEARCH -b \$NG_BASE "(cn=\$MNG)" cn | grep -i ^cn:\` ]]; then
               MNG_PRESENT=TRUE
            fi
         fi


         if [[ -n \`grep ^+:@ \$ESA\` ]] && [[ \$MNG_PRESENT == TRUE ]]; then
            # If setup_ldap.sh completed update the motd and process any additional
            # ldap work
            if [[ -f /etc/sso ]]; then
               /maint/scripts/regensso.sh
               /maint/scripts/setup_motd.sh
               /maint/scripts/setup_rhss.sh CLOUD
            fi
         fi

         ###########################
         # Cleanup the agent /data/ directory.
         rm -rf "/opt/hyperic/hyperic-hqee-agent-*/data/*"
         chown -R eithprcp:eithprcp /opt/hyperic

      fi
   fi
   ###########################
   # The VMware agent has trouble starting in some cases before the
   # clone changes have been completed.  Restart to ensure it is running
   # on the first boot.
   VMTSVC=/etc/vmware-tools/services.sh
   logger -t clonecheck -s "NOTICE: Restarting VMware tools daemon."
   \${VMTSVC} restart
   sleep 60	# SDR 6688679 - Increased timeout so more restart failures are caught.
   \${VMTSVC} status > /tmp/vmware-tools.status 2>&1 ; EC=\$?
   if [[ \$EC -gt 0 ]] ; then
      logger -t clonecheck -s "\$(cat /tmp/vmware-tools.status)"
      logger -t clonecheck -s "WARNING: VMware tools not running (Code:\$EC), restarting again."
      \${VMTSVC} restart
      sleep 60	# SDR 6688679 - Increased timeout so more restart failures are caught.
      \${VMTSVC} status > /tmp/vmware-tools.status 2>&1 ; EC=\$?
      if [[ \$EC -gt 0 ]] ; then
        logger -t clonecheck -s "\$(cat /tmp/vmware-tools.status)"
        logger -t clonecheck -s "FAILURE: VMware tools not restarting (Code:\$EC)."
      else
        # VMware tools started second time.  Cleanup.
        rm -f /tmp/vmware-tools.status
      fi
   else
      # VMware tools started first time.  Cleanup.
      rm -f /tmp/vmware-tools.status
   fi
   rm -f /tmp/vmware-tools.status

   logger -t clonecheck -s "NOTICE: Clone setup complete, welcome to the domain."
   /bin/cp -f /etc/issue.orig /etc/issue 2>/dev/null
}

f_Stop () {

   echo "This script is not persistent. The stop option is for API compliance."
}


if test \$# != 1; then
    f_Usage
    RETVAL=0
else
   case "\$1" in

       --help) f_Usage
               RETVAL=0
               ;;
        start) f_Start
               RETVAL=\$?
               ;;
         stop) f_Stop
               RETVAL=\$?
               ;;
            *) f_Usage
               RETVAL=0
               ;;
   esac
fi
exit \$RETVAL

EOF

chmod 755 $RCSCRIPT
/sbin/chkconfig --add $RCN
/sbin/chkconfig $RCN on


echo Finished - poweroff and create template.

###############################################################

