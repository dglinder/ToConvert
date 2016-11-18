#!/bin/sh

# 8/22/2005
# Randy Solberg 
# 
#6/13/08 - sgphilli - corrected script to reflect changes made to bb-hosts
#8/11/11 - Phil changed passwd and added reboot at end of script
#6/12/2012 - SDW - overhauled the script to add error handling, syntax checking, 
#                  and make menu selections current.

#######FUNCTION DECLARATIONS##############################

if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

###########MAIN EXECUTION START###########################

export LOGFILE=/var/log/install/configure_bb.log
if [[ ! -d /var/log/install ]]; then mkdir -p /var/log/install; fi
f_SetLogLevel 0
VTS="date +%Y%m%d%H%M%S"

# Begin logging
echo "`$VTS` : $0 log start" | $LOG1

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

echo "`$VTS` : System Info - KERNEL=$KERNEL DISTRO=$DISTRO RELEASE=$RELEASE UPDATE=$UPDATE" | $LOG1

# Create bbuser home directory and copy Big Brother
#mkdir -p /home/bbuser
tar -xzf /maint/scripts/tars/bbuser.tar.gz -C /home
chmod 755 /home/bbuser
cd /home/bbuser
#cp -rp /maint/scripts/bbuser/bb1* .
ln -s bb19c bb
chmod 755 /home/bbuser/bb19c/runbb.sh
chmod -R 755 /home/bbuser/bb19c/bin
chmod 755 /home/bbuser/bb19c/etc/*.sh*
chmod -R 755 /home/bbuser/bb19c/ext

# Add bbuser to the user list
echo "`$VTS` : Adding the Big Brother user and group" | $LOG1

if [[ `grep bbuser /etc/passwd | wc -l` -eq 1 ]]; then
   groupadd -g 2521 bbuser 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   #usermod -g bbuser -p '\$1\$VZFP2KJe\$O09yiE9A7lKr9BNF.k/Rq0' bbuser
   usermod -g bbuser -p '$1$VZFP2KJe$O09yiE9A7lKr9BNF.k/Rq0' bbuser 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
else
   #useradd -u 2521 -d /home/bbuser -p '\$1\$VZFP2KJe\$O09yiE9A7lKr9BNF.k/Rq0' bbuser
   useradd -u 2521 -d /home/bbuser -p '$1$VZFP2KJe$O09yiE9A7lKr9BNF.k/Rq0' bbuser 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
fi
echo -n "   "; id bbuser 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
echo -n "   "; groups bbuser 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1

# Checking link and add log directory
echo ""
echo "Checking links..." 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
if [ -L /usr/log ] ; then 
   echo "   /usr/log is a link -- good" 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   echo "Making bb logging directory..." 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   mkdir /usr/log/bb 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   chmod 777 /usr/log/bb 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
else
   echo "   /usr/log is not a link to /var/log -- fix it and rerun this script! " 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   exit 1
fi

# Getting site info from user

# BB Site Info will be derrived from the /usr/eos/data/expcfg file
# and checked against /maint/scripts/sitelist.cfg

EXPCFG=/usr/eos/data/expcfg
#SITELIST=sitelist.cfg
SITELIST=/maint/scripts/sitelist.cfg


if [[ ! -s $EXPCFG ]]; then
   echo "Warning: site number has not been set.  Attempting to set it now..." 2>&1 | sed 's/^/'"`$VTS` :"'/g' | $LOG1
   if [[ ! -s $SITELIST ]]; then
      echo "Unable to locate the sitelist.cfg file. The site number can be set"
      echo "manually by writing it to $EXPCFG. Please set it and re-run this"
      echo "script."
      echo "`$VTS` : $SITELIST is not accessible, site number must be set manually" | $LOG1
      exit
   fi
   echo "Please choose a site number from the following list:"
   echo ""
   f_MakeSiteMenu $SITELIST


   VC1=NO
   while [[ $VC1 != YES ]]; do
      echo ""
      read -p "Please enter the site number: " SITENUM
      echo "`$VTS` : User Input [site number] provided answer \"$SITENUM\"" >> $LOGFILE
      if [[ -z `grep "^${SITENUM}:" $SITELIST` ]]; then
         echo "`$VTS` : Invalid User Input [site number] provided answer \"$SITENUM\"" >> $LOGFILE
         read -p "\"$SITENUM\" is not a valid selection. Press Enter to try again. " JUNK
         tput cuu1; tput el; tput cuu1; tput el
         unset SITENUM
      else
         VC1=YES
      fi
   
   done
else
   SITENUM=`cat $EXPCFG | awk '{print $NF}'`
   if [[ -s $SITELIST ]]; then
      if [[ -z `grep "^${SITENUM}:" $SITELIST` ]]; then
         echo "`$VTS` : Warning: $SITENUM does not match an entry in $SITELIST and may be invalid." | $LOG1
         echo ""
         sleep 4
      fi
   fi
fi
   
echo ""
echo "Setting site number to $SITENUM"
echo "`$VTS` : Setting site number to $SITENUM" | $LOG1

# Attempt to read the BU from the SSO so we don't have to prompt the user
if [[ -s /etc/sso ]] && [[ -n `grep "^BU=" /etc/sso` ]]; then
   BU=`grep "^BU=" /etc/sso | awk -F'=' '{print $2}'`
fi

if [[ -z $BU ]]; then

   echo ""
   echo "Which Business Unit owns the server?"
   echo ""
   echo "   1) Corporate (eitcorp)"
   echo "   2) Intercall (intercall)"
   echo "   3) WIC (wic)"
   echo "   4) WBS (wbs)"
   echo "   5) WAN (wan)"
   echo ""
   VC2=NO
   while [[ $VC2 != YES ]]; do
      read -p "Select 1-5: " BUNUM
      echo "`$VTS` : User Input [Business Unit 1=CORP 2=ITC 3=WIC 4=WBS 5=WAN] provided answer \"$BNUM\"" >> $LOGFILE
      if [[ $BUNUM -lt 1 ]] || [[ $BUNUM -gt 5 ]]; then
         echo "\"$BUNUM\" is not a valid choice, please select 1-5."
         echo "`$VTS` : Invalid User Input [Business Unit 1=CORP 2=ITC 3=WIC 4=WBS 5=WAN] provided answer \"$BNUM\"" >> $LOGFILE
            read -p "Press Enter to continue. " JUNK
         unset BUNUM
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      else
         VC2=YES
      fi
   
   done

   case $BUNUM in
   
      1) BU=eitcorp
         ;;
      2) BU=intercall
         ;;
      3) BU=wic
         ;;
      4) BU=wbs
         ;;
      5) BU=wan
         ;;
      *) echo "`$VTS` : Business Unit validation failure, please debug this script." | $LOG1
         exit
         ;;
   esac
fi


# Set up the BBHOSTS file

# If a bbohsts file already exists, remove it so the re-configured system will
# start in "off" mode
if [[ -f ~bbuser/bb/etc/bb-hosts ]]; then
   rm -f ~bbuser/bb/etc/bb-hosts
fi
BBHOSTFILE=~bbuser/bb/etc/bb-hosts.off
LIP=`f_FindPubIP`
LNAME=`hostname -s`
DSERVHN="bbserv${sitenum}.wic.west.com"
DSERVIP=`/usr/bin/host $DSERVHN | grep "has address" | awk '{print $NF}'`

if [[ -z $DSERVIP ]]; then
   DSERVHN=`grep ^${SITENUM}: $SITELIST | awk -F':' '{print $3}'`
   DSERVIP=`grep ^${SITENUM}: $SITELIST | awk -F':' '{print $4}'`
fi

echo "$DSERVIP $DSERVHN # BBNET BBDISPLAY BBPAGER http://$DSERVHN/ telnet" > $BBHOSTFILE
echo "$LIP $LNAME # telnet" >> $BBHOSTFILE

# Setting permissions on bbuser
cd /home
chown -R bbuser:bbuser ~bbuser

# Setting ACLs on bbuser

chmod -R u+w /home/bbuser/bb


# inittab is deprecated in RHEL6, and Big Brother will run fine with an rcscript instead
echo "`$VTS` : Installing rc script for Big Brother" | $LOG1
if [[ -z `grep 'Big Brother is now' /etc/inittab` ]]; then
   echo "# DO NOT ADD Big Brother to inittab" >> /etc/inittab
   echo "# Big Brother is now started/stopped with /etc/init.d/runbb" >> /etc/inittab
fi

# Create and activate the "runbb" initscript

cat << EOF > /etc/init.d/runbb
#!/bin/sh

# the following is the LSB init header
#
### BEGIN INIT INFO
# Provides: runbb
# Required-Start: network
# Required-Stop: network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: stop/start Big Brother daemon
# Description: This is a script for starting and stopping the Big Brother daemon
### END INIT INFO

# the following is chkconfig init header
#
# runbb:  stop/start bb daemon
#
# chkconfig: 345 99 01
# description:  This is a script for starting and stopping the runbb daemon
#

RUNASUSER=bbuser
export UEXEC="su \$RUNASUSER -c 'cd /home/bbuser/bb; ./runbb.sh start'"
export DEXEC="su \$RUNASUSER -c 'cd /home/bbuser/bb; ./runbb.sh stop'"
export BBHOSTS=/home/bbuser/bb/etc/bb-hosts

f_Usage() {

   echo "Usage: \$0 [start|stop|restart]"

}


f_Start () {

   echo "Starting \$0"
   if [[ ! -s \$BBHOSTS ]]; then
      echo ""
      echo "Big Brother has not been enabled yet."
      echo ""
      echo "Big Brother can usually be enabled by renaming:"
      echo ""
      echo "  \$BBHOSTS.off"
      echo "    TO"
      echo "  \$BBHOSTS"
      echo ""
   else
      echo \$UEXEC | /bin/bash
   fi
}

f_Stop () {

   if [[ ! -s \$BBHOSTS ]]; then
      echo "Big Brother is not enabled."
   else
      echo "Stopping \$0"
      echo \$DEXEC | /bin/bash

      # The runbb.sh script does not properly kill off nohup children,
      # the following logic will kill off anything owned by bbuser running with init as the ppid
      for p in \`ps -u \$RUNASUSER -o ppid,pid | awk '\$1 == 1 {print $2}'\`; do
         /bin/kill -9 \$p 2>&1 | > /dev/null
      done
   fi

}


if test \$# != 1; then
    f_Usage
fi
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
   restart) f_Stop
            f_Start
            RETVAL=\$?
            ;;
         *) f_Usage
            RETVAL=0
            ;;
esac
exit \$RETVAL


EOF
chmod 755 /etc/init.d/runbb

#/bin/cp /maint/scripts/rcscripts/runbb /etc/init.d/runbb
/sbin/chkconfig runbb on
/etc/init.d/runbb start 2>&1 | >> /dev/null
#end bb install
#echo ""
echo "`$VTS` : Big Brother installation has been completed." | $LOG1
exit 0
