#!/bin/bash

# Common settings for common services


# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

CHKCONFIG=/sbin/chkconfig
INITD=/etc/init.d
TARS_DIR=/maint/scripts/tars

# Define the Deactivate and Activate lists.

DALIST="vsfptd rhnsd cups ip6tables autofs portmap autofs rhsmcertd nfslock netfs avahi-daemon kudzu gpm apmd lpd httpd smartd sendmail"
ALIST="iptables sshd"

#Process De-activate list
for SN in $DALIST; do
   if [[ $PRODUCT == RHEL ]];then
      if [[ $RELEASE -le 6 ]]; then
         if [[ -s "${INITD}/${SN}" ]]; then
            $CHKCONFIG $SN off
         fi
      else
         if [[ -s "/usr/lib/systemd/system/${SN}.service" ]]; then
            /bin/systemctl disable ${SN}.service 2>&1 | >>/dev/null
         fi
      fi
   fi
done

#Process Activate list
for SN in $ALIST; do
   if [[ -s "${INITD}/${SN}" ]]; then
      $CHKCONFIG $SN --level 345 on
   fi
done

# NSCD setup
if [[ $PRODUCT == RHEL ]];then
   if [[ $RELEASE -le 6 ]]; then
      /sbin/chkconfig --add nscd
      /sbin/chkconfig nscd on
      /sbin/service nscd start 2>&1 | >> /dev/null
   else
      /bin/systemctl enable nscd.service 2>&1 | >>/dev/null
      /bin/systemctl start nscd.service 2>&1 | >>/dev/null
   fi
fi

# "Install" clean machine
BIN_TAR="${TARS_DIR}/bin.tar.gz"

/bin/tar -C /usr/local/ -xf "${BIN_TAR}" bin/cdate bin/clean_machine.sh bin/Clean_Machine
/bin/chmod 755 /usr/local/bin/cdate /usr/local/bin/clean_machine.sh /usr/local/bin/Clean_Machine


# Add clean machine to CRON
ROOTCRONTAB=/var/spool/cron/root
if [[ $PRODUCT == RHEL ]];then
   if [[ $RELEASE -le 6 ]]; then
      CRON_RESTART="/etc/init.d/crond restart"
   else
      CRON_RESTART="/bin/systemctl restart crond.service"
   fi
fi


# If the root crontab already exists, back it up
if [[ -s $ROOTCRONTAB ]];then 
   /bin/cp $ROOTCRONTAB /var/spool/cron.root.${TS}
   # If there are existing clean_machine entries in root's crontab, remove them
   if [[ -n `/bin/egrep 'clean_machine.cfg|clean_machine.sh' $ROOTCRONTAB` ]]; then
      /bin/sed -i '/clean_machine/d;/CLEAN MACHINE/d' $ROOTCRONTAB
   fi
fi

# Add entries
echo "0 0 * * * /bin/touch /opt/log/clean_machine/clean_machine.cfg > /dev/null 2>&1" >> $ROOTCRONTAB
echo "0 4 * * * /opt/local/bin/clean_machine.sh > /dev/null 2>&1" >> $ROOTCRONTAB

$CRON_RESTART


# NTP setup
if [[ "`f_DetectVM`" != "TRUE" ]]; then
   $CHKCONFIG ntpd on
fi

# SENDMAIL setup 
if [[ -f /etc/sendmail.cf ]]; then
   SMCONF=/etc/sendmail.cf
   sed -i.${TS} s/^DS/DSmail.corp.westworlds.com/ $SMCONF
elif [[ -f /etc/mail/sendmail.cf ]]; then
   SMCONF=/etc/mail/sendmail.cf
   sed -i.${TS} s/^DS/DSmail.corp.westworlds.com/ $SMCONF
elif [[ -f /etc/postfix/main.cf ]]; then
   if [[ -z `grep ^relayhost /etc/postfix/main.cf | grep mail.corp.westworlds.com` ]]; then
      echo "" >> /etc/postfix/main.cf
      echo "# West SMTP relay" >> /etc/postfix/main.cf
      echo "relayhost = mail.corp.westworlds.com" >> /etc/postfix/main.cf
   fi
fi

# Make sure postfix starts before sendmail
if [[ -f /etc/init.d/sendmail ]] && [[ -z `grep "Required-Start" /etc/init.d/sendmail | grep postfix` ]] && [[ $PRODUCT == RHEL ]] && [[ $RELEASE -le 6 ]]; then
   sed -i '/Required-Start:/s/$/ postfix/' /etc/init.d/sendmail

##20150513 - Alex
#This section re-enables sendmail to start by default.
#this is not something we want running by default.
#   $CHKCONFIG --del sendmail
#   $CHKCONFIG --add sendmail
##/20150513

fi

# NOTE: sendmail should not be configured to start automatically

# Disable ctrl+alt+delete to reboot
if [[ $PRODUCT == RHEL ]];then
   if [[ $RELEASE -lt 6 ]]; then
      if [[ -z `grep ctrlaltdel /etc/inittab | grep -i disabled` ]]; then
         sed -i.orig '/ctrlaltdel/s/^/#/;/ctrlaltdel/s/$/\nca::ctrlaltdel:\/bin\/echo "NOTICE: Ctrl+Alt+Delete is disabled" >\&1/' /etc/inittab
      fi
   elif [[ $RELEASE -eq 6 ]]; then

cat << EOF > /etc/init/control-alt-delete.conf
# control-alt-delete - emergency keypress handling
#
# This task is run whenever the Control-Alt-Delete key combination is
# pressed.  Usually used to shut down the machine.

start on control-alt-delete

exec echo "Control-Alt-Delete has been disabled"

EOF
   
   else
      ln -sf /dev/null /usr/lib/systemd/system/ctrl-alt-del.target
   fi
fi

# Disable selinux
sed -i.orig 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
   
# remove service definitions for insecure protocols
egrep '^login[ \t]' /etc/services >> /etc/.services.disabled
sed -i '/^login[ \t]/d' /etc/services
egrep '^shell[ \t]' /etc/services >> /etc/.services.disabled
sed -i '/^shell[ \t]/d' /etc/services
egrep '^exec[ \t]' /etc/services >> /etc/.services.disabled
sed -i '/^exec[ \t]/d' /etc/services
egrep '^COS_shell[ \t]' /etc/services >> /etc/.services.disabled
sed -i '/^COS_shell[ \t]/d' /etc/services   
if [[ -f /etc/xinetd.conf ]]; then sed -i '/^includedir/d' /etc/xinetd.conf; fi

