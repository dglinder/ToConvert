#!/bin/sh

# Updated 20131217

# Configure DNS servers using nearest-neighbor logic
# Primary and Secondary will be chosen from Site-Specific DNS servers
# Tertiary will be chosen from between corporate DNS servers


###                        ###
###  PRELIMINARY SETTINGS  ###
###                        ###

# This is the default action the script will take without arguments
# Possible settings are PRETEND, UPDATE, or FORCE
# PRETEND - same as -P argument
#    will go through the motions and produce a report but will not update resolv.conf
#
# UPDATE - same as -C argument
#    will update resolv.conf using the safest settings and produce a report
#
# FORCE - same as -F argument
#    will ignore some safety checks and update resolv.conf with recommended settings, and produce a report


# ONLY CHANGE THIS VALUE IF YOU CAN'T RUN THE SCRIPT WITH ARGUMENTS, OTHERWISE JUST USE THE ARGUMENTS
DEFAULT_ACTION=PRETEND

SERVERLIST=/maint/scripts/dnsservers.txt
TEST_A_REC=west.com
TMPLST=/tmp/dlst.tmp
OPTTMP=/tmp/dopt.tmp
RESOLV=/etc/resolv.conf
RESOLVNEW=/etc/.resolv.conf.new
TS=`date +%Y%m%d%H%M%S`
RESOLVBAK=/etc/resolv.conf.${TS}
RESOLVBAKLAST=/etc/.resolv.conf.lastbackup

export TEST_A_REC

# Determine Operating System
OS=`uname -s`

f_CleanExit () {
   EC=$1
   #if [ -f "/tmp/pushscript.cmd" ]; then
   #   $RM -f "/tmp/pushscript.cmd"
   #fi
   exit $EC
}



# Define executables 
case $OS in 

   Linux ) NSLOOKUP=/usr/bin/nslookup
           GREP=/bin/grep
           RM=/bin/rm
           BC=/usr/bin/bc
           TIME=/usr/bin/time
           CAT=/bin/cat
           SORT=/bin/sort
           AWK=/bin/awk
           HEAD=/usr/bin/head
           TAIL=/usr/bin/tail
           EGREP=/bin/egrep
           SED=/bin/sed
           CP=/bin/cp
           MV=/bin/mv
           PS=/bin/ps
           WC=/usr/bin/wc
           CUT=/bin/cut
           WHICH=/usr/bin/which
           CHMOD=/bin/chmod
           HNAME=/bin/hostname
           IFCONFIG=/sbin/ifconfig
           NETSTAT=/bin/netstat

           if [ ! -x "$CP" ]; then
              if [ -n `find /opt/cosmos | grep /cp$` ]; then
                 CP=`find /opt/cosmos | grep /cp$`
              fi
           fi   


           # Special command switches
           NSLOOKUP_C="$NSLOOKUP -sil"
           ;;
     AIX ) NSLOOKUP=/usr/bin/nslookup
           GREP=/usr/bin/grep
           RM=/usr/bin/rm
           BC=/usr/bin/bc
           TIME=/usr/bin/time
           CAT=/usr/bin/cat
           SORT=/usr/bin/sort
           AWK=/usr/bin/awk
           HEAD=/usr/bin/head
           TAIL=/usr/bin/tail
           EGREP=/usr/bin/egrep
           SED=/usr/bin/sed
           CP=/usr/bin/cp
           MV=/usr/bin/mv
           PS=/usr/bin/ps
           WC=/usr/bin/wc
           CUT=/usr/bin/cut
           WHICH=/usr/bin/which
           CHMOD=/usr/bin/chmod
           HNAME=/usr/bin/hostname
           IFCONFIG=/etc/ifconfig
           NETSTAT=/usr/bin/netstat

           # Special command switches
           NSLOOKUP_C="$NSLOOKUP -sil"

           VER=`uname -v`
           REL=`uname -r`
           export VER
           if [ "$VER" = "4" ]; then
              echo ",FAILURE:UNSUPPORTED_OS_OR_VERSION-AIX${VER}.${REL}:EXIT_CODE_7"
              f_CleanExit 7
              exit
           fi
           if [ "$VER" = "5" ]; then
              if [ "$REL" = "1" ]; then
                 echo ",FAILURE:UNSUPPORTED_OS_OR_VERSION-AIX${VER}.${REL}:EXIT_CODE_7"
                 f_CleanExit 7
                 exit
              fi
              if [ "$REL" = "2" ]; then
                 echo ",FAILURE:UNSUPPORTED_OS_OR_VERSION-AIX${VER}.${REL}:EXIT_CODE_7"
                 f_CleanExit 7
                 exit
              fi
           fi

           ;;
   SunOS ) NSLOOKUP=/usr/sbin/nslookup
           GREP=/usr/bin/grep
           RM=/usr/bin/rm
           BC=/usr/bin/bc
           TIME=/usr/bin/time
           CAT=/usr/bin/cat
           SORT=/usr/bin/sort
           AWK=/usr/bin/awk
           HEAD=/usr/bin/head
           TAIL=/usr/bin/tail
           EGREP=/usr/bin/egrep
           SED=/usr/bin/sed
           CP=/usr/bin/cp
           MV=/usr/bin/mv
           PS=/usr/bin/ps
           WC=/usr/bin/wc
           CUT=/usr/bin/cut
           WHICH=/usr/bin/which
           CHMOD=/usr/bin/chmod
           HNAME=/usr/bin/hostname
           IFCONFIG=/usr/sbin/ifconfig
           NETSTAT=/usr/bin/netstat
           BASH=/usr/bin/bash

           # Special command switches
           if [ `uname -r` = 5.8 ]; then
              NSLOOKUP_C=$NSLOOKUP
           else
              NSLOOKUP_C="$NSLOOKUP -sil"
           fi
           ;;

       * ) echo ",FAILURE:UNSUPPORTED_OS_OR_VERSION-${OS}:EXIT_CODE_2"
           f_CleanExit 2
           exit
           ;;
esac


# Verify that the essential executables are all present and accounted for
REQ_BINS="$NSLOOKUP $GREP $RM $BC $TIME $CAT $SORT $AWK $HEAD $TAIL $EGREP $SED $CP $MV $PS $WC $CUT $WHICH $CHMOD $HNAME $IFCONFIG $NETSTAT"

# Solaris uniquely requires BASH
if [ "$OS" = "SunOS" ]; then
   REQ_BINS="$REQ_BINS $BASH"
fi

# Assume pre-check failure is false to start with - it'll be switched to TRUE for any single failure
PCF=FALSE
ML=
for REQ_BIN in $REQ_BINS; do

   if [ ! -x "$REQ_BIN" ]; then
      PCF=TRUE
      ML="$ML;$REQ_BIN"
   fi

done


if [ $PCF = TRUE ]; then 
   echo ",FAILURE:MISSING_REQUIRED_BINARY(s)[$ML]:EXIT_CODE_3"
   f_CleanExit 3
   exit
fi

# The Solaris version of /bin/sh is not compatible with this script, so
# if we encounter Solaris, we'll attempt to change the shebang and re-run
# the script with BASH
if [ "$OS" = "SunOS" ]; then

   # Define the temporary executable name
   SOLEX=/tmp/configure_dns_solaris.sh

   # Check to see if the shebang is already set to BASH
   $HEAD -1 $0 | $GREP $BASH 2>&1 >> /dev/null
   if [ $? != 0 ]; then
      # If not already set to BASH, then we'll need to write
      # out the new executable
      if [ -f $SOLEX ]; then $RM $SOLEX; fi

      # Escape all of the slashes in the BASH path string so we can use it with sed
      EBASH=`echo $BASH | $SED 's/\\//\\\\\//g'`

      # Use sed to replace the default shebang with BASH
      $SED "s/^#!\/bin\/sh/#!${EBASH}/" $0 > $SOLEX

      # Verify that we wrote a file and it isn't empty
      if [ -s $SOLEX ]; then
         # Make the new temp file executable
         $CHMOD +x $SOLEX

         # Execute the new script and capture it's exit code as EC
         $SOLEX
         EC=$?
 
         # Remove the temp script
         $RM $SOLEX
 
         # Exit with whatever code the temp script exited with
         exit $EC
      else
         echo ",FAILURE:FAILURE_TO_CREATE$SOLEX:EXIT_CODE_8"
         f_CleanExit 8
         exit
      fi
   fi
fi


# Export executable variables
export NSLOOKUP GREP RM BC TIME CAT SORT AWK HEAD TAIL EGREP SED CP MV PS WC CUT WHICH CHMOD HNAME NSLOOKUP_C IFCONFIG NETSTAT

###                            ###
###  END PRELIMINARY SETTINGS  ###
###                            ###

###                        ###
###  FUNCTION DEFINITIONS  ###
###                        ###


f_Usage () {

   echo "Usage: "
   echo "   $0 [-F|-P]"
   echo ""
   echo ""
   echo "   If run without arguments the script will run in pretend/read only mode"
   echo ""
   echo "   The script will automatically try to determine the best servers"
   echo "   based on the contents of /maint/scripts/dnsservers.txt"
   echo "   The format of the file must be:"
   echo "   <type> <DNS Server FQDN> <DNS Server IP>"
   echo ""
   echo "   Where:"
   echo "      <type> is either \"s\" for site-specific, or \"p\" for primary site"
   echo "      <DNS Server FQDN> is the fully qualified domain name of the DNS Server"
   echo "      <DNS Server IP> is the IP address of the server"
   echo ""
   echo "   The script will choose the two fastest-responding site servers as primary"
   echo "   and secondary servers, and the fastest of the primary site servers as a"
   echo "   tertiary."
   echo ""
   echo "   If the file is missing, hard-coded internal defaults will be used."
   echo ""
   echo "   By default the script will only replace DNS servers that it knows about."
   echo "   If the /etc/resolv.conf of a server has DNS servers that are not recognized"
   echo "   They will be left intact and in the same order as they originally appeared."
   echo ""
   echo "   If a server is not configured for DNS at all, the script will not attempt"
   echo "   to make any changes, as doing so may impact system performance."
   echo ""
   echo "   OPTIONS:"
   echo ""
   echo "   -F  FORCE override both safety catches: replace unknown servers in resolv.conf"
   echo "       with the recommended servers, and configure servers that are not"
   echo "       presently configured for DNS."
   echo ""
   echo "   -P  Pretend only - don't make updates, just show what updates would have"
   echo "       been made. (This is the default action)"
   echo ""
   echo "   -C  Change/update.  This will replace known legacy servers, preserve all existing"
   echo "       optional settings, and avoid configuring servers that don't already use DNS."
   echo ""


}


# Function to get average response time from a DNS server
# Usage: f_DNSAverageResponse <IP>
# Output: <average response time in seconds>
#            OR
#         -1 (DNS Service not found)
f_DNSAverageResponse () {

   unset DITC
   DITC=$1

   # Verify that we're even getting responses on port 53
   RESPONDS=NO
   if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
      if [[ -z `echo -e "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP 2>&1 | $EGREP -i "no response"` ]]; then
         RESPONDS=YES
      fi
   elif [[ `uname -s` == AIX ]] && [[ `uname -v` == 5 ]]; then
      if [[ -z `echo "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP 2>&1 | $EGREP -i "no response"` ]]; then
         RESPONDS=YES
      fi
   else
      if [[ -z `$NSLOOKUP_C west.com ${DITC} 2>&1 | $GREP "connection timed out"` ]]; then
         RESPONDS=YES
      fi
   fi

   if [[ $RESPONDS == YES ]]; then

      # make sure we're always dealing with fresh variables
      unset thistime totaltime average lasttime fastesttime
     
      #Set the number of subsequent times to check
      CHECKCOUNT=8
      CHECK=0
      while [[ $CHECK -lt $CHECKCOUNT ]]; do
      #for i in {1..4}; do

         # Adding a sleep here will greatly extend the running time of this script but may get us cleaner results
         #sleep 1

         # measure time with nmap
         #thistime=`/usr/bin/nmap -sU -p 53 $DITC 2>&1 | grep seconds | awk '{print $(NF-1)}'`

         # measure with time and nslookup
         # perform one lookup to get the entry in cache, so we're averaging raw response time
         if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
            echo -e "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP 2>&1 > /dev/null
            thistime=`{ time echo -e "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
         elif [[ `uname -s` == AIX ]] && [[ `uname -v` == 5 ]]; then
            echo "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP 2>&1 > /dev/null
            thistime=`{ time echo "set timeout=3\nset retries=2\nserver $DITC\nwest.com\nexit\n" | $NSLOOKUP; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
         else
            $NSLOOKUP_C  west.com $DITC 2>&1 > /dev/null
            thistime=`{ time $NSLOOKUP_C west.com ${DITC}; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
         fi

         # first time through, just assign thstime to totaltime
         if [[ -z $totaltime ]]; then
            totaltime=$thistime
         else
            totaltime=`echo "$totaltime + $thistime" | $BC -l`
         fi

         # Calculate the fastest response observed out of the sample
         if [[ -z $lasttime ]] || [[ $thistime < $lasttime ]]; then
            fastesttime=$thistime
         fi
        
         let CHECK=$CHECK+1

      done

      average=`echo "$totaltime / $CHECKCOUNT" | $BC -l | $CUT -b1-5`
      lasttime=$thistime

      #echo $average
      echo $totaltime
      #echo $fastesttime

   else
      # The server doesn't respond to DNS at all
      echo -1
   fi

}

#-----------------
# Function: f_ValidIPv4
#-----------------
# Checks a string to ensure it contains a valid
# ipv4 address
#-----------------
# Usage: f_ValidIPv4 <IP>
#-----------------
# Returns: TRUE, FALSE
f_ValidIPv4 () {

   IPv4=$1
   # Valid until proven otherwise
   RESULT=TRUE

   # Does it have 4 octets?
   if [[ `echo $IPv4 | $AWK -F'.' '{print NF}'` -ne 4 ]]; then
      RESULT=FALSE
   else
      # Look at each octet
      for o in `echo $IPv4 | $SED  's/\./ /g'`; do
         # Is the octet numeric?
         if [[ -z `echo $o | $EGREP "^[0-9]+$"` ]]; then
            RESULT=FALSE
         else
            # Is the octet less than 0 or greater than 255?
            if [[ $o -lt 0 ]] || [[ $o -gt 255 ]]; then
               RESULT=FALSE
            fi
         fi
      done
   fi
   echo $RESULT
}


###                            ###
###  END FUNCTION DEFINITIONS  ###
###                            ###


##############################
###                        ###
###  MAIN EXECUTION START  ###
###                        ###
##############################

############################################################################
###################
### DNS NOMINATION


###                        ###
###     READ ARGUMENTS     ###
###                        ###

# The default action is pretend - this is to prevent accidental modification of a system
ACTION=$DEFAULT_ACTION

if [[ -n "$1" ]]; then
   if [[ "$1" == "-C" ]]; then
      ACTION=UPDATE
   elif [[ "$1" == "-F" ]]; then
      ACTION=FORCE
   elif [[ "$1" == "-P" ]]; then
      ACTION=PRETEND
   else
      f_Usage
      exit 5
   fi
fi

###                        ###
###   END READ ARGUMENTS   ###
###                        ###

###                       ###
###  CHECK CURRENT STATE  ###
###                       ###

# First need to see if this server is even configured for DNS
USEDNS=NO
if [[ -s "$RESOLV" ]] && [[ -n `$EGREP -v "^.*#" $RESOLV | $EGREP "nameserver"` ]]; then
   USEDNS=YES
fi


###                           ###
###  END CHECK CURRENT STATE  ###
###                           ###



###                                ###
###     CHECK UPDATE POTENTIAL     ###
###                                ###

# Verify whether resolv.conf is writeable
if [[ ! -w "$RESOLV" ]]; then
   WRITABLE=NO

   # If we're doing a "pretend" operation, this isn't such a big deal
   # but if we're doing an update operation, we're going to exit with a failure code
   if [[ $ACTION == UPDATE ]] || [[ $ACTION == FORCE ]]; then
      echo ",FAILURE:RESOLV.CONF NOT WRITABLE BY USER $USER:EXIT_CODE_9"
      f_CleanExit 9
      exit
   fi


else
   WRITABLE=YES

fi

if [[ "$USEDNS" == "NO" ]] && [[ "$ACTION" != "FORCE" ]]; then
   echo ",FAILURE:SERVER DOES NOT USE DNS:EXIT_CODE_13"
   f_CleanExit 13
   exit
fi

###                                    ###
###     END CHECK UPDATE POTENTIAL     ###
###                                    ###


###                      ###
###  READ/SET VARIABLES  ###
###                      ###


# This is a list of servers that need to be removed from
# resolv.conf
#LEGACY_IPLIST="172.30.9.151 172.30.94.108 172.30.41.227 10.28.101.26 216.57.98.32 216.57.106.45 216.57.106.46 216.57.98.33 216.57.102.97 216.57.102.98 216.57.106.48 216.57.106.49 216.57.102.95 216.57.102.96 216.57.110.24 216.57.110.25 216.57.102.42 10.28.101.40 10.28.101.41 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 172.30.41.224 172.30.41.225 172.30.8.24 172.30.8.25 172.30.8.204 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15 192.168.12.14 192.168.12.15"

LEGACY_IPLIST="10.0.0.210 10.0.14.100 10.0.35.210 10.19.124.23 10.28.101.26 10.28.101.40 10.28.101.41 10.51.254.102 10.62.21.10 10.62.21.20 10.62.220.2 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 10.70.192.22 10.70.71.68 172.30.41.224 172.30.41.225 172.30.41.227 172.30.8.204 172.30.8.24 172.30.8.25 172.30.9.151 172.30.9.228 172.30.94.108 172.30.94.116 192.168.12.14 192.168.12.15 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15"

#LEGACY_TER="10.62.21.10 10.62.21.20 172.30.9.151 172.30.94.108"
LEGACY_TER="10.0.0.210 10.0.14.100 10.0.35.210 10.19.124.23 10.28.101.26 10.28.101.40 10.28.101.41 10.51.254.102 10.62.21.10 10.62.21.20 10.62.220.2 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 10.70.192.22 10.70.71.68 172.30.41.224 172.30.41.225 172.30.41.227 172.30.8.204 172.30.8.24 172.30.8.25 172.30.9.151 172.30.9.228 172.30.94.108 172.30.94.116 192.168.12.14 192.168.12.15 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15"

# Default values - this is a fallback in case everything else fails
D_PRIMARY="10.19.119.82"
D_SECONDARY="10.19.119.83"
D_TERTIARY="10.17.126.43"
D_SEARCH="wic.west.com icallinc.com one.west.com"


# Try to see if we have a serverlist - that will be the preferred method
#echo "Looking for $SERVERLIST"

if [[ -s $SERVERLIST ]]; then
   PRIMARY_IPLIST=`grep ^p $SERVERLIST | awk '{print $3}'`
   SS_IPLIST=`grep ^s $SERVERLIST | awk '{print $3}'`
#else
#   echo "      not found, using defaults"
fi


# If we don't have these populated, then fall back on static values
if [[ -z $PRIMARY_IPLIST ]]; then
   PRIMARY_IPLIST="10.19.119.82 10.19.119.83"
fi

if [[ -z $SS_IPLIST ]]; then
   SS_IPLIST="10.28.101.51 10.28.101.52 10.70.1.60 10.70.1.61 10.17.126.43 10.17.126.44 10.64.10.152 10.64.10.153 10.166.128.52 10.166.128.53"
fi


###                          ###
###  END READ/SET VARIABLES  ###
###                          ###



###                                ###
###  CALCULATE RECOMMENDED CONFIG  ###
###                                ###

# Determine primary and secondary servers 
#echo "Negotiating best Site-Specific DNS servers."
#echo ""

# Remove any previous version of TMPLST
if [[ -f $TMPLST ]]; then $RM $TMPLST; fi

for s in $SS_IPLIST; do
#   echo "Checking server $s"
   # Make sure the server actually responds to dns requests
   RESPONDS=NO
   if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
      if [[ -z `echo -e "set timeout=3\nset retries=2\nserver $s\n$TEST_A_REC\nexit\n" | $NSLOOKUP 2>&1 | grep -i "no response"` ]]; then
         RESPONDS=YES
      fi
   else
      if [[ -z `$NSLOOKUP_C $TEST_A_REC ${s} 2>&1 | $GREP "connection timed out"` ]]; then
         RESPONDS=YES
      fi
   fi

   if [[ $RESPONDS == YES ]]; then
      # Add the server to the validated version of the list
      V_SS_IPLIST="$V_SS_IPLIST,$s,"
      # Collect the lookup data (may not be average, but will be sortable just the same
      time=`f_DNSAverageResponse $s`
      if [[ $time != -1 ]]; then

         # If we got a valid response time for the server, then add it to the TMPLST
         echo "$s,$time" >> $TMPLST
      fi
   fi

done

if [[ ! -s $TMPLST ]]; then
   echo ",FAILURE:NO_REACHABLE_PRIMARY_SECONDARY:EXIT_CODE_6"
   f_CleanExit 6
   exit
fi

#Use sort to grab the two fastest servers from the list
PRIMARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -1 | $AWK -F',' '{print $1}'`
SECONDARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 | head -2 | $TAIL -1 | $AWK -F',' '{print $1}'`
$RM $TMPLST

# Now pick a tertiary from the list of primary DNS servers
#echo "Negotiating best Tertiary DNS server."
#echo ""

for p in $PRIMARY_IPLIST; do
   # Make sure the server actually responds to DNS requests
   if [[ -z `$NSLOOKUP_C $TEST_A_REC $p 2>&1 | $GREP -i "connection timed out"` ]]; then
      # Add to valid list
      V_PRIMARY_IPLIST="$V_PRIMARY_IPLIST,$p,"
      # Collect response times
      time=`f_DNSAverageResponse $p`
      echo "$p,$time" >> $TMPLST
   fi

done

if [[ ! -s $TMPLST ]]; then
   echo ",FAILURE:NO_REACHABLE_TERTIARY:EXIT_CODE_60"
   f_CleanExit 6
   exit
fi

TERTIARY=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -1 | $AWK -F',' '{print $1}'`
$RM $TMPLST

# Verify that the value we pulled out of the TMPLST is a valid IP address
# Different systems may handle certain syntax differently

EP_VALID=`f_ValidIPv4 $PRIMARY_SS`
ES_VALID=`f_ValidIPv4 $SECONDARY_SS`
ET_VALID=`f_ValidIPv4 $TERTIARY`

if [[ "$EP_VALID" != "TRUE" ]] || [[ "$ES_VALID" != "TRUE" ]] || [[ "$ET_VALID" != "TRUE" ]]; then
   echo ",FAILURE:INVALID SERVER ADDRESSES REPORTED BY ELECTION EP=\"$PRIMARY_SS\" ES=\"$SECONDARY_SS\" ET=\"$TERTIARY\":EXIT_CODE_14"
   f_CleanExit 14
   exit
fi



# Check against hardware list

# Set a general deviation flag for easy identification
DEVIATE=NO

# Set this server's hostname
THN=`$HNAME | $AWK -F'.' '{print $1}'`

# Get the location by hostname
THLOC=`$GREP -i "^##@NIBU@##${THN}," $0 | $AWK -F',' '{print $4}'`

# Attempt to set the location by IP
TGW=`$NETSTAT -rn | $EGREP "^0.0.0.0|^default" | $AWK '{print $2}'`
if [ "$TGW" = "0.0.0.0" ]; then
   if [ -f /etc/sysconfig/network ]; then
      if [ -n `$GREP "^GATEWAY=" /etc/sysconfig/network` ]; then
         TGW=`$GREP "^GATEWAY=" /etc/sysconfig/network | $AWK -F'=' '{print $2}'`
      fi
   fi
fi
TNWP=`echo $TGW | $AWK -F'.' '{print $1"."$2"."$3"."}'`
TIP=`$IFCONFIG -a | $GREP $TNWP | $AWK '{print $2}' | $SED 's/^addr://' | $HEAD -1`
TILOC=`$GREP ",${TIP}," $0 | $GREP "^##@NIBU@##" | $AWK -F',' '{print $4}' | $HEAD -1`

# See if the locationi by hostname and location by ip match
HWDBMATCH=NO
if [[ -n $THLOC ]] && [[ -n $TILOC ]]; then
   if [[ -n `echo $THLOC | $GREP -i "^${TILOC}$"` ]]; then
      HWDBMATCH=YES
   fi
else
   HDBMATCH=N/A
fi


# if location is not found, set it to unknown
if [[ -z $THLOC ]]; then
   THLOC=UNK
   THBU=UNK
else
   THBU=`$GREP -i "^##@NIBU@##${THN}," $0 | $AWK -F',' '{print $3}' | $HEAD -1`
fi

if [[ -z $TILOC ]]; then
   TILOC=UNK
   TIBU=UNK
else
   TIBU=`$GREP ",${TIP}," $0 | $GREP "^##@NIBU@##" | $AWK -F',' '{print $3}' | $HEAD -1`
fi


PLOC=`$GREP "^##@NSSC@##${PRIMARY_SS}," $0 | $AWK -F',' '{print $2}'`
SLOC=`$GREP "^##@NSSC@##${SECONDARY_SS}," $0 | $AWK -F',' '{print $2}'`

# See if the (either of) the server's site(s) in the hw database has a SS dns server
SWS='^ATL01$|^SWN01$|^DEN01$|^DEN06$|^OMA10$|^LON13$'
if [[ -n `echo $THLOC | $EGREP -i "$SWS"` ]] || [[ -n `echo $TILOC | $EGREP -i "$SWS"` ]]; then
   HASL=YES
   # Verify that the elected servers are the proper ones for this server according to it's location
   # in the hw database either by hostname or IP
   if [[ -n `echo $PLOC | $EGREP -i "^${THLOC}$|^${TILOC}$"` ]]; then
      PMATCH=MATCH
   else
      PMATCH=MISMATCH
      DEVIATE=YES
   fi

   if [[ -n `echo $SLOC | $EGREP -i "^${THLOC}$|^${TILOC}$"` ]]; then
      SMATCH=MATCH
   else
      SMATCH=MISMATCH
      DEVIATE=YES
   fi

else
   # If there is no local/site specific dns server then matching is not necessary
   HASL=NO
   PMATCH=N/A
   SMATCH=N/A
fi

### DNS NOMINATION
###################
############################################################################


############################################################################
###################
### HOST ANALYSIS

###                        ###
###  GET CURRENT SETTINGS  ###
###                        ###

# If the server currently uses DNS, read the current values.
if [[ "$USEDNS" == "YES" ]]; then
   # Read the current configuration - options will be handled separately during the update process
   C_SEARCH=`$EGREP -v "^#" $RESOLV | $EGREP "^.*search" | $SED "s/^.*search[ \t]//"`
   C_DOMAIN=`$EGREP -v "^#" $RESOLV | $EGREP "^.*domain" | $SED "s/^.*domain[ \t]//"`

   # For DNS resolver addresses, we need to determine how many are being used to accurately set the variables
   RESOLVER_COUNT=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | wc -l`
   C_PRIMARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -1`

   if [[ $RESOLVER_COUNT -ge 2 ]]; then
      C_SECONDARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -2 | tail -1`
      if [[ $RESOLVER_COUNT -ge 3 ]]; then
         C_TERTIARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -3 | tail -1`
      fi
   fi

fi

###                            ###
###  END GET CURRENT SETTINGS  ###
###                            ###

### HOST ANALYSIS
###################
############################################################################

############################################################################
###################
### EXECUTE AND REPORT


###                          ###
###   DECIDE NEW RESOLVERS   ###
###                          ###

# Only servers we know about will be replaced 
META_IPLIST="$LEGACY_IPLIST $SS_IPLIST $PRIMARY_IPLIST"

# If we successfully elected a primary and...
  #  the result we got back is definitely an IP address and...
    # either there was no existing primary or the existing primary is on or list of servers to remove...
if [[ -n $PRIMARY_SS ]] && [[ `f_ValidIPv4 $PRIMARY_SS` != FALSE ]] && ( [[ -z $C_PRIMARY ]] || [[ -n `echo $META_IPLIST | grep $C_PRIMARY` ]] ); then
   # If the server has a local server and its BU is WIC then we'll force it to use the local server
   # regardless of the election process
   if [[ $HASL == YES ]] && ([[ "$THBU" == "WIC" ]] || [[ "$TIBU" == "WIC" ]]); then

      N_PRIMARY=`$GREP "^##@NSSC@##" $0 | $SED 's/^##@NSSC@##//g' | $AWK -F',' -v L=$TILOC '{if($2==L) print $1}' | $HEAD -1`

      if [[ -z $N_PRIMARY ]]; then
      
         N_PRIMARY=`$GREP "^##@NSSC@##" $0 | $SED 's/^##@NSSC@##//g' | $AWK -F',' -v L=$THLOC '{if($2==L) print $1}' | $HEAD -1`

      fi

      # Since we're bypassing the algorithm for WIC, it's no longer safe to assume that the elected server is reachable
      if [[ -z `echo $V_SS_IPLIST | egrep ",$N_PRIMARY,|,$N_PRIMARY$"` ]]; then
         echo ",FAILURE:WIC SITE OVERRIDE ($TILOC) SERVER $N_PRIMARY NOT REACHABLE:EXIT_CODE_10"
         f_CleanExit 10
         exit

      fi
   
   else
      N_PRIMARY=$PRIMARY_SS
   fi
else
   N_PRIMARY=$C_PRIMARY
fi


# Negotiate Secondary
if [[ -n $SECONDARY_SS ]] && [[ `f_ValidIPv4 $SECONDARY_SS` != FALSE ]] && ( [[ -z $C_SECONDARY ]] || [[ -n `echo $META_IPLIST | grep $C_SECONDARY` ]] ); then
   # If the server has a local server and its BU is WIC then we'll force it to use the local server
   # regardless of the election process
   if [[ $HASL == YES ]] && ([[ "$THBU" == "WIC" ]] || [[ "$TIBU" == "WIC" ]]); then

      N_SECONDARY=`$GREP "^##@NSSC@##" $0 | $SED 's/^##@NSSC@##//g' | $AWK -F',' -v L=$TILOC '{if($2==L) print $1}' | $TAIL -1`
      if [[ -z $N_SECONDARY ]]; then
      
         N_SECONDARY=`$GREP "^##@NSSC@##" $0 | $SED 's/^##@NSSC@##//g' | $AWK -F',' -v L=$THLOC '{if($2==L) print $1}' | $TAIL -1`

      fi

      # Since we're bypassing the algorithm for WIC, it's no longer safe to assume that the elected server is reachable
      if [[ -z `echo $V_SS_IPLIST | egrep ",$N_SECONDARY,|,$N_SECONDARY$"` ]]; then
         echo ",FAILURE:WIC SITE OVERRIDE ($TILOC) SERVER $N_SECONDARY NOT REACHABLE:EXIT_CODE_10"
         f_CleanExit 10
         exit

      fi


   else
      N_SECONDARY=$SECONDARY_SS
   fi
else
   N_SECONDARY=$C_SECONDARY
fi


# Negotiate Tertiary - if the intercall server(s) "LEGACY_TER" is tertiary, it will be replaced
if [[ -n $TERTIARY ]] && [[ `f_ValidIPv4 $TERTIARY` != FALSE ]] && ( [[ -z $C_TERTIARY ]] || [[ -n `echo $META_IPLIST | grep $C_TERTIARY` ]] || [[ -n `echo $LEGACY_TER | grep  "$C_TERTIARY"` ]] ); then
   N_TERTIARY=$TERTIARY
else
   N_TERTIARY=$C_TERTIARY
fi

###                          ###
###   DECIDE NEW RESOLVERS   ###
###                          ###

###                                      ###
###   EXECUTE ACTION / GENERATE CONFIG   ###
###                                      ###

#if [[ $ACTION == PRETEND ]]; then
#   RESOLVBAK_S=N/A
#   UPDATE_GENERATED=NO
#   
#elif [[ $ACTION == UPDATE ]]; then
if [[ $ACTION == UPDATE ]] || [[ $ACTION == PRETEND ]]; then
   
   # Check to see if we actually need to update anything - if the new pri, sec, ter are the same as current, then we don't
   if [[ "$N_PRIMARY" == "$C_PRIMARY" ]] && [[ "$N_SECONDARY" == "$C_SECONDARY" ]] && [[ "$N_TERTIARY" == "$C_TERTIARY" ]]; then
      RESOLVBAK_S=N/A
      UPDATE_GENERATED=NO
   else
      if [[ $WRITABLE == YES ]]; then
         # Preserve any options that may have been set
         if [[ -n `$EGREP -v "^#" $RESOLV | $EGREP "^.*options"` ]]; then
            $EGREP -v "^#" $RESOLV | $EGREP "^.*options" > $OPTTMP
         fi
   
         # Clear out any previous "new" files that didn't get cleaned up
         if [[ -f ${RESOLVNEW} ]]; then echo > ${RESOLVNEW}; fi
      
         # Add a domain line if the server originally had one
         if [[ -n $C_DOMAIN ]]; then
            echo "domain $C_DOMAIN" >> ${RESOLVNEW}
         fi
   
         # Add a search line.  Use the default if the server did not have one to begin with.
         if [[ -n $C_SEARCH ]]; then
            echo "search $C_SEARCH" >> ${RESOLVNEW}
         else
            echo "search $D_SEARCH" >> ${RESOLVNEW}
         fi
   
         # Add primary server
         echo "nameserver $N_PRIMARY" >> ${RESOLVNEW}
   
         # Add secondary server IF we have one
         if [[ -n $N_SECONDARY ]]; then
            echo "nameserver $N_SECONDARY" >> ${RESOLVNEW}
         fi
   
         # Add tertiary server IF we have one
         if [[ -n $N_TERTIARY ]]; then
            echo "nameserver $N_TERTIARY" >> ${RESOLVNEW}
         fi
   
         # Add in any options that were present in the original file
         if [[ -s $OPTTMP ]]; then
            $CAT $OPTTMP >> ${RESOLVNEW}
            $RM "$OPTTMP"
         fi
   
         # The new config has been generated      
   
         # Updated will be set to yes here, but may still be switched back to no
         # if the update fails for some reason, such as backup failure, etc...
         if [[ -s "${RESOLVNEW}" ]]; then
            UPDATE_GENERATED=YES
         else
            UPDATE_GENERATED=NO
         fi

      else
         UPDATE_GENERATED=NO
      fi
   fi

elif [[ $ACTION == FORCE ]]; then

   # Check to see if we actually have enough data to forcibly update
   if ([[ -n $PRIMARY_SS ]] && [[ `f_ValidIPv4 $PRIMARY_SS` != FALSE ]]) && ([[ -n $SECONDARY_SS ]] && [[ `f_ValidIPv4 $SECONDARY_SS` != FALSE ]]) && ([[ -n $TERTIARY ]] && [[ `f_ValidIPv4 $TERTIARY` != FALSE ]]); then

      if [[ $WRITABLE == YES ]]; then
         # Preserve any options that may have been set
         if [[ -n `$EGREP -v "^#" $RESOLV | $EGREP "^.*options"` ]]; then
            $EGREP -v "^#" $RESOLV | $EGREP "^.*options" > $OPTTMP
         fi
   
         # Clear out any previous "new" files that didn't get cleaned up
         if [[ -f ${RESOLVNEW} ]]; then echo > ${RESOLVNEW}; fi
   
         # Add a domain line if the server originally had one
         if [[ -n $C_DOMAIN ]]; then
            echo "domain $C_DOMAIN" >> ${RESOLVNEW}
         fi
   
         # Add a search line.  Use the default if the server did not have one to begin with.
         if [[ -n $C_SEARCH ]]; then
            echo "search $C_SEARCH" >> ${RESOLVNEW}
         else
            echo "search $D_SEARCH" >> ${RESOLVNEW}
         fi
   
         # Add primary server
         echo "nameserver $PRIMARY_SS" >> ${RESOLVNEW}
   
         # Add secondary server 
         echo "nameserver $SECONDARY_SS" >> ${RESOLVNEW}
   
         # Add tertiary server IF we have one
         echo "nameserver $TERTIARY" >> ${RESOLVNEW}

         # Add in any options that were present in the original file
         if [[ -s $OPTTMP ]]; then
            $CAT $OPTTMP >> ${RESOLVNEW}
            $RM "$OPTTMP"
         fi
   
         # The new config has been generated

         # Updated will be set to yes here, but may still be switched back to no
         # if the update fails for some reason, such as backup failure, etc...
         if [[ -s "${RESOLVNEW}" ]]; then
            UPDATE_GENERATED=YES
         else
            UPDATE_GENERATED=NO
         fi
      else
         UPDATE_GENERATED=NO
      fi

   else

      RESOLVBAK_S=N/A
      UPDATE_GENERATED=NO

   fi

else

   UPDATED=NO


fi

###                                          ###
###   END EXECUTE ACTION / GENERATE CONFIG   ###
###                                          ###

###                                 ###
###  BACKUP OLD/INSTALL NEW CONFIG  ###
###                                 ###

if [[ $ACTION == UPDATE ]] || [[ $ACTION == FORCE ]]; then

   if [[ $UPDATE_GENERATED == NO ]]; then

      UPDATE_NEEDED=NO

   else

      UPDATE_NEEDED=YES

      # Back up the previous resolv.conf
      $CP ${RESOLV} ${RESOLVBAK}

      # Create non-dated "most recent" backup file for rapid rollback
      $CP ${RESOLV} ${RESOLVBAKLAST}
   
      # If the backup file was not written for any reason, then abort
      if [[ ! -s ${RESOLVBAK} ]] || [[ ! -s ${RESOLVBAKLAST} ]]; then
         UPDATED=NO
      elif [[ ! -s ${RESOLVNEW} ]]; then
         UPDATED=FAILED-no-update-generated
      else
   
         RESOLVBAK_S=$RESOLVBAK
         # Replace the old config with the new one
         $MV ${RESOLVNEW} ${RESOLV}
         if [[ "$?" == "0" ]]; then
            UPDATED=YES
          
   
            # If performing an update, make sure we restart/reload any DNS caching daemons
            # to ensure that the changes are picked up.
   
            if [[ "$OS" == "Linux" ]]; then
               if [[ -n `$PS --no-header -C nscd -o pid` ]]; then
                  /etc/init.d/nscd reload 2>&1 > /dev/null
               fi
            fi
         
            if [[ "$OS" == "AIX" ]]; then
               if [[ -n `/usr/bin/lssrc -s netcd | grep "active"` ]]; then
                  /usr/bin/stopsrc -s netcd 2>&1 > /dev/null
                  sleep 10
                  /usr/bin/startsrc -s netcd 2>&1 > /dev/null
               fi
            fi
         
            if [[ "$OS" == "SunOS" ]]; then
               if [[ -n `$PS -ef -o comm | grep "/nscd$"` ]]; then
                  /etc/init.d/nscd stop 2>&1 > /dev/null
                  /etc/init.d/nscd start 2>&1 > /dev/null
               fi
            fi
         else
            UPDATED=NO
         fi
      fi
   fi
else
   if [[ -f ${RESOLVNEW} ]]; then
      $RM "$RESOLVNEW"
   fi
   UPDATE_NEEDED=N/A
   UPDATED=NO
fi

###                                     ###
###  END BACKUP OLD/INSTALL NEW CONFIG  ###
###                                     ###

###                    ###
###   OUTPUT REPORT    ###
###                    ###

# THN = This server's reported hostname
# THBU = This server's BU based on the hostname found in the hardware database
# THLOC = This server's site location based on hostname found in the hardware database
# TIP = This server's reported primary IP (determined by comparison to default gateway)
# TILOC = This server's site location based on the IP found in the hardware database
# TIBU = This server's BU based on the IP found in the hardware database
# HWDBMATCH = (YES|NO) This server was found in the hardware database by either IP, hostname, or both
# PRIMARY_SS = This is the primary DNS server selected by the election process
# PLOC = This is the site location of the primary DNS server selected by the election process
# SECONDARY_SS = This is the secondary DNS server selected by the election process
# SLOC = This is the location of the secondary DNS server selected by the election process
# TERTIARY = This is the tertiary server selected by the election process
# HASL = (YES|NO) This server's location (either THLOC or TILOC) has a local DNS server
# PMATCH = (MATCH|MISMATCH|N/A) The primary server elected matches (either THLOC or TILOC) - N/A if HASL is "NO"
# SMATCH = (MATCH|MISMATCH|N/A) The secondary server elected matches the site (either THLOC or TILOC) - N/A if HASL is "NO"
# DEVIATE = (YES|NO) The servers's location has local DNS but it wasn't elected
# OS = The OS type of the server
# USEDNS = (YES|NO) Is the server currently configured to use DNS
# C_PRIMARY = the current primary DNS resolver for the server
# C_SECONDARY = the current secondary DNS resolver for the server 
# C_TERTIARY = the current tertiary DNS resolver for the server
# N_PRIMARY = the primary server that will/would be acutally used - if the current primary is unrecognized it won't be replaced
# N_SECONDARY = the secondary server that will/would be acutally used - if the current secondary is unrecognized it won't be replaced
# N_TERTIARY = the tertiary server that will/would be acutally used - if the current tertiary is unrecognized it won't be replaced
# ACTION = (PRETEND|UPDATE|FORCE)
# UPDATED = (YES|NO) set to No if pretending or if the update action did not change anything
# RESOLVBAK_S = the name of the backup file containing the old resolv.conf (N/A if not modifying or forcing a server with no previous config)
# UPDATE_NEEDED = (YES|NO|N/A) whether the update is needed or if the server is already using current settings will be N/A for PRETEND
# UPDATE_GENERATED = (YES|NO) was an update file generated?

echo ",${THN},${TIP},${OS},${THBU},${TIBU},${THLOC},${TILOC},${HWDBMATCH},${HASL},${USEDNS},${ACTION},${PRIMARY_SS},${PLOC},${SECONDARY_SS},${SLOC},${TERTIARY},${PMATCH},${SMATCH},${DEVIATE},${N_PRIMARY},${N_SECONDARY},${N_TERTIARY},${RESOLVBAK_S},${UPDATE_NEEDED},${UPDATE_GENERATED},${UPDATED}"


### EXECUTE AND REPORT
###################
############################################################################


f_CleanExit
exit

##@NSSC@##10.28.101.51,ATL01
##@NSSC@##10.28.101.52,ATL01
##@NSSC@##10.64.10.152,SWN01
##@NSSC@##10.64.10.153,SWN01
##@NSSC@##10.29.103.50,DEN01
##@NSSC@##10.29.103.51,DEN01
##@NSSC@##10.70.1.60,DEN06
##@NSSC@##10.70.1.61,DEN06
##@NSSC@##10.17.126.43,OMA10
##@NSSC@##10.17.126.44,OMA10
##@NSSC@##10.166.128.52,LON13
##@NSSC@##10.166.128.53,LON13
   
##@NIBU@##atl01hmc1,10.28.124.36,EIT,ATL01
##@NIBU@##atlprogdhcp,10.62.198.10,ITC,ATL07
##@NIBU@##bcuadmin001,10.27.60.23,WIC,OMA00
##@NIBU@##bcuadmin002,10.27.60.26,WIC,OMA00
##@NIBU@##bcuetl001,10.27.60.36,WIC,OMA00
##@NIBU@##bcuetl002,10.27.60.38,WIC,OMA00
##@NIBU@##bcuetl003,10.27.60.40,WIC,OMA00
##@NIBU@##bcuetl004,10.27.60.42,WIC,OMA00
##@NIBU@##bcumgmt001,10.27.60.21,WIC,OMA00
##@NIBU@##cc-bb,10.62.233.23,ITC,OMA01
##@NIBU@##centost,10.70.64.100,ITC,DEN06
##@NIBU@##den06-cuc02-pri,10.72.8.48,ITC,DEN06
##@NIBU@##den06-cuc02-sec,10.72.8.49,ITC,DEN06
##@NIBU@##den06-cucm02-pub01,10.72.8.50,ITC,DEN06
##@NIBU@##den06-cucm02-sub01,10.72.8.51,ITC,DEN06
##@NIBU@##den06esx63,10.72.7.21,ITC,DEN06
##@NIBU@##den06esx64,10.72.7.22,ITC,DEN06
##@NIBU@##den06esx65,10.72.7.23,ITC,DEN06
##@NIBU@##den06esx66,10.72.7.24,ITC,DEN06
##@NIBU@##den06esx67,10.72.7.25,ITC,DEN06
##@NIBU@##den06esx68,10.72.7.26,ITC,DEN06
##@NIBU@##den06esx69,10.72.7.27,ITC,DEN06
##@NIBU@##den06esx70,10.72.7.28,ITC,DEN06
##@NIBU@##den06esx71,10.72.7.29,ITC,DEN06
##@NIBU@##Den06esx72,10.70.65.64,EIT,DEN06
##@NIBU@##DEN06FTP,10.72.181.41,ITC,DEN06
##@NIBU@##DEN06GVS101,10.72.178.71,ITC,DEN06
##@NIBU@##DEN06GVS102,10.72.178.72,ITC,DEN06
##@NIBU@##DEN06GVS103,10.72.178.73,ITC,DEN06
##@NIBU@##DEN06GVS104,10.72.178.74,ITC,DEN06
##@NIBU@##DEN06GVS105,10.72.178.75,ITC,DEN06
##@NIBU@##DEN06GVS106,10.72.178.76,ITC,DEN06
##@NIBU@##DEN06GVS107,10.72.178.77,ITC,DEN06
##@NIBU@##DEN06GVS108,10.72.178.78,ITC,DEN06
##@NIBU@##DEN06GVS109,10.72.178.79,ITC,DEN06
##@NIBU@##DEN06GVS110,10.72.178.80,ITC,DEN06
##@NIBU@##DEN06GVS111,10.72.178.81,ITC,DEN06
##@NIBU@##DEN06GVS112,10.72.178.82,ITC,DEN06
##@NIBU@##DEN06GVS113,10.72.178.83,ITC,DEN06
##@NIBU@##DEN06GVS114,10.72.178.84,ITC,DEN06
##@NIBU@##DEN06GVS115,10.72.178.85,ITC,DEN06
##@NIBU@##DEN06GVS116,10.72.178.86,ITC,DEN06
##@NIBU@##DEN06GVS117,10.72.178.87,ITC,DEN06
##@NIBU@##DEN06GVS118,10.72.178.88,ITC,DEN06
##@NIBU@##DEN06GVS119,10.72.178.89,ITC,DEN06
##@NIBU@##DEN06GVS120,10.72.178.90,ITC,DEN06
##@NIBU@##den06hmc1,10.70.1.11,ITC,DEN06
##@NIBU@##den06hmc2,10.72.212.43,ITC,DEN06
##@NIBU@##den06mom01,10.70.1.15,EIT,DEN06
##@NIBU@##den06pasr58,10.18.154.16,WIC,OMA11
##@NIBU@##DEN06TDB101,10.72.178.35,ITC,DEN06
##@NIBU@##DEN06TDB102,10.72.178.36,ITC,DEN06
##@NIBU@##DEN06TDB103,10.72.178.37,ITC,DEN06
##@NIBU@##DEN06TDB104,10.72.178.38,ITC,DEN06
##@NIBU@##eitlinux1885,10.70.0.137,WIC,DEN06
##@NIBU@##Engineering Image1 Server,n/a,EIT,OMA00
##@NIBU@##Engineering Image2 Server,n/a,EIT,OMA00
##@NIBU@##Engineering Image3 Server,n/a,EIT,OMA00
##@NIBU@##Engineering Image4 Server,n/a,EIT,OMA00
##@NIBU@##eos1,10.29.119.20,WIC,DEN01
##@NIBU@##eos10,10.29.119.36,WIC,DEN01
##@NIBU@##eos1000,172.30.43.101,WIC,DEN01
##@NIBU@##eos1001,172.30.43.102,WIC,DEN01
##@NIBU@##eos1002,172.30.43.103,WIC,DEN01
##@NIBU@##eos1003,172.30.43.104,WIC,DEN01
##@NIBU@##eos1004,172.30.43.105,WIC,DEN01
##@NIBU@##eos1005,172.30.43.106,WIC,DEN01
##@NIBU@##eos1006,172.30.43.107,WIC,DEN01
##@NIBU@##eos1007,172.30.43.108,WIC,DEN01
##@NIBU@##eos1008,172.30.43.109,WIC,ATL01
##@NIBU@##eos1009,172.30.43.110,WIC,ATL01
##@NIBU@##eos1010,172.30.43.111,WIC,ATL01
##@NIBU@##eos1011,172.30.43.112,WIC,DEN01
##@NIBU@##eos1012,172.30.43.113,WIC,DEN01
##@NIBU@##eos1013,172.30.43.114,WIC,DEN01
##@NIBU@##eos1014,172.30.43.115,WIC,DEN01
##@NIBU@##eos1015,172.30.43.116,WIC,DEN01
##@NIBU@##eos1016,172.30.43.117,WIC,DEN01
##@NIBU@##eos1017,172.30.43.118,WIC,DEN01
##@NIBU@##eos1018,172.30.43.119,WIC,DEN01
##@NIBU@##eos1019,172.30.43.120,WIC,DEN01
##@NIBU@##eos1020,172.30.43.81,ITC,DEN01
##@NIBU@##eos1021,172.30.43.82,ITC,DEN01
##@NIBU@##eos1022,172.30.43.83,ITC,DEN01
##@NIBU@##eos1023,172.30.43.84,ITC,DEN01
##@NIBU@##eos1024,172.30.43.85,ITC,DEN01
##@NIBU@##eos1025,172.30.43.86,ITC,DEN01
##@NIBU@##eos1026,172.30.43.87,ITC,DEN01
##@NIBU@##eos1027,172.30.43.88,ITC,DEN01
##@NIBU@##eos1028,172.30.43.89,ITC,DEN01
##@NIBU@##eos1029,172.30.43.90,ITC,DEN01
##@NIBU@##eos1030,172.30.43.91,ITC,DEN01
##@NIBU@##eos1031,172.30.43.92,ITC,DEN01
##@NIBU@##eos1032,172.30.43.93,ITC,DEN01
##@NIBU@##eos1033,172.30.43.94,ITC,DEN01
##@NIBU@##eos1034,172.30.43.95,ITC,DEN01
##@NIBU@##eos1035,172.30.43.96,ITC,DEN01
##@NIBU@##eos1036,172.30.43.97,ITC,DEN01
##@NIBU@##eos1037,172.30.43.98,ITC,DEN01
##@NIBU@##eos1038,172.30.43.99,ITC,DEN01
##@NIBU@##eos1039,172.30.43.100,ITC,DEN01
##@NIBU@##eos1040,172.30.43.61,ITC,DEN01
##@NIBU@##eos1041,172.30.43.62,ITC,DEN01
##@NIBU@##eos1042,172.30.43.63,ITC,DEN01
##@NIBU@##eos1043,172.30.43.64,ITC,DEN01
##@NIBU@##eos1044,172.30.43.65,ITC,DEN01
##@NIBU@##eos1045,172.30.43.66,ITC,DEN01
##@NIBU@##eos1046,172.30.43.67,ITC,DEN01
##@NIBU@##eos1047,172.30.43.68,ITC,DEN01
##@NIBU@##eos1048,172.30.43.69,ITC,DEN01
##@NIBU@##eos1049,172.30.43.70,ITC,DEN01
##@NIBU@##eos1050,172.30.43.71,ITC,DEN01
##@NIBU@##eos1051,172.30.43.72,ITC,DEN01
##@NIBU@##eos1052,172.30.43.73,ITC,DEN01
##@NIBU@##eos1053,172.30.43.74,ITC,DEN01
##@NIBU@##eos1054,172.30.43.75,ITC,DEN01
##@NIBU@##eos1055,172.30.43.76,ITC,DEN01
##@NIBU@##eos1056,172.30.43.77,ITC,DEN01
##@NIBU@##eos1057,172.30.43.78,ITC,DEN01
##@NIBU@##eos1058,172.30.43.79,ITC,DEN01
##@NIBU@##eos1059,172.30.43.80,ITC,DEN01
##@NIBU@##eos1060,172.30.43.41,ITC,DEN01
##@NIBU@##eos1061,172.30.43.42,ITC,DEN01
##@NIBU@##eos1062,172.30.43.43,ITC,DEN01
##@NIBU@##eos1063,172.30.43.44,ITC,DEN01
##@NIBU@##eos1064,172.30.43.45,ITC,DEN01
##@NIBU@##eos1065,172.30.43.46,ITC,DEN01
##@NIBU@##eos1066,172.30.43.47,ITC,DEN01
##@NIBU@##eos1067,172.30.43.48,ITC,DEN01
##@NIBU@##eos1068,172.30.43.49,ITC,DEN01
##@NIBU@##eos1069,172.30.43.50,ITC,DEN01
##@NIBU@##eos1070,172.30.43.51,ITC,DEN01
##@NIBU@##eos1071,172.30.43.52,ITC,DEN01
##@NIBU@##eos1073,172.30.43.54,ITC,DEN01
##@NIBU@##eos1074,172.30.43.55,ITC,DEN01
##@NIBU@##eos1075,172.30.43.56,ITC,DEN01
##@NIBU@##eos1076,172.30.43.57,ITC,DEN01
##@NIBU@##eos1077,172.30.43.58,ITC,DEN01
##@NIBU@##eos1078,172.30.43.59,ITC,DEN01
##@NIBU@##eos1079,172.30.43.60,ITC,DEN01
##@NIBU@##eos1080,172.30.43.21,ITC,DEN01
##@NIBU@##eos1081,172.30.43.22,ITC,DEN01
##@NIBU@##eos1082,172.30.43.23,ITC,DEN01
##@NIBU@##eos1083,172.30.43.24,ITC,DEN01
##@NIBU@##eos1084,172.30.43.25,ITC,DEN01
##@NIBU@##eos1085,172.30.43.26,ITC,DEN01
##@NIBU@##eos1086,172.30.43.27,ITC,DEN01
##@NIBU@##eos1087,172.30.43.28,ITC,DEN01
##@NIBU@##eos1088,172.30.43.29,ITC,DEN01
##@NIBU@##eos1089,172.30.43.30,ITC,DEN01
##@NIBU@##eos1090,172.30.43.31,ITC,DEN01
##@NIBU@##eos1091,172.30.43.32,ITC,DEN01
##@NIBU@##eos1092,172.30.43.33,ITC,DEN01
##@NIBU@##eos1093,172.30.43.34,ITC,DEN01
##@NIBU@##eos1094,172.30.43.35,ITC,DEN01
##@NIBU@##eos1095,172.30.43.36,ITC,DEN01
##@NIBU@##eos1096,172.30.43.37,ITC,DEN01
##@NIBU@##eos1098,172.30.43.39,ITC,DEN01
##@NIBU@##eos1099,172.30.43.40,ITC,DEN01
##@NIBU@##eos1130,172.31.65.189,WIC,ATL01
##@NIBU@##eos1131,172.31.65.190,WIC,ATL01
##@NIBU@##eos1132,172.31.65.191,WIC,ATL01
##@NIBU@##eos1133,172.31.65.192,WIC,ATL01
##@NIBU@##eos1134,172.30.44.118,WIC,DEN01
##@NIBU@##eos1135,172.31.65.193,WIC,ATL01
##@NIBU@##eos1136,172.31.65.194,WIC,ATL01
##@NIBU@##eos1137,172.31.65.195,WIC,ATL01
##@NIBU@##eos1138,172.31.65.196,WIC,ATL01
##@NIBU@##eos1139,172.30.44.123,WIC,DEN01
##@NIBU@##eos12,10.29.119.38,WIC,DEN01
##@NIBU@##eos1210,172.30.44.34,WIC,DEN01
##@NIBU@##eos1211,172.30.44.35,WIC,DEN01
##@NIBU@##eos1212,172.30.44.36,WIC,DEN01
##@NIBU@##eos1213,172.30.44.37,WIC,DEN01
##@NIBU@##eos1214,172.30.44.38,WIC,DEN01
##@NIBU@##eos1215,172.30.44.39,WIC,DEN01
##@NIBU@##eos1216,172.30.44.40,WIC,DEN01
##@NIBU@##eos1217,172.30.44.41,WIC,DEN01
##@NIBU@##eos1218,172.30.44.42,WIC,DEN01
##@NIBU@##eos1219,172.30.44.43,WIC,DEN01
##@NIBU@##eos1220,172.30.44.44,WIC,DEN01
##@NIBU@##eos1221,172.30.44.45,WIC,DEN01
##@NIBU@##eos1222,172.30.44.46,WIC,DEN01
##@NIBU@##eos1223,172.30.44.47,WIC,DEN01
##@NIBU@##eos1224,172.30.44.48,WIC,DEN01
##@NIBU@##eos1225,172.30.44.49,WIC,DEN01
##@NIBU@##eos1226,172.30.44.50,WIC,DEN01
##@NIBU@##eos1227,172.30.44.51,WIC,DEN01
##@NIBU@##eos1229,172.30.44.53,WIC,DEN01
##@NIBU@##eos1230,172.30.43.121,WIC,DEN01
##@NIBU@##eos1231,172.30.43.122,WIC,DEN01
##@NIBU@##eos1232,172.30.43.123,WIC,DEN01
##@NIBU@##eos1233,172.30.43.124,WIC,DEN01
##@NIBU@##eos1234,172.30.43.125,WIC,DEN01
##@NIBU@##eos1235,172.30.43.126,WIC,DEN01
##@NIBU@##eos1236,172.30.43.127,WIC,DEN01
##@NIBU@##eos1237,172.30.43.128,WIC,DEN01
##@NIBU@##eos1238,172.30.43.129,WIC,DEN01
##@NIBU@##eos1239,172.30.43.130,WIC,DEN01
##@NIBU@##eos1240,172.30.43.131,WIC,DEN01
##@NIBU@##eos1241,172.30.43.132,WIC,DEN01
##@NIBU@##eos1242,172.30.43.133,WIC,DEN01
##@NIBU@##eos1243,172.30.43.134,WIC,DEN01
##@NIBU@##eos1245,172.30.43.136,WIC,DEN01
##@NIBU@##eos1246,172.30.43.137,WIC,DEN01
##@NIBU@##eos1247,172.30.43.138,WIC,DEN01
##@NIBU@##eos1248,172.30.43.139,WIC,DEN01
##@NIBU@##eos1249,172.30.43.140,WIC,DEN01
##@NIBU@##eos1252,172.30.40.227,ITC,DEN01
##@NIBU@##eos1253,172.30.40.133,ITC,DEN01
##@NIBU@##eos1254,172.30.40.175,ITC,DEN01
##@NIBU@##eos1255,172.30.40.176,ITC,DEN01
##@NIBU@##eos1270,172.30.42.1,ITC,DEN01
##@NIBU@##eos1271,172.30.42.2,ITC,DEN01
##@NIBU@##eos1272,172.30.42.3,ITC,DEN01
##@NIBU@##eos1273,172.30.42.4,ITC,DEN01
##@NIBU@##eos1274,172.30.42.5,ITC,DEN01
##@NIBU@##eos1275,172.30.42.6,ITC,DEN01
##@NIBU@##eos1276,172.30.42.7,ITC,DEN01
##@NIBU@##eos1277,172.30.42.8,ITC,DEN01
##@NIBU@##eos1278,172.30.42.9,ITC,DEN01
##@NIBU@##eos1279,172.30.42.10,ITC,DEN01
##@NIBU@##eos1280,172.30.42.11,ITC,DEN01
##@NIBU@##eos1281,172.30.42.12,ITC,DEN01
##@NIBU@##eos1282,172.30.42.13,ITC,DEN01
##@NIBU@##eos1283,172.30.42.14,ITC,DEN01
##@NIBU@##eos1284,172.30.42.15,ITC,DEN01
##@NIBU@##eos1285,172.30.42.16,ITC,DEN01
##@NIBU@##eos1286,172.30.42.17,ITC,DEN01
##@NIBU@##eos1287,172.30.42.18,ITC,DEN01
##@NIBU@##eos1288,172.30.42.19,ITC,DEN01
##@NIBU@##eos1289,172.30.42.20,ITC,DEN01
##@NIBU@##eos1290,172.30.42.21,ITC,DEN01
##@NIBU@##eos1291,172.30.42.22,ITC,DEN01
##@NIBU@##eos1292,172.30.42.23,ITC,DEN01
##@NIBU@##eos1293,172.30.42.24,ITC,DEN01
##@NIBU@##eos1294,172.30.42.25,ITC,DEN01
##@NIBU@##eos1295,172.30.42.26,ITC,DEN01
##@NIBU@##eos1296,172.30.42.27,ITC,DEN01
##@NIBU@##eos1297,172.30.42.28,ITC,DEN01
##@NIBU@##eos1298,172.30.42.29,ITC,DEN01
##@NIBU@##eos1299,172.30.42.30,ITC,DEN01
##@NIBU@##eos13,10.29.119.40,WIC,DEN01
##@NIBU@##eos1300,172.30.42.31,ITC,DEN01
##@NIBU@##eos1301,172.30.42.32,ITC,DEN01
##@NIBU@##eos1302,172.30.42.33,ITC,DEN01
##@NIBU@##eos1303,172.30.42.34,ITC,DEN01
##@NIBU@##eos1304,172.30.42.35,ITC,DEN01
##@NIBU@##eos1305,172.30.42.36,ITC,DEN01
##@NIBU@##eos1306,172.30.42.37,ITC,DEN01
##@NIBU@##eos1307,172.30.42.38,ITC,DEN01
##@NIBU@##eos1308,172.30.42.39,ITC,DEN01
##@NIBU@##eos1309,172.30.42.40,ITC,DEN01
##@NIBU@##eos1310,172.30.42.41,ITC,DEN01
##@NIBU@##eos1311,172.30.42.42,ITC,DEN01
##@NIBU@##eos1312,172.30.42.43,ITC,DEN01
##@NIBU@##eos1313,172.30.42.44,ITC,DEN01
##@NIBU@##eos1314,172.30.42.45,ITC,DEN01
##@NIBU@##eos1315,172.30.42.46,ITC,DEN01
##@NIBU@##eos1316,172.30.42.47,ITC,DEN01
##@NIBU@##eos1317,172.30.42.48,ITC,DEN01
##@NIBU@##eos1318,172.30.42.49,ITC,DEN01
##@NIBU@##eos1319,172.30.42.50,ITC,DEN01
##@NIBU@##eos1320,172.30.42.51,ITC,DEN01
##@NIBU@##eos1321,172.30.42.52,ITC,DEN01
##@NIBU@##eos1322,172.30.42.53,ITC,DEN01
##@NIBU@##eos1323,172.30.42.54,ITC,DEN01
##@NIBU@##eos1324,172.30.42.55,ITC,DEN01
##@NIBU@##eos1325,172.30.42.56,ITC,DEN01
##@NIBU@##eos1326,172.30.42.57,ITC,DEN01
##@NIBU@##eos1327,172.30.42.58,ITC,DEN01
##@NIBU@##eos1328,172.30.42.59,ITC,DEN01
##@NIBU@##eos1329,172.30.42.60,ITC,DEN01
##@NIBU@##eos1330,172.30.42.61,ITC,DEN01
##@NIBU@##eos1331,172.30.42.62,ITC,DEN01
##@NIBU@##eos1332,172.30.42.63,ITC,DEN01
##@NIBU@##eos1334,172.30.42.65,ITC,DEN01
##@NIBU@##eos1335,172.30.42.66,ITC,DEN01
##@NIBU@##eos1336,172.30.42.67,ITC,DEN01
##@NIBU@##eos1337,172.30.42.68,ITC,DEN01
##@NIBU@##eos1338,172.30.42.69,ITC,DEN01
##@NIBU@##eos1339,172.30.42.70,ITC,DEN01
##@NIBU@##eos1340,172.30.42.71,ITC,DEN01
##@NIBU@##eos1341,172.30.42.72,ITC,DEN01
##@NIBU@##eos1342,172.30.42.73,ITC,DEN01
##@NIBU@##eos1343,172.30.42.74,ITC,DEN01
##@NIBU@##eos1344,172.30.42.75,ITC,DEN01
##@NIBU@##eos1345,172.30.42.76,ITC,DEN01
##@NIBU@##eos1346,172.30.42.77,ITC,DEN01
##@NIBU@##eos1347,172.30.42.78,ITC,DEN01
##@NIBU@##eos1348,172.30.42.79,ITC,DEN01
##@NIBU@##eos1349,172.30.42.80,ITC,DEN01
##@NIBU@##eos1350,172.30.42.81,ITC,DEN01
##@NIBU@##eos1351,172.30.42.82,ITC,DEN01
##@NIBU@##eos1352,172.30.42.83,ITC,DEN01
##@NIBU@##eos1353,172.30.42.84,ITC,DEN01
##@NIBU@##eos1354,172.30.42.85,ITC,DEN01
##@NIBU@##eos1355,172.30.42.86,ITC,DEN01
##@NIBU@##eos1356,172.30.42.87,ITC,DEN01
##@NIBU@##eos1357,172.30.42.88,ITC,DEN01
##@NIBU@##eos1358,172.30.42.89,ITC,DEN01
##@NIBU@##eos1359,172.30.42.90,ITC,DEN01
##@NIBU@##eos1360,172.30.42.91,ITC,DEN01
##@NIBU@##eos1361,172.30.42.92,ITC,DEN01
##@NIBU@##eos1362,172.30.42.93,ITC,DEN01
##@NIBU@##eos1363,172.30.42.94,ITC,DEN01
##@NIBU@##eos1364,172.30.42.95,ITC,DEN01
##@NIBU@##eos1365,172.30.42.96,ITC,DEN01
##@NIBU@##eos1366,172.30.42.97,ITC,DEN01
##@NIBU@##eos1367,172.30.42.98,ITC,DEN01
##@NIBU@##eos1368,172.30.42.99,ITC,DEN01
##@NIBU@##eos1369,172.30.42.100,ITC,DEN01
##@NIBU@##eos14,10.29.119.42,WIC,DEN01
##@NIBU@##eos1425,172.30.52.194,ITC,DEN01
##@NIBU@##eos1426,172.30.52.195,ITC,DEN01
##@NIBU@##eos1427,172.30.52.196,ITC,DEN01
##@NIBU@##eos1429,172.30.52.198,ITC,DEN01
##@NIBU@##eos1430,172.30.52.199,ITC,DEN01
##@NIBU@##eos1431,172.30.52.200,ITC,DEN01
##@NIBU@##eos1432,172.30.52.201,ITC,DEN01
##@NIBU@##eos1433,172.30.52.202,ITC,DEN01
##@NIBU@##eos1434,172.30.52.203,ITC,DEN01
##@NIBU@##eos1437,172.30.44.24,ITC,DEN01
##@NIBU@##eos1438,172.30.44.25,ITC,DEN01
##@NIBU@##eos1439,172.30.44.26,ITC,DEN01
##@NIBU@##eos1440,172.30.44.27,ITC,DEN01
##@NIBU@##eos1441,172.30.44.28,ITC,DEN01
##@NIBU@##eos1442,172.30.44.29,ITC,DEN01
##@NIBU@##eos1443,172.30.44.30,ITC,DEN01
##@NIBU@##eos1444,172.30.44.31,ITC,DEN01
##@NIBU@##eos1445,172.30.44.32,ITC,DEN01
##@NIBU@##eos1450,172.30.43.1,ITC,DEN01
##@NIBU@##eos1451,172.30.43.2,ITC,DEN01
##@NIBU@##eos1452,172.30.43.3,ITC,DEN01
##@NIBU@##eos1453,172.30.43.4,ITC,DEN01
##@NIBU@##eos1454,172.30.43.5,ITC,DEN01
##@NIBU@##eos1455,172.30.43.6,ITC,DEN01
##@NIBU@##eos1456,172.30.43.7,ITC,DEN01
##@NIBU@##eos1457,172.30.43.8,ITC,DEN01
##@NIBU@##eos1458,172.30.43.9,ITC,DEN01
##@NIBU@##eos1459,172.30.43.10,ITC,DEN01
##@NIBU@##eos1460,172.30.43.11,ITC,DEN01
##@NIBU@##eos1461,172.30.43.12,ITC,DEN01
##@NIBU@##eos1462,172.30.43.13,ITC,DEN01
##@NIBU@##eos1463,172.30.43.14,ITC,DEN01
##@NIBU@##eos1464,172.30.43.15,ITC,DEN01
##@NIBU@##eos1465,172.30.43.16,ITC,DEN01
##@NIBU@##eos1466,172.30.43.17,ITC,DEN01
##@NIBU@##eos1467,172.30.43.18,ITC,DEN01
##@NIBU@##eos1468,172.30.43.19,ITC,DEN01
##@NIBU@##eos1469,172.30.43.20,ITC,DEN01
##@NIBU@##eos15,10.29.119.44,WIC,DEN01
##@NIBU@##eos155,172.30.9.105,WIC,OMA10
##@NIBU@##eos156,172.30.9.106,WIC,OMA10
##@NIBU@##eos1560,172.30.41.81,WIC,DEN01
##@NIBU@##eos1561,172.30.41.82,WIC,DEN01
##@NIBU@##eos1562,172.30.41.83,WIC,DEN01
##@NIBU@##eos1563,172.30.41.84,WIC,DEN01
##@NIBU@##eos1564,172.30.41.85,WIC,DEN01
##@NIBU@##eos1565,172.30.41.86,WIC,DEN01
##@NIBU@##eos1566,172.30.41.87,WIC,DEN01
##@NIBU@##eos1567,172.30.41.88,WIC,DEN01
##@NIBU@##eos1568,172.30.41.89,WIC,DEN01
##@NIBU@##eos1569,172.30.41.90,WIC,DEN01
##@NIBU@##eos157,172.30.9.107,WIC,OMA10
##@NIBU@##eos1570,172.30.41.91,WIC,DEN01
##@NIBU@##eos1571,172.30.41.92,WIC,DEN01
##@NIBU@##eos1572,172.30.41.93,WIC,DEN01
##@NIBU@##eos1573,172.30.41.94,WIC,DEN01
##@NIBU@##eos1574,172.30.41.95,WIC,DEN01
##@NIBU@##eos1575,172.30.41.96,WIC,DEN01
##@NIBU@##eos1576,172.30.41.97,WIC,DEN01
##@NIBU@##eos1577,172.30.41.98,WIC,DEN01
##@NIBU@##eos1578,172.30.41.99,WIC,DEN01
##@NIBU@##eos1579,172.30.41.100,WIC,DEN01
##@NIBU@##eos158,172.30.9.108,WIC,OMA10
##@NIBU@##eos159,172.30.9.109,WIC,OMA10
##@NIBU@##eos16,10.29.119.46,WIC,DEN01
##@NIBU@##eos160,172.30.9.110,WIC,OMA10
##@NIBU@##eos1600,10.29.119.100,WIC,DEN01
##@NIBU@##eos1601,10.29.119.102,WIC,DEN01
##@NIBU@##eos1602,10.29.119.104,WIC,DEN01
##@NIBU@##eos1603,10.29.119.106,WIC,DEN01
##@NIBU@##eos1604,10.29.119.108,WIC,DEN01
##@NIBU@##eos1605,10.29.119.110,WIC,DEN01
##@NIBU@##eos1606,10.29.119.112,WIC,DEN01
##@NIBU@##eos1607,10.29.119.114,WIC,DEN01
##@NIBU@##eos1608,10.29.118.20,WIC,DEN01
##@NIBU@##eos1609,10.29.118.22,WIC,DEN01
##@NIBU@##eos161,172.30.9.111,WIC,OMA10
##@NIBU@##eos1610,10.29.118.24,WIC,DEN01
##@NIBU@##eos1611,10.29.118.26,WIC,DEN01
##@NIBU@##eos1612,10.29.118.28,WIC,DEN01
##@NIBU@##eos1613,10.29.118.30,WIC,DEN01
##@NIBU@##eos1614,10.29.118.32,WIC,DEN01
##@NIBU@##eos1615,10.29.118.34,WIC,DEN01
##@NIBU@##eos1616,10.29.118.36,WIC,DEN01
##@NIBU@##eos1617,10.29.118.38,WIC,DEN01
##@NIBU@##eos1618,10.29.118.40,WIC,DEN01
##@NIBU@##eos1619,10.29.118.42,WIC,DEN01
##@NIBU@##eos162,172.30.9.112,WIC,OMA10
##@NIBU@##eos1620,10.29.118.44,WIC,DEN01
##@NIBU@##eos1621,10.29.118.46,WIC,DEN01
##@NIBU@##eos1622,10.29.118.48,WIC,DEN01
##@NIBU@##eos1623,10.29.118.50,WIC,DEN01
##@NIBU@##eos1624,10.29.118.52,WIC,DEN01
##@NIBU@##eos1625,10.29.118.54,WIC,DEN01
##@NIBU@##eos1626,10.29.118.56,WIC,DEN01
##@NIBU@##eos1627,10.29.118.58,WIC,DEN01
##@NIBU@##eos1628,10.29.118.60,WIC,DEN01
##@NIBU@##eos1629,10.29.118.62,WIC,DEN01
##@NIBU@##eos163,172.30.9.113,WIC,OMA10
##@NIBU@##eos1630,10.29.118.64,WIC,DEN01
##@NIBU@##eos1631,10.29.118.66,WIC,DEN01
##@NIBU@##eos1632,10.29.118.68,WIC,DEN01
##@NIBU@##eos1633,10.29.118.70,WIC,DEN01
##@NIBU@##eos1634,10.29.118.72,WIC,DEN01
##@NIBU@##eos1635,10.29.118.74,WIC,DEN01
##@NIBU@##eos1636,10.29.118.76,WIC,DEN01
##@NIBU@##eos1637,10.29.118.78,WIC,DEN01
##@NIBU@##eos1638,10.29.118.80,WIC,DEN01
##@NIBU@##eos1639,10.29.118.82,WIC,DEN01
##@NIBU@##eos164,172.30.9.114,WIC,OMA10
##@NIBU@##eos165,172.30.9.115,WIC,OMA10
##@NIBU@##eos166,172.30.9.116,WIC,OMA10
##@NIBU@##eos1660,172.30.40.41,WIC,DEN01
##@NIBU@##eos1661,172.30.40.42,WIC,DEN01
##@NIBU@##eos1662,172.30.40.43,WIC,DEN01
##@NIBU@##eos1663,172.30.40.44,WIC,DEN01
##@NIBU@##eos1664,172.30.40.45,WIC,DEN01
##@NIBU@##eos1665,172.30.40.46,WIC,DEN01
##@NIBU@##eos1666,172.30.40.47,WIC,DEN01
##@NIBU@##eos1667,172.30.40.48,WIC,DEN01
##@NIBU@##eos1668,172.30.40.49,WIC,DEN01
##@NIBU@##eos1669,172.30.40.50,WIC,DEN01
##@NIBU@##eos167,172.30.9.117,WIC,OMA10
##@NIBU@##eos1670,172.30.40.51,WIC,DEN01
##@NIBU@##eos1671,172.30.40.52,WIC,DEN01
##@NIBU@##eos1672,172.30.40.53,WIC,DEN01
##@NIBU@##eos1673,172.30.40.54,WIC,DEN01
##@NIBU@##eos1674,172.30.40.55,WIC,DEN01
##@NIBU@##eos1675,172.30.40.56,WIC,DEN01
##@NIBU@##eos1676,172.30.40.57,WIC,DEN01
##@NIBU@##eos1677,172.30.40.58,WIC,DEN01
##@NIBU@##eos1678,172.30.40.59,WIC,DEN01
##@NIBU@##eos1679,172.30.40.60,WIC,DEN01
##@NIBU@##eos168,172.30.9.118,WIC,OMA10
##@NIBU@##eos169,172.30.9.119,WIC,OMA10
##@NIBU@##eos17,10.29.119.48,WIC,DEN01
##@NIBU@##eos170,172.30.9.120,WIC,OMA10
##@NIBU@##eos171,172.30.9.121,WIC,OMA10
##@NIBU@##eos172,172.30.9.122,WIC,OMA10
##@NIBU@##eos173,172.30.9.123,WIC,OMA10
##@NIBU@##eos1730,10.29.225.21,ITC,DEN01
##@NIBU@##eos1731,10.29.225.22,ITC,DEN01
##@NIBU@##eos174,172.30.9.124,WIC,OMA10
##@NIBU@##eos175,172.30.3.21,WIC,OMA01
##@NIBU@##eos177,172.30.3.23,WIC,OMA01
##@NIBU@##eos178,172.30.3.24,WIC,OMA01
##@NIBU@##eos18,10.29.119.50,WIC,DEN01
##@NIBU@##eos181,172.30.3.27,WIC,OMA01
##@NIBU@##eos1810,172.30.10.56,WIC,OMA10
##@NIBU@##eos1811,172.30.10.57,WIC,OMA10
##@NIBU@##eos1812,172.30.10.58,WIC,OMA10
##@NIBU@##eos1813,172.30.10.59,WIC,OMA10
##@NIBU@##eos1814,172.30.10.60,WIC,OMA10
##@NIBU@##eos1815,172.30.10.61,WIC,OMA10
##@NIBU@##eos1816,172.30.10.62,WIC,OMA10
##@NIBU@##eos1817,172.30.10.63,WIC,OMA10
##@NIBU@##eos1818,172.30.10.64,WIC,OMA10
##@NIBU@##eos1819,172.30.10.65,WIC,OMA10
##@NIBU@##eos182,172.30.3.28,WIC,OMA01
##@NIBU@##eos1820,172.30.10.101,WIC,OMA10
##@NIBU@##eos1821,172.30.10.102,WIC,OMA10
##@NIBU@##eos1822,172.30.10.103,WIC,OMA10
##@NIBU@##eos1823,172.30.10.104,WIC,OMA10
##@NIBU@##eos1824,172.30.10.105,WIC,OMA10
##@NIBU@##eos1825,172.30.10.106,WIC,OMA10
##@NIBU@##eos1826,172.30.10.107,WIC,OMA10
##@NIBU@##eos1827,172.30.10.108,WIC,OMA10
##@NIBU@##eos1828,172.30.10.109,WIC,OMA10
##@NIBU@##eos1829,172.30.10.110,WIC,OMA10
##@NIBU@##eos183,172.30.3.29,WIC,OMA01
##@NIBU@##eos1830,10.19.55.21,WIC,OMA01
##@NIBU@##eos1831,10.19.55.23,WIC,OMA01
##@NIBU@##eos1832,10.19.55.25,WIC,OMA01
##@NIBU@##eos1834,10.19.55.29,WIC,OMA01
##@NIBU@##eos1835,10.19.55.31,WIC,OMA01
##@NIBU@##eos1836,10.19.55.45,WIC,OMA01
##@NIBU@##eos1837,10.19.55.47,WIC,OMA01
##@NIBU@##eos1838,10.19.55.49,WIC,OMA01
##@NIBU@##eos1839,10.19.55.51,WIC,OMA01
##@NIBU@##eos184,172.30.3.30,WIC,OMA01
##@NIBU@##eos1840,10.19.55.33,WIC,OMA01
##@NIBU@##eos1841,10.19.55.35,WIC,OMA01
##@NIBU@##eos1842,10.19.55.37,WIC,OMA01
##@NIBU@##eos1843,10.19.55.39,WIC,OMA01
##@NIBU@##eos1844,10.19.55.41,WIC,OMA01
##@NIBU@##eos1846,10.19.55.53,WIC,OMA01
##@NIBU@##eos1848,10.19.55.57,WIC,OMA01
##@NIBU@##eos1849,10.19.55.59,WIC,OMA01
##@NIBU@##eos186,172.30.3.32,WIC,OMA01
##@NIBU@##eos187,172.30.3.33,WIC,OMA01
##@NIBU@##eos188,172.30.3.34,WIC,OMA01
##@NIBU@##eos189,172.30.3.35,WIC,OMA01
##@NIBU@##eos1898,10.27.194.54,WIC,OMA00
##@NIBU@##eos19,10.29.119.52,WIC,DEN01
##@NIBU@##eos190,172.30.3.36,WIC,OMA01
##@NIBU@##Eos1901,10.27.192.93,WIC,OMA00
##@NIBU@##Eos1902,10.27.192.25,WIC,OMA00
##@NIBU@##Eos1904,10.27.192.26,WIC,OMA00
##@NIBU@##Eos1905,10.27.192.77,WIC,OMA00
##@NIBU@##Eos1906,10.27.192.28,WIC,OMA00
##@NIBU@##Eos1909,10.27.192.30,WIC,OMA00
##@NIBU@##eos191,172.30.3.37,WIC,OMA01
##@NIBU@##Eos1910,10.27.192.31,WIC,OMA00
##@NIBU@##Eos1912,10.27.192.32,WIC,OMA00
##@NIBU@##Eos1914,10.27.192.33,WIC,OMA00
##@NIBU@##Eos1917,172.30.112.73,WIC,OMA00
##@NIBU@##Eos1918,10.27.192.37,WIC,OMA00
##@NIBU@##Eos1919,10.27.192.36,WIC,OMA00
##@NIBU@##eos192,172.30.3.38,WIC,OMA01
##@NIBU@##Eos1921,10.27.192.38,WIC,OMA00
##@NIBU@##Eos1924,10.27.192.101,WIC,OMA00
##@NIBU@##Eos1925,10.27.192.102,WIC,OMA00
##@NIBU@##Eos1926,10.27.192.40,WIC,OMA00
##@NIBU@##Eos1929,10.27.192.42,WIC,OMA00
##@NIBU@##eos193,172.30.3.39,WIC,ATL01
##@NIBU@##eos1932,172.30.112.82,WIC,OMA00
##@NIBU@##eos1933,172.30.114.49,WIC,OMA00
##@NIBU@##Eos1937,10.27.192.43,ITC,OMA00
##@NIBU@##eos1938,172.30.112.172,WIC,OMA00
##@NIBU@##Eos1939,10.27.192.44,ITC,OMA00
##@NIBU@##eos194,172.30.3.40,WIC,ATL01
##@NIBU@##Eos1940,10.27.192.45,ITC,OMA00
##@NIBU@##eos1941,172.30.112.194,WIC,OMA00
##@NIBU@##eos1943,172.30.112.177,WIC,OMA00
##@NIBU@##Eos1944,10.27.192.46,WIC,OMA00
##@NIBU@##Eos1945,10.27.192.47,WIC,OMA00
##@NIBU@##Eos1948,10.27.192.48,WIC,OMA00
##@NIBU@##Eos1949,10.27.192.107,WIC,OMA00
##@NIBU@##eos195,172.30.3.41,WIC,ATL01
##@NIBU@##Eos1950,10.27.192.49,WIC,OMA00
##@NIBU@##Eos1951,10.27.192.50,WIC,OMA00
##@NIBU@##Eos1953,10.18.128.32,WIC,OMA11
##@NIBU@##Eos1954,10.18.128.33,WIC,OMA11
##@NIBU@##Eos1955,10.27.192.52,WIC,OMA00
##@NIBU@##Eos1956,10.27.192.53,WIC,OMA00
##@NIBU@##Eos1957,10.27.192.54,WIC,OMA00
##@NIBU@##Eos1958,10.27.192.55,WIC,OMA00
##@NIBU@##Eos1959,10.27.192.56,WIC,OMA00
##@NIBU@##eos196,172.30.3.42,WIC,ATL01
##@NIBU@##Eos1960,10.27.192.63,WIC,OMA00
##@NIBU@##Eos1963,10.27.192.59,WIC,OMA00
##@NIBU@##Eos1964,10.18.128.34,WIC,OMA11
##@NIBU@##Eos1965,10.18.128.35,WIC,OMA11
##@NIBU@##Eos1966,10.27.192.60,WIC,OMA00
##@NIBU@##Eos1967,10.27.192.61,WIC,OMA00
##@NIBU@##Eos1968,10.27.192.62,WIC,OMA00
##@NIBU@##Eos1969,10.27.192.63,WIC,OMA00
##@NIBU@##Eos1970,10.27.192.64,ITC,OMA00
##@NIBU@##Eos1971,10.27.192.65,ITC,OMA00
##@NIBU@##eos1972,172.30.112.253,WIC,OMA00
##@NIBU@##eos1973,172.30.112.254,WIC,OMA00
##@NIBU@##eos1974,172.30.116.100,WIC,OMA00
##@NIBU@##Eos1975,10.27.192.68,WIC,OMA00
##@NIBU@##Eos1979,10.27.192.69,WIC,OMA00
##@NIBU@##Eos1984,10.27.192.91,WIC,OMA00
##@NIBU@##eos1985,10.27.193.120,WIC,OMA00
##@NIBU@##eos1986,10.27.193.121,WIC,OMA00
##@NIBU@##Eos1988,10.27.192.74,WIC,OMA00
##@NIBU@##Eos1989,10.27.192.92,WIC,OMA00
##@NIBU@##Eos1990,10.18.128.21,WIC,OMA11
##@NIBU@##Eos1991,10.18.128.22,WIC,OMA11
##@NIBU@##Eos1992,10.18.128.23,WIC,OMA11
##@NIBU@##Eos1993,10.18.128.24,WIC,OMA11
##@NIBU@##Eos1994,10.18.128.25,WIC,OMA11
##@NIBU@##Eos1995,10.18.128.26,WIC,OMA11
##@NIBU@##Eos1996,10.18.128.27,WIC,OMA11
##@NIBU@##Eos1997,10.18.128.28,WIC,OMA11
##@NIBU@##Eos1998,10.18.128.29,WIC,OMA11
##@NIBU@##Eos1999,10.18.128.30,WIC,OMA11
##@NIBU@##eos2,10.29.119.22,WIC,DEN01
##@NIBU@##eos20,10.29.119.54,WIC,DEN01
##@NIBU@##eos200,172.30.3.92,WIC,ATL01
##@NIBU@##eos201,172.30.3.93,WIC,ATL01
##@NIBU@##eos202,172.30.3.94,WIC,ATL01
##@NIBU@##eos203,172.30.3.95,WIC,ATL01
##@NIBU@##eos204,172.30.3.96,WIC,ATL01
##@NIBU@##eos2040,172.30.64.41,ITC,ATL01
##@NIBU@##eos2042,172.30.64.43,ITC,ATL01
##@NIBU@##eos2043,172.30.64.44,ITC,ATL01
##@NIBU@##eos2044,172.30.64.45,ITC,ATL01
##@NIBU@##eos2045,172.30.64.46,ITC,ATL01
##@NIBU@##eos2046,172.30.64.47,ITC,ATL01
##@NIBU@##eos2047,172.30.64.48,ITC,ATL01
##@NIBU@##eos2048,172.30.64.49,ITC,ATL01
##@NIBU@##eos2049,172.30.64.50,ITC,ATL01
##@NIBU@##eos205,172.30.3.97,WIC,ATL01
##@NIBU@##eos2050,172.30.64.51,ITC,ATL01
##@NIBU@##eos2051,172.30.64.52,ITC,ATL01
##@NIBU@##eos2052,172.30.64.53,ITC,ATL01
##@NIBU@##eos2053,172.30.64.54,ITC,ATL01
##@NIBU@##eos2054,172.30.64.55,ITC,ATL01
##@NIBU@##eos2056,172.30.64.57,ITC,ATL01
##@NIBU@##eos2057,172.30.64.58,ITC,ATL01
##@NIBU@##eos2058,172.30.64.59,ITC,ATL01
##@NIBU@##eos2059,172.30.64.60,ITC,ATL01
##@NIBU@##eos206,172.30.3.98,WIC,ATL01
##@NIBU@##eos2060,172.30.64.61,ITC,ATL01
##@NIBU@##eos2061,172.30.64.62,ITC,ATL01
##@NIBU@##eos2062,172.30.64.63,ITC,ATL01
##@NIBU@##eos2063,172.30.64.64,ITC,ATL01
##@NIBU@##eos2064,172.30.64.65,ITC,ATL01
##@NIBU@##eos2065,172.30.64.66,ITC,ATL01
##@NIBU@##eos2066,172.30.64.67,ITC,ATL01
##@NIBU@##eos2067,172.30.64.68,ITC,ATL01
##@NIBU@##eos2068,172.30.64.69,ITC,ATL01
##@NIBU@##eos2069,172.30.64.70,ITC,ATL01
##@NIBU@##eos207,172.30.3.99,WIC,OMA01
##@NIBU@##eos2070,172.30.64.71,ITC,ATL01
##@NIBU@##eos2071,172.30.64.72,ITC,ATL01
##@NIBU@##eos2072,172.30.64.73,ITC,ATL01
##@NIBU@##eos2073,172.30.64.74,ITC,ATL01
##@NIBU@##eos2074,172.30.64.75,ITC,ATL01
##@NIBU@##eos2075,172.30.64.76,ITC,ATL01
##@NIBU@##eos2076,172.30.64.77,ITC,ATL01
##@NIBU@##eos2077,172.30.64.78,ITC,ATL01
##@NIBU@##eos2078,172.30.64.79,ITC,ATL01
##@NIBU@##eos2079,172.30.64.80,ITC,ATL01
##@NIBU@##eos2080,172.30.64.81,ITC,ATL01
##@NIBU@##eos2081,172.30.64.82,ITC,ATL01
##@NIBU@##eos2082,172.30.64.83,ITC,ATL01
##@NIBU@##eos2083,172.30.64.84,ITC,ATL01
##@NIBU@##eos2084,172.30.64.85,ITC,ATL01
##@NIBU@##eos2085,172.30.64.86,ITC,ATL01
##@NIBU@##eos2086,172.30.64.87,ITC,ATL01
##@NIBU@##eos2087,172.30.64.88,ITC,ATL01
##@NIBU@##eos2088,172.30.64.89,ITC,ATL01
##@NIBU@##eos2089,172.30.64.90,ITC,ATL01
##@NIBU@##eos2090,172.30.64.91,ITC,ATL01
##@NIBU@##eos2091,172.30.64.92,ITC,ATL01
##@NIBU@##eos2092,172.30.64.93,ITC,ATL01
##@NIBU@##eos2093,172.30.64.94,ITC,ATL01
##@NIBU@##eos2094,172.30.64.95,ITC,ATL01
##@NIBU@##eos2095,172.30.64.96,ITC,ATL01
##@NIBU@##eos2096,172.30.64.97,ITC,ATL01
##@NIBU@##eos2097,172.30.64.98,ITC,ATL01
##@NIBU@##eos2098,172.30.64.99,ITC,ATL01
##@NIBU@##eos2099,172.30.64.100,ITC,ATL01
##@NIBU@##eos2100,172.30.64.101,ITC,ATL01
##@NIBU@##eos2101,172.30.64.102,ITC,ATL01
##@NIBU@##eos2102,172.30.64.103,ITC,ATL01
##@NIBU@##eos2103,172.30.64.104,ITC,ATL01
##@NIBU@##eos2104,172.30.64.105,ITC,ATL01
##@NIBU@##eos2105,172.30.64.106,ITC,ATL01
##@NIBU@##eos2106,172.30.64.107,ITC,ATL01
##@NIBU@##eos2107,172.30.64.108,ITC,ATL01
##@NIBU@##eos2108,172.30.64.109,ITC,ATL01
##@NIBU@##eos2109,172.30.64.110,ITC,ATL01
##@NIBU@##eos2110,172.30.64.111,ITC,ATL01
##@NIBU@##eos2111,172.30.64.112,ITC,ATL01
##@NIBU@##eos2112,172.30.64.113,ITC,ATL01
##@NIBU@##eos2113,172.30.64.114,ITC,ATL01
##@NIBU@##eos2114,172.30.64.115,ITC,ATL01
##@NIBU@##eos2115,172.30.64.116,ITC,ATL01
##@NIBU@##eos2116,172.30.64.117,ITC,ATL01
##@NIBU@##eos2117,172.30.64.118,ITC,ATL01
##@NIBU@##eos2118,172.30.64.119,ITC,ATL01
##@NIBU@##eos2119,172.30.64.120,ITC,ATL01
##@NIBU@##eos213,172.30.4.22,WIC,OMA01
##@NIBU@##eos214,172.30.4.23,WIC,OMA01
##@NIBU@##eos215,172.30.4.24,WIC,OMA01
##@NIBU@##eos216,172.30.4.25,WIC,OMA01
##@NIBU@##eos217,172.30.4.26,WIC,OMA01
##@NIBU@##eos218,172.30.4.27,WIC,OMA01
##@NIBU@##eos219,172.30.4.28,WIC,OMA01
##@NIBU@##eos22,10.29.119.56,WIC,DEN01
##@NIBU@##eos220,172.30.4.29,WIC,OMA01
##@NIBU@##eos221,172.30.4.30,WIC,OMA01
##@NIBU@##eos222,172.30.4.31,WIC,OMA01
##@NIBU@##eos2220,10.31.135.61,ITC,PHX01
##@NIBU@##eos2221,10.31.135.62,ITC,PHX01
##@NIBU@##eos2222,10.31.135.63,ITC,PHX01
##@NIBU@##eos2223,10.31.135.64,ITC,PHX01
##@NIBU@##eos2224,10.31.135.65,ITC,PHX01
##@NIBU@##eos2225,10.31.135.66,ITC,PHX01
##@NIBU@##eos223,172.30.4.32,WIC,OMA01
##@NIBU@##eos224,172.30.4.33,WIC,OMA01
##@NIBU@##eos226,172.30.4.35,WIC,OMA01
##@NIBU@##eos227,172.30.4.36,WIC,OMA01
##@NIBU@##eos228,172.30.4.37,WIC,OMA01
##@NIBU@##eos229,172.30.4.38,WIC,OMA01
##@NIBU@##eos23,10.29.117.40,WIC,DEN01
##@NIBU@##eos230,172.30.4.39,WIC,OMA01
##@NIBU@##eos2320,10.17.57.21,WIC,OMA10
##@NIBU@##eos2321,10.17.57.22,WIC,OMA10
##@NIBU@##eos2322,10.17.57.23,WIC,OMA10
##@NIBU@##eos2323,10.17.57.24,WIC,OMA10
##@NIBU@##eos2324,10.17.57.25,WIC,OMA10
##@NIBU@##eos2325,10.17.57.26,WIC,OMA10
##@NIBU@##eos2326,10.17.57.27,WIC,OMA10
##@NIBU@##eos2327,10.17.57.28,WIC,OMA10
##@NIBU@##eos2328,10.17.57.29,WIC,ATL01
##@NIBU@##eos2329,10.17.57.30,WIC,ATL01
##@NIBU@##eos2330,10.17.57.31,WIC,OMA10
##@NIBU@##eos2331,10.17.57.32,WIC,OMA10
##@NIBU@##eos2332,10.17.57.33,WIC,OMA10
##@NIBU@##eos2333,10.17.57.34,WIC,OMA10
##@NIBU@##eos2334,10.17.57.35,WIC,OMA10
##@NIBU@##eos2335,10.17.57.36,WIC,OMA10
##@NIBU@##eos2336,10.17.57.37,WIC,OMA10
##@NIBU@##eos2337,10.17.57.38,WIC,OMA10
##@NIBU@##eos2340,172.30.44.54,WIC,DEN01
##@NIBU@##eos2341,172.30.44.55,WIC,DEN01
##@NIBU@##eos2342,172.30.44.56,WIC,DEN01
##@NIBU@##eos2343,172.30.44.57,WIC,DEN01
##@NIBU@##eos2344,172.30.44.58,WIC,DEN01
##@NIBU@##eos2345,172.30.44.59,WIC,DEN01
##@NIBU@##eos2346,172.30.44.60,WIC,DEN01
##@NIBU@##eos2347,172.30.44.61,WIC,DEN01
##@NIBU@##eos2348,172.30.44.62,WIC,ATL01
##@NIBU@##eos2349,172.30.44.63,WIC,ATL01
##@NIBU@##eos2350,172.30.44.64,WIC,DEN01
##@NIBU@##eos2351,172.30.44.65,WIC,DEN01
##@NIBU@##eos2352,172.30.44.66,WIC,DEN01
##@NIBU@##eos2353,172.30.44.67,WIC,DEN01
##@NIBU@##eos2354,172.30.44.68,WIC,DEN01
##@NIBU@##eos2355,172.30.44.69,WIC,DEN01
##@NIBU@##eos2356,172.30.44.70,WIC,DEN01
##@NIBU@##eos2357,172.30.44.71,WIC,DEN01
##@NIBU@##eos2359,172.30.44.73,WIC,DEN01
##@NIBU@##eos2380,172.30.40.21,WIC,DEN01
##@NIBU@##eos2381,172.30.40.22,WIC,DEN01
##@NIBU@##eos2382,172.30.40.23,WIC,DEN01
##@NIBU@##eos2383,172.30.40.24,WIC,DEN01
##@NIBU@##eos2384,172.30.40.25,WIC,DEN01
##@NIBU@##eos2385,172.30.40.26,WIC,DEN01
##@NIBU@##eos2386,172.30.40.27,WIC,DEN01
##@NIBU@##eos2387,172.30.40.28,WIC,DEN01
##@NIBU@##eos2388,172.30.40.29,WIC,DEN01
##@NIBU@##eos2389,172.30.40.30,WIC,DEN01
##@NIBU@##eos2390,172.30.40.31,WIC,DEN01
##@NIBU@##eos2391,172.30.40.32,WIC,DEN01
##@NIBU@##eos2392,172.30.40.33,WIC,DEN01
##@NIBU@##eos2393,172.30.40.34,WIC,DEN01
##@NIBU@##eos2394,172.30.40.35,WIC,DEN01
##@NIBU@##eos2395,172.30.40.36,WIC,DEN01
##@NIBU@##eos2396,172.30.40.37,WIC,DEN01
##@NIBU@##eos2397,172.30.40.38,WIC,DEN01
##@NIBU@##eos2398,172.30.40.39,WIC,DEN01
##@NIBU@##eos2399,172.30.40.40,WIC,DEN01
##@NIBU@##eos2400,10.17.59.155,WIC,OMA10
##@NIBU@##eos2401,10.17.59.156,WIC,OMA10
##@NIBU@##eos2402,10.17.59.157,WIC,OMA10
##@NIBU@##eos2403,10.17.59.158,WIC,OMA10
##@NIBU@##eos2404,10.17.59.159,WIC,OMA10
##@NIBU@##eos2405,10.17.59.160,WIC,OMA10
##@NIBU@##eos2406,10.17.59.161,WIC,OMA10
##@NIBU@##eos2407,10.17.59.162,WIC,OMA10
##@NIBU@##eos2408,10.17.59.163,WIC,OMA10
##@NIBU@##eos2409,10.17.59.164,WIC,OMA10
##@NIBU@##eos2410,10.17.59.165,WIC,OMA10
##@NIBU@##eos2411,10.17.59.166,WIC,OMA10
##@NIBU@##eos2412,10.17.59.167,WIC,OMA10
##@NIBU@##eos2413,10.17.59.168,WIC,OMA10
##@NIBU@##eos2414,10.17.59.169,WIC,OMA10
##@NIBU@##eos2415,10.17.59.170,WIC,OMA10
##@NIBU@##eos2416,10.17.59.171,WIC,OMA10
##@NIBU@##eos2417,10.17.59.172,WIC,OMA10
##@NIBU@##eos2418,10.17.60.205,WIC,OMA10
##@NIBU@##eos2419,10.17.60.206,WIC,OMA10
##@NIBU@##eos2420,10.17.60.207,WIC,OMA10
##@NIBU@##eos2421,10.17.60.208,WIC,OMA10
##@NIBU@##eos2422,10.17.60.209,WIC,OMA10
##@NIBU@##eos2423,10.17.60.210,WIC,OMA10
##@NIBU@##eos2424,10.17.60.211,WIC,OMA10
##@NIBU@##eos2425,10.17.60.212,WIC,OMA10
##@NIBU@##eos2426,10.17.60.213,WIC,OMA10
##@NIBU@##eos2427,10.17.60.214,WIC,OMA10
##@NIBU@##eos2428,10.17.60.215,WIC,OMA10
##@NIBU@##eos2429,10.17.60.216,WIC,OMA10
##@NIBU@##eos250,10.29.119.60,WIC,DEN01
##@NIBU@##eos251,10.29.119.62,WIC,DEN01
##@NIBU@##eos252,10.29.119.64,WIC,DEN01
##@NIBU@##eos253,10.29.119.66,WIC,DEN01
##@NIBU@##eos255,10.29.119.68,WIC,DEN01
##@NIBU@##eos256,10.29.119.70,WIC,DEN01
##@NIBU@##eos258,10.29.119.72,WIC,DEN01
##@NIBU@##eos259,10.29.119.74,WIC,DEN01
##@NIBU@##eos260,10.29.119.76,WIC,DEN01
##@NIBU@##eos262,10.29.119.78,WIC,DEN01
##@NIBU@##eos263,10.29.119.80,WIC,DEN01
##@NIBU@##eos264,10.29.119.82,WIC,DEN01
##@NIBU@##eos265,10.29.119.84,WIC,DEN01
##@NIBU@##eos2655,172.30.70.156,ITC,ATL01
##@NIBU@##eos2656,172.30.70.157,ITC,ATL01
##@NIBU@##eos2657,172.30.70.158,ITC,ATL01
##@NIBU@##eos2658,172.30.70.159,ITC,ATL01
##@NIBU@##eos2659,172.30.70.160,ITC,ATL01
##@NIBU@##eos266,10.29.119.86,WIC,DEN01
##@NIBU@##eos2660,172.30.70.161,ITC,ATL01
##@NIBU@##eos2661,172.30.70.162,ITC,ATL01
##@NIBU@##eos2662,172.30.70.163,ITC,ATL01
##@NIBU@##eos2663,172.30.70.164,ITC,ATL01
##@NIBU@##eos2664,172.30.70.165,ITC,ATL01
##@NIBU@##eos2665,172.30.70.166,ITC,ATL01
##@NIBU@##eos2666,172.30.70.167,ITC,ATL01
##@NIBU@##eos2667,172.30.70.168,ITC,ATL01
##@NIBU@##eos2668,172.30.70.169,ITC,ATL01
##@NIBU@##eos2669,172.30.70.170,ITC,ATL01
##@NIBU@##eos267,10.29.119.88,WIC,DEN01
##@NIBU@##eos2670,172.30.70.171,ITC,ATL01
##@NIBU@##eos2671,172.30.70.172,ITC,ATL01
##@NIBU@##eos2672,172.30.70.173,ITC,ATL01
##@NIBU@##eos2673,172.30.70.174,ITC,ATL01
##@NIBU@##eos2674,172.30.70.175,ITC,ATL01
##@NIBU@##eos2675,172.30.70.176,ITC,ATL01
##@NIBU@##eos2676,172.30.70.177,ITC,ATL01
##@NIBU@##eos2677,172.30.70.178,ITC,ATL01
##@NIBU@##eos2678,172.30.70.179,ITC,ATL01
##@NIBU@##eos2679,172.30.70.180,ITC,ATL01
##@NIBU@##eos269,10.29.119.90,WIC,DEN01
##@NIBU@##eos2690,10.19.60.142,WIC,OMA01
##@NIBU@##eos2691,10.19.60.144,WIC,OMA01
##@NIBU@##eos2692,10.19.60.146,WIC,OMA01
##@NIBU@##eos2693,10.19.60.148,WIC,OMA01
##@NIBU@##eos2694,10.19.60.150,WIC,OMA01
##@NIBU@##eos2695,10.19.60.152,WIC,OMA01
##@NIBU@##eos27,10.19.59.122,WIC,OMA01
##@NIBU@##eos270,10.29.119.92,WIC,DEN01
##@NIBU@##eos271,10.29.119.94,WIC,DEN01
##@NIBU@##eos272,10.29.119.96,WIC,DEN01
##@NIBU@##eos273,10.29.119.98,WIC,DEN01
##@NIBU@##eos2760,10.19.60.102,WIC,OMA01
##@NIBU@##eos2761,10.19.60.104,WIC,OMA01
##@NIBU@##eos2762,10.19.60.106,WIC,OMA01
##@NIBU@##eos2763,10.19.60.108,WIC,OMA01
##@NIBU@##eos2764,10.19.60.110,WIC,OMA01
##@NIBU@##eos2765,10.19.60.112,WIC,OMA01
##@NIBU@##eos2766,10.19.60.114,WIC,OMA01
##@NIBU@##eos2767,10.19.60.116,WIC,OMA01
##@NIBU@##eos2768,10.19.60.118,WIC,OMA01
##@NIBU@##eos2769,10.19.60.120,WIC,OMA01
##@NIBU@##eos2770,10.19.60.122,WIC,OMA01
##@NIBU@##eos2771,10.19.60.124,WIC,OMA01
##@NIBU@##eos2772,10.19.60.126,WIC,OMA01
##@NIBU@##eos2773,10.19.60.128,WIC,OMA01
##@NIBU@##eos2774,10.19.60.130,WIC,OMA01
##@NIBU@##eos2775,10.19.60.132,WIC,OMA01
##@NIBU@##eos2776,10.19.60.134,WIC,OMA01
##@NIBU@##eos2777,10.19.60.136,WIC,OMA01
##@NIBU@##eos2778,10.19.60.138,WIC,OMA01
##@NIBU@##eos2779,10.19.60.140,WIC,OMA01
##@NIBU@##eos2780,172.30.40.125,WIC,DEN01
##@NIBU@##eos2781,172.30.40.126,WIC,DEN01
##@NIBU@##eos2782,172.30.40.127,WIC,DEN01
##@NIBU@##eos2783,172.30.40.128,WIC,DEN01
##@NIBU@##eos2784,172.30.40.129,WIC,DEN01
##@NIBU@##eos2785,172.30.40.134,WIC,DEN01
##@NIBU@##eos2786,172.30.40.135,WIC,DEN01
##@NIBU@##eos2787,172.30.40.136,WIC,DEN01
##@NIBU@##eos2788,172.30.40.137,WIC,DEN01
##@NIBU@##eos2789,172.30.40.138,WIC,DEN01
##@NIBU@##eos2790,172.30.40.139,WIC,DEN01
##@NIBU@##eos2791,172.30.40.141,WIC,DEN01
##@NIBU@##eos2792,172.30.40.142,WIC,DEN01
##@NIBU@##eos2793,172.30.40.143,WIC,DEN01
##@NIBU@##eos2794,172.30.40.144,WIC,DEN01
##@NIBU@##eos2795,172.30.40.145,WIC,DEN01
##@NIBU@##eos2796,172.30.40.155,WIC,DEN01
##@NIBU@##eos2797,172.30.40.157,WIC,DEN01
##@NIBU@##eos2798,172.30.40.158,WIC,DEN01
##@NIBU@##eos2799,172.30.40.159,WIC,DEN01
##@NIBU@##eos28,10.19.59.124,WIC,OMA01
##@NIBU@##eos2810,172.30.72.91,ITC,ATL01
##@NIBU@##eos2811,172.30.72.92,ITC,ATL01
##@NIBU@##eos2812,172.30.72.93,ITC,ATL01
##@NIBU@##eos2813,172.30.72.94,ITC,ATL01
##@NIBU@##eos2814,172.30.72.95,ITC,ATL01
##@NIBU@##eos2815,172.30.72.96,ITC,ATL01
##@NIBU@##eos2816,172.30.72.97,ITC,ATL01
##@NIBU@##eos2850,10.19.59.100,WIC,OMA01
##@NIBU@##eos2851,10.19.59.101,WIC,OMA01
##@NIBU@##eos2852,10.19.59.102,WIC,OMA01
##@NIBU@##eos2853,10.19.59.103,WIC,OMA01
##@NIBU@##eos2854,10.19.59.104,WIC,OMA01
##@NIBU@##eos2855,10.19.59.105,WIC,OMA01
##@NIBU@##eos2856,10.19.59.106,WIC,OMA01
##@NIBU@##eos2857,10.19.59.107,WIC,OMA01
##@NIBU@##eos2871,10.29.97.107,WIC,DEN01
##@NIBU@##eos2872,10.29.97.108,WIC,DEN01
##@NIBU@##eos2873,10.29.97.109,WIC,DEN01
##@NIBU@##eos2874,10.29.97.110,WIC,DEN01
##@NIBU@##eos2875,10.29.97.111,WIC,DEN01
##@NIBU@##eos2876,10.29.97.112,WIC,DEN01
##@NIBU@##eos2877,10.29.97.113,WIC,DEN01
##@NIBU@##eos2878,10.29.97.114,WIC,DEN01
##@NIBU@##eos2879,10.29.97.115,WIC,DEN01
##@NIBU@##eos29,10.19.59.126,WIC,OMA01
##@NIBU@##eos2910,172.30.112.248,WIC,OMA00
##@NIBU@##eos2911,172.30.112.251,WIC,OMA00
##@NIBU@##eos2963,10.27.194.126,WIC,OMA00
##@NIBU@##eos2964,10.27.194.127,WIC,OMA00
##@NIBU@##eos2984,172.30.3.102,WIC,OMA01
##@NIBU@##eos2985,172.30.3.103,WIC,OMA01
##@NIBU@##eos2986,10.19.60.93,WIC,OMA01
##@NIBU@##eos2987,10.19.60.95,WIC,OMA01
##@NIBU@##eos3,10.29.119.24,WIC,DEN01
##@NIBU@##eos30,10.19.59.128,WIC,OMA01
##@NIBU@##eos3077,10.29.99.43,WIC,DEN01
##@NIBU@##eos3078,10.29.99.44,WIC,DEN01
##@NIBU@##eos3079,10.29.99.75,WIC,DEN01
##@NIBU@##eos3080,10.29.99.76,WIC,DEN01
##@NIBU@##eos3081,10.29.99.107,WIC,DEN01
##@NIBU@##eos3082,10.29.99.108,WIC,DEN01
##@NIBU@##eos3083,10.29.99.139,WIC,DEN01
##@NIBU@##eos3084,10.29.99.140,WIC,DEN01
##@NIBU@##eos3085,10.29.99.171,WIC,DEN01
##@NIBU@##eos3086,10.29.99.172,WIC,DEN01
##@NIBU@##eos3088,10.29.99.204,WIC,DEN01
##@NIBU@##eos31,10.19.59.130,WIC,OMA01
##@NIBU@##eos3125,10.19.52.21,WIC,OMA01
##@NIBU@##eos3126,10.19.52.22,WIC,OMA01
##@NIBU@##eos3127,10.19.52.23,WIC,OMA01
##@NIBU@##eos3140,10.28.96.51,WIC,ATL01
##@NIBU@##eos3141,10.28.96.52,WIC,ATL01
##@NIBU@##eos3142,10.28.96.81,WIC,ATL01
##@NIBU@##eos3143,10.28.96.82,WIC,ATL01
##@NIBU@##eos3144,10.28.96.113,WIC,ATL01
##@NIBU@##eos3145,10.28.96.114,WIC,ATL01
##@NIBU@##eos3146,10.28.96.145,WIC,ATL01
##@NIBU@##eos3147,10.28.96.146,WIC,ATL01
##@NIBU@##eos3148,10.28.96.178,WIC,ATL01
##@NIBU@##eos3149,10.28.96.179,WIC,ATL01
##@NIBU@##eos3163,10.28.106.21,WIC,ATL01
##@NIBU@##eos3164,10.28.106.35,WIC,ATL01
##@NIBU@##eos3165,10.28.106.22,WIC,ATL01
##@NIBU@##eos3166,10.28.106.36,WIC,ATL01
##@NIBU@##eos3167,10.28.106.23,WIC,ATL01
##@NIBU@##eos3168,10.28.106.37,WIC,ATL01
##@NIBU@##eos3169,10.28.106.24,WIC,ATL01
##@NIBU@##eos3170,10.28.106.38,WIC,ATL01
##@NIBU@##eos3171,10.28.106.25,WIC,ATL01
##@NIBU@##eos3172,10.28.106.39,WIC,ATL01
##@NIBU@##eos32,10.19.59.132,WIC,OMA01
##@NIBU@##eos33,10.19.57.23,WIC,OMA01
##@NIBU@##eos337,172.30.9.101,WIC,OMA10
##@NIBU@##eos34,10.19.57.25,WIC,OMA01
##@NIBU@##eos35,10.19.57.27,WIC,OMA01
##@NIBU@##eos350,10.19.55.61,WIC,OMA01
##@NIBU@##eos351,10.19.55.63,WIC,OMA01
##@NIBU@##eos352,10.19.55.65,WIC,OMA01
##@NIBU@##eos353,10.19.55.67,WIC,OMA01
##@NIBU@##eos354,10.19.60.166,WIC,OMA01
##@NIBU@##eos355,10.19.60.168,WIC,OMA01
##@NIBU@##eos356,10.19.60.170,WIC,OMA01
##@NIBU@##eos358,10.19.60.174,WIC,OMA01
##@NIBU@##eos359,10.19.60.176,WIC,OMA01
##@NIBU@##eos36,10.19.57.29,WIC,OMA01
##@NIBU@##eos360,10.19.60.178,WIC,OMA01
##@NIBU@##eos362,10.19.60.182,WIC,OMA01
##@NIBU@##eos363,10.19.60.184,WIC,OMA01
##@NIBU@##eos364,10.19.60.154,WIC,OMA01
##@NIBU@##eos365,10.19.60.156,WIC,OMA01
##@NIBU@##eos366,10.19.60.158,WIC,OMA01
##@NIBU@##eos367,10.19.60.160,WIC,OMA01
##@NIBU@##eos368,10.19.60.162,WIC,OMA01
##@NIBU@##eos369,10.19.60.164,WIC,OMA01
##@NIBU@##eos37,10.19.57.31,WIC,OMA01
##@NIBU@##eos38,10.19.57.33,WIC,OMA01
##@NIBU@##eos388,172.30.7.1,WIC,OMA10
##@NIBU@##eos389,172.30.7.2,WIC,OMA10
##@NIBU@##eos39,10.19.57.35,WIC,OMA01
##@NIBU@##eos390,172.30.7.3,WIC,OMA10
##@NIBU@##eos391,172.30.7.4,WIC,OMA10
##@NIBU@##eos392,172.30.7.5,WIC,OMA10
##@NIBU@##eos393,172.30.7.6,WIC,OMA10
##@NIBU@##eos394,172.30.7.7,WIC,OMA10
##@NIBU@##eos395,172.30.7.8,WIC,OMA10
##@NIBU@##eos396,172.30.7.9,WIC,OMA10
##@NIBU@##eos397,172.30.7.10,WIC,OMA10
##@NIBU@##eos4,172.30.1.91,WIC,OMA01
##@NIBU@##eos40,10.19.57.37,WIC,OMA01
##@NIBU@##eos4000,172.30.114.96,WIC,OMA00
##@NIBU@##eos4001,172.30.114.190,WIC,OMA00
##@NIBU@##eos44,172.30.2.86,WIC,OMA01
##@NIBU@##eos48,172.30.2.87,WIC,OMA01
##@NIBU@##eos5,10.29.119.26,WIC,DEN01
##@NIBU@##eos500,172.30.9.125,WIC,OMA10
##@NIBU@##eos501,172.30.9.126,WIC,OMA10
##@NIBU@##eos502,172.30.9.127,WIC,OMA10
##@NIBU@##eos503,172.30.9.128,WIC,OMA10
##@NIBU@##eos504,172.30.9.129,WIC,OMA10
##@NIBU@##eos505,172.30.9.130,WIC,OMA10
##@NIBU@##eos506,172.30.9.131,WIC,OMA10
##@NIBU@##eos507,172.30.9.132,WIC,OMA10
##@NIBU@##eos508,172.30.9.133,WIC,OMA10
##@NIBU@##eos509,172.30.9.134,WIC,OMA10
##@NIBU@##Eos511,10.27.192.72,WIC,OMA00
##@NIBU@##Eos512,10.27.192.76,WIC,OMA00
##@NIBU@##Eos514,10.27.192.94,WIC,OMA00
##@NIBU@##Eos515,10.27.192.78,ITC,OMA00
##@NIBU@##Eos516,10.27.192.79,ITC,OMA00
##@NIBU@##Eos517,10.27.192.80,ITC,OMA00
##@NIBU@##Eos518,10.27.192.81,ITC,OMA00
##@NIBU@##Eos519,10.27.192.95,WIC,OMA00
##@NIBU@##eos524,172.30.112.181,WIC,OMA00
##@NIBU@##eos525,172.30.9.135,WIC,OMA10
##@NIBU@##eos526,172.30.9.136,WIC,OMA10
##@NIBU@##eos527,172.30.9.137,WIC,OMA10
##@NIBU@##eos528,172.30.9.138,WIC,OMA10
##@NIBU@##eos529,172.30.9.139,WIC,OMA10
##@NIBU@##eos530,172.30.9.140,WIC,OMA10
##@NIBU@##eos531,172.30.9.141,WIC,OMA10
##@NIBU@##eos532,172.30.9.142,WIC,OMA10
##@NIBU@##eos533,172.30.9.143,WIC,OMA10
##@NIBU@##eos534,172.30.9.144,WIC,OMA10
##@NIBU@##eos54,172.30.2.88,WIC,OMA01
##@NIBU@##eos540,10.27.194.75,WIC,OMA00
##@NIBU@##Eos541,10.27.192.83,WIC,OMA00
##@NIBU@##Eos542,10.27.192.84,WIC,OMA00
##@NIBU@##Eos543,10.27.192.85,WIC,OMA00
##@NIBU@##eos55,172.30.2.89,WIC,OMA01
##@NIBU@##eos564,10.17.59.197,WIC,OMA10
##@NIBU@##eos565,10.17.59.196,WIC,OMA10
##@NIBU@##eos567,10.17.59.21,WIC,OMA10
##@NIBU@##eos57,172.30.2.91,WIC,OMA01
##@NIBU@##eos58,172.30.2.92,WIC,OMA01
##@NIBU@##eos585,172.30.112.182,WIC,OMA00
##@NIBU@##eos586,172.30.8.94,WIC,OMA10
##@NIBU@##eos587,172.30.9.102,WIC,OMA10
##@NIBU@##eos59,172.30.2.93,WIC,OMA01
##@NIBU@##eos6,10.29.119.28,WIC,DEN01
##@NIBU@##eos600,172.31.65.197,WIC,ATL01
##@NIBU@##eos601,172.30.7.42,WIC,OMA10
##@NIBU@##eos602,172.31.65.198,WIC,ATL01
##@NIBU@##eos603,172.31.65.199,WIC,ATL01
##@NIBU@##eos604,172.31.65.205,WIC,ATL01
##@NIBU@##eos605,172.31.65.206,WIC,ATL01
##@NIBU@##eos606,172.31.65.207,WIC,ATL01
##@NIBU@##eos607,172.30.7.48,WIC,OMA10
##@NIBU@##eos608,172.31.65.208,WIC,ATL01
##@NIBU@##eos62,172.30.2.95,WIC,OMA01
##@NIBU@##Eos63,10.27.192.86,ITC,OMA00
##@NIBU@##Eos64,10.27.192.87,ITC,OMA00
##@NIBU@##eos7,10.29.119.30,WIC,DEN01
##@NIBU@##Eos71,10.27.192.88,ITC,OMA00
##@NIBU@##Eos72,10.27.192.89,WIC,OMA00
##@NIBU@##Eos781,10.27.192.90,WIC,OMA00
##@NIBU@##eos8,10.29.119.32,WIC,DEN01
##@NIBU@##eos811,172.30.9.1,WIC,OMA10
##@NIBU@##eos812,172.30.9.2,WIC,OMA10
##@NIBU@##eos813,172.30.9.3,WIC,OMA10
##@NIBU@##eos814,172.30.9.4,WIC,OMA10
##@NIBU@##eos815,172.30.9.5,WIC,OMA10
##@NIBU@##eos816,172.30.9.6,WIC,OMA10
##@NIBU@##eos817,172.30.9.7,WIC,OMA10
##@NIBU@##eos818,172.30.9.8,WIC,OMA10
##@NIBU@##eos819,172.30.9.9,WIC,OMA10
##@NIBU@##eos82,172.30.1.92,WIC,OMA01
##@NIBU@##eos820,172.30.9.10,WIC,OMA10
##@NIBU@##eos821,172.30.9.11,WIC,OMA10
##@NIBU@##eos822,172.30.9.12,WIC,OMA10
##@NIBU@##eos824,172.30.9.14,WIC,OMA10
##@NIBU@##eos825,172.30.9.15,WIC,OMA10
##@NIBU@##eos826,172.30.9.16,WIC,OMA10
##@NIBU@##eos827,172.30.9.17,WIC,OMA10
##@NIBU@##eos828,172.30.9.18,WIC,OMA10
##@NIBU@##eos829,172.30.9.19,WIC,OMA10
##@NIBU@##eos830,172.30.9.20,WIC,OMA10
##@NIBU@##eos831,172.30.9.21,WIC,OMA10
##@NIBU@##eos832,172.30.9.22,WIC,OMA10
##@NIBU@##eos833,172.30.9.23,WIC,OMA10
##@NIBU@##eos834,172.30.9.24,WIC,OMA10
##@NIBU@##eos840,10.17.59.145,WIC,OMA10
##@NIBU@##eos841,10.17.59.146,WIC,OMA10
##@NIBU@##eos842,172.30.52.197,WIC,OMA10
##@NIBU@##eos843,10.17.59.148,WIC,OMA10
##@NIBU@##eos844,10.17.59.149,WIC,OMA10
##@NIBU@##eos845,10.17.59.150,WIC,OMA10
##@NIBU@##eos846,10.17.59.151,WIC,OMA10
##@NIBU@##eos847,10.17.59.152,WIC,OMA10
##@NIBU@##eos848,10.17.59.153,WIC,OMA10
##@NIBU@##eos849,10.17.59.154,WIC,OMA10
##@NIBU@##eos879,172.30.7.11,WIC,OMA10
##@NIBU@##eos880,172.30.7.12,WIC,OMA10
##@NIBU@##eos881,172.30.7.13,WIC,OMA10
##@NIBU@##eos882,172.30.7.14,WIC,OMA10
##@NIBU@##eos883,172.30.7.15,WIC,OMA10
##@NIBU@##eos884,172.30.7.16,WIC,OMA10
##@NIBU@##eos885,172.30.7.17,WIC,OMA10
##@NIBU@##eos886,172.30.7.18,WIC,OMA10
##@NIBU@##eos887,172.30.7.19,WIC,OMA10
##@NIBU@##eos888,172.30.7.20,WIC,OMA10
##@NIBU@##eos889,172.30.7.21,WIC,OMA10
##@NIBU@##eos890,172.30.7.22,WIC,OMA10
##@NIBU@##eos891,172.30.7.23,WIC,OMA10
##@NIBU@##eos892,172.30.7.24,WIC,OMA10
##@NIBU@##eos893,172.30.7.25,WIC,OMA10
##@NIBU@##eos894,172.30.7.26,WIC,OMA10
##@NIBU@##eos895,172.30.7.27,WIC,OMA10
##@NIBU@##eos896,172.30.7.28,WIC,OMA10
##@NIBU@##eos897,172.30.7.29,WIC,OMA10
##@NIBU@##eos898,172.30.7.30,WIC,OMA10
##@NIBU@##eos899,172.30.7.31,WIC,OMA10
##@NIBU@##eos9,10.29.119.34,WIC,DEN01
##@NIBU@##eos900,172.30.7.32,WIC,OMA10
##@NIBU@##eos901,172.30.7.33,WIC,OMA10
##@NIBU@##eos902,172.30.7.34,WIC,OMA10
##@NIBU@##eos903,172.30.7.35,WIC,OMA10
##@NIBU@##eos904,172.30.7.36,WIC,OMA10
##@NIBU@##eos913,172.30.7.37,WIC,OMA10
##@NIBU@##eos914,172.30.7.38,WIC,OMA10
##@NIBU@##eos915,172.30.7.39,WIC,OMA10
##@NIBU@##eos916,172.30.7.40,WIC,OMA10
##@NIBU@##eos920,172.30.2.96,WIC,OMA01
##@NIBU@##eos922,172.30.2.98,WIC,OMA01
##@NIBU@##eos923,172.30.2.99,WIC,OMA01
##@NIBU@##eos924,172.30.2.100,WIC,OMA01
##@NIBU@##eos925,172.30.2.101,WIC,OMA01
##@NIBU@##eos926,172.30.2.102,WIC,OMA01
##@NIBU@##eos927,172.30.2.103,WIC,OMA01
##@NIBU@##eos928,172.30.2.104,WIC,OMA01
##@NIBU@##eos929,172.30.2.105,WIC,OMA01
##@NIBU@##eos930,172.30.2.106,WIC,OMA01
##@NIBU@##eos931,172.30.2.107,WIC,OMA01
##@NIBU@##eos932,172.30.2.108,WIC,OMA01
##@NIBU@##eos933,172.30.2.109,WIC,OMA01
##@NIBU@##eos934,172.30.2.110,WIC,OMA01
##@NIBU@##eos935,172.30.2.111,WIC,OMA01
##@NIBU@##eos936,172.30.2.112,WIC,OMA01
##@NIBU@##eos937,172.30.2.113,WIC,OMA01
##@NIBU@##eos938,172.30.2.114,WIC,OMA01
##@NIBU@##eos939,172.30.2.115,WIC,OMA01
##@NIBU@##eos940,172.30.2.116,WIC,OMA01
##@NIBU@##eos941,172.30.2.117,WIC,OMA01
##@NIBU@##eos942,172.30.2.118,WIC,OMA01
##@NIBU@##eos943,172.30.2.119,WIC,OMA01
##@NIBU@##eos944,172.30.2.120,WIC,OMA01
##@NIBU@##eos945,172.30.2.121,WIC,OMA01
##@NIBU@##eos946,172.30.2.122,WIC,OMA01
##@NIBU@##eos947,172.30.2.123,WIC,OMA01
##@NIBU@##eos948,172.30.2.124,WIC,OMA01
##@NIBU@##eos949,172.30.2.125,WIC,OMA01
##@NIBU@##eos950,10.19.57.77,WIC,OMA01
##@NIBU@##eos951,10.19.57.39,WIC,OMA01
##@NIBU@##eos952,10.19.57.41,WIC,OMA01
##@NIBU@##eos953,10.19.57.43,WIC,OMA01
##@NIBU@##eos954,10.19.57.45,WIC,OMA01
##@NIBU@##eos955,10.19.57.47,WIC,OMA01
##@NIBU@##eos956,10.19.57.49,WIC,OMA01
##@NIBU@##eos957,10.19.57.51,WIC,OMA01
##@NIBU@##eos958,10.19.57.53,WIC,OMA01
##@NIBU@##eos959,10.19.57.55,WIC,OMA01
##@NIBU@##eos960,10.19.57.57,WIC,OMA01
##@NIBU@##eos961,10.19.57.59,WIC,OMA01
##@NIBU@##eos962,10.19.57.61,WIC,OMA01
##@NIBU@##eos963,10.19.57.63,WIC,OMA01
##@NIBU@##eos964,10.19.57.65,WIC,OMA01
##@NIBU@##eos965,10.19.57.67,WIC,OMA01
##@NIBU@##eos967,10.19.57.71,WIC,OMA01
##@NIBU@##eos968,10.19.57.73,WIC,OMA01
##@NIBU@##eos969,10.19.57.75,WIC,OMA01
##@NIBU@##eos970,172.30.8.70,WIC,OMA10
##@NIBU@##eos972,172.30.8.72,WIC,OMA10
##@NIBU@##eos973,172.30.8.73,WIC,OMA10
##@NIBU@##eos974,172.30.8.74,WIC,OMA10
##@NIBU@##eos975,172.30.8.75,WIC,OMA10
##@NIBU@##eos976,172.30.8.76,WIC,OMA10
##@NIBU@##eos977,172.30.8.77,WIC,OMA10
##@NIBU@##eos978,172.30.8.78,WIC,OMA10
##@NIBU@##eos979,172.30.8.79,WIC,OMA10
##@NIBU@##eos980,172.30.8.80,WIC,OMA10
##@NIBU@##eos981,172.30.8.81,WIC,OMA10
##@NIBU@##eos982,172.30.8.82,WIC,OMA10
##@NIBU@##eos983,172.30.8.83,WIC,OMA10
##@NIBU@##eos984,172.30.8.84,WIC,OMA10
##@NIBU@##eos985,172.30.8.85,WIC,OMA10
##@NIBU@##eos986,172.30.8.86,WIC,OMA10
##@NIBU@##eos987,172.30.8.87,WIC,OMA10
##@NIBU@##eos988,172.30.8.88,WIC,OMA10
##@NIBU@##gpetl001,10.17.100.73,WIC,OMA10
##@NIBU@##gpetl002,10.17.100.74,WIC,OMA10
##@NIBU@##hawkeye,10.62.118.16,ITC,WPT02
##@NIBU@##hera.armwest.icm,10.251.49.151,WCMG,OMA11
##@NIBU@##ibm100,10.27.194.30,WIC,OMA00
##@NIBU@##ibm104,172.30.8.182,WIC,OMA10
##@NIBU@##ibm105,172.30.41.160,WIC,DEN01
##@NIBU@##ibm108,10.29.124.45,WIC,DEN01
##@NIBU@##ibm112,10.29.122.72,WIC,DEN01
##@NIBU@##ibm114,172.30.8.153,WIC,OMA10
##@NIBU@##ibm119,10.27.123.24,WIC,OMA00
##@NIBU@##ibm124,172.30.10.113,EIT,OMA10
##@NIBU@##ibm126,172.30.41.158,WIC,DEN01
##@NIBU@##ibm127,172.30.0.104,WIC,OMA01
##@NIBU@##ibm136,172.30.43.164,EIT,DEN01
##@NIBU@##ibm137,172.30.10.151,WIC,OMA10
##@NIBU@##ibm143,216.57.110.47,WIC,SAT01
##@NIBU@##ibm145,10.27.194.25,WIC,OMA00
##@NIBU@##ibm146,10.27.194.26,WIC,OMA00
##@NIBU@##ibm149,10.27.216.155,WIC,OMA00
##@NIBU@##ibm152,172.30.112.84,WIC,OMA00
##@NIBU@##ibm153,10.42.119.22,WIC,SAT01
##@NIBU@##ibm171,172.30.43.175,WIC,DEN01
##@NIBU@##ibm193,172.30.39.100,WIC,DEN01
##@NIBU@##ibm194,172.30.8.184,WIC,OMA10
##@NIBU@##ibm195,172.30.2.126,WIC,OMA01
##@NIBU@##ibm197,172.30.78.136,EIT,OMA00
##@NIBU@##ibm203,172.30.78.139,WIC,OMA00
##@NIBU@##ibm204,172.30.39.109,ITC,DEN01
##@NIBU@##ibm208,172.30.1.17,WIC,OMA01
##@NIBU@##ibm209,172.30.0.109,WIC,OMA01
##@NIBU@##ibm210,172.30.41.161,ITC,DEN01
##@NIBU@##ibm211,172.30.78.140,ITC,ATL01
##@NIBU@##ibm212,172.30.10.100,WIC,OMA10
##@NIBU@##ibm213,172.30.4.100,WIC,OMA01
##@NIBU@##ibm215,10.27.194.88,WIC,OMA00
##@NIBU@##ibm216,10.27.194.89,WIC,OMA00
##@NIBU@##ibm217,10.29.114.36,WIC,DEN01
##@NIBU@##ibm218,10.27.194.91,WIC,OMA00
##@NIBU@##ibm219,10.28.124.53,WIC,ATL01
##@NIBU@##ibm23,172.30.113.157,WIC,OMA00
##@NIBU@##ibm231,172.30.41.177,WIC,DEN01
##@NIBU@##ibm232,172.30.7.149,WIC,OMA10
##@NIBU@##ibm233l,10.27.216.58,WIC,OMA00
##@NIBU@##ibm234l,10.27.216.59,WIC,OMA00
##@NIBU@##ibm237,172.30.113.229,WIC,OMA00
##@NIBU@##ibm242,10.27.220.27,WIC,OMA00
##@NIBU@##ibm243,172.30.78.154,ITC,ATL01
##@NIBU@##ibm245,172.30.153.21,WIC,OMA01
##@NIBU@##ibm246,172.30.153.20,WIC,OMA01
##@NIBU@##ibm248,10.27.194.27,WIC,OMA00
##@NIBU@##ibm249,172.30.43.154,ITC,DEN01
##@NIBU@##ibm250,172.30.43.153,ITC,DEN01
##@NIBU@##ibm252,172.30.78.160,ITC,ATL01
##@NIBU@##ibm253,172.30.78.161,ITC,ATL01
##@NIBU@##ibm255,10.18.129.66,EIT,OMA11
##@NIBU@##ibm258,172.30.57.20,WIC,DEN01
##@NIBU@##ibm259,172.30.57.21,WIC,DEN01
##@NIBU@##ibm261,172.30.185.20,WIC,OMA10
##@NIBU@##ibm262,172.30.185.21,WIC,OMA10
##@NIBU@##ibm263,172.30.113.74,WIC,OMA00
##@NIBU@##ibm264,172.30.113.75,WIC,OMA00
##@NIBU@##ibm266,10.27.194.28,WIC,OMA00
##@NIBU@##ibm267,10.27.194.29,WIC,OMA00
##@NIBU@##ibm268,10.27.194.33,ITC,OMA00
##@NIBU@##ibm270,172.30.21.90,EIT,SAT01
##@NIBU@##ibm271,172.30.21.91,WIC,SAT01
##@NIBU@##ibm272,172.30.116.105,WCMG,OMA00
##@NIBU@##ibm276,10.27.58.78,WIC,OMA00
##@NIBU@##ibm277,10.18.118.66,EIT,OMA11
##@NIBU@##ibm278,172.30.185.23,WIC,OMA10
##@NIBU@##ibm279,172.30.153.22,WIC,OMA01
##@NIBU@##ibm281,172.30.57.23,WIC,DEN01
##@NIBU@##ibm29,172.30.112.101,WIC,OMA00
##@NIBU@##ibm290,172.30.78.179,WCMG,ATL01
##@NIBU@##ibm293,172.30.1.171,EIT,OMA01
##@NIBU@##ibm295,172.30.57.24,WIC,DEN01
##@NIBU@##ibm296,172.30.185.24,WIC,OMA10
##@NIBU@##ibm298,172/na,WIC,DEN01
##@NIBU@##ibm300,172.30.43.189,WIC,DEN01
##@NIBU@##ibm321,172.30.78.19,WIC,OMA00
##@NIBU@##ibm324,172.30.1.128,WIC,OMA01
##@NIBU@##ibm327,172.30.10.51,WNG,OMA10
##@NIBU@##ibm329,172.30.21.158,WIC,SAT01
##@NIBU@##ibm33,10.27.194.80,WIC,OMA00
##@NIBU@##ibm330,172.30.112.83,WIC,OMA00
##@NIBU@##ibm332,172.30.10.180,WIC,OMA10
##@NIBU@##ibm344,172.30.41.122,WCMG,DEN01
##@NIBU@##ibm347,10.18.129.67,WIC,OMA11
##@NIBU@##ibm348,10.18.129.68,WIC,OMA11
##@NIBU@##ibm349,see wicdevhmc,WIC,OMA00
##@NIBU@##ibm351,10.27.58.47,WCMG,OMA00
##@NIBU@##ibm352,000.000.000.996,WIC,DEN01
##@NIBU@##ibm357,10.18.153.110,WIC,OMA11
##@NIBU@##ibm358,10.18.153.117,WIC,OMA11
##@NIBU@##ibm360,216.57.102.49,WIC,OMA01
##@NIBU@##ibm361,216.57.102.50,WIC,OMA01
##@NIBU@##ibm362,10.19.117.82,WIC,OMA01
##@NIBU@##ibm363,10.19.117.84,WIC,OMA01
##@NIBU@##ibm364,10.19.117.86,WIC,OMA01
##@NIBU@##ibm365,10.29.124.35,WIC,DEN01
##@NIBU@##ibm366,10.29.124.36,WIC,DEN01
##@NIBU@##ibm367,172.30.9.196,WIC,OMA10
##@NIBU@##ibm368,10.29.122.13,WNG,DEN01
##@NIBU@##ibm371,10.18.146.22,WIC,OMA11
##@NIBU@##ibm374,10.27.216.40,WIC,OMA00
##@NIBU@##ibm376,10.31.40.30,ITC,PHX01
##@NIBU@##ibm378,10.31.40.29,ITC,PHX01
##@NIBU@##ibm383,10.27.194.115,ITC,OMA00
##@NIBU@##ibm387,10.27.194.95,WIC,OMA00
##@NIBU@##ibm388,172.30.8.176,WNG,OMA10
##@NIBU@##ibm389,10.27.123.50,WIC,OMA00
##@NIBU@##ibm390,172.30.7.154,WIC,OMA10
##@NIBU@##ibm392,10.27.123.70,EIT,OMA00
##@NIBU@##ibm393,10.29.124.64,WIC,DEN01
##@NIBU@##ibm394,10.29.124.67,WIC,DEN01
##@NIBU@##ibm395,10.31.72.23,ITC,PHX01
##@NIBU@##ibm396,10.31.72.24,ITC,PHX01
##@NIBU@##ibm399,10.163.72.40,ITC,SIN01
##@NIBU@##ibm40,172.30.21.164,WIC,SAT01
##@NIBU@##ibm400,10.163.72.41,ITC,SIN01
##@NIBU@##ibm405,10.31.135.27,ITC,PHX01
##@NIBU@##ibm406,10.27.194.118,WIC,OMA00
##@NIBU@##ibm411,10.29.122.57,WIC,DEN01
##@NIBU@##ibm412,172.30.78.55,WIC,ATL01
##@NIBU@##ibm415,10.129.2.100,TVX,DEN01
##@NIBU@##ibm416,172.30.78.57,WCMG,ATL01
##@NIBU@##ibm417,10.29.124.76,WCMG,DEN01
##@NIBU@##ibm419,10.18.139.25,WIC,OMA11
##@NIBU@##ibm420,10.62.21.24,ITC,WPT01
##@NIBU@##ibm421,10.27.113.78,WIC,OMA00
##@NIBU@##ibm423,10.128.2.97,TVX,ATL01
##@NIBU@##ibm424,10.29.114.68,WIC,DEN01
##@NIBU@##ibm425,10.17.61.220,WIC,OMA10
##@NIBU@##ibm426,10.17.61.222,WIC,OMA10
##@NIBU@##ibm427,10.28.124.71,WIC,ATL01
##@NIBU@##ibm428,10.62.72.63,ITC,VAL01
##@NIBU@##ibm429,10.64.10.22,ITC,SWN01
##@NIBU@##ibm431,10.64.5.100,ITC,SWN01
##@NIBU@##ibm432,10.64.5.101,ITC,SWN01
##@NIBU@##ibm433,10.64.3.100,ITC,SWN01
##@NIBU@##ibm434,10.64.3.101,ITC,SWN01
##@NIBU@##ibm435,10.64.2.100,ITC,SWN01
##@NIBU@##ibm436,10.27.124.126,EIT,OMA00
##@NIBU@##ibm437,10.64.10.63,ITC,SWN01
##@NIBU@##ibm439,172.30.10.173,WIC,OMA10
##@NIBU@##ibm44,172.30.21.169,WIC,SAT01
##@NIBU@##ibm440,10.28.200.28,ITC,ATL01
##@NIBU@##ibm441,10.28.200.52,ITC,ATL01
##@NIBU@##ibm442,10.42.117.68,WCMG,SAT01
##@NIBU@##ibm443,10.27.220.32,ITC,OMA00
##@NIBU@##ibm444,172.30.112.217,EIT,OMA00
##@NIBU@##ibm445,10.28.124.35,EIT,ATL01
##@NIBU@##ibm446,10.29.114.32,EIT,DEN01
##@NIBU@##ibm447,10.27.113.41,WIC,OMA00
##@NIBU@##ibm448,10.27.113.42,WIC,OMA00
##@NIBU@##ibm45,172.30.10.48,WIC,OMA10
##@NIBU@##ibm451,10.29.114.35,WIC,DEN01
##@NIBU@##ibm452,10.29.100.36,WIC,DEN01
##@NIBU@##ibm453,10.28.100.25,WIC,ATL01
##@NIBU@##ibm455,10.27.214.208,ITC,OMA00
##@NIBU@##ibm456,10.27.194.51,ITC,OMA00
##@NIBU@##ibm457,10.31.40.69,ITC,PHX01
##@NIBU@##ibm458,10.31.40.71,ITC,PHX01
##@NIBU@##ibm461,10.31.72.90,ITC,PHX01
##@NIBU@##ibm462,10.31.72.92,ITC,PHX01
##@NIBU@##ibm463,10.27.216.95,ITC,OMA00
##@NIBU@##ibm464,10.31.103.33,ITC,PHX01
##@NIBU@##ibm465,10.31.103.35,ITC,PHX01
##@NIBU@##ibm466,10.31.135.32,ITC,PHX01
##@NIBU@##ibm467,10.31.135.34,ITC,PHX01
##@NIBU@##ibm468,10.29.168.62,ITC,DEN01
##@NIBU@##ibm469,10.29.168.64,ITC,DEN01
##@NIBU@##ibm470,10.28.168.34,ITC,ATL01
##@NIBU@##ibm471,10.28.168.36,ITC,ATL01
##@NIBU@##ibm472,10.28.184.34,ITC,ATL01
##@NIBU@##ibm473,10.28.184.36,ITC,ATL01
##@NIBU@##ibm474,10.166.200.28,ITC,LON09
##@NIBU@##ibm475,10.166.200.52,ITC,LON09
##@NIBU@##ibm476,10.64.12.90,ITC,SWN01
##@NIBU@##ibm477,10.64.12.54,ITC,SWN01
##@NIBU@##ibm478,10.167.200.28,ITC,SHG01
##@NIBU@##ibm479,10.167.200.30,ITC,SHG01
##@NIBU@##ibm480,172.30.112.16,WIC,OMA00
##@NIBU@##ibm481,10.168.200.28,ITC,SIN04
##@NIBU@##ibm482,10.168.200.52,ITC,SIN04
##@NIBU@##ibm483,10.27.114.66,CORP,OMA00
##@NIBU@##ibm484,172.30.43.165,CORP,DEN01
##@NIBU@##ibm488,10.42.100.50,WBS,SAT01
##@NIBU@##ibm489,10.27.216.164,WIC,OMA00
##@NIBU@##ibm490,10.64.49.56,ITC,SWN01
##@NIBU@##ibm491,10.27.115.62,EIT,OMA00
##@NIBU@##ibm492,10.64.49.67,ITC,SWN01
##@NIBU@##ibm493,10.17.125.20,WIC,OMA10
##@NIBU@##ibm494,10.70.2.44,WIC,DEN06
##@NIBU@##ibm495,10.70.2.34,WIC,DEN06
##@NIBU@##ibm496,10.27.122.169,WIC,OMA00
##@NIBU@##ibm497,10.29.114.72,WIC,DEN01
##@NIBU@##ibm498,172.30.7.247,WIC,OMA10
##@NIBU@##ibm499,10.62.72.64,ITC,VAL01
##@NIBU@##ibm500,10.62.72.65,ITC,VAL01
##@NIBU@##ibm501,10.62.72.66,ITC,VAL01
##@NIBU@##ibm502,10.27.110.47,CORP,OMA00
##@NIBU@##ibm503,ibm503 NOIP,EIT,OMA00
##@NIBU@##ibm504,ibm504 NOIP,EIT,OMA00
##@NIBU@##ibm505,10.27.69.21,EIT,OMA00
##@NIBU@##ibm506,10.27.69.23,EIT,OMA00
##@NIBU@##ibm508,10.27.69.27,EIT,OMA00
##@NIBU@##ibm509,10.50.210.37,EIT,OMA00
##@NIBU@##ibm510,10.50.210.38,EIT,OMA00
##@NIBU@##ibm511,10.50.210.39,EIT,OMA00
##@NIBU@##ibm512,10.50.210.40,EIT,OMA00
##@NIBU@##ibm513,10.50.210.80,EIT,OMA00
##@NIBU@##ibm514,10.50.210.81,EIT,OMA00
##@NIBU@##ibm515,10.50.210.82,EIT,OMA00
##@NIBU@##ibm516,10.27.69.28,EIT,OMA00
##@NIBU@##ibm517,10.27.69.30,EIT,OMA00
##@NIBU@##ibm518,10.27.69.33,EIT,OMA00
##@NIBU@##ibm519,10.50.210.83,EIT,OMA00
##@NIBU@##ibm520,10.50.210.84,EIT,OMA00
##@NIBU@##ibm521,10.50.210.85,EIT,OMA00
##@NIBU@##ibm522,10.50.210.86,EIT,OMA00
##@NIBU@##ibm523,10.50.210.87,EIT,OMA00
##@NIBU@##ibm524,10.50.210.88,EIT,OMA00
##@NIBU@##ibm525,10.50.210.89,EIT,OMA00
##@NIBU@##ibm526,10.27.69.24,EIT,OMA00
##@NIBU@##ibm527,10.27.69.31,EIT,OMA00
##@NIBU@##ibm528,10.27.69.32,EIT,OMA00
##@NIBU@##ibm529,10.62.72.127,ITC,VAL01
##@NIBU@##ibm530,10.166.200.72,ITC,LON09
##@NIBU@##ibm531,10.166.200.64,ITC,LON09
##@NIBU@##ibm533,10.70.1.12,EIT,DEN06
##@NIBU@##ibm534,10.72.200.35,ITC,DEN06
##@NIBU@##ibm535,10.72.200.36,ITC,DEN06
##@NIBU@##ibm536,10.72.200.54,ITC,DEN06
##@NIBU@##ibm537,10.72.200.55,ITC,DEN06
##@NIBU@##ibm538,10.70.64.22,EIT,DEN06
##@NIBU@##ibm539,10.27.69.25,CORP,OMA00
##@NIBU@##ibm54,172.30.112.203,EIT,OMA00
##@NIBU@##ibm541,10.72.200.81,ITC,DEN06
##@NIBU@##ibm542,10.72.200.82,ITC,DEN06
##@NIBU@##ibm543,10.27.214.140,ITC,OMA00
##@NIBU@##ibm544,10.170.200.37,ITC,SYD07
##@NIBU@##ibm545,10.170.200.38,ITC,SYD07
##@NIBU@##ibm546,10.31.72.111,ITC,PHX01
##@NIBU@##ibm547,10.31.72.112,ITC,PHX01
##@NIBU@##ibm548,10.72.0.22,ITC,DEN06
##@NIBU@##ibm549,10.72.0.23,ITC,DEN06
##@NIBU@##ibm550,10.63.100.175,ITC,DEN05
##@NIBU@##ibm551,10.27.110.86,WIC,OMA00
##@NIBU@##ibm552,10.64.49.107,ITC,SWN01
##@NIBU@##ibm553,10.64.4.42,ITC,SWN01
##@NIBU@##ibm554,10.112.8.35,ITC,MUM03
##@NIBU@##ibm555,10.112.8.36,ITC,MUM03
##@NIBU@##ibm556,ibm556,WIC,DEN01
##@NIBU@##ibm557,10.28.106.57,WNI,OMA00
##@NIBU@##ibm558,10.29.114.76,WNI,DEN01
##@NIBU@##IBM560,10.72.216.35,ITC,DEN06
##@NIBU@##IBM561,10.72.216.36,ITC,DEN06
##@NIBU@##IBM562,10.72.216.52,ITC,DEN06
##@NIBU@##IBM563,10.72.216.53,ITC,DEN06
##@NIBU@##ibm564,10.72.216.77,ITC,DEN06
##@NIBU@##ibm565,10.72.216.78,ITC,DEN06
##@NIBU@##IBM566boot,10.17.125.30,WNG,OMA10
##@NIBU@##IBM567boot,10.17.125.31,WNG,OMA10
##@NIBU@##ibm572,10.162.40.26,ITC,GLC01
##@NIBU@##ibm573,10.162.40.27,ITC,GLC01
##@NIBU@##IBM574,N/A,WIC,ATL01
##@NIBU@##IBM578,10.64.49.144,ITC,SWN01
##@NIBU@##ibm579,10.64.49.145,ITC,SWN01
##@NIBU@##ibm580,10.166.168.35,ITC,LON13
##@NIBU@##ibm581,10.166.168.36,ITC,LON13
##@NIBU@##IBM582,none,ITC,DEN06
##@NIBU@##ibm589,10.28.100.36,WIC,ATL01
##@NIBU@##ibm593,10.29.104.110,WIC,DEN01
##@NIBU@##ibm594,10.29.104.111,WIC,DEN01
##@NIBU@##ibm595,10.29.104.112,WIC,DEN01
##@NIBU@##ibm596,10.29.104.113,WIC,DEN01
##@NIBU@##ibm597,10.29.104.114,WIC,DEN01
##@NIBU@##ibm598,10.29.104.115,WIC,DEN01
##@NIBU@##ibm599,10.29.104.116,WIC,DEN01
##@NIBU@##ibm600,10.29.104.117,WIC,DEN01
##@NIBU@##IBM601,10.65.40.35,ITC,SWN01
##@NIBU@##IBM602,10.65.40.36,ITC,SWN01
##@NIBU@##ibm607,10.65.40.70,ITC,SWN01
##@NIBU@##ibm608,10.65.40.79,ITC,SWN01
##@NIBU@##ibm609,10.65.40.62,ITC,SWN01
##@NIBU@##ibm610,10.65.40.63,ITC,SWN01
##@NIBU@##IBM611,10.27.128.118/119/120/121/122/123,WIC,OMA00
##@NIBU@##ibm612,10.72.0.44,ITC,DEN06
##@NIBU@##ibm613,10.72.0.45,ITC,DEN06
##@NIBU@##ibm614,10.72.0.46,ITC,DEN06
##@NIBU@##ibm615,10.72.0.47,ITC,DEN06
##@NIBU@##ibm616,10.72.0.48,ITC,DEN06
##@NIBU@##ibm617,10.72.0.49,ITC,DEN06
##@NIBU@##ibm618,10.72.0.50,ITC,DEN06
##@NIBU@##ibm619,10.72.0.51,ITC,DEN06
##@NIBU@##ibm620,10.72.0.52,ITC,DEN06
##@NIBU@##ibm621,10.72.0.53,ITC,DEN06
##@NIBU@##ibm622,10.72.0.54,ITC,DEN06
##@NIBU@##ibm623,10.72.0.55,ITC,DEN06
##@NIBU@##ibm624,10.72.0.56,ITC,DEN06
##@NIBU@##ibm625,10.72.0.57,ITC,DEN06
##@NIBU@##ibm626,10.72.0.58,ITC,DEN06
##@NIBU@##ibm627,10.72.0.59,ITC,DEN06
##@NIBU@##ibm628,10.72.0.60,ITC,DEN06
##@NIBU@##ibm630,10.27.128.120,WIC,OMA00
##@NIBU@##ibm631,10.27.128.121,WIC,OMA00
##@NIBU@##ibm632,10.27.128.122,WIC,OMA00
##@NIBU@##ibm633,10.27.128.123,WIC,OMA00
##@NIBU@##IBM637,0.0.0.0,WIC,DEN01
##@NIBU@##IBM638,0.0.0.0,WIC,ATL01
##@NIBU@##ibm639,10.166.168.76,ITC,LON13
##@NIBU@##ibm640,10.166.168.77,ITC,LON13
##@NIBU@##ibm65,10.27.124.103,WIC,OMA00
##@NIBU@##ibm654,10.28.100.52,WIC,ATL01
##@NIBU@##ibm712,10.168.216.35,ITC,SIN10
##@NIBU@##ibm713,10.168.216.36,ITC,SIN10
##@NIBU@##IBM714,10.65.56.35,ITC,SWN01
##@NIBU@##IBM715,10.65.56.36,ITC,SWN01
##@NIBU@##IBM716,10.65.56.52,ITC,SWN01
##@NIBU@##IBM717,10.65.56.53,ITC,SWN01
##@NIBU@##IBM718,10.65.56.68,ITC,SWN01
##@NIBU@##IBM719,10.65.56.69,ITC,SWN01
##@NIBU@##ibm720,10.166.118.56,ITC,LON13
##@NIBU@##ibm722,10.170.200.47,ITC,SYD07
##@NIBU@##IBM724,10.64.49.45,ITC,SWN01
##@NIBU@##IBM725,10.64.49.46,ITC,SWN01
##@NIBU@##ibm726,10.168.112.50,ITC,SIN10
##@NIBU@##ibm727,10.168.112.51,ITC,SIN10
##@NIBU@##ibm728,10.166.118.57,ITC,LON13
##@NIBU@##ibm729,10.166.118.58,ITC,LON13
##@NIBU@##ibm730,10.27.201.29,ITC,OMA00
##@NIBU@##ibm731,10.70.7.11,WIC,DEN06
##@NIBU@##ibm732,10.70.7.12,WIC,DEN06
##@NIBU@##IBM737,10.166.168.119,ITC,LON13
##@NIBU@##IBM738,10.166.168.120,ITC,LON13
##@NIBU@##ibm74,172.30.112.202,WIC,OMA00
##@NIBU@##ibm77,172.30.7.177,WIC,OMA10
##@NIBU@##ibm78,172.30.112.107,WIC,OMA00
##@NIBU@##ibm79,172.30.1.109,WIC,OMA01
##@NIBU@##ibm84,172.30.1.15,WIC,OMA01
##@NIBU@##ibm85,172.30.9.172,WIC,OMA10
##@NIBU@##ibm9,10.29.124.33,WIC,DEN01
##@NIBU@##ibm90,10.27.216.56,WIC,OMA00
##@NIBU@##ibm91,10.27.216.57,WIC,OMA00
##@NIBU@##ibm94,172.30.43.186,EIT,DEN01
##@NIBU@##ibm95,172.30.7.213,WIC,OMA10
##@NIBU@##ibm96,10.27.216.90,WIC,OMA00
##@NIBU@##ibmx,10.27.194.67,WIC,OMA00
##@NIBU@##icauls02,10.62.236.20,ITC,MBW01
##@NIBU@##icauls03,10.62.223.23,ITC,SYD01
##@NIBU@##icauls05,10.62.223.22,ITC,MBW01
##@NIBU@##icauls06,10.62.236.24,ITC,MBW01
##@NIBU@##iccals03,ICCALS03,ITC,EDM01
##@NIBU@##iccals04,10.169.200.40,ITC,EDM01
##@NIBU@##iccals05,10.169.200.41,ITC,EDM01
##@NIBU@##iccals06,10.169.200.42,ITC,TOR03
##@NIBU@##iccals08,10.169.200.21,ITC,TOR03
##@NIBU@##iccals09,10.169.200.22,ITC,TOR03
##@NIBU@##iccals10,10.169.200.23,ITC,TOR03
##@NIBU@##iccals11,10.169.200.24,ITC,TOR03
##@NIBU@##icexls02,192.168.10.191,ITC,SWN01
##@NIBU@##icexls04,192.168.10.23,ITC,SWN01
##@NIBU@##icexls08,ICEXLS08,ITC,SWN01
##@NIBU@##icexls15,192.168.10.92,ITC,SWN01
##@NIBU@##icexls16,192.168.20.41,ITC,SWN01
##@NIBU@##icexls17,192.168.20.42,ITC,SWN01
##@NIBU@##icexls18,192.168.20.43,ITC,SWN01
##@NIBU@##icexls19,192.168.20.44,ITC,SWN01
##@NIBU@##icexls20,192.168.10.222,ITC,SWN01
##@NIBU@##icexls23,192.168.10.223,ITC,SWN01
##@NIBU@##icexls24,192.168.20.30,ITC,SWN01
##@NIBU@##icexls25,192.168.10.43,ITC,SWN01
##@NIBU@##icexls28,192.168.10.58,ITC,SWN01
##@NIBU@##icexls32,192.168.10.50,ITC,SWN01
##@NIBU@##icexls34,192.168.10.52,ITC,SWN01
##@NIBU@##icexls36,192.168.10.220,ITC,SWN01
##@NIBU@##icexls37,192.168.10.221,ITC,SWN01
##@NIBU@##icexls38,192.168.10.237,ITC,SWN01
##@NIBU@##icexls40,192.168.10.238,ITC,SWN01
##@NIBU@##icexls41,192.168.10.239,ITC,SWN01
##@NIBU@##icexls42,10.62.10.235,ITC,SWN01
##@NIBU@##icexls43,10.62.10.236,ITC,SWN01
##@NIBU@##icexls46,ICEXLS46,ITC,SWN01
##@NIBU@##icexls47,192.168.10.59,ITC,SWN01
##@NIBU@##icexls48,192.168.10.60,ITC,SWN01
##@NIBU@##icexls50,192.168.10.140,ITC,SWN01
##@NIBU@##icexls51,192.168.10.141,ITC,SWN01
##@NIBU@##icexls52,192.168.10.142,ITC,SWN01
##@NIBU@##icexls53,192.168.10.143,ITC,SWN01
##@NIBU@##icexls54,192.168.10.144,ITC,SWN01
##@NIBU@##icexls55,ICEXLS55,ITC,SWN01
##@NIBU@##icexls56,ICEXLS56,ITC,SWN01
##@NIBU@##icexls59,192.168.10.102,ITC,SWN01
##@NIBU@##icexls60,192.168.10.103,ITC,SWN01
##@NIBU@##icexls61,192.168.10.104,ITC,SWN01
##@NIBU@##icexls63,192.168.10.163,ITC,SWN01
##@NIBU@##icexls64,192.168.10.164,ITC,SWN01
##@NIBU@##icexls65,192.168.10.165,ITC,SWN01
##@NIBU@##icexls68,10.64.22.86,ITC,SWN01
##@NIBU@##icexls69,192.168.10.169,ITC,SWN01
##@NIBU@##icexls71,10.62.10.71,ITC,SWN01
##@NIBU@##icexls72,10.62.10.72,ITC,SWN01
##@NIBU@##icexls73,10.62.10.73,ITC,SWN01
##@NIBU@##icexls76,10.62.10.237,ITC,SWN01
##@NIBU@##icexls77,192.168.10.242,ITC,SWN01
##@NIBU@##icexls78,192.168.10.109,ITC,SWN01
##@NIBU@##icexls79,192.168.10.110,ITC,SWN01
##@NIBU@##icexls80,192.168.10.205,ITC,SWN01
##@NIBU@##icexls81,192.168.10.206,ITC,SWN01
##@NIBU@##icextess01,10.64.10.89,ITC,SWN01
##@NIBU@##icextim01,10.62.10.59,ITC,SWN01
##@NIBU@##icextim02,10.62.10.60,ITC,SWN01
##@NIBU@##icindls01,10.62.41.10,ITC,DEL01
##@NIBU@##icindls02,10.62.41.11,ITC,DEL01
##@NIBU@##icindls03,10.62.41.12,ITC,DEL01
##@NIBU@##icindls04,10.62.41.13,ITC,DEL01
##@NIBU@##icngdns01,10.62.36.9,ITC,NWN01
##@NIBU@##icsgls01 _old,192.168.226.36,ITC,SIN01
##@NIBU@##icsgls02_old,192.168.226.35,ITC,SIN01
##@NIBU@##Icukls04,10.62.119.9,ITC,GLC02
##@NIBU@##Icukls05,10.62.119.72,ITC,GLC02
##@NIBU@##icukls07,10.62.119.50,ITC,GLC01
##@NIBU@##icukls08,10.62.119.51,ITC,GLC01
##@NIBU@##icukls09,10.62.119.52,ITC,GLC01
##@NIBU@##icukls10,10.62.119.53,ITC,GLC01
##@NIBU@##icukls29,10.62.119.49,ITC,GLC01
##@NIBU@##icukls30,10.62.122.26,ITC,GLC01
##@NIBU@##icuksl14,ICUKSL14,ITC,GLC01
##@NIBU@##icvaaix01,10.62.72.102,ITC,VAL01
##@NIBU@##icvaaix03,10.62.72.104,ITC,VAL01
##@NIBU@##icvaaix05,10.62.72.125,ITC,VAL01
##@NIBU@##icvals03,10.62.125.9,ITC,VAL01
##@NIBU@##icvals05,10.62.72.131,ITC,VAL01
##@NIBU@##icvatime01,10.6.128.16,ITC,VAL01
##@NIBU@##icwpaix06,10.62.72.129,ITC,VAL01
##@NIBU@##icwpbb01,10.62.21.199,EIT,WPT01
##@NIBU@##icwpbb01-new,ICWPBB01-NEW,EIT,WPT01
##@NIBU@##icwpbb02,10.62.21.145,EIT,WPT01
##@NIBU@##icwpesw2,10.62.29.115,ITC,WPT03
##@NIBU@##icwpesw-b,10.62.29.114,ITC,WPT03
##@NIBU@##icwpeweb,10.62.29.15,ITC,WPT03
##@NIBU@##icwpeweb01,10.62.29.31,ITC,WPT03
##@NIBU@##icwpeweb02,10.62.29.30,ITC,WPT03
##@NIBU@##icwpls01,10.62.22.30,ITC,WPT01
##@NIBU@##icwpls02,10.62.21.23,ITC,WPT01
##@NIBU@##icwpls03,10.62.21.98,ITC,WPT01
##@NIBU@##icwpls04,172.16.21.51,ITC,WPT01
##@NIBU@##icwpls05,10.62.21.13,ITC,WPT01
##@NIBU@##icwpls06,10.62.21.12,ITC,WPT01
##@NIBU@##icwpls07,ICWPLS07,ITC,WPT01
##@NIBU@##icwpls08,100.1.4.103,ITC,WPT01
##@NIBU@##icwpls09,100.1.4.104,ITC,WPT01
##@NIBU@##icwpls10,10.62.21.221,ITC,WPT01
##@NIBU@##icwpls100,10.62.21.101,ITC,WPT01
##@NIBU@##icwpls101,10.62.26.101,ITC,WPT03
##@NIBU@##icwpls102,10.62.26.102,ITC,WPT03
##@NIBU@##icwpls104,10.62.26.104,ITC,WPT03
##@NIBU@##icwpls105,10.62.26.105,ITC,WPT03
##@NIBU@##icwpls106,10.62.21.44,ITC,WPT01
##@NIBU@##icwpls107,10.62.21.45,ITC,WPT01
##@NIBU@##icwpls108,10.62.21.89,ITC,WPT01
##@NIBU@##icwpls109,10.62.21.90,ITC,WPT01
##@NIBU@##icwpls11,10.62.21.62,ITC,WPT01
##@NIBU@##icwpls112,10.62.21.58,ITC,WPT01
##@NIBU@##icwpls113,10.62.21.59,ITC,WPT01
##@NIBU@##icwpls114,10.62.22.247,ITC,WPT01
##@NIBU@##icwpls116,10.62.21.110,ITC,WPT01
##@NIBU@##icwpls12,10.62.21.155,ITC,WPT01
##@NIBU@##icwpls13,ICWPLS13,ITC,WPT01
##@NIBU@##icwpls14,10.62.22.32,ITC,WPT01
##@NIBU@##icwpls15,ICWPLS15,ITC,WPT01
##@NIBU@##icwpls16,ICWPLS16,ITC,WPT01
##@NIBU@##icwpls165,10.62.22.165,ITC,WPT01
##@NIBU@##icwpls166,10.62.22.166,ITC,WPT01
##@NIBU@##icwpls167,10.62.22.167,ITC,WPT01
##@NIBU@##icwpls168,10.62.22.168,ITC,WPT01
##@NIBU@##icwpls17,100.1.4.131,ITC,WPT01
##@NIBU@##icwpls18,100.1.4.133,ITC,WPT01
##@NIBU@##icwpls19,100.1.4.135,ITC,WPT01
##@NIBU@##icwpls20,100.1.4.137,ITC,WPT01
##@NIBU@##icwpls22,ICWPLS22,ITC,WPT01
##@NIBU@##icwpls23,ICWPLS23,ITC,WPT01
##@NIBU@##icwpls24,100.1.1.23,ITC,WPT01
##@NIBU@##icwpls25,10.62.26.44,ITC,WPT03
##@NIBU@##icwpls26,10.62.26.45,ITC,WPT03
##@NIBU@##icwpls27,ICWPLS27,ITC,WPT03
##@NIBU@##icwpls28,ICWPLS28,ITC,WPT03
##@NIBU@##icwpls29,ICWPLS29,ITC,WPT03
##@NIBU@##icwpls30,ICWPLS30,ITC,WPT03
##@NIBU@##icwpls31,ICWPLS31,ITC,WPT03
##@NIBU@##icwpls32,10.62.21.232,ITC,WPT01
##@NIBU@##icwpls33,10.62.21.233,ITC,WPT01
##@NIBU@##icwpls34,10.62.21.234,ITC,WPT01
##@NIBU@##icwpls35,10.62.22.55,ITC,WPT01
##@NIBU@##icwpls36,10.62.22.34,ITC,WPT01
##@NIBU@##icwpls37,10.62.22.56,ITC,WPT01
##@NIBU@##icwpls40,100.1.4.55,ITC,WPT01
##@NIBU@##icwpls41,100.1.4.56,ITC,WPT01
##@NIBU@##icwpls42,10.62.22.57,ITC,WPT01
##@NIBU@##icwpls43,10.62.22.65,ITC,WPT01
##@NIBU@##icwpls44,ICWPLS44,ITC,WPT03
##@NIBU@##icwpls46,ICWPLS46,ITC,WPT01
##@NIBU@##icwpls47,100.1.4.74,ITC,WPT03
##@NIBU@##icwpls48,100.1.4.75,ITC,WPT03
##@NIBU@##icwpls51,10.62.21.17,ITC,WPT01
##@NIBU@##icwpls52,10.62.21.18,ITC,WPT01
##@NIBU@##icwpls53,10.62.21.19,ITC,WPT01
##@NIBU@##icwpls54,ICWPLS54,ITC,WPT01
##@NIBU@##icwpls55,ICWPLS55,ITC,WPT01
##@NIBU@##icwpls56,ICWPLS56,ITC,WPT01
##@NIBU@##icwpls58,ICWPLS58,ITC,WPT01
##@NIBU@##icwpls59,10.62.27.11,ITC,WPT02
##@NIBU@##icwpls60,172.16.22.54,ITC,WPT02
##@NIBU@##icwpls62,ICWPLS62,ITC,WPT01
##@NIBU@##icwpls63,ICWPLS63,ITC,WPT01
##@NIBU@##icwpls64,ICWPLS64,ITC,WPT01
##@NIBU@##icwpls65,10.62.22.61,ITC,WPT01
##@NIBU@##icwpls66,ICWPLS66,ITC,WPT01
##@NIBU@##icwpls67,ICWPLS67,ITC,WPT01
##@NIBU@##icwpls68,10.62.22.68,ITC,WPT01
##@NIBU@##icwpls73,172.16.21.73,ITC,WPT01
##@NIBU@##icwpls74,10.62.21.206,ITC,WPT01
##@NIBU@##icwpls75,ICWPLS75,ITC,WPT03
##@NIBU@##icwpls76,ICWPLS76,ITC,WPT03
##@NIBU@##icwpls77,172.16.21.77,ITC,WPT01
##@NIBU@##icwpls78,10.62.21.78,ITC,WPT01
##@NIBU@##icwpls79,10.62.21.79,ITC,WPT01
##@NIBU@##icwpls80,172.16.21.53,ITC,WPT02
##@NIBU@##icwpls81,10.62.21.81,ITC,WPT01
##@NIBU@##icwpls82,ICWPLS82,ITC,WPT01
##@NIBU@##icwpls83,10.62.21.83,ITC,WPT01
##@NIBU@##icwpls84,10.62.21.84,ITC,WPT01
##@NIBU@##icwpls85,10.62.21.85,ITC,WPT01
##@NIBU@##icwpls86,10.62.21.31,ITC,WPT01
##@NIBU@##icwpls90,10.62.21.86,ITC,WPT01
##@NIBU@##icwpls91,10.62.21.87,ITC,WPT01
##@NIBU@##icwpls92,icwpls92,ITC,WPT01
##@NIBU@##icwpls93,icwpls93,ITC,WPT01
##@NIBU@##icwpls94,10.62.21.94,ITC,WPT01
##@NIBU@##icwpls95,10.62.21.164,ITC,WPT01
##@NIBU@##icwpls96,10.62.21.40,ITC,WPT01
##@NIBU@##icwpls97,10.62.21.41,ITC,WPT01
##@NIBU@##icwpls98,10.62.21.222,ITC,WPT01
##@NIBU@##icwpls99,10.62.21.223,ITC,WPT01
##@NIBU@##icwpmail1,10.62.21.22,ITC,WPT01
##@NIBU@##icwpmail2,10.62.21.21,ITC,WPT01
##@NIBU@##icwpss00,100.1.1.230,ITC,WPT01
##@NIBU@##icwpss01,100.1.1.231,ITC,WPT01
##@NIBU@##icwpss02,10.62.21.99,ITC,WPT01
##@NIBU@##icwpss05,10.62.72.47,ITC,VAL01
##@NIBU@##icwpss08,ICWPSS08,ITC,WPT01
##@NIBU@##icwpss09,10.62.26.22,ITC,WPT03
##@NIBU@##icwpss11,10.62.72.13,ITC,VAL01
##@NIBU@##icwpss13,Using testaix05 IP- Alias,ITC,WPT01
##@NIBU@##icwpss15,10.62.72.41,ITC,VAL01
##@NIBU@##icwpss16,10.62.72.43,ITC,VAL01
##@NIBU@##icwpss17,172.16.26.84,ITC,WPT03
##@NIBU@##icwpss18,10.62.26.21,ITC,WPT03
##@NIBU@##icwpss19,192.168.115.119,ITC,VAL02
##@NIBU@##icwpss20,10.62.21.25,ITC,WPT01
##@NIBU@##icwpss21,100.1.1.89,ITC,WPT01
##@NIBU@##icwpss22,ICWPSS22,ITC,WPT03
##@NIBU@##icwpss23,10.62.33.23,ITC,WPT02
##@NIBU@##icwpss24,10.62.33.25,ITC,WPT02
##@NIBU@##icwpss25,10.62.115.200,ITC,VAL02
##@NIBU@##icwpss26,10.62.115.202,ITC,VAL02
##@NIBU@##icwpss27,10.62.115.201,ITC,VAL02
##@NIBU@##icwpss29,172.16.26.83,ITC,WPT03
##@NIBU@##icwpss31,172.16.26.85,ITC,WPT03
##@NIBU@##icwpss32,10.62.26.108,ITC,WPT03
##@NIBU@##icwpss33,10.62.33.12,ITC,WPT02
##@NIBU@##icwpss34,10.62.72.34,ITC,VAL01
##@NIBU@##icwpss36,10.62.26.112,ITC,WPT03
##@NIBU@##icwpss37,ICWPSS37,ITC,WPT02
##@NIBU@##icwpss38,10.62.22.31,ITC,WPT01
##@NIBU@##icwpss39,172.16.26.86,ITC,WPT03
##@NIBU@##icwpss40,172.16.26.88,ITC,WPT03
##@NIBU@##icwpss41,172.16.26.87,ITC,WPT03
##@NIBU@##icwpss42,10.62.72.17,ITC,VAL01
##@NIBU@##icwpss43,10.62.72.19,ITC,VAL01
##@NIBU@##icwpss44,172.16.22.64,ITC,WPT01
##@NIBU@##icwpss45,172.16.22.65,ITC,WPT01
##@NIBU@##icwpss46,ICWPSS46,ITC,VAL02
##@NIBU@##icwpss48,ICWPSS48,ITC,VAL02
##@NIBU@##icwpss50,10.62.33.11,ITC,WPT02
##@NIBU@##icwpss51,192.168.115.150,ITC,VAL02
##@NIBU@##icwpss52,ICWPSS52,ITC,WPT01
##@NIBU@##icwpss53,ICWPSS53,ITC,WPT01
##@NIBU@##icwpss54,10.62.26.54,ITC,WPT03
##@NIBU@##icwpss55,10.62.26.55,ITC,WPT03
##@NIBU@##icwpss56,10.62.33.148,ITC,WPT02
##@NIBU@##icwpss57,10.62.33.149,ITC,WPT02
##@NIBU@##icwpss58,10.62.72.15,ITC,VAL01
##@NIBU@##icwpss59,10.62.72.16,ITC,VAL01
##@NIBU@##icwpss66,10.62.21.166,ITC,WPT01
##@NIBU@##icwpss67,ICWPSS67,ITC,WPT02
##@NIBU@##icwpss68,10.62.72.68,ITC,VAL01
##@NIBU@##icwpss69,10.62.33.66,ITC,WPT02
##@NIBU@##icwpss70,10.62.21.70,ITC,WPT01
##@NIBU@##icwpss73,10.62.21.28,ITC,WPT01
##@NIBU@##icwpss74,10.62.21.29,ITC,WPT01
##@NIBU@##icwpss75,10.62.21.205,ITC,WPT01
##@NIBU@##icwpss76,10.62.115.206,ITC,VAL02
##@NIBU@##icwpss77,10.62.115.205,ITC,VAL02
##@NIBU@##icwpss78,10.62.115.207,ITC,VAL02
##@NIBU@##icwpss79,10.62.26.206,ITC,WPT03
##@NIBU@##icwpss80,10.62.26.205,ITC,WPT03
##@NIBU@##icwpss81,10.62.26.207,ITC,WPT03
##@NIBU@##icwpss82,ICWPSS82,ITC,WPT03
##@NIBU@##icwpss83,ICWPSS83,ITC,WPT03
##@NIBU@##icwpss84,ICWPSS84,ITC,WPT03
##@NIBU@##icwpss86,10.62.21.42,ITC,WPT01
##@NIBU@##icwptime01,10.62.21.6,ITC,WPT01
##@NIBU@##impervadf3,10.70.4.13,WIC,DEN06
##@NIBU@##impervadf4,10.28.102.120,WIC,ATL01
##@NIBU@##lawson,10.62.21.126,ITC,WPT01
##@NIBU@##legato-master 1,100.1.4.150,ITC,WPT01
##@NIBU@##legato-master 2,100.1.4.151,ITC,WPT03
##@NIBU@##linunx5918,10.27.217.149,WIC,OMA00
##@NIBU@##linux1,10.27.194.64,WIC,OMA00
##@NIBU@##linux1000,216.57.106.27,WIC,SAT01
##@NIBU@##linux1001,216.57.106.28,WIC,SAT01
##@NIBU@##linux1002,216.57.106.29,WIC,SAT01
##@NIBU@##linux1003,216.57.106.30,WIC,SAT01
##@NIBU@##linux1004,216.57.110.27,WIC,SAT01
##@NIBU@##linux1005,216.57.110.28,WIC,SAT01
##@NIBU@##linux1006,216.57.110.29,WIC,SAT01
##@NIBU@##linux1007,216.57.110.30,WIC,SAT01
##@NIBU@##linux1008,216.57.110.31,WIC,SAT01
##@NIBU@##linux1009,10.42.122.122,WIC,SAT01
##@NIBU@##linux1010,linux1010,ITC,PHX01
##@NIBU@##linux1011,linux1011,ITC,PHX01
##@NIBU@##linux1012,10.27.123.20,WIC,OMA00
##@NIBU@##linux1013,216.57.98.48,ITC,OMA01
##@NIBU@##linux1014,216.57.98.47,ITC,OMA01
##@NIBU@##linux1015,10.27.123.23,ITC,OMA00
##@NIBU@##linux104,10.27.194.142,WIC,OMA00
##@NIBU@##linux1044,10.27.115.95,WIC,OMA00
##@NIBU@##linux1045,10.17.52.239,WIC,OMA10
##@NIBU@##linux1046,10.17.52.240,WIC,OMA10
##@NIBU@##linux1047,10.17.52.241,WIC,OMA10
##@NIBU@##linux1048,10.29.96.208,WIC,DEN01
##@NIBU@##linux1049,10.29.96.213,WIC,DEN01
##@NIBU@##linux105,10.27.193.73,WIC,OMA00
##@NIBU@##linux1050,10.29.96.214,WIC,DEN01
##@NIBU@##linux1051,10.27.123.26,EIT,OMA00
##@NIBU@##linux1053,10.27.214.209,ITC,OMA00
##@NIBU@##linux1054,10.27.193.64,WIC,OMA00
##@NIBU@##linux1055,10.27.194.147,WIC,OMA00
##@NIBU@##linux1056,10.27.194.148,WIC,OMA00
##@NIBU@##linux106,10.27.193.74,WIC,OMA00
##@NIBU@##linux107,10.27.193.75,WIC,OMA00
##@NIBU@##linux1072,10.70.0.53,WIC,DEN06
##@NIBU@##linux1073,10.70.0.67,WIC,DEN06
##@NIBU@##linux1075,10.70.0.92,WIC,DEN06
##@NIBU@##linux1076,10.29.96.238,WIC,DEN01
##@NIBU@##linux1077,10.29.96.247,WIC,DEN01
##@NIBU@##linux1078,10.27.128.27,WIC,OMA00
##@NIBU@##linux1079,10.29.96.246,WIC,DEN01
##@NIBU@##linux108,10.27.193.76,WIC,OMA00
##@NIBU@##linux1080,10.29.96.240,WIC,DEN01
##@NIBU@##linux1081,10.17.53.55,WIC,OMA10
##@NIBU@##linux1082,10.17.53.42,WIC,OMA10
##@NIBU@##linux1083,10.17.53.54,WIC,OMA10
##@NIBU@##linux1084,10.17.53.43,WIC,OMA10
##@NIBU@##linux1085,10.17.53.53,WIC,OMA10
##@NIBU@##linux1086,10.17.53.44,WIC,OMA10
##@NIBU@##linux1087,10.27.128.29,WIC,OMA00
##@NIBU@##linux1088,10.27.128.30,WIC,OMA00
##@NIBU@##linux1089,10.27.128.28,WIC,OMA00
##@NIBU@##linux109,10.27.193.77,WIC,OMA00
##@NIBU@##linux1091,10.42.122.125,EIT,SAT01
##@NIBU@##linux1094,10.17.53.49,WIC,OMA10
##@NIBU@##linux1095,10.18.153.114,WIC,OMA11
##@NIBU@##linux1096,10.18.153.112,WIC,OMA11
##@NIBU@##linux1097,10.18.153.115,WIC,OMA11
##@NIBU@##linux1098,10.18.153.116,WIC,OMA11
##@NIBU@##linux1099,10.27.123.34,ITC,OMA00
##@NIBU@##linux11,10.27.193.36,EIT,OMA00
##@NIBU@##linux110,10.27.193.78,WIC,OMA00
##@NIBU@##linux1100,10.27.123.35,ITC,OMA00
##@NIBU@##linux1101,10.27.123.36,ITC,OMA00
##@NIBU@##linux1102,10.27.123.37,ITC,OMA00
##@NIBU@##linux1103,216.57.106.34,ITC,SAT01
##@NIBU@##linux1104,216.57.106.35,ITC,SAT01
##@NIBU@##linux1106,216.57.110.35,ITC,SAT01
##@NIBU@##linux1107,10.27.193.176,WIC,OMA00
##@NIBU@##linux1108,10.27.193.177,WIC,OMA00
##@NIBU@##linux1109,10.29.97.12,WIC,DEN01
##@NIBU@##linux111,10.27.193.49,WIC,OMA00
##@NIBU@##linux1110,10.29.97.13,WIC,DEN01
##@NIBU@##linux1111,10.29.97.14,WIC,DEN01
##@NIBU@##linux1112,10.29.97.15,WIC,DEN01
##@NIBU@##linux1113,10.29.97.16,WIC,DEN01
##@NIBU@##linux1114,10.29.97.20,WIC,DEN01
##@NIBU@##linux1115,10.29.97.21,WIC,DEN01
##@NIBU@##linux1116,10.29.97.22,WIC,DEN01
##@NIBU@##linux1117,10.29.97.23,WIC,DEN01
##@NIBU@##linux1118,10.29.97.24,WIC,DEN01
##@NIBU@##linux1119,10.29.97.25,WIC,DEN01
##@NIBU@##linux112,10.27.193.50,WIC,OMA00
##@NIBU@##linux1120,10.27.194.101,WIC,OMA00
##@NIBU@##linux1122,10.29.97.42,WIC,DEN01
##@NIBU@##linux1123,10.29.97.43,WIC,DEN01
##@NIBU@##linux1124,10.29.97.44,WIC,DEN01
##@NIBU@##linux1125,10.29.97.45,WIC,DEN01
##@NIBU@##linux1126,10.29.97.46,WIC,DEN01
##@NIBU@##linux1127,10.29.97.51,WIC,DEN01
##@NIBU@##linux1128,10.29.97.52,WIC,DEN01
##@NIBU@##linux1129,10.29.97.53,WIC,DEN01
##@NIBU@##linux1130,10.29.97.54,WIC,DEN01
##@NIBU@##linux1131,10.29.97.55,WIC,DEN01
##@NIBU@##linux1132,10.27.193.169,WIC,OMA00
##@NIBU@##linux1133,10.29.124.54,WIC,DEN01
##@NIBU@##linux1134,10.29.124.55,EIT,DEN01
##@NIBU@##linux1136,10.62.33.62,ITC,WPT02
##@NIBU@##linux1137,10.27.123.52,WIC,OMA00
##@NIBU@##linux1138,10.27.217.15,ITC,OMA00
##@NIBU@##linux1139,10.27.217.16,ITC,OMA00
##@NIBU@##linux1140,10.27.217.17,ITC,OMA00
##@NIBU@##linux1141,10.27.193.85,WIC,OMA00
##@NIBU@##linux1142,10.17.53.10,WIC,OMA10
##@NIBU@##linux1143,10.17.53.11,WIC,OMA10
##@NIBU@##linux1144,10.17.53.12,WIC,OMA10
##@NIBU@##linux1145,10.17.53.13,WIC,OMA10
##@NIBU@##linux1146,10.17.53.14,WIC,OMA10
##@NIBU@##linux1147,10.17.53.18,WIC,OMA10
##@NIBU@##linux1148,10.17.53.19,WIC,OMA10
##@NIBU@##linux1149,10.17.53.20,WIC,OMA10
##@NIBU@##linux115,10.27.193.122,ITC,OMA00
##@NIBU@##linux1150,10.17.53.21,WIC,OMA10
##@NIBU@##linux1151,10.17.53.22,WIC,OMA10
##@NIBU@##linux1152,10.17.53.23,WIC,OMA10
##@NIBU@##linux1153,10.17.52.234,WIC,OMA10
##@NIBU@##linux1155,10.17.52.236,WIC,OMA10
##@NIBU@##linux1156,10.17.52.237,WIC,OMA10
##@NIBU@##linux1157,10.17.52.238,WIC,OMA10
##@NIBU@##linux1158,10.17.52.243,WIC,OMA10
##@NIBU@##linux1159,10.17.52.244,WIC,OMA10
##@NIBU@##linux116,10.27.123.47,WIC,OMA00
##@NIBU@##linux1160,10.17.52.245,WIC,OMA10
##@NIBU@##linux1161,10.17.52.246,WIC,OMA10
##@NIBU@##linux1162,10.17.52.247,WIC,OMA10
##@NIBU@##linux1163,000.000.000.996,WIC,DEN01
##@NIBU@##linux1164,10.18.153.150,WIC,OMA11
##@NIBU@##linux1165,10.18.153.139,WIC,OMA11
##@NIBU@##LINUX1166,10.18.153.151,WIC,OMA11
##@NIBU@##linux118,10.27.110.78,ITC,OMA00
##@NIBU@##linux1181,10.17.53.74,WIC,OMA10
##@NIBU@##linux1182,10.17.53.75,WIC,OMA10
##@NIBU@##linux1183,10.17.53.76,WIC,OMA10
##@NIBU@##linux1184,10.17.53.77,WIC,OMA10
##@NIBU@##linux1185,10.17.53.78,WIC,OMA10
##@NIBU@##linux1186,10.17.53.79,WIC,OMA10
##@NIBU@##linux1187,10.17.53.80,WIC,OMA10
##@NIBU@##linux1188,10.17.53.81,WIC,OMA10
##@NIBU@##linux1189,10.17.53.82,WIC,OMA10
##@NIBU@##linux1190,10.17.53.83,WIC,OMA10
##@NIBU@##linux1191,10.17.53.84,WIC,OMA10
##@NIBU@##linux1192,10.17.53.85,WIC,OMA10
##@NIBU@##linux1193,10.17.53.86,WIC,OMA10
##@NIBU@##linux1194,10.29.97.236,WIC,DEN01
##@NIBU@##linux1195,10.29.97.237,WIC,DEN01
##@NIBU@##linux1196,10.29.97.238,WIC,DEN01
##@NIBU@##linux1197,10.29.97.239,WIC,DEN01
##@NIBU@##linux1198,10.29.97.240,WIC,DEN01
##@NIBU@##linux1199,10.29.97.241,WIC,DEN01
##@NIBU@##linux120,10.27.193.189,WIC,OMA00
##@NIBU@##linux1200,10.29.97.242,WIC,DEN01
##@NIBU@##linux1201,10.70.0.32,WIC,DEN06
##@NIBU@##linux1202,10.70.0.74,WIC,DEN06
##@NIBU@##linux1203,10.70.0.120,WIC,DEN06
##@NIBU@##linux1204,10.70.0.157,WIC,DEN06
##@NIBU@##linux1205,10.70.0.204,WIC,DEN06
##@NIBU@##linux1206,10.70.0.243,WIC,DEN06
##@NIBU@##linux1207,10.62.33.157,ITC,WPT02
##@NIBU@##linux1208,10.27.198.50,ITC,OMA00
##@NIBU@##linux1210,10.64.2.46,ITC,SWN01
##@NIBU@##linux1211,10.64.2.47,ITC,SWN01
##@NIBU@##linux1212,10.64.2.48,ITC,SWN01
##@NIBU@##linux1213,10.64.2.49,ITC,SWN01
##@NIBU@##linux1214,10.31.72.49,ITC,PHX01
##@NIBU@##linux1215,10.31.72.50,ITC,PHX01
##@NIBU@##linux1216,10.31.72.51,ITC,PHX01
##@NIBU@##linux1217,10.31.72.52,ITC,PHX01
##@NIBU@##linux1218,10.31.72.53,ITC,PHX01
##@NIBU@##linux1219,10.31.72.54,ITC,PHX01
##@NIBU@##linux1220,10.27.216.173,ITC,OMA00
##@NIBU@##linux1221,10.27.216.174,ITC,OMA00
##@NIBU@##linux1222,10.31.72.27,ITC,PHX01
##@NIBU@##linux1223,10.31.72.28,ITC,PHX01
##@NIBU@##linux1224,10.31.72.29,ITC,PHX01
##@NIBU@##linux1225,10.31.72.30,ITC,PHX01
##@NIBU@##linux1226,10.27.193.182,WIC,OMA00
##@NIBU@##linux1227,10.27.193.183,WIC,OMA00
##@NIBU@##linux1228,10.64.12.58,ITC,SWN01
##@NIBU@##linux1229,10.64.12.59,ITC,SWN01
##@NIBU@##Linux123,172.30.4.158,WIC,OMA01
##@NIBU@##linux1230,10.64.12.60,ITC,SWN01
##@NIBU@##linux1231,10.64.12.61,ITC,SWN01
##@NIBU@##linux1232,216.57.110.43,WDR,SAT01
##@NIBU@##linux1233,216.57.110.44,WDR,SAT01
##@NIBU@##linux1234,216.57.102.210,WDR,OMA01
##@NIBU@##linux1235,192.168.113.11,WCMG,OMA00
##@NIBU@##linux1236,216.57.102.210,WDR,OMA01
##@NIBU@##linux1239,216.57.100.116,WIC,OMA01
##@NIBU@##Linux124,172.30.2.127,WIC,OMA01
##@NIBU@##linux1240,216.57.100.117,WIC,OMA01
##@NIBU@##linux1241,216.57.100.118,CORP,OMA01
##@NIBU@##linux1242,216.57.100.119,WIC,OMA01
##@NIBU@##linux1243,216.57.100.110,WIC,OMA01
##@NIBU@##linux1244,216.57.100.111,WIC,OMA01
##@NIBU@##linux1245,216.57.108.26,WIC,SAT01
##@NIBU@##linux1246,216.57.108.27,WIC,SAT01
##@NIBU@##linux1247,10.31.103.49,ITC,PHX01
##@NIBU@##linux1248,10.62.22.248,WIC,OMA00
##@NIBU@##linux1249,10.27.123.56,WIC,OMA00
##@NIBU@##linux125,10.27.193.86,WIC,OMA00
##@NIBU@##linux1250,216.57.106.31,WDR,SAT01
##@NIBU@##linux1251,10.27.216.38,ITC,OMA00
##@NIBU@##linux1252,10.27.216.39,ITC,OMA00
##@NIBU@##linux1253,10.31.40.58,ITC,PHX01
##@NIBU@##linux1254,10.27.220.57,ITC,OMA00
##@NIBU@##linux1255,10.27.216.81,WIC,OMA00
##@NIBU@##Linux1256,10.19.52.143,WIC,OMA01
##@NIBU@##Linux1257,10.19.52.146,WIC,OMA01
##@NIBU@##Linux1258,10.19.52.147,WIC,OMA01
##@NIBU@##linux1259,linux1259,WIC,DEN01
##@NIBU@##linux1261,10.17.53.17,WIC,OMA10
##@NIBU@##linux1262,10.27.217.18,WIC,OMA00
##@NIBU@##linux1263,10.162.40.45,ITC,GLC01
##@NIBU@##linux1264,10.162.40.46,ITC,GLC01
##@NIBU@##linux1265,10.162.40.47,ITC,GLC01
##@NIBU@##linux1266,10.162.40.48,ITC,GLC01
##@NIBU@##linux1267,10.162.40.49,ITC,GLC01
##@NIBU@##linux1268,10.162.40.50,ITC,GLC01
##@NIBU@##linux1269,10.162.40.51,ITC,GLC01
##@NIBU@##linux127,172.30.4.40,WIC,OMA01
##@NIBU@##linux1270,10.162.40.52,ITC,GLC01
##@NIBU@##linux1271,10.162.40.53,ITC,GLC01
##@NIBU@##linux1272,10.162.40.54,EIT,GLC01
##@NIBU@##linux1273,10.162.40.55,EIT,GLC01
##@NIBU@##linux1274,10.162.40.56,ITC,GLC01
##@NIBU@##linux1275,10.162.40.57,ITC,GLC01
##@NIBU@##linux1276,10.162.40.58,ITC,GLC01
##@NIBU@##linux1277,10.162.40.59,ITC,GLC01
##@NIBU@##linux1278,10.162.40.60,ITC,GLC01
##@NIBU@##linux1281,10.163.72.20,ITC,SIN01
##@NIBU@##linux1282,10.163.72.21,ITC,SIN01
##@NIBU@##linux1283,10.163.72.22,ITC,SYD07
##@NIBU@##linux1284,10.163.72.23,ITC,SYD07
##@NIBU@##linux1285,10.163.72.24,ITC,SYD07
##@NIBU@##linux1286,10.163.72.25,ITC,SYD07
##@NIBU@##linux1287,10.163.72.26,ITC,SIN01
##@NIBU@##linux1288,10.163.72.27,ITC,SYD01
##@NIBU@##linux1289,10.168.200.68,EIT,SIN01
##@NIBU@##linux1290,10.168.200.67,EIT,SIN01
##@NIBU@##linux1291,10.163.72.30,ITC,SYD01
##@NIBU@##linux1292,10.163.72.31,ITC,SYD01
##@NIBU@##linux1293,10.163.72.32,ITC,SYD07
##@NIBU@##linux1294,10.27.216.21,ITC,OMA00
##@NIBU@##linux1295,linux1295,WIC,OMA00
##@NIBU@##linux1296,10.27.216.23,ITC,OMA00
##@NIBU@##linux1297,10.28.200.47,ITC,ATL01
##@NIBU@##linux1298,10.28.200.48,ITC,ATL01
##@NIBU@##linux13,172.30.94.245,EIT,OMA11
##@NIBU@##linux130,10.27.192.82,WIC,OMA00
##@NIBU@##linux1300,10.19.115.21,WIC,OMA01
##@NIBU@##linux1301,10.19.115.28,WIC,OMA01
##@NIBU@##linux1302,10.19.115.23,WIC,OMA01
##@NIBU@##linux1303,10.42.119.34,WIC,SAT01
##@NIBU@##linux1304,172.30.78.34,WCMG,ATL01
##@NIBU@##linux1305,10.18.153.198,WIC,OMA11
##@NIBU@##linux1306,10.18.153.199,WIC,OMA11
##@NIBU@##linux1307,10.18.153.200,WIC,OMA11
##@NIBU@##linux1308,10.18.153.201,WIC,OMA11
##@NIBU@##linux1309,10.18.153.202,WIC,OMA11
##@NIBU@##linux1310,10.18.153.203,WIC,OMA11
##@NIBU@##linux1311,10.18.153.204,WIC,OMA11
##@NIBU@##linux1312,10.18.153.205,WIC,OMA11
##@NIBU@##linux1313,10.18.153.206,WIC,OMA11
##@NIBU@##linux1314,10.18.153.207,WIC,OMA11
##@NIBU@##linux1315,10.18.153.230,WIC,OMA11
##@NIBU@##linux1316,10.18.153.231,WIC,OMA11
##@NIBU@##linux1317,10.18.153.232,WIC,OMA11
##@NIBU@##linux1318,10.18.153.233,WIC,OMA11
##@NIBU@##linux1319,10.18.153.234,WIC,OMA11
##@NIBU@##linux132,172.30.94.232,WIC,OMA11
##@NIBU@##linux1320,10.18.153.235,WIC,OMA11
##@NIBU@##linux1321,10.18.153.236,WIC,OMA11
##@NIBU@##linux1322,10.18.153.237,WIC,OMA11
##@NIBU@##linux1323,10.18.153.238,WIC,OMA11
##@NIBU@##linux1324,10.18.153.239,WIC,OMA11
##@NIBU@##linux1325,135.000.000.000,WIC,OMA11
##@NIBU@##linux1326,10.31.72.80,ITC,PHX01
##@NIBU@##linux1327,10.31.72.81,ITC,PHX01
##@NIBU@##linux1328,10.31.72.82,ITC,PHX01
##@NIBU@##linux1329,10.31.72.83,ITC,PHX01
##@NIBU@##linux133,172.30.94.233,WIC,OMA11
##@NIBU@##linux1330,10.27.58.45,WCMG,OMA00
##@NIBU@##linux1331,10.27.58.46,WCMG,OMA00
##@NIBU@##linux1332,10.29.122.16,WCMG,DEN01
##@NIBU@##linux1333,10.170.200.30,ITC,SYD07
##@NIBU@##linux1334,10.170.200.31,ITC,SYD07
##@NIBU@##linux1335,10.170.200.32,ITC,SYD07
##@NIBU@##linux1336,10.17.57.12,WIC,OMA10
##@NIBU@##linux1337,10.29.122.15,WIC,DEN01
##@NIBU@##linux1338,10.27.58.57,ITC,OMA00
##@NIBU@##linux1339,10.17.57.61,ITC,OMA10
##@NIBU@##linux134,172.30.1.3,WIC,OMA01
##@NIBU@##linux1340,10.50.191.58,ITC,OMA00
##@NIBU@##linux1341,10.50.191.51,WIC,OMA00
##@NIBU@##linux1342,10.50.191.52,WIC,OMA00
##@NIBU@##linux1343,10.50.191.53,WIC,OMA00
##@NIBU@##linux1347,10.50.191.57,CORP,OMA00
##@NIBU@##linux1350,10.27.117.26,WIC,OMA00
##@NIBU@##linux1351,10.27.124.91,WNG,OMA00
##@NIBU@##linux1352,10.27.124.92,WNG,OMA00
##@NIBU@##linux1353,10.27.216.92,WNG,OMA00
##@NIBU@##linux1354,10.18.129.91,WNG,OMA11
##@NIBU@##linux1355,10.29.122.31,WNG,DEN01
##@NIBU@##linux1356,10.29.122.32,WNG,DEN01
##@NIBU@##linux136,10.100.0.136,WIC,OMA11
##@NIBU@##linux1365,10.27.216.85,ITC,OMA00
##@NIBU@##linux1366,10.27.216.86,ITC,OMA00
##@NIBU@##linux1367,10.27.216.87,ITC,OMA00
##@NIBU@##linux1368,10.27.216.130,ITC,OMA00
##@NIBU@##linux1369,10.31.103.23,ITC,PHX01
##@NIBU@##linux137,10.100.0.137,WIC,OMA11
##@NIBU@##linux1370,10.31.103.42,ITC,PHX01
##@NIBU@##linux1371,10.31.103.24,ITC,PHX01
##@NIBU@##linux1372,10.31.103.43,ITC,PHX01
##@NIBU@##linux1373,10.31.104.21,ITC,PHX01
##@NIBU@##linux1374,10.31.104.42,ITC,PHX01
##@NIBU@##linux1375,10.31.135.24,ITC,PHX01
##@NIBU@##linux1376,10.31.104.43,ITC,PHX01
##@NIBU@##linux1377,10.31.103.25,ITC,PHX01
##@NIBU@##linux1378,10.31.103.44,ITC,PHX01
##@NIBU@##linux1379,10.31.103.26,ITC,PHX01
##@NIBU@##linux1380,10.31.103.45,ITC,PHX01
##@NIBU@##linux1381,10.31.135.25,ITC,PHX01
##@NIBU@##linux1382,10.31.135.44,ITC,PHX01
##@NIBU@##linux1383,10.31.135.26,ITC,PHX01
##@NIBU@##linux1384,10.31.135.45,ITC,PHX01
##@NIBU@##linux1385,10.31.103.21,ITC,PHX01
##@NIBU@##linux1386,10.31.103.40,ITC,PHX01
##@NIBU@##linux1387,10.31.104.19,ITC,PHX01
##@NIBU@##linux1388,10.31.104.40,ITC,PHX01
##@NIBU@##linux1389,10.64.49.91,ITC,SWN01
##@NIBU@##linux139,10.27.58.44,WIC,OMA00
##@NIBU@##linux1390,10.62.22.22,ITC,SWN01
##@NIBU@##linux1391,10.27.198.51,ITC,OMA00
##@NIBU@##linux1392,10.72.200.75,ITC,DEN06
##@NIBU@##linux1393,10.31.103.22,ITC,PHX01
##@NIBU@##linux1394,10.31.103.41,ITC,PHX01
##@NIBU@##linux1395,10.31.104.20,ITC,PHX01
##@NIBU@##linux1396,10.31.104.41,ITC,PHX01
##@NIBU@##linux1397,10.162.40.64,ITC,GLC01
##@NIBU@##linux1398,10.162.40.65,ITC,GLC01
##@NIBU@##linux1399,10.162.40.66,ITC,GLC01
##@NIBU@##linux14,172.30.94.119,WIC,OMA11
##@NIBU@##linux1400,10.162.40.67,ITC,GLC01
##@NIBU@##linux1401,10.163.72.36,ITC,SYD07
##@NIBU@##linux1402,10.163.73.37,ITC,SYD07
##@NIBU@##linux1403,10.163.72.38,ITC,SYD07
##@NIBU@##linux1404,10.163.72.39,ITC,SYD07
##@NIBU@##linux1405,10.19.121.161,WCMG,OMA01
##@NIBU@##linux1406,216.57.98.88,WCMG,OMA01
##@NIBU@##linux1407,10.42.119.12,WCMG,SAT01
##@NIBU@##linux1408,216.57.106.50,WCMG,SAT01
##@NIBU@##linux141,10.64.10.77,ITC,SWN01
##@NIBU@##linux1410,10.27.110.84,WIC,OMA00
##@NIBU@##linux1411,linux1411,EIT,OMA00
##@NIBU@##linux1412,10.27.194.152,EIT,OMA00
##@NIBU@##linux1413,10.27.216.124,WIC,OMA00
##@NIBU@##linux1414,10.27.216.125,WIC,OMA00
##@NIBU@##linux1415,10.27.193.197,WIC,OMA00
##@NIBU@##linux1416,10.162.40.63,ITC,GLC01
##@NIBU@##linux1417,192.168.10.195,ITC,SWN01
##@NIBU@##linux1418,192.168.10.196,ITC,SWN01
##@NIBU@##linux1419,192.168.10.197,ITC,SWN01
##@NIBU@##linux142,10.27.194.151,WIC,OMA00
##@NIBU@##linux1420,172.30.78.41,WCMG,ATL01
##@NIBU@##linux1421,172.30.78.42,WCMG,ATL01
##@NIBU@##linux1422,172.30.78.43,WCMG,ATL01
##@NIBU@##linux1423,172.30.78.44,WCMG,ATL01
##@NIBU@##linux1424,172.30.78.45,WCMG,ATL01
##@NIBU@##linux1425,10.29.122.50,WCMG,DEN01
##@NIBU@##linux1426,10.29.122.51,WCMG,DEN01
##@NIBU@##linux1427,10.29.122.52,WCMG,DEN01
##@NIBU@##linux1428,10.29.122.53,WCMG,DEN01
##@NIBU@##linux1429,10.29.122.54,WCMG,DEN01
##@NIBU@##linux1430,10.62.35.23,ITC,WPT02
##@NIBU@##linux1431,10.62.35.24,ITC,WPT02
##@NIBU@##linux1432,10.62.16.101,ITC,OMA00
##@NIBU@##linux1433,10.62.16.102,ITC,OMA00
##@NIBU@##linux1434,10.62.72.145,ITC,VAL01
##@NIBU@##linux1435,10.62.72.146,ITC,VAL01
##@NIBU@##linux1436,10.64.10.64,ITC,SWN01
##@NIBU@##linux1437,10.64.10.65,ITC,SWN01
##@NIBU@##linux1438,10.62.235.10,ITC,TYO01
##@NIBU@##linux1439,10.62.235.11,ITC,TYO01
##@NIBU@##linux1440,10.62.228.50,ITC,HKG01
##@NIBU@##linux1441,10.62.228.51,ITC,HKG01
##@NIBU@##linux1442,10.62.223.21,ITC,MBW01
##@NIBU@##linux1443,10.62.223.23,ITC,MBW01
##@NIBU@##linux1444,10.31.40.62,ITC,PHX01
##@NIBU@##linux1445,10.31.40.63,ITC,PHX01
##@NIBU@##linux1446,10.31.40.64,ITC,PHX01
##@NIBU@##linux1447,10.31.40.65,ITC,PHX01
##@NIBU@##Linux145,172.30.10.29,WIC,OMA10
##@NIBU@##linux1452,10.27.193.236,WIC,OMA00
##@NIBU@##linux1454,10.27.119.66,CORP,OMA00
##@NIBU@##linux1455,10.62.71.10,ITC,VAL01
##@NIBU@##linux1456,216.57.110.48,CORP,SAT01
##@NIBU@##linux1457,10.27.193.196,ITC,OMA00
##@NIBU@##linux1458,10.62.35.35,ITC,WPT02
##@NIBU@##linux1459,10.62.72.153,ITC,VAL01
##@NIBU@##Linux146,172.30.10.30,WIC,OMA10
##@NIBU@##linux1460,10.27.119.77,WIC,OMA00
##@NIBU@##linux1461,linux1461,CORP,OMA00
##@NIBU@##linux1462,10.67.71.21,ITC,VAL01
##@NIBU@##linux1463,10.62.71.22,ITC,VAL01
##@NIBU@##linux1464,10.27.217.23,ITC,OMA00
##@NIBU@##linux1465,10.27.217.24,ITC,OMA00
##@NIBU@##linux1466,10.162.40.70,ITC,GLC01
##@NIBU@##linux1467,10.162.40.69,ITC,GLC01
##@NIBU@##linux1468,10.163.7.21,ITC,SIN01
##@NIBU@##linux1469,10.163.7.22,ITC,SIN01
##@NIBU@##linux147,172.30.8.112,WIC,OMA10
##@NIBU@##linux1470,10.164.40.62,ITC,SYD09
##@NIBU@##linux1471,10.164.40.63,ITC,SYD09
##@NIBU@##linux1473,10.62.70.21,ITC,VAL01
##@NIBU@##linux1474,10.62.70.22,ITC,VAL01
##@NIBU@##linux1475,10.62.70.23,ITC,VAL01
##@NIBU@##linux1476,10.62.70.24,ITC,VAL01
##@NIBU@##linux1477,10.62.35.31,ITC,WPT02
##@NIBU@##linux1478,10.62.35.32,ITC,WPT02
##@NIBU@##linux1479,10.62.35.33,ITC,WPT02
##@NIBU@##linux148,172.30.8.113,WIC,OMA10
##@NIBU@##linux1480,10.62.35.34,ITC,WPT02
##@NIBU@##linux1481,10.62.70.25,ITC,VAL01
##@NIBU@##linux1482,10.62.70.26,ITC,VAL01
##@NIBU@##linux1483,172.30.114.97,EIT,OMA00
##@NIBU@##linux1484,10.62.33.237,ITC,WPT02
##@NIBU@##linux1485,10.62.33.206,ITC,WPT02
##@NIBU@##linux1486,172.30.114.98,WIC,OMA00
##@NIBU@##linux1487,10.64.16.22,ITC,SWN01
##@NIBU@##linux1488,10.64.16.23,ITC,SWN01
##@NIBU@##linux1489,10.27.193.102,WIC,OMA00
##@NIBU@##linux149,172.30.8.114,WIC,OMA10
##@NIBU@##linux1490,10.27.214.150,WIC,OMA00
##@NIBU@##linux1491,10.19.117.119,ITC,OMA01
##@NIBU@##linux1493,10.64.16.13,ITC,SWN01
##@NIBU@##linux1497,10.64.22.28,ITC,SWN01
##@NIBU@##linux1498,10.64.18.20,ITC,SWN01
##@NIBU@##linux1499,10.64.20.37,ITC,SWN01
##@NIBU@##linux15,172.30.94.120,WIC,OMA11
##@NIBU@##linux150,172.30.41.203,WIC,DEN01
##@NIBU@##linux1500,10.64.16.76,ITC,SWN01
##@NIBU@##linux1501,10.64.20.39,ITC,SWN01
##@NIBU@##linux1502,10.64.18.58,ITC,SWN01
##@NIBU@##linux1503,10.64.18.60,ITC,SWN01
##@NIBU@##linux1505,10.50.191.59,WIC,OMA00
##@NIBU@##linux1506,10.50.191.60,CORP,OMA00
##@NIBU@##linux1509,172.30.113.176,EIT,OMA00
##@NIBU@##linux151,172.30.10.80,WIC,OMA10
##@NIBU@##linux1510,10.27.193.25,WIC,OMA00
##@NIBU@##linux1511,10.18.153.147,WIC,OMA11
##@NIBU@##linux1512,10.18.153.148,WIC,OMA11
##@NIBU@##linux1513,10.18.153.149,WIC,OMA11
##@NIBU@##linux1514,10.62.27.250,ITC,WPT02
##@NIBU@##linux1515,10.62.27.252,ITC,WPT02
##@NIBU@##linux1516,10.62.10.63,ITC,SWN01
##@NIBU@##linux1517,10.64.12.38,ITC,SWN01
##@NIBU@##linux1518,10.29.168.40,ITC,DEN01
##@NIBU@##linux1519,10.27.114.85,ITC,OMA00
##@NIBU@##linux152,172.30.10.21,WIC,OMA10
##@NIBU@##linux1520,10.29.168.41,ITC,DEN01
##@NIBU@##linux1521,10.29.168.22,ITC,DEN01
##@NIBU@##linux1522,10.29.168.42,ITC,DEN01
##@NIBU@##linux1523,10.29.168.23,ITC,DEN01
##@NIBU@##linux1524,10.29.168.43,ITC,DEN01
##@NIBU@##linux1525,10.29.168.24,ITC,DEN01
##@NIBU@##linux1526,10.29.168.44,ITC,DEN01
##@NIBU@##linux1527,10.29.168.25,ITC,DEN01
##@NIBU@##linux1528,10.29.168.45,ITC,DEN01
##@NIBU@##linux1529,10.29.168.26,ITC,DEN01
##@NIBU@##linux153,172.30.8.118,WIC,OMA10
##@NIBU@##linux1530,10.29.168.46,ITC,DEN01
##@NIBU@##linux1531,10.29.168.27,ITC,DEN01
##@NIBU@##linux1537,10.27.214.157,WIC,OMA00
##@NIBU@##linux1538,10.64.5.42,ITC,SWN01
##@NIBU@##linux1539,10.64.5.43,ITC,SWN01
##@NIBU@##linux154,172.30.8.119,WIC,OMA10
##@NIBU@##linux1540,10.64.5.44,ITC,SWN01
##@NIBU@##linux1541,10.64.5.45,ITC,SWN01
##@NIBU@##linux1542,10.64.3.31,ITC,SWN01
##@NIBU@##linux1543,10.64.3.32,ITC,SWN01
##@NIBU@##linux1544,10.64.5.46,ITC,SWN01
##@NIBU@##linux1545,10.64.5.47,ITC,SWN01
##@NIBU@##linux1547,10.64.2.28,ITC,SWN01
##@NIBU@##linux1548,10.62.35.39,ITC,WPT02
##@NIBU@##linux1549,10.62.35.40,ITC,WPT02
##@NIBU@##linux155,172.30.8.120,WIC,OMA10
##@NIBU@##linux1550,10.62.35.41,ITC,WPT02
##@NIBU@##linux1551,10.62.35.42,ITC,WPT02
##@NIBU@##linux1552,10.62.35.43,ITC,WPT02
##@NIBU@##linux1554,10.62.10.54,ITC,SWN01
##@NIBU@##linux1555,10.62.10.55,ITC,SWN01
##@NIBU@##linux1556,10.62.21.203,ITC,WPT01
##@NIBU@##linux1557,10.62.21.204,ITC,WPT01
##@NIBU@##linux1558,10.29.122.55,WIC,DEN01
##@NIBU@##linux1559,10.28.124.51,WIC,ATL01
##@NIBU@##linux156,172.30.8.121,WIC,OMA10
##@NIBU@##linux1560,10.27.214.93,WIC,OMA00
##@NIBU@##linux1561,10.27.214.94,WIC,OMA00
##@NIBU@##linux1562,10.20.6.104,WAM,PMJ01
##@NIBU@##linux1566,10.28.168.21,ITC,ATL01
##@NIBU@##linux1567,10.28.168.40,ITC,ATL01
##@NIBU@##linux1568,10.28.168.22,ITC,ATL01
##@NIBU@##linux1569,10.28.168.41,ITC,ATL01
##@NIBU@##linux157,172.30.113.167,EIT,OMA00
##@NIBU@##linux1570,10.28.168.23,ITC,ATL01
##@NIBU@##linux1571,10.28.168.42,ITC,ATL01
##@NIBU@##linux1572,10.28.168.24,ITC,ATL01
##@NIBU@##linux1573,10.28.168.43,ITC,ATL01
##@NIBU@##linux1574,10.28.168.25,ITC,ATL01
##@NIBU@##linux1575,10.28.168.44,ITC,ATL01
##@NIBU@##linux1576,10.31.103.52,ITC,PHX01
##@NIBU@##linux1577,10.27.110.54,ITC,OMA00
##@NIBU@##linux1578,10.28.168.27,ITC,ATL01
##@NIBU@##linux1579,10.28.168.46,ITC,ATL01
##@NIBU@##linux1580,10.28.184.21,ITC,ATL01
##@NIBU@##linux1581,10.28.184.40,ITC,ATL01
##@NIBU@##linux1582,10.28.184.22,ITC,ATL01
##@NIBU@##linux1583,10.28.184.41,ITC,ATL01
##@NIBU@##linux1584,10.28.184.23,ITC,ATL01
##@NIBU@##linux1585,10.28.184.42,ITC,ATL01
##@NIBU@##linux1586,10.28.184.24,ITC,ATL01
##@NIBU@##linux1587,10.28.184.43,ITC,ATL01
##@NIBU@##linux1588,10.28.184.25,ITC,ATL01
##@NIBU@##linux1589,10.28.184.44,ITC,ATL01
##@NIBU@##linux1590,10.28.184.26,ITC,ATL01
##@NIBU@##linux1591,10.27.110.56,ITC,OMA00
##@NIBU@##linux1592,10.28.184.27,ITC,ATL01
##@NIBU@##linux1593,10.28.184.46,ITC,ATL01
##@NIBU@##linux1594,10.27.220.21,WCMG,OMA00
##@NIBU@##linux1595,10.27.220.22,WCMG,OMA00
##@NIBU@##linux1598,10.64.5.21,ITC,SWN01
##@NIBU@##linux1599,10.64.5.22,ITC,SWN01
##@NIBU@##linux160,172.30.53.1,ITC,DEN01
##@NIBU@##linux1601,10.64.5.24,ITC,SWN01
##@NIBU@##linux1602,10.64.5.25,ITC,SWN01
##@NIBU@##linux1603,10.64.5.26,ITC,SWN01
##@NIBU@##linux1604,10.64.6.27,ITC,SWN01
##@NIBU@##linux1605,10.64.5.28,ITC,SWN01
##@NIBU@##linux1606,10.64.5.29,ITC,SWN01
##@NIBU@##linux1607,10.64.5.30,ITC,SWN01
##@NIBU@##linux1608,10.64.2.21,ITC,SWN01
##@NIBU@##linux1609,10.64.2.22,ITC,SWN01
##@NIBU@##linux161,172.30.53.2,ITC,DEN01
##@NIBU@##linux1610,10.64.2.23,ITC,SWN01
##@NIBU@##linux1611,10.64.3.21,ITC,SWN01
##@NIBU@##linux1612,10.64.3.22,ITC,SWN01
##@NIBU@##linux1613,10.64.3.23,ITC,SWN01
##@NIBU@##linux1614,10.64.3.24,ITC,SWN01
##@NIBU@##linux1615,10.64.3.25,ITC,SWN01
##@NIBU@##linux1616,10.64.12.37,ITC,SWN01
##@NIBU@##linux1617,10.27.216.150,ITC,OMA00
##@NIBU@##linux1618,10.27.193.213,ITC,OMA00
##@NIBU@##linux1619,172.31.9.90,EIT,OMA10
##@NIBU@##linux162,172.30.53.3,ITC,DEN01
##@NIBU@##linux1620,10.27.117.31,CORP,OMA00
##@NIBU@##linux1621,10.27.117.33,CORP,OMA00
##@NIBU@##linux1623,10.17.52.48,WIC,OMA10
##@NIBU@##linux1624,10.17.52.49,WIC,OMA10
##@NIBU@##linux1625,10.17.52.82,WIC,OMA10
##@NIBU@##linux1626,10.17.52.80,WIC,OMA10
##@NIBU@##linux1627,10.17.52.81,WIC,OMA10
##@NIBU@##linux163,172.30.53.4,ITC,DEN01
##@NIBU@##linux1631,10.62.132.10,ITC,SWN01
##@NIBU@##linux1632,10.62.132.11,ITC,SWN01
##@NIBU@##linux1634,10.62.132.13,ITC,SWN01
##@NIBU@##linux1635,10.62.132.20,EIT,SWN01
##@NIBU@##linux1636,10.62.132.21,ITC,SWN01
##@NIBU@##linux1637,10.62.132.22,ITC,SWN01
##@NIBU@##linux1638,10.62.132.23,ITC,SWN01
##@NIBU@##linux1639,10.62.133.21,ITC,SWN01
##@NIBU@##linux164,172.30.53.5,ITC,DEN01
##@NIBU@##linux1640,216.57.102.141,ITC,OMA01
##@NIBU@##linux1641,10.27.214.216,WIC,OMA00
##@NIBU@##linux1642,10.27.214.215,WIC,OMA00
##@NIBU@##linux1643,10.64.7.11,ITC,SWN01
##@NIBU@##linux1644,10.64.7.12,ITC,SWN01
##@NIBU@##linux1645,10.64.7.13,ITC,SWN01
##@NIBU@##linux1646,10.64.7.14,ITC,SWN01
##@NIBU@##linux1647,10.64.7.15,ITC,SWN01
##@NIBU@##linux1648,10.64.7.16,ITC,SWN01
##@NIBU@##linux1649,10.64.7.17,ITC,SWN01
##@NIBU@##linux165,172.30.53.6,ITC,DEN01
##@NIBU@##linux1650,10.64.7.18,ITC,SWN01
##@NIBU@##linux1651,10.64.7.19,ITC,SWN01
##@NIBU@##linux1652,10.64.7.20,ITC,SWN01
##@NIBU@##linux1653,10.64.7.21,ITC,SWN01
##@NIBU@##linux1654,10.64.7.22,ITC,SWN01
##@NIBU@##linux1655,10.64.7.23,ITC,SWN01
##@NIBU@##linux1656,10.64.7.24,ITC,SWN01
##@NIBU@##linux1657,216.57.102.145,ITC,OMA01
##@NIBU@##linux1658,216.57.102.148,ITC,OMA01
##@NIBU@##linux1659,10.64.9.12,ITC,SWN01
##@NIBU@##linux166,172.30.53.7,ITC,DEN01
##@NIBU@##linux1660,10.64.9.13,ITC,SWN01
##@NIBU@##linux1661,10.64.9.14,ITC,SWN01
##@NIBU@##linux1662,10.64.9.15,ITC,SWN01
##@NIBU@##linux1663,10.64.9.16,ITC,SWN01
##@NIBU@##linux1664,10.64.9.17,ITC,SWN01
##@NIBU@##linux1665,10.64.9.18,ITC,SWN01
##@NIBU@##linux1666,10.64.9.19,ITC,SWN01
##@NIBU@##linux1667,10.64.9.20,ITC,SWN01
##@NIBU@##linux1668,10.64.9.21,ITC,SWN01
##@NIBU@##linux1669,10.64.9.22,ITC,SWN01
##@NIBU@##linux167,172.30.53.8,ITC,DEN01
##@NIBU@##linux1670,10.64.9.11,ITC,SWN01
##@NIBU@##linux1671,10.64.9.23,ITC,SWN01
##@NIBU@##linux1672,10.64.9.24,ITC,SWN01
##@NIBU@##linux1673,216.57.102.146,ITC,OMA01
##@NIBU@##linux1674,216.57.102.149,ITC,OMA01
##@NIBU@##linux1676,linux1676,ITC,SWN01
##@NIBU@##linux1677,10.64.23.12,ITC,SWN01
##@NIBU@##linux1678,10.64.23.43,ITC,SWN01
##@NIBU@##linux1679,10.64.23.44,ITC,SWN01
##@NIBU@##linux168,172.30.53.9,ITC,DEN01
##@NIBU@##linux1680,10.64.23.45,ITC,SWN01
##@NIBU@##linux1681,10.64.23.46,ITC,SWN01
##@NIBU@##linux1682,10.64.23.47,ITC,SWN01
##@NIBU@##linux1683,10.64.23.48,ITC,SWN01
##@NIBU@##linux1684,10.64.23.49,ITC,SWN01
##@NIBU@##linux1685,10.64.23.11,ITC,SWN01
##@NIBU@##linux1686,linux1686,ITC,SWN01
##@NIBU@##linux1687,10.64.23.13,ITC,SWN01
##@NIBU@##linux1688,10.64.23.14,ITC,SWN01
##@NIBU@##linux1689,10.64.23.15,ITC,SWN01
##@NIBU@##linux169,172.30.53.10,ITC,DEN01
##@NIBU@##linux1690,10.64.23.16,ITC,SWN01
##@NIBU@##linux1691,10.64.23.17,ITC,SWN01
##@NIBU@##linux1692,10.64.23.18,ITC,SWN01
##@NIBU@##linux1693,216.57.102.147,ITC,OMA01
##@NIBU@##linux1694,216.57.102.150,ITC,OMA01
##@NIBU@##linux1696,10.27.193.66,WNG,OMA00
##@NIBU@##linux1697,10.62.21.212,ITC,WPT01
##@NIBU@##linux1698,10.62.21.218,ITC,WPT01
##@NIBU@##linux1699,10.64.10.25,ITC,SWN01
##@NIBU@##linux170,172.30.53.11,ITC,DEN01
##@NIBU@##linux1700,10.64.10.26,ITC,SWN01
##@NIBU@##linux1701,10.62.35.53,ITC,WPT02
##@NIBU@##linux1702,10.62.35.54,ITC,WPT02
##@NIBU@##linux1703,10.29.100.27,WIC,DEN01
##@NIBU@##linux1704,10.29.114.40,WIC,DEN01
##@NIBU@##linux1705,10.27.115.27,WIC,OMA00
##@NIBU@##linux1706,10.26.184.78,WIC,OMA10
##@NIBU@##linux1708,10.29.100.23,WIC,DEN01
##@NIBU@##linux171,172.30.53.12,ITC,DEN01
##@NIBU@##linux1712,10.27.216.162,ITC,OMA00
##@NIBU@##linux1718,linux1718,WIC,OMA00
##@NIBU@##linux1719,linux1719,WIC,OMA00
##@NIBU@##linux172,172.30.53.13,ITC,DEN01
##@NIBU@##linux1720,linux1720,WIC,OMA00
##@NIBU@##linux1721,linux1721,WIC,OMA00
##@NIBU@##linux1722,linux1722,WIC,OMA00
##@NIBU@##linux1726,10.18.154.13,WIC,OMA11
##@NIBU@##linux1727,10.18.154.14,WIC,OMA11
##@NIBU@##linux1728,linux1728,EIT,DEN01
##@NIBU@##linux1729,10.27.122.84,ITC,OMA00
##@NIBU@##linux173,172.30.53.14,ITC,DEN01
##@NIBU@##linux1730,10.29.96.116,WIC,DEN01
##@NIBU@##linux1731,10.29.96.117,WIC,DEN01
##@NIBU@##linux1732,10.29.96.118,WIC,DEN01
##@NIBU@##linux1733,10.29.96.119,WIC,DEN01
##@NIBU@##linux1734,10.29.96.120,WIC,DEN01
##@NIBU@##linux1735,10.19.122.196,ITC,OMA01
##@NIBU@##linux1736,10.62.35.146,ITC,WPT02
##@NIBU@##linux174,172.30.53.15,ITC,DEN01
##@NIBU@##linux1747,10.64.22.76,ITC,SWN01
##@NIBU@##linux1748,10.64.22.77,ITC,SWN01
##@NIBU@##linux1749,10.64.20.27,ITC,SWN01
##@NIBU@##linux1750,10.64.20.28,ITC,SWN01
##@NIBU@##linux1751,10.64.18.119,ITC,SWN01
##@NIBU@##linux1752,10.64.22.78,ITC,SWN01
##@NIBU@##linux1753,10.64.22.79,ITC,SWN01
##@NIBU@##linux1754,10.64.20.29,ITC,SWN01
##@NIBU@##linux1755,10.64.20.30,ITC,SWN01
##@NIBU@##linux1756,10.64.18.120,ITC,SWN01
##@NIBU@##linux1757,10.50.191.66,WIC,OMA00
##@NIBU@##linux1758,10.27.119.206,WIC,OMA00
##@NIBU@##linux1759,10.27.119.207,WIC,OMA00
##@NIBU@##linux176,172.30.53.17,ITC,DEN01
##@NIBU@##linux1760,10.27.119.208,WIC,OMA00
##@NIBU@##linux1761,10.27.119.209,WIC,OMA00
##@NIBU@##linux1762,10.27.119.210,WIC,OMA00
##@NIBU@##linux1763,10.27.119.211,WIC,OMA00
##@NIBU@##linux1764,10.50.191.68,CORP,OMA00
##@NIBU@##linux1765,10.50.191.74,WIC,OMA00
##@NIBU@##linux1766,10.27.60.50,WIC,OMA00
##@NIBU@##linux1767,10.28.96.11,WIC,ATL01
##@NIBU@##linux1768,10.28.96.12,WIC,ATL01
##@NIBU@##linux1769,10.28.96.13,WIC,ATL01
##@NIBU@##linux177,172.30.53.18,ITC,DEN01
##@NIBU@##linux1770,10.28.96.14,WIC,ATL01
##@NIBU@##linux1771,10.28.96.15,WIC,ATL01
##@NIBU@##linux1773,10.28.96.17,WIC,ATL01
##@NIBU@##linux1774,10.28.96.18,WIC,ATL01
##@NIBU@##linux1775,10.28.96.19,WIC,ATL01
##@NIBU@##linux1776,10.28.96.20,WIC,ATL01
##@NIBU@##linux1777,10.28.96.21,WIC,ATL01
##@NIBU@##linux1778,10.28.96.22,WIC,ATL01
##@NIBU@##linux1779,10.28.96.23,WIC,ATL01
##@NIBU@##linux178,172.30.53.19,ITC,DEN01
##@NIBU@##linux1780,10.17.52.173,WIC,OMA10
##@NIBU@##linux1781,10.17.52.174,WIC,OMA10
##@NIBU@##linux1782,10.17.52.181,WIC,OMA10
##@NIBU@##linux1783,10.29.96.113,WIC,DEN01
##@NIBU@##linux1784,10.29.96.114,WIC,DEN01
##@NIBU@##linux1785,10.29.96.115,WIC,DEN01
##@NIBU@##linux1786,10.29.96.139,WIC,DEN01
##@NIBU@##linux1787,10.29.96.140,WIC,DEN01
##@NIBU@##linux1788,10.29.96.141,WIC,DEN01
##@NIBU@##linux1789,linux1789,WIC,DEN01
##@NIBU@##linux179,172.30.53.20,ITC,DEN01
##@NIBU@##linux1790,10.29.96.150,WIC,DEN01
##@NIBU@##linux1791,linux1791,WIC,DEN01
##@NIBU@##linux1792,10.29.96.152,WIC,DEN01
##@NIBU@##linux1793,10.29.97.48,WIC,DEN01
##@NIBU@##linux1794,10.29.97.49,WIC,DEN01
##@NIBU@##linux1795,10.29.97.50,WIC,DEN01
##@NIBU@##linux1796,10.29.96.242,WIC,DEN01
##@NIBU@##linux1797,10.29.96.243,WIC,DEN01
##@NIBU@##linux1798,10.29.96.245,WIC,DEN01
##@NIBU@##linux1799,10.62.35.60,ITC,WPT02
##@NIBU@##linux18,linux18,EIT,OMA00
##@NIBU@##linux180,172.30.53.21,ITC,DEN01
##@NIBU@##linux1800,10.62.35.61,ITC,WPT02
##@NIBU@##linux1801,10.62.35.62,ITC,WPT02
##@NIBU@##linux1802,10.19.119.65,ITC,OMA01
##@NIBU@##linux1803,10.19.119.67,ITC,OMA01
##@NIBU@##linux1804,10.50.191.77,CORP,OMA00
##@NIBU@##linux1805,10.27.119.213,WBS,OMA00
##@NIBU@##linux1806,10.27.119.214,WBS,OMA00
##@NIBU@##linux1808,10.42.119.121,WCMG,SAT01
##@NIBU@##linux1809,10.64.10.29,ITC,SWN01
##@NIBU@##linux181,172.30.53.22,ITC,DEN01
##@NIBU@##linux1810,10.27.119.216,WIC,OMA00
##@NIBU@##linux1811,10.27.119.217,WIC,OMA00
##@NIBU@##linux1812,10.62.235.20,ITC,TYO01
##@NIBU@##linux1813,10.62.235.21,ITC,TYO01
##@NIBU@##linux1814,10.64.10.68,ITC,SWN01
##@NIBU@##linux1815,10.64.10.69,ITC,SWN01
##@NIBU@##linux1816,10.64.10.70,ITC,SWN01
##@NIBU@##linux1817,10.64.10.71,ITC,SWN01
##@NIBU@##linux1818,10.64.10.72,ITC,SWN01
##@NIBU@##linux1819,10.27.119.240,WIC,OMA00
##@NIBU@##linux182,172.30.53.23,ITC,DEN01
##@NIBU@##linux1820,216.57.98.227,WIC,OMA01
##@NIBU@##linux1824,10.19.52.20,WIC,OMA01
##@NIBU@##linux1825,10.19.52.52,WIC,OMA01
##@NIBU@##linux1826,10.50.191.44,WIC,OMA00
##@NIBU@##linux1827,10.50.191.78,WIC,OMA00
##@NIBU@##linux1828,10.50.191.226,WIC,OMA00
##@NIBU@##linux183,172.30.53.24,ITC,DEN01
##@NIBU@##linux1830,10.29.96.57,WIC,DEN01
##@NIBU@##linux1831,10.29.96.82,WIC,DEN01
##@NIBU@##linux1834,10.29.99.45,WIC,DEN01
##@NIBU@##linux1835,10.29.99.46,WIC,DEN01
##@NIBU@##linux1836,10.29.99.47,WIC,DEN01
##@NIBU@##linux1837,10.29.99.49,WIC,DEN01
##@NIBU@##linux1838,10.29.99.50,WIC,DEN01
##@NIBU@##linux1839,10.29.99.51,WIC,DEN01
##@NIBU@##linux184,172.30.53.25,ITC,DEN01
##@NIBU@##linux1840,10.29.99.52,WIC,DEN01
##@NIBU@##linux1841,10.29.99.53,WIC,DEN01
##@NIBU@##linux1842,10.29.99.54,WIC,DEN01
##@NIBU@##linux1845,10.29.99.77,WIC,DEN01
##@NIBU@##linux1846,10.29.99.78,WIC,DEN01
##@NIBU@##linux1847,10.29.99.79,WIC,DEN01
##@NIBU@##linux1848,10.29.99.81,WIC,DEN01
##@NIBU@##linux1849,10.29.99.82,WIC,DEN01
##@NIBU@##linux185,172.30.53.26,ITC,DEN01
##@NIBU@##linux1850,10.29.99.83,WIC,DEN01
##@NIBU@##linux1851,10.29.99.84,WIC,DEN01
##@NIBU@##linux1852,10.29.99.85,WIC,DEN01
##@NIBU@##linux1853,10.29.99.86,WIC,DEN01
##@NIBU@##linux1856,10.29.99.109,WIC,DEN01
##@NIBU@##linux1857,10.29.99.110,WIC,DEN01
##@NIBU@##linux186,172.30.53.27,ITC,DEN01
##@NIBU@##linux1863,10.29.99.117,WIC,DEN01
##@NIBU@##linux1864,216.57.101.203,WIC,DEN01
##@NIBU@##linux1868,10.29.99.142,WIC,DEN01
##@NIBU@##linux1869,10.29.99.143,WIC,DEN01
##@NIBU@##linux187,172.30.53.28,ITC,DEN01
##@NIBU@##linux1870,10.29.99.145,WIC,DEN01
##@NIBU@##linux1871,10.29.99.146,WIC,DEN01
##@NIBU@##linux1872,10.29.99.147,WIC,DEN01
##@NIBU@##linux1873,10.29.99.148,WIC,DEN01
##@NIBU@##linux1874,216.57.101.204,WIC,DEN01
##@NIBU@##linux1875,216.57.101.205,WIC,DEN01
##@NIBU@##linux1876,none,CORP,OMA00
##@NIBU@##linux1879,10.29.99.173,WIC,DEN01
##@NIBU@##linux188,172.30.75.1,ITC,ATL01
##@NIBU@##linux1880,10.29.99.174,WIC,DEN01
##@NIBU@##linux1881,10.29.99.175,WIC,DEN01
##@NIBU@##linux1882,10.70.0.99,WIC,DEN06
##@NIBU@##linux1883,10.70.0.113,WIC,DEN06
##@NIBU@##linux1884,10.70.0.183,WIC,DEN06
##@NIBU@##linux1886,10.70.0.151,WIC,DEN06
##@NIBU@##linux1887,216.57.101.206,WIC,DEN01
##@NIBU@##linux1888,10.28.96.24,WNG,ATL01
##@NIBU@##linux189,172.30.75.2,ITC,ATL01
##@NIBU@##linux1891,10.70.0.167,WIC,DEN06
##@NIBU@##linux1892,10.70.0.176,WIC,DEN06
##@NIBU@##linux1893,10.70.0.184,WIC,DEN06
##@NIBU@##linux1894,10.70.0.206,WIC,DEN06
##@NIBU@##linux1895,10.70.0.236,WIC,DEN06
##@NIBU@##linux1896,10.70.0.251,WIC,DEN06
##@NIBU@##linux1897,10.27.193.166,WIC,OMA00
##@NIBU@##linux1898,10.29.99.212,WIC,DEN01
##@NIBU@##linux1899,10.28.96.245,WNG,ATL01
##@NIBU@##linux190,172.30.75.3,ITC,ATL01
##@NIBU@##linux1900,10.29.99.214,WIC,DEN01
##@NIBU@##linux1904,10.29.99.238,WIC,DEN01
##@NIBU@##linux1905,10.29.99.239,WIC,DEN01
##@NIBU@##linux1906,10.29.99.240,WIC,DEN01
##@NIBU@##linux1907,10.29.99.241,WIC,DEN01
##@NIBU@##linux1908,10.29.99.242,WIC,DEN01
##@NIBU@##linux1909,10.29.99.243,WIC,DEN01
##@NIBU@##linux191,172.30.75.4,ITC,ATL01
##@NIBU@##linux1910,10.29.99.244,WIC,DEN01
##@NIBU@##linux1914,10.28.96.56,EIT,ATL01
##@NIBU@##linux192,172.30.75.5,ITC,ATL01
##@NIBU@##linux1925,10.28.96.209,WIC,ATL01
##@NIBU@##linux1926,10.28.96.210,WIC,ATL01
##@NIBU@##linux1927,10.28.96.244,WIC,ATL01
##@NIBU@##linux1928,10.28.96.50,WIC,ATL01
##@NIBU@##linux1929,10.28.96.177,WIC,ATL01
##@NIBU@##linux193,172.30.75.6,ITC,ATL01
##@NIBU@##linux1930,10.28.96.243,WIC,ATL01
##@NIBU@##linux1931,10.28.96.120,WIC,ATL01
##@NIBU@##linux1932,10.28.96.147,WIC,ATL01
##@NIBU@##linux1933,10.28.96.53,WIC,ATL01
##@NIBU@##linux1934,10.28.96.54,WIC,ATL01
##@NIBU@##linux1935,10.28.96.55,WIC,ATL01
##@NIBU@##linux1936,10.28.96.83,WIC,ATL01
##@NIBU@##linux1937,10.28.96.84,WIC,ATL01
##@NIBU@##linux1938,10.28.96.85,WIC,ATL01
##@NIBU@##linux1939,10.28.96.86,WIC,ATL01
##@NIBU@##linux194,172.30.75.7,ITC,ATL01
##@NIBU@##linux1940,10.28.96.87,WIC,ATL01
##@NIBU@##linux1941,10.28.96.88,WIC,ATL01
##@NIBU@##linux1942,10.28.96.115,WIC,ATL01
##@NIBU@##linux1943,10.28.96.116,WIC,ATL01
##@NIBU@##linux1944,10.28.96.117,WIC,ATL01
##@NIBU@##linux1945,10.28.96.118,WIC,ATL01
##@NIBU@##linux1946,10.28.96.119,WIC,ATL01
##@NIBU@##linux1947,10.28.96.148,WIC,ATL01
##@NIBU@##linux1948,10.28.96.149,WIC,ATL01
##@NIBU@##linux195,172.30.75.8,ITC,ATL01
##@NIBU@##linux1951,10.28.96.152,WIC,DEN06
##@NIBU@##linux1954,10.28.96.182,WIC,ATL01
##@NIBU@##linux1955,10.28.96.183,WIC,ATL01
##@NIBU@##linux1956,10.28.96.184,WIC,ATL01
##@NIBU@##linux1957,10.28.96.211,WIC,ATL01
##@NIBU@##linux1958,10.28.96.212,WIC,ATL01
##@NIBU@##linux1959,10.28.96.213,WIC,ATL01
##@NIBU@##linux196,172.30.75.9,ITC,ATL01
##@NIBU@##linux1960,10.28.96.214,WIC,ATL01
##@NIBU@##linux1961,10.28.96.215,WIC,ATL01
##@NIBU@##linux1962,10.28.96.216,WIC,ATL01
##@NIBU@##linux1963,10.28.96.246,WIC,ATL01
##@NIBU@##linux1964,10.28.96.247,WIC,ATL01
##@NIBU@##linux1965,10.28.96.248,WIC,ATL01
##@NIBU@##linux1966,10.28.96.49,WIC,ATL01
##@NIBU@##linux1967,10.28.96.242,WIC,ATL01
##@NIBU@##linux1968,10.50.191.116,ITC,OMA00
##@NIBU@##linux1969,10.50.191.117,ITC,OMA00
##@NIBU@##linux197,172.30.75.10,ITC,ATL01
##@NIBU@##linux1970,10.50.191.118,CORP,OMA00
##@NIBU@##linux1972,10.20.24.20,WCMG,ELP01
##@NIBU@##linux1973,10.20.24.22,WCMG,ELP01
##@NIBU@##linux1974,10.29.97.19,WIC,DEN01
##@NIBU@##linux1975,10.17.52.180,WIC,OMA10
##@NIBU@##linux1976,10.27.193.217,WIC,OMA00
##@NIBU@##linux1977,10.27.193.218,WIC,OMA00
##@NIBU@##linux1978,10.18.129.93,WIC,OMA11
##@NIBU@##linux198,172.30.75.11,ITC,ATL01
##@NIBU@##linux1983,10.28.124.58,WIC,ATL01
##@NIBU@##linux1984,10.28.100.21,WIC,ATL01
##@NIBU@##linux1985,10.28.100.22,WIC,ATL01
##@NIBU@##linux1987,10.19.119.71,ITC,OMA01
##@NIBU@##linux1988,10.19.119.72,ITC,OMA01
##@NIBU@##linux1989,10.19.119.73,ITC,OMA01
##@NIBU@##linux199,172.30.75.12,ITC,ATL01
##@NIBU@##linux1990,10.19.119.74,ITC,OMA01
##@NIBU@##linux1992,10.28.200.21,ITC,ATL01
##@NIBU@##linux1993,10.28.200.22,ITC,ATL01
##@NIBU@##linux1994,10.28.200.25,ITC,ATL01
##@NIBU@##linux1996,10.28.200.27,ITC,ATL01
##@NIBU@##linux1997,10.28.200.45,ITC,ATL01
##@NIBU@##linux1998,10.28.200.46,ITC,ATL01
##@NIBU@##linux1999,10.28.200.49,ITC,ATL01
##@NIBU@##linux1new,10.27.193.230,WIC,OMA00
##@NIBU@##linux200,172.30.75.13,ITC,ATL01
##@NIBU@##linux2001,10.28.200.51,ITC,ATL01
##@NIBU@##linux2002,10.42.117.21,WBS,SAT01
##@NIBU@##linux2003,10.28.101.35,WIC,ATL01
##@NIBU@##linux2004,10.28.101.36,WIC,ATL01
##@NIBU@##linux2005,10.28.101.37,WIC,ATL01
##@NIBU@##linux2006,10.28.101.38,WIC,ATL01
##@NIBU@##linux2007,10.28.101.39,WIC,ATL01
##@NIBU@##linux2009,216.57.102.170,WIC,OMA01
##@NIBU@##linux201,172.30.75.14,ITC,ATL01
##@NIBU@##linux2010,10.27.60.90,WIC,OMA00
##@NIBU@##linux2011,10.27.60.92,WIC,OMA00
##@NIBU@##linux2012,10.50.191.99,WIC,OMA00
##@NIBU@##linux2013,216.57.101.104,WIC,DEN01
##@NIBU@##linux2014,216.57.101.105,WIC,DEN01
##@NIBU@##linux2015,216.57.101.106,WIC,DEN01
##@NIBU@##linux2016,216.57.101.107,WIC,DEN01
##@NIBU@##linux2019,10.20.217.95,WCMG,HSV01
##@NIBU@##linux202,172.30.75.15,ITC,ATL01
##@NIBU@##linux2020,10.20.217.96,WCMG,HSV01
##@NIBU@##linux2021,10.20.151.76,WCMG,NLS01
##@NIBU@##linux2022,10.20.151.77,WCMG,NLS01
##@NIBU@##linux2023,10.26.184.84,WCMG,OMA13
##@NIBU@##linux2024,10.26.184.85,WCMG,OMA13
##@NIBU@##linux2025,10.35.88.22,WCMG,PNS01
##@NIBU@##linux2026,10.35.88.23,WCMG,PNS01
##@NIBU@##linux2027,10.26.111.68,WCMG,RNO01
##@NIBU@##linux2028,10.26.111.69,WCMG,RNO01
##@NIBU@##linux2029,10.23.52.100,WCMG,SPO01
##@NIBU@##linux203,172.30.75.16,ITC,ATL01
##@NIBU@##linux2030,10.23.52.102,WCMG,SPO01
##@NIBU@##linux2033,10.27.217.75,ITC,OMA00
##@NIBU@##linux2034,10.27.217.76,ITC,OMA00
##@NIBU@##linux2035,10.27.217.77,ITC,OMA00
##@NIBU@##linux2036,10.27.217.78,ITC,OMA00
##@NIBU@##linux2037,10.27.217.79,ITC,OMA00
##@NIBU@##linux2038,216.57.100.112,WIC,OMA01
##@NIBU@##Linux2039,10.17.52.185,WIC,OMA10
##@NIBU@##linux204,172.30.75.17,ITC,ATL01
##@NIBU@##Linux2040,10.17.52.17,WIC,OMA10
##@NIBU@##Linux2041,10.17.52.18,WIC,OMA10
##@NIBU@##linux2042,10.17.52.114,WIC,OMA10
##@NIBU@##linux2043,10.27.194.128,WIC,OMA00
##@NIBU@##linux2044,10.27.194.129,WIC,OMA00
##@NIBU@##linux2045,10.50.191.199,WIC,OMA00
##@NIBU@##linux2046,216.57.101.99,WCMG,DEN01
##@NIBU@##linux2047,216.57.101.100,WCMG,DEN01
##@NIBU@##linux2048,216.57.101.101,WCMG,DEN01
##@NIBU@##linux2049,216.57.102.167,WCMG,OMA01
##@NIBU@##linux205,172.30.75.18,ITC,ATL01
##@NIBU@##linux2050,216.57.102.168,WCMG,OMA01
##@NIBU@##linux2051,216.57.102.169,WCMG,OMA01
##@NIBU@##linux2055,10.27.211.13,WIC,OMA00
##@NIBU@##linux2056,10.27.211.14,WIC,OMA00
##@NIBU@##linux2057,10.62.21.71,ITC,WPT01
##@NIBU@##Linux2058,10.29.99.55,WIC,DEN01
##@NIBU@##Linux2059,10.29.99.56,WIC,DEN01
##@NIBU@##linux206,172.30.75.19,ITC,ATL01
##@NIBU@##Linux2060,10.29.99.87,WIC,DEN01
##@NIBU@##Linux2061,10.29.99.88,WIC,DEN01
##@NIBU@##Linux2062,10.29.99.119,WIC,DEN01
##@NIBU@##Linux2063,10.29.99.120,WIC,DEN01
##@NIBU@##Linux2064,10.29.99.151,WIC,DEN01
##@NIBU@##Linux2065,10.29.99.152,WIC,DEN01
##@NIBU@##Linux2066,10.29.99.183,WIC,DEN01
##@NIBU@##Linux2067,10.29.99.184,WIC,DEN01
##@NIBU@##Linux2068,10.29.99.215,WIC,DEN01
##@NIBU@##Linux2069,10.29.99.216,WIC,DEN01
##@NIBU@##linux207,172.30.75.20,ITC,ATL01
##@NIBU@##Linux2070,10.29.99.246,WIC,DEN01
##@NIBU@##Linux2071,10.29.99.247,WIC,DEN01
##@NIBU@##Linux2072,10.29.99.248,WIC,DEN01
##@NIBU@##linux2075,10.17.125.75,WIC,OMA10
##@NIBU@##linux2076,10.28.124.32,WIC,ATL01
##@NIBU@##linux2077,10.28.124.33,WIC,ATL01
##@NIBU@##linux2078,10.27.193.56,WIC,OMA00
##@NIBU@##linux2079,10.29.116.21,ITC,DEN01
##@NIBU@##linux208,172.30.75.21,ITC,ATL01
##@NIBU@##linux2081,10.28.124.34,ITC,ATL01
##@NIBU@##linux2084,216.57.101.53,EIT,DEN01
##@NIBU@##linux2085,192.168.0.1,EIT,OMA00
##@NIBU@##linux2086,10.27.115.32,ITC,OMA00
##@NIBU@##linux2087,10.17.61.218,ITC,OMA00
##@NIBU@##linux2089,10.64.2.70,ITC,SWN01
##@NIBU@##linux209,172.30.75.22,ITC,ATL01
##@NIBU@##linux2090,10.64.2.71,ITC,SWN01
##@NIBU@##linux2091,10.64.216.23,ITC,VAL01
##@NIBU@##linux2092,10.28.124.43,ITC,ATL01
##@NIBU@##linux2093,10.54.24.222,ITC,YGK01
##@NIBU@##linux2095,10.27.220.44,WIC,OMA00
##@NIBU@##linux2096,10.27.193.173,WIC,OMA00
##@NIBU@##linux2097,10.29.114.50,WIC,DEN01
##@NIBU@##linux2098,10.29.114.52,WIC,DEN01
##@NIBU@##linux2099,10.29.114.54,WIC,DEN01
##@NIBU@##linux21,172.30.9.151,EIT,OMA10
##@NIBU@##linux210,172.30.75.23,ITC,ATL01
##@NIBU@##linux2100,10.17.56.50,WIC,OMA10
##@NIBU@##linux2101,10.17.56.52,WIC,OMA10
##@NIBU@##linux2102,10.17.56.54,WIC,OMA10
##@NIBU@##linux2103,10.25.56.82,CORP,BPT01
##@NIBU@##linux2104,10.27.198.23,WIC,OMA00
##@NIBU@##linux2105,10.27.198.24,WIC,OMA00
##@NIBU@##linux2106,10.27.198.25,WIC,OMA00
##@NIBU@##linux2107,10.27.198.26,WIC,OMA00
##@NIBU@##linux2108,10.27.198.27,WIC,OMA00
##@NIBU@##linux2109,10.27.198.28,WIC,OMA00
##@NIBU@##linux211,172.30.21.181,WIC,DEN01
##@NIBU@##linux2110,10.27.198.29,WIC,OMA00
##@NIBU@##linux2111,216.57.98.143,EIT,OMA01
##@NIBU@##linux2112,10.27.117.100,CORP,OMA00
##@NIBU@##linux2113,10.27.117.102,CORP,OMA00
##@NIBU@##linux2114,10.62.10.61,ITC,SWN01
##@NIBU@##linux2115,10.62.10.61,ITC,SWN01
##@NIBU@##linux212,172.30.21.182,WIC,DEN01
##@NIBU@##linux2122,10.166.200.21,ITC,LON01
##@NIBU@##linux2123,10.166.200.22,ITC,LON01
##@NIBU@##linux2124,10.166.200.23,ITC,LON01
##@NIBU@##linux2125,10.166.200.24,ITC,LON01
##@NIBU@##linux2126,10.166.200.25,ITC,LON01
##@NIBU@##linux2127,10.166.200.26,ITC,LON01
##@NIBU@##linux2128,10.166.200.27,ITC,LON01
##@NIBU@##linux2129,10.166.200.45,ITC,LON01
##@NIBU@##linux2130,10.166.200.46,ITC,LON01
##@NIBU@##linux2131,10.166.200.47,ITC,LON01
##@NIBU@##linux2132,10.166.200.48,ITC,LON01
##@NIBU@##linux2133,10.166.200.49,ITC,LON01
##@NIBU@##linux2134,10.166.200.50,ITC,LON01
##@NIBU@##linux2135,10.166.200.51,ITC,LON01
##@NIBU@##linux2136,10.27.220.47,WIC,OMA00
##@NIBU@##linux2137,10.27.220.49,WIC,OMA00
##@NIBU@##linux2139,10.27.115.78,WIC,OMA00
##@NIBU@##linux214,172.30.112.187,WIC,OMA00
##@NIBU@##linux2146,10.64.2.31,ITC,SWN01
##@NIBU@##linux2147,10.64.4.20,ITC,SWN01
##@NIBU@##linux2148,10.64.4.21,ITC,SWN01
##@NIBU@##linux2149,10.18.139.62,WIC,OMA11
##@NIBU@##linux2150,10.18.139.64,WIC,OMA11
##@NIBU@##linux2151,75.78.1.67,ITC,SWN01
##@NIBU@##linux2152,75.78.1.62,ITC,SWN01
##@NIBU@##linux2153,75.78.1.63,ITC,SWN01
##@NIBU@##linux2154,75.78.1.64,ITC,SWN01
##@NIBU@##linux2155,75.78.1.65,ITC,SWN01
##@NIBU@##linux2156,75.78.1.66,ITC,SWN01
##@NIBU@##linux2157,216.57.102.180,CORP,OMA01
##@NIBU@##linux2158,10.27.115.79,WIC,OMA00
##@NIBU@##linux2159,10.167.201.11,ITC,SHG01
##@NIBU@##Linux216,172.30.1.216,WIC,OMA01
##@NIBU@##linux2160,10.184.152.104,ITC,SHG01
##@NIBU@##linux2161,10.167.201.13,ITC,SHG01
##@NIBU@##linux2162,10.167.201.14,ITC,SHG01
##@NIBU@##linux2163,10.167.201.15,ITC,SHG01
##@NIBU@##linux2164,10.167.201.16,ITC,SHG01
##@NIBU@##linux2165,10.167.201.17,ITC,SHG01
##@NIBU@##linux2166,10.28.168.52,ITC,ATL01
##@NIBU@##linux2167,10.28.168.54,ITC,ATL01
##@NIBU@##linux2168,10.31.72.47,ITC,PHX01
##@NIBU@##linux2169,10.31.72.49,ITC,PHX01
##@NIBU@##Linux217,172.30.1.217,WIC,OMA01
##@NIBU@##linux2170,10.27.220.51,ITC,OMA00
##@NIBU@##linux2171,216.57.101.55,WIC,DEN01
##@NIBU@##linux2172,10.64.21.36,ITC,SWN01
##@NIBU@##linux2173,10.64.12.80,ITC,SWN01
##@NIBU@##linux2174,10.64.12.81,ITC,SWN01
##@NIBU@##linux2175,10.64.12.82,ITC,SWN01
##@NIBU@##linux2176,10.64.2.35,ITC,SWN01
##@NIBU@##linux2177,10.64.2.36,ITC,SWN01
##@NIBU@##linux2178,10.64.2.37,ITC,SWN01
##@NIBU@##linux218,172.30.112.155,WIC,OMA00
##@NIBU@##linux2183,10.168.200.25,ITC,SIN01
##@NIBU@##linux2184,10.168.200.26,ITC,SIN01
##@NIBU@##linux2185,10.168.200.27,ITC,SIN01
##@NIBU@##linux219,172.30.112.156,CORP,OMA00
##@NIBU@##linux2190,10.168.200.49,ITC,SIN01
##@NIBU@##linux2191,10.168.200.50,ITC,SIN01
##@NIBU@##linux2192,10.168.200.51,ITC,SIN01
##@NIBU@##linux2193,10.168.200.30,ITC,SIN01
##@NIBU@##linux2194,10.168.200.66,ITC,SIN01
##@NIBU@##linux2195,75.78.2.56,ITC,SWN01
##@NIBU@##linux2196,75.78.2.57,ITC,SWN01
##@NIBU@##linux2197,10.64.12.74,ITC,SWN01
##@NIBU@##linux2198,10.64.12.75,ITC,SWN01
##@NIBU@##linux2199,10.64.4.22,ITC,SWN01
##@NIBU@##linux220,10.27.193.137,WIC,OMA00
##@NIBU@##linux2200,10.64.4.23,ITC,SWN01
##@NIBU@##linux2201,10.31.135.50,ITC,PHX01
##@NIBU@##linux2202,10.27.96.17,EIT,OMA00
##@NIBU@##linux2203,172.30.185.26,WIC,OMA10
##@NIBU@##linux2204,172.30.185.27,WIC,OMA10
##@NIBU@##linux2205,172.30.57.27,WIC,DEN01
##@NIBU@##linux2215,10.184.16.22,ITC,WDC03
##@NIBU@##linux2219,10.27.115.97,ITC,OMA00
##@NIBU@##linux2221,10.64.10.90,ITC,SWN01
##@NIBU@##linux2222,10.64.10.91,ITC,SWN01
##@NIBU@##linux2223,10.70.3.40,ITC,DEN06
##@NIBU@##linux2224,10.70.3.41,ITC,DEN06
##@NIBU@##linux2225,10.64.22.35,ITC,SWN01
##@NIBU@##linux2226,10.64.22.36,ITC,SWN01
##@NIBU@##linux2227,75.78.1.57,ITC,SWN01
##@NIBU@##linux2228,75.78.1.58,ITC,SWN01
##@NIBU@##linux2229,75.78.1.59,ITC,SWN01
##@NIBU@##linux2230,10.64.49.28,ITC,SWN01
##@NIBU@##linux2231,10.64.49.29,ITC,SWN01
##@NIBU@##linux2232,75.78.1.60,ITC,SWN01
##@NIBU@##linux2233,75.78.1.61,ITC,SWN01
##@NIBU@##linux2234,10.64.4.30,ITC,SWN01
##@NIBU@##linux2235,10.64.2.52,ITC,SWN01
##@NIBU@##linux2236,75.78.1.157,ITC,SWN01
##@NIBU@##linux2237,10.64.2.75,ITC,SWN01
##@NIBU@##linux2238,10.64.2.76,ITC,SWN01
##@NIBU@##linux2239,10.64.2.77,ITC,SWN01
##@NIBU@##linux224,10.27.193.23,WIC,OMA00
##@NIBU@##linux2240,75.78.1.158,ITC,SWN01
##@NIBU@##linux2241,10.64.2.79,ITC,SWN01
##@NIBU@##linux2244,10.64.2.80,ITC,SWN01
##@NIBU@##linux2245,10.64.2.81,ITC,SWN01
##@NIBU@##linux2246,75.78.1.47,ITC,SWN01
##@NIBU@##linux2247,75.78.1.48,ITC,SWN01
##@NIBU@##linux2248,75.78.2.62,ITC,SWN01
##@NIBU@##linux2249,75.78.2.63,ITC,SWN01
##@NIBU@##linux2250,10.64.2.82,ITC,SWN01
##@NIBU@##linux2251,10.64.2.83,ITC,SWN01
##@NIBU@##linux2252,75.78.1.51,ITC,SWN01
##@NIBU@##linux2253,75.78.1.52,ITC,SWN01
##@NIBU@##linux2254,75.78.2.64,ITC,SWN01
##@NIBU@##linux2255,75.78.2.65,ITC,SWN01
##@NIBU@##linux2256,10.64.12.94,ITC,SWN01
##@NIBU@##linux2257,10.25.24.40,EIT,RMT01
##@NIBU@##linux2258,10.24.56.65,EIT,CLL01
##@NIBU@##linux2259,10.42.117.66,EIT,SAT01
##@NIBU@##Linux226,10.29.115.113,WIC,DEN01
##@NIBU@##linux2260,10.20.217.87,EIT,HSV01
##@NIBU@##linux2261,10.24.248.50,EIT,MNL02
##@NIBU@##linux2262,10.19.114.57,EIT,OMA01
##@NIBU@##linux2263,10.19.114.59,EIT,OMA01
##@NIBU@##linux2264,10.19.114.61,EIT,OMA01
##@NIBU@##linux2265,10.64.49.24,ITC,SWN01
##@NIBU@##linux2266,10.64.49.25,ITC,SWN01
##@NIBU@##linux2267,10.64.49.26,ITC,SWN01
##@NIBU@##linux2269,10.64.2.41,ITC,SWN01
##@NIBU@##Linux227,10.29.115.114,WIC,DEN01
##@NIBU@##linux2270,10.64.2.42,ITC,SWN01
##@NIBU@##linux2271,10.64.2.50,ITC,SWN01
##@NIBU@##linux2272,10.64.4.27,ITC,SWN01
##@NIBU@##linux2273,10.19.115.93,WIC,OMA01
##@NIBU@##linux2276,10.27.113.33,WIC,OMA00
##@NIBU@##linux2277,10.27.113.30,WIC,OMA00
##@NIBU@##linux2278,10.27.113.37,WIC,OMA00
##@NIBU@##linux2279,173.30.57.28,WIC,DEN01
##@NIBU@##linux228,10.27.193.37,WIC,OMA00
##@NIBU@##linux2280,10.64.49.51,ITC,SWN01
##@NIBU@##linux2281,10.64.49.52,ITC,SWN01
##@NIBU@##linux2282,10.64.49.32,ITC,SWN01
##@NIBU@##linux2283,10.64.49.33,ITC,SWN01
##@NIBU@##linux2284,10.64.2.98,ITC,SWN01
##@NIBU@##linux2285,10.64.2.99,ITC,SWN01
##@NIBU@##linux2286,10.64.2.102,ITC,SWN01
##@NIBU@##linux2287,10.64.2.104,ITC,SWN01
##@NIBU@##linux2288,75.78.1.82,ITC,SWN01
##@NIBU@##linux2289,75.78.1.83,ITC,SWN01
##@NIBU@##linux229,10.27.216.139,WIC,OMA00
##@NIBU@##linux2292,75.78.2.80,ITC,SWN01
##@NIBU@##linux2293,75.78.2.81,ITC,SWN01
##@NIBU@##linux2294,75.78.1.86,ITC,SWN01
##@NIBU@##linux2295,75.78.1.87,ITC,SWN01
##@NIBU@##linux2296,75.78.1.88,ITC,SWN01
##@NIBU@##linux2297,75.78.1.89,ITC,SWN01
##@NIBU@##linux23,10.19.61.78,WIC,OMA01
##@NIBU@##linux2308,10.27.217.141,WIC,OMA00
##@NIBU@##linux2309,10.27.217.142,WIC,OMA00
##@NIBU@##linux2310,10.27.217.143,WIC,OMA00
##@NIBU@##linux2312,10.27.200.25,WIC,OMA00
##@NIBU@##linux2313,10.27.200.27,WIC,OMA00
##@NIBU@##linux2314,10.27.217.144,WIC,OMA00
##@NIBU@##linux232,172.30.41.206,WIC,DEN01
##@NIBU@##LINUX2320,10.27.217.158,WIC,OMA00
##@NIBU@##LINUX2321,10.27.217.159,WIC,OMA00
##@NIBU@##LINUX2322,10.27.217.160,WIC,OMA00
##@NIBU@##LINUX2323,10.27.217.161,WIC,OMA00
##@NIBU@##linux2328,10.27.217.171,WIC,OMA00
##@NIBU@##linux2329,10.27.217.172,WIC,OMA00
##@NIBU@##linux233,172.30.41.207,WIC,DEN01
##@NIBU@##linux2330,10.27.217.173,WIC,OMA00
##@NIBU@##linux2331,10.27.217.174,WIC,OMA00
##@NIBU@##linux2332,10.27.68.21,WIC,OMA00
##@NIBU@##linux2333,10.27.68.22,WIC,OMA00
##@NIBU@##linux2334,10.27.68.23,WIC,OMA00
##@NIBU@##linux2335,10.27.68.24,WIC,OMA00
##@NIBU@##linux2336,10.27.68.25,WIC,OMA00
##@NIBU@##linux2337,10.28.226.33,WIC,ATL01
##@NIBU@##linux2338,10.27.68.27,WIC,OMA00
##@NIBU@##linux2339,10.27.68.28,WIC,OMA00
##@NIBU@##linux234,172.30.41.204,WIC,DEN01
##@NIBU@##linux2340,10.27.68.37,WIC,OMA00
##@NIBU@##linux2341,10.27.68.38,WIC,OMA00
##@NIBU@##linux2342,10.27.68.39,WIC,OMA00
##@NIBU@##linux2343,10.27.68.40,WIC,OMA00
##@NIBU@##linux2344,10.27.68.41,WIC,OMA00
##@NIBU@##linux2345,10.27.68.42,WIC,OMA00
##@NIBU@##linux2346,10.28.226.34,WIC,ATL01
##@NIBU@##linux2348,10.27.68.57,WIC,OMA00
##@NIBU@##linux235,172.30.41.205,WIC,DEN01
##@NIBU@##linux2350,10.27.68.59,WIC,OMA00
##@NIBU@##linux2352,10.27.68.61,WIC,OMA00
##@NIBU@##linux2353,10.27.68.62,WIC,OMA00
##@NIBU@##linux2357,10.28.107.91,WIC,ATL01
##@NIBU@##linux2358,10.28.103.32,WIC,ATL01
##@NIBU@##linux2359,10.62.21.209,ITC,WPT01
##@NIBU@##linux236,172.30.113.98,WIC,OMA00
##@NIBU@##linux2360,10.18.153.166,WIC,OMA11
##@NIBU@##linux2361,10.18.153.180,WIC,OMA11
##@NIBU@##linux2362,10.18.153.176,WIC,OMA11
##@NIBU@##linux2363,10.18.153.177,WIC,OMA11
##@NIBU@##linux2364,10.18.153.178,WIC,OMA11
##@NIBU@##linux2369,75.78.2.88,ITC,SWN01
##@NIBU@##linux237,172.30.113.9,WIC,OMA00
##@NIBU@##linux2370,75.78.2.89,ITC,SWN01
##@NIBU@##linux2371,75.78.1.94,ITC,SWN01
##@NIBU@##linux2372,75.78.1.95,ITC,SWN01
##@NIBU@##linux2373,10.64.49.50,EIT,SWN01
##@NIBU@##linux2374,10.28.96.112,WIC,ATL01
##@NIBU@##linux2375,10.28.96.171,WIC,ATL01
##@NIBU@##linux2376,10.28.96.172,WIC,ATL01
##@NIBU@##linux2377,10.28.96.173,WIC,ATL01
##@NIBU@##linux2378,10.28.96.174,WIC,ATL01
##@NIBU@##linux2379,10.28.96.175,WIC,ATL01
##@NIBU@##linux238,172.30.113.89,WIC,OMA00
##@NIBU@##linux2380,10.28.96.176,WIC,ATL01
##@NIBU@##linux2381,10.28.96.235,WIC,ATL01
##@NIBU@##linux2382,10.28.96.236,WIC,ATL01
##@NIBU@##Linux2383,10.28.96.237,WIC,ATL01
##@NIBU@##Linux2384,10.28.96.238,WIC,ATL01
##@NIBU@##linux2385,10.28.96.239,WIC,ATL01
##@NIBU@##linux2388,10.64.6.73,ITC,SWN01
##@NIBU@##linux2389,10.64.6.74,ITC,SWN01
##@NIBU@##linux239,172.30.113.88,WIC,OMA00
##@NIBU@##linux2390,10.64.6.75,ITC,SWN01
##@NIBU@##linux2391,10.64.6.76,ITC,SWN01
##@NIBU@##linux2392,10.27.113.39,WIC,OMA00
##@NIBU@##linux2393,75.78.1.106,ITC,SWN01
##@NIBU@##linux2394,75.78.1.107,ITC,SWN01
##@NIBU@##linux2395,10.64.2.106,ITC,SWN01
##@NIBU@##linux2396,10.64.2.107,ITC,SWN01
##@NIBU@##linux2397,75.78.1.108,ITC,SWN01
##@NIBU@##linux2398,75.78.1.109,ITC,SWN01
##@NIBU@##linux2399,75.78.2.106,ITC,SWN01
##@NIBU@##linux24,linux24,EIT,OMA00
##@NIBU@##linux240,172.30.154.20,EIT,OMA01
##@NIBU@##linux2400,75.78.2.107,ITC,SWN01
##@NIBU@##linux2401,10.64.2.108,ITC,SWN01
##@NIBU@##linux2402,10.64.2.109,ITC,SWN01
##@NIBU@##linux2403,75.78.2.108,ITC,SWN01
##@NIBU@##linux2404,75.78.1.112,ITC,SWN01
##@NIBU@##linux2405,10.28.103.33,WIC,ATL01
##@NIBU@##linux2406,10.17.53.112,WIC,OMA10
##@NIBU@##linux2407,10.17.53.113,WIC,OMA10
##@NIBU@##linux2408,10.27.128.33,WIC,OMA00
##@NIBU@##linux2409,10.28.103.30,WIC,ATL01
##@NIBU@##linux241,172.30.152.21,WIC,OMA01
##@NIBU@##linux2410,10.27.68.51,WIC,OMA00
##@NIBU@##linux2411,10.27.68.53,WIC,OMA00
##@NIBU@##linux2412,10.27.111.21,WIC,OMA00
##@NIBU@##linux2413,10.27.112.21,WIC,OMA00
##@NIBU@##linux2414,172.30.8.150,WIC,OMA10
##@NIBU@##linux2415,172.30.8.152,WIC,OMA10
##@NIBU@##linux2416,10.29.114.45,WIC,DEN01
##@NIBU@##linux2417,10.29.114.46,WIC,DEN01
##@NIBU@##linux2418,10.27.68.93,WIC,OMA00
##@NIBU@##linux2419,10.27.68.95,WIC,OMA00
##@NIBU@##linux242,10.27.193.22,WIC,OMA00
##@NIBU@##linux2420,10.26.184.70,WIC,OMA10
##@NIBU@##linux2421,10.29.99.19,WCMG,DEN01
##@NIBU@##linux2422,10.29.99.20,WCMG,DEN01
##@NIBU@##linux2427,10.29.114.63,WCMG,DEN01
##@NIBU@##linux2428,10.29.114.64,WCMG,DEN01
##@NIBU@##linux2434,10.62.26.70,ITC,WPT03
##@NIBU@##linux2436,10.0.0.211,CORP,OMA01
##@NIBU@##linux2437,10.0.35.210,CORP,OMA11
##@NIBU@##linux2439,216.57.101.207,WIC,DEN01
##@NIBU@##linux244,172.30.2.62,EIT,OMA01
##@NIBU@##linux2440,10.28.124.63,WIC,ATL01
##@NIBU@##linux2441,10.27.220.200,WIC,OMA00
##@NIBU@##linux2442,10.64.51.29,ITC,SWN01
##@NIBU@##linux2443,10.64.2.119,ITC,SWN01
##@NIBU@##linux2444,10.64.2.120,ITC,SWN01
##@NIBU@##linux2447,10.64.51.23,ITC,SWN01
##@NIBU@##linux2448,10.70.224.21,WIC,DEN06
##@NIBU@##linux2449,10.70.224.22,WIC,DEN06
##@NIBU@##linux245,172.30.8.125,EIT,OMA10
##@NIBU@##linux2450,10.70.224.23,WIC,DEN06
##@NIBU@##linux2451,10.70.224.24,WIC,DEN06
##@NIBU@##linux2452,10.70.224.25,WIC,DEN06
##@NIBU@##linux2453,10.70.224.26,WIC,DEN06
##@NIBU@##linux2454,10.70.224.27,WIC,DEN06
##@NIBU@##linux2455,10.70.224.28,WIC,DEN06
##@NIBU@##linux2456,10.70.224.29,WIC,DEN06
##@NIBU@##linux2457,10.70.224.35,WIC,DEN06
##@NIBU@##linux2458,10.70.224.36,WIC,DEN06
##@NIBU@##linux2459,10.70.224.37,WIC,DEN06
##@NIBU@##Linux246,10.29.115.100,WIC,DEN01
##@NIBU@##linux2460,10.70.224.38,WIC,DEN06
##@NIBU@##linux2461,10.70.224.39,WIC,DEN06
##@NIBU@##linux2462,10.70.224.40,WIC,DEN06
##@NIBU@##linux2463,10.70.224.41,WIC,DEN06
##@NIBU@##linux2464,10.70.224.49,WIC,DEN06
##@NIBU@##linux2465,10.29.97.26,WIC,DEN01
##@NIBU@##linux2466,10.29.97.17,WIC,DEN01
##@NIBU@##linux2467,10.70.224.55,WIC,DEN06
##@NIBU@##linux2468,10.70.224.56,WIC,DEN06
##@NIBU@##Linux247,10.29.115.101,WIC,DEN01
##@NIBU@##Linux2470,10.29.97.154,WIC,DEN01
##@NIBU@##linux2471,10.29.97.155,WIC,DEN01
##@NIBU@##linux2472,10.29.97.156,WIC,DEN01
##@NIBU@##linux2473,10.29.97.186,WIC,DEN01
##@NIBU@##linux2474,10.29.97.187,WIC,DEN01
##@NIBU@##linux2475,10.70.0.199,WIC,DEN06
##@NIBU@##linux2476,10.70.0.214,WIC,DEN06
##@NIBU@##linux2477,10.27.193.160,WIC,OMA00
##@NIBU@##linux2478,10.70.224.72,WIC,DEN06
##@NIBU@##linux2479,10.70.224.73,WIC,DEN06
##@NIBU@##Linux248,172.30.4.190,WIC,OMA01
##@NIBU@##linux2480,10.70.224.80,WIC,DEN06
##@NIBU@##linux2481,10.70.224.81,WIC,DEN06
##@NIBU@##linux2482,10.70.224.82,WIC,DEN06
##@NIBU@##linux2483,10.70.224.83,WIC,DEN06
##@NIBU@##linux2484,10.70.0.25,WIC,DEN06
##@NIBU@##linux2485,10.70.0.26,WIC,DEN06
##@NIBU@##linux2486,10.62.235.30,ITC,TYO05
##@NIBU@##linux2487,10.62.235.32,ITC,TYO05
##@NIBU@##linux2488,10.42.118.94,EIT,SAT01
##@NIBU@##linux2489,10.64.49.81,EIT,SWN01
##@NIBU@##Linux249,172.30.4.191,WIC,OMA01
##@NIBU@##linux2490,10.27.113.71,EIT,OMA00
##@NIBU@##linux2491,75.78.1.138,ITC,SWN01
##@NIBU@##linux2492,75.78.1.139,ITC,SWN01
##@NIBU@##linux2493,10.64.51.30,ITC,SWN01
##@NIBU@##linux2494,10.64.51.31,ITC,SWN01
##@NIBU@##linux2495,10.64.51.32,ITC,SWN01
##@NIBU@##linux2496,10.64.51.33,ITC,SWN01
##@NIBU@##linux2497,75.78.1.134,ITC,SWN01
##@NIBU@##linux2498,75.78.1.135,ITC,SWN01
##@NIBU@##linux2499,10.64.2.121,ITC,SWN01
##@NIBU@##linux25,10.27.193.21,WIC,OMA00
##@NIBU@##linux250,10.29.115.102,WIC,DEN01
##@NIBU@##linux2500,10.64.2.122,ITC,SWN01
##@NIBU@##linux2501,75.78.1.136,ITC,SWN01
##@NIBU@##linux2502,75.78.1.137,ITC,SWN01
##@NIBU@##linux2503,10.64.2.123,ITC,SWN01
##@NIBU@##linux2504,10.27.113.73,WIC,OMA00
##@NIBU@##linux2505,10.70.1.23,EIT,DEN06
##@NIBU@##linux2506,10.169.200.40,ITC,TOR03
##@NIBU@##linux2507,10.169.200.43,ITC,TOR03
##@NIBU@##linux2508,10.64.51.34,ITC,SWN01
##@NIBU@##linux2509,10.64.51.35,ITC,SWN01
##@NIBU@##linux251,10.29.115.104,WIC,DEN01
##@NIBU@##linux2510,10.64.2.136,ITC,SWN01
##@NIBU@##linux2511,10.64.2.137,ITC,SWN01
##@NIBU@##linux2512,10.64.2.138,ITC,SWN01
##@NIBU@##linux2513,216.57.102.75,WCMG,OMA01
##@NIBU@##linux2515,10.18.123.114,EIT,OMA11
##@NIBU@##linux2516,10.64.51.36,ITC,SWN01
##@NIBU@##linux2517,10.64.51.37,ITC,SWN01
##@NIBU@##linux2518,10.64.2.72,ITC,SWN01
##@NIBU@##linux2519,10.64.2.73,ITC,SWN01
##@NIBU@##Linux252,10.29.115.110 ,WIC,DEN01
##@NIBU@##linux2520,10.64.2.74,ITC,SWN01
##@NIBU@##linux2521,10.62.236.21,ITC,SYD01
##@NIBU@##linux2522,10.62.236.23,ITC,SYD01
##@NIBU@##linux2523,10.62.236.24,ITC,SYD01
##@NIBU@##linux2524,10.62.223.24,ITC,SYD01
##@NIBU@##linux2525,10.62.222.25,ITC,SIN04
##@NIBU@##linux2526,10.62.222.26,ITC,SIN04
##@NIBU@##linux2527,10.62.222.27,ITC,SIN04
##@NIBU@##linux2528,10.62.222.28,ITC,SIN04
##@NIBU@##linux2529,10.27.220.100,ITC,OMA00
##@NIBU@##linux2530,10.27.220.102,ITC,OMA00
##@NIBU@##linux2531,10.27.220.104,ITC,OMA00
##@NIBU@##linux2532,10.27.220.106,ITC,OMA00
##@NIBU@##linux2533,172.30.10.34,WIC,OMA10
##@NIBU@##linux2534,216.57.102.217,WIC,OMA01
##@NIBU@##linux2535,10.27.60.106,WIC,OMA00
##@NIBU@##linux2536,10.54.24.40,ITC,YGK01
##@NIBU@##linux2537,10.54.24.42,ITC,YGK01
##@NIBU@##linux2538,10.54.24.44,ITC,YGK01
##@NIBU@##linux2539,10.54.24.46,ITC,YGK01
##@NIBU@##linux254,172.30.4.182,WIC,OMA01
##@NIBU@##linux2540,10.62.21.242,ITC,WPT01
##@NIBU@##linux2542,10.62.21.20,ITC,WPT01
##@NIBU@##linux2543,216.57.109.57,TVX,ATL01
##@NIBU@##LINUX2544,216.57.109.58,TVX,ATL01
##@NIBU@##linux2545,10.27.200.41,WIC,OMA00
##@NIBU@##linux2546,10.27.200.43,WIC,OMA00
##@NIBU@##linux2547,10.27.200.44,WIC,OMA00
##@NIBU@##linux2548,10.27.200.45,WIC,OMA00
##@NIBU@##linux2549,10.27.200.46,WIC,OMA00
##@NIBU@##linux255,172.30.4.183,WIC,OMA01
##@NIBU@##linux2550,10.27.200.47,WIC,OMA00
##@NIBU@##linux2551,10.27.200.48,ITC,OMA00
##@NIBU@##linux2552,10.27.200.49,WIC,OMA00
##@NIBU@##linux2553,10.18.131.25,WIC,OMA11
##@NIBU@##linux2554,10.18.131.47,WIC,OMA11
##@NIBU@##linux2555,10.18.131.48,WIC,OMA11
##@NIBU@##linux2556,10.18.131.49,WIC,OMA11
##@NIBU@##linux2557,10.18.131.50,WIC,OMA11
##@NIBU@##linux2558,10.18.131.51,WIC,OMA11
##@NIBU@##linux2559,10.18.131.32,WIC,OMA11
##@NIBU@##linux256,10.27.193.38,WIC,OMA00
##@NIBU@##linux2560,10.18.131.33,WIC,OMA11
##@NIBU@##linux2561,10.27.217.205,WIC,OMA00
##@NIBU@##linux2562,10.27.217.190,WIC,OMA00
##@NIBU@##linux2563,10.27.217.206,WIC,OMA00
##@NIBU@##linux2564,10.27.217.191,WIC,OMA00
##@NIBU@##linux2565,10.28.103.26,WIC,ATL01
##@NIBU@##linux2566,10.27.217.192,WIC,OMA00
##@NIBU@##linux2567,10.27.217.208,WIC,OMA00
##@NIBU@##linux2568,10.27.217.193,WIC,OMA00
##@NIBU@##linux2569,10.27.217.167,WIC,OMA00
##@NIBU@##linux257,10.27.193.39,WIC,OMA00
##@NIBU@##linux2570,10.27.217.194,WIC,OMA00
##@NIBU@##linux2571,10.27.217.209,WIC,OMA00
##@NIBU@##linux2572,10.27.217.195,WIC,OMA00
##@NIBU@##linux2573,10.27.217.210,WIC,OMA00
##@NIBU@##linux2574,10.27.217.196,WIC,OMA00
##@NIBU@##linux2575,10.27.217.211,WIC,OMA00
##@NIBU@##linux2576,10.27.217.197,WIC,OMA00
##@NIBU@##linux2577,10.27.217.212,WIC,OMA00
##@NIBU@##LINUX2578,10.28106.42,WIC,ATL01
##@NIBU@##linux258,10.27.193.40,WIC,OMA00
##@NIBU@##linux2580,10.27.68.80,WIC,OMA00
##@NIBU@##linux2582,10.17.53.110,WIC,OMA10
##@NIBU@##linux2583,10.17.53.111,WIC,OMA10
##@NIBU@##linux2584,10.28.103.28,WIC,ATL01
##@NIBU@##linux2587,10.27.193.163,WIC,OMA00
##@NIBU@##linux2588,10.28.103.27,WIC,ATL01
##@NIBU@##linux2589,10.28.103.42,WIC,ATL01
##@NIBU@##linux259,10.27.193.41,WIC,OMA00
##@NIBU@##linux2591,10.28.107.82,WIC,ATL01
##@NIBU@##linux2592,10.27.193.162,WIC,OMA00
##@NIBU@##linux2593,10.17.53.109,WIC,OMA10
##@NIBU@##linux2594,10.27.200.94,WIC,OMA00
##@NIBU@##linux2595,10.27.200.95,WIC,OMA00
##@NIBU@##linux2596,10.27.200.96,WIC,OMA00
##@NIBU@##linux2597,10.27.200.97,WIC,OMA00
##@NIBU@##linux2598,10.27.130.182,WIC,OMA00
##@NIBU@##linux2599,10.27.130.183,WIC,OMA00
##@NIBU@##linux260,172.30.3.180,WIC,OMA01
##@NIBU@##linux2600,10.27.128.23,WIC,OMA00
##@NIBU@##linux2601,10.27.128.24,WIC,OMA00
##@NIBU@##linux2602,10.27.193.161,WIC,OMA00
##@NIBU@##linux2603,10.27.96.18,WIC,OMA00
##@NIBU@##linux2605,10.70.224.87,WIC,DEN06
##@NIBU@##linux2608,10.29.97.212,WIC,DEN01
##@NIBU@##linux2609,10.29.97.145,WIC,DEN01
##@NIBU@##linux261,172.30.9.179,EIT,OMA10
##@NIBU@##linux2611,10.70.224.74,WIC,DEN06
##@NIBU@##linux2612,10.29.97.213,WIC,DEN01
##@NIBU@##linux2616,10.70.224.76,WIC,ATL01
##@NIBU@##linux2617,10.70.224.86,WIC,DEN01
##@NIBU@##linux262,172.30.43.155,EIT,DEN01
##@NIBU@##linux2620,10.27.220.60,WIC,OMA00
##@NIBU@##linux2621,10.27.220.61,WIC,OMA00
##@NIBU@##linux2622,10.27.220.62,WIC,OMA00
##@NIBU@##linux2623,10.27.220.63,WIC,OMA00
##@NIBU@##linux2624,10.27.220.64,WIC,OMA00
##@NIBU@##linux2625,10.27.220.65,WIC,OMA00
##@NIBU@##linux2626,10.27.220.66,WIC,OMA00
##@NIBU@##linux263,172.30.78.159,EIT,ATL01
##@NIBU@##linux2632,10.27.128.34,WIC,OMA00
##@NIBU@##linux2633,10.27.220.67,WIC,OMA00
##@NIBU@##linux2634,10.29.104.21,WIC,DEN01
##@NIBU@##linux2635,10.29.104.22,WIC,DEN01
##@NIBU@##linux2636,10.29.104.23,WIC,DEN01
##@NIBU@##linux2637,10.29.104.24,WIC,DEN01
##@NIBU@##linux2638,10.29.104.25,WIC,DEN01
##@NIBU@##linux2639,10.29.104.26,WIC,DEN01
##@NIBU@##linux264,172.30.1.135,EIT,OMA01
##@NIBU@##linux2640,10.29.104.27,WIC,DEN01
##@NIBU@##linux2641,10.29.104.28,WIC,DEN01
##@NIBU@##linux2642,10.29.104.29,WIC,DEN01
##@NIBU@##linux2643,10.29.104.30,WIC,DEN01
##@NIBU@##linux2644,10.29.104.31,WIC,DEN01
##@NIBU@##linux2645,10.29.99.149,WIC,DEN01
##@NIBU@##Linux2646,10.29.104.33,WIC,DEN01
##@NIBU@##Linux2647,10.29.104.34,WIC,DEN01
##@NIBU@##linux2648,10.64.2.129,ITC,SWN01
##@NIBU@##linux2649,10.64.2.130,ITC,SWN01
##@NIBU@##linux265,172.30.21.88,EIT,SAT01
##@NIBU@##linux2650,10.64.2.131,ITC,SWN01
##@NIBU@##linux2651,10.64.2.132,ITC,SWN01
##@NIBU@##linux2652,10.64.2.133,ITC,SWN01
##@NIBU@##linux2653,10.64.2.134,ITC,SWN01
##@NIBU@##linux2654,75.78.1.142,ITC,SWN01
##@NIBU@##linux2655,75.78.1.143,ITC,SWN01
##@NIBU@##linux2656,75.78.1.144,ITC,SWN01
##@NIBU@##linux2657,75.78.1.145,ITC,SWN01
##@NIBU@##linux2658,75.78.1.146,ITC,SWN01
##@NIBU@##linux2659,75.78.1.147,ITC,SWN01
##@NIBU@##linux266,172.30.21.89,EIT,SAT01
##@NIBU@##linux2660,75.78.1.148,ITC,SWN01
##@NIBU@##linux2661,75.78.1.149,ITC,SWN01
##@NIBU@##linux2662,10.27.127.173,WNG,OMA00
##@NIBU@##linux2663,10.27.198.49,WNG,OMA00
##@NIBU@##linux2664,10.62.228.54,ITC,HKG01
##@NIBU@##linux2665,10.62.228.56,ITC,HKG01
##@NIBU@##linux267,172.30.41.178,EIT,DEN01
##@NIBU@##linux2676,10.28.106.26,WIC,ATL01
##@NIBU@##linux2677,10.28.106.40,WIC,ATL01
##@NIBU@##linux2678,10.28.106.27,WIC,ATL01
##@NIBU@##linux2679,10.28.106.41,WIC,ATL01
##@NIBU@##linux268,172.30.78.16,EIT,ATL01
##@NIBU@##linux2680,10.28.106.28,WIC,ATL01
##@NIBU@##linux2681,10.28.103.29,WIC,ATL01
##@NIBU@##linux2682,10.28.106.29,WIC,ATL01
##@NIBU@##linux2683,10.28.106.43,WIC,ATL01
##@NIBU@##linux2684,10.28.106.30,WIC,ATL01
##@NIBU@##linux2685,10.28.106.44,WIC,ATL01
##@NIBU@##Linux2686,10.28.106.31,WIC,ATL01
##@NIBU@##Linux2687,10.28.106.45,WIC,ATL01
##@NIBU@##Linux2688,10.28.106.32,WIC,ATL01
##@NIBU@##Linux2689,10.28.106.46,WIC,ATL01
##@NIBU@##linux269,172.30.78.27,EIT,ATL01
##@NIBU@##Linux2690,10.28.106.33,WIC,ATL01
##@NIBU@##Linux2691,10.28.106.47,WIC,ATL01
##@NIBU@##linux2692,10.28.106.34,WIC,ATL01
##@NIBU@##linux2693,10.28.106.48,WIC,ATL01
##@NIBU@##linux2694,10.166.200.66,ITC,LON09
##@NIBU@##linux2695,10.166.200.67,ITC,LON09
##@NIBU@##linux2696,10.166.200.68,ITC,LON09
##@NIBU@##linux2697,10.166.200.69,ITC,LON09
##@NIBU@##linux2698,10.166.200.70,ITC,LON09
##@NIBU@##linux2699,10.166.200.71,ITC,LON09
##@NIBU@##linux270,172.30.1.1,EIT,OMA01
##@NIBU@##linux2700,10.166.200.73,ITC,LON09
##@NIBU@##linux2701,10.166.200.74,ITC,LON09
##@NIBU@##linux2702,10.166.200.75,ITC,LON09
##@NIBU@##linux2703,10.166.200.76,ITC,LON09
##@NIBU@##linux2704,10.166.200.77,ITC,LON09
##@NIBU@##linux2705,10.166.200.78,ITC,LON09
##@NIBU@##linux2706,10.166.200.79,ITC,LON09
##@NIBU@##linux2707,10.166.200.80,ITC,LON09
##@NIBU@##linux2708,10.166.200.82,ITC,LON09
##@NIBU@##linux2709,10.166.200.83,EIT,LON09
##@NIBU@##linux271,172.30.7.151,EIT,OMA10
##@NIBU@##linux2710,10.70.1.13,EIT,DEN06
##@NIBU@##linux2712,10.70.1.16,EIT,DEN06
##@NIBU@##linux2713,75.78.162.26,WIC,DEN06
##@NIBU@##linux2714,192.168.113.3,EIT,OMA00
##@NIBU@##linux2715,192.168.113.4,EIT,OMA00
##@NIBU@##linux2716,10.72.200.21,ITC,DEN06
##@NIBU@##linux2717,10.72.200.22,ITC,DEN06
##@NIBU@##linux2718,10.72.200.23,ITC,DEN06
##@NIBU@##linux2719,10.72.200.24,ITC,DEN06
##@NIBU@##linux272,10.29.224.25,ITC,DEN01
##@NIBU@##linux2720,10.72.200.25,ITC,DEN06
##@NIBU@##linux2721,10.72.200.26,ITC,DEN06
##@NIBU@##linux2722,10.72.200.27,ITC,DEN06
##@NIBU@##linux2723,10.72.200.28,ITC,DEN06
##@NIBU@##linux2724,10.72.200.29,ITC,DEN06
##@NIBU@##linux2725,10.72.200.30,ITC,DEN06
##@NIBU@##linux2726,10.72.200.31,ITC,DEN06
##@NIBU@##linux2727,10.72.200.32,ITC,DEN06
##@NIBU@##linux2728,10.72.200.33,ITC,DEN06
##@NIBU@##linux2729,10.72.200.34,ITC,DEN06
##@NIBU@##linux2730,10.72.200.40,ITC,DEN06
##@NIBU@##linux2731,10.72.200.41,ITC,DEN06
##@NIBU@##linux2732,10.72.200.42,ITC,DEN06
##@NIBU@##linux2733,10.72.200.43,ITC,DEN06
##@NIBU@##linux2734,10.72.200.44,ITC,DEN06
##@NIBU@##linux2735,10.72.200.45,ITC,DEN06
##@NIBU@##linux2736,10.72.200.46,ITC,DEN06
##@NIBU@##linux2737,10.72.200.47,ITC,DEN06
##@NIBU@##linux2738,10.72.200.48,ITC,DEN06
##@NIBU@##linux2739,10.72.200.49,ITC,DEN06
##@NIBU@##linux274,172.30.21.100,WIC,SAT01
##@NIBU@##linux2740,10.72.200.50,ITC,DEN06
##@NIBU@##linux2741,10.72.200.51,ITC,DEN06
##@NIBU@##linux2742,10.72.200.52,ITC,DEN06
##@NIBU@##linux2743,10.72.200.53,ITC,DEN06
##@NIBU@##linux2744,10.72.200.37,ITC,DEN06
##@NIBU@##linux2745,10.72.200.38,ITC,DEN06
##@NIBU@##linux2746,10.72.200.39,ITC,DEN06
##@NIBU@##linux2747,10.27.193.158,WIC,OMA00
##@NIBU@##linux2748,10.70.0.18,WIC,DEN06
##@NIBU@##LINUX2749,10.18.153.142,WIC,OMA11
##@NIBU@##linux2750,10.70.0.36,WIC,DEN06
##@NIBU@##linux2751,10.70.0.43,WIC,DEN06
##@NIBU@##Linux2752,10.27.193.159,WIC,OMA00
##@NIBU@##linux2753,10.70.0.64,WIC,DEN06
##@NIBU@##linux2755,10.70.0.78,WIC,DEN06
##@NIBU@##linux2756,10.70.0.85,WIC,DEN06
##@NIBU@##LINUX2757,10.18.153.146,WIC,OMA11
##@NIBU@##linux2758,10.70.0.148,WIC,DEN06
##@NIBU@##LINUX2759,10.18.153.143,WIC,OMA11
##@NIBU@##linux276,172.30.78.20,WIC,OMA00
##@NIBU@##linux2760,10.70.0.162,WIC,DEN06
##@NIBU@##linux2761,10.70.0.169,WIC,DEN06
##@NIBU@##linux2762,10.18.153.141,WIC,OMA11
##@NIBU@##linux2763,10.70.0.190,WIC,DEN06
##@NIBU@##linux2764,10.70.0.197,WIC,DEN06
##@NIBU@##linux2765,10.18.153.144,WIC,OMA11
##@NIBU@##linux2766,10.70.0.211,WIC,DEN06
##@NIBU@##linux2767,10.70.0.239,WIC,DEN06
##@NIBU@##linux2768,10.70.0.17,WIC,DEN06
##@NIBU@##linux2769,10.70.2.26,WIC,DEN06
##@NIBU@##linux277,10.29.224.26,ITC,DEN01
##@NIBU@##linux2770,10.70.2.19,WIC,DEN06
##@NIBU@##linux2771,10.70.0.252,WIC,DEN06
##@NIBU@##linux2772,10.70.0.245,WIC,DEN06
##@NIBU@##linux2773,10.70.0.238,WIC,DEN06
##@NIBU@##linux2774,10.70.0.224,WIC,DEN06
##@NIBU@##linux2775,10.70.0.217,WIC,DEN06
##@NIBU@##linux2776,10.70.0.210,WIC,DEN06
##@NIBU@##linux2777,10.70.0.203,WIC,DEN06
##@NIBU@##linux2778,10.70.0.196,WIC,DEN06
##@NIBU@##linux2779,10.70.0.182,WIC,DEN06
##@NIBU@##linux278,172.30.53.40,ITC,DEN01
##@NIBU@##linux2780,10.70.0.175,WIC,DEN06
##@NIBU@##linux2781,10.70.0.168,WIC,DEN06
##@NIBU@##linux2782,10.70.0.161,WIC,DEN06
##@NIBU@##linux2783,10.70.0.35,WIC,DEN06
##@NIBU@##linux2784,10.70.0.154,WIC,DEN06
##@NIBU@##linux2785,10.70.0.147,WIC,DEN06
##@NIBU@##linux2786,10.70.0.140,WIC,DEN06
##@NIBU@##linux2787,10.70.0.133,WIC,DEN06
##@NIBU@##linux2788,10.70.0.126,WIC,DEN06
##@NIBU@##linux2789,10.70.0.112,WIC,DEN06
##@NIBU@##linux279,172.30.78.21,WIC,OMA00
##@NIBU@##linux2790,10.70.0.105,WIC,DEN06
##@NIBU@##linux2791,10.70.0.98,WIC,DEN06
##@NIBU@##linux2792,10.70.0.91,WIC,DEN06
##@NIBU@##linux2793,10.70.0.84,WIC,DEN06
##@NIBU@##linux2794,10.70.0.56,WIC,DEN06
##@NIBU@##linux2795,10.70.0.49,WIC,DEN06
##@NIBU@##linux2796,10.70.0.42,WIC,DEN06
##@NIBU@##linux2797,10.70.0.13,WIC,DEN06
##@NIBU@##linux2798,10.70.0.139,WIC,DEN06
##@NIBU@##linux2799,10.70.0.181,WIC,DEN06
##@NIBU@##linux28,172.30.39.15,EIT,DEN01
##@NIBU@##linux280,172.30.53.42,ITC,DEN01
##@NIBU@##linux2800,10.70.2.20,WIC,DEN06
##@NIBU@##linux2801,10.70.0.195,WIC,DEN06
##@NIBU@##linux2802,10.70.0.63,WIC,DEN06
##@NIBU@##linux2803,10.70.0.87,WIC,DEN06
##@NIBU@##linux2804,10.70.0.213,WIC,DEN06
##@NIBU@##linux2805,10.70.2.13,WIC,DEN06
##@NIBU@##linux2806,10.70.0.70,WIC,DEN06
##@NIBU@##linux2807,10.70.0.93,WIC,DEN06
##@NIBU@##linux2808,10.70.0.187,WIC,DEN06
##@NIBU@##linux2809,10.70.2.23,WIC,DEN06
##@NIBU@##linux281,10.29.224.23,ITC,DEN01
##@NIBU@##linux2810,10.70.0.136,WIC,DEN06
##@NIBU@##linux2811,10.70.0.22,WIC,DEN06
##@NIBU@##linux2812,10.70.0.75,WIC,DEN06
##@NIBU@##linux2813,10.70.0.158,WIC,DEN06
##@NIBU@##linux2814,10.70.0.234,WIC,DEN06
##@NIBU@##linux2815,10.70.0.221,WIC,DEN06
##@NIBU@##linux2816,10.70.0.68,WIC,DEN06
##@NIBU@##linux2817,10.70.0.15,WIC,DEN06
##@NIBU@##linux2818,10.70.0.31,WIC,DEN06
##@NIBU@##linux2819,10.70.0.38,WIC,DEN06
##@NIBU@##Linux282,172.30.53.44,ITC,DEN01
##@NIBU@##linux2820,10.70.0.48,WIC,DEN06
##@NIBU@##linux2821,10.70.0.51,WIC,DEN06
##@NIBU@##linux2822,10.70.0.16,WIC,DEN06
##@NIBU@##linux2823,10.70.0.62,WIC,DEN06
##@NIBU@##linux2824,10.70.0.66,WIC,DEN06
##@NIBU@##linux2825,10.70.0.73,WIC,DEN06
##@NIBU@##linux2826,10.70.0.80,WIC,DEN06
##@NIBU@##linux2827,10.70.0.89,WIC,DEN06
##@NIBU@##linux2828,10.70.0.102,WIC,DEN06
##@NIBU@##linux2829,10.70.0.107,WIC,DEN06
##@NIBU@##linux283,172.30.53.45,ITC,DEN01
##@NIBU@##linux2830,10.70.0.119,WIC,DEN06
##@NIBU@##linux2831,10.70.0.144,WIC,DEN06
##@NIBU@##linux2832,10.70.0.150,WIC,DEN06
##@NIBU@##linux2833,10.70.0.165,WIC,DEN06
##@NIBU@##linux2834,10.70.0.173,WIC,DEN06
##@NIBU@##linux2835,10.70.0.177,WIC,DEN06
##@NIBU@##linux2836,10.70.0.186,WIC,DEN06
##@NIBU@##linux2837,10.70.0.191,WIC,DEN06
##@NIBU@##linux2838,10.70.0.200,WIC,DEN06
##@NIBU@##linux2839,10.70.0.208,WIC,DEN06
##@NIBU@##linux284,172.30.75.162,ITC,ATL01
##@NIBU@##linux2840,10.70.0.231,WIC,DEN06
##@NIBU@##linux2841,10.70.0.235,WIC,DEN06
##@NIBU@##linux2842,10.70.0.242,WIC,DEN06
##@NIBU@##linux285,172.30.75.155,ITC,ATL01
##@NIBU@##linux2857,10.70.0.110,WIC,OMA10
##@NIBU@##linux286,172.30.75.28,ITC,ATL01
##@NIBU@##linux2863,10.70.0.46,WIC,DEN06
##@NIBU@##linux2864,10.70.2.24,WIC,DEN06
##@NIBU@##linux2865,10.70.0.55,WIC,DEN06
##@NIBU@##linux2866,10.17.53.50,WIC,OMA10
##@NIBU@##linux2867,10.17.53.51,WIC,OMA10
##@NIBU@##linux2868,10.70.2.21,WIC,DEN06
##@NIBU@##linux2869,10.70.0.215,WIC,DEN06
##@NIBU@##linux287,172.30.75.51,ITC,ATL01
##@NIBU@##linux2870,10.70.0.143,WIC,DEN06
##@NIBU@##linux2871,10.70.0.129,WIC,DEN06
##@NIBU@##linux2872,10.70.0.88,WIC,DEN06
##@NIBU@##linux2873,10.70.0.23,WIC,DEN06
##@NIBU@##linux2874,10.70.0.40,WIC,DEN06
##@NIBU@##linux2875,10.70.0.52,WIC,DEN06
##@NIBU@##linux2876,10.70.0.76,WIC,DEN06
##@NIBU@##linux2877,10.70.0.94,WIC,DEN06
##@NIBU@##linux2878,10.70.0.104,WIC,DEN06
##@NIBU@##linux2879,10.70.0.106,WIC,DEN06
##@NIBU@##linux288,10.29.224.24,ITC,DEN01
##@NIBU@##linux2880,10.70.0.114,WIC,DEN06
##@NIBU@##linux2881,10.70.0.121,WIC,DEN06
##@NIBU@##linux2882,10.70.0.122,WIC,DEN06
##@NIBU@##linux2883,10.70.0.131,WIC,DEN06
##@NIBU@##linux2884,10.70.0.135,WIC,DEN06
##@NIBU@##linux2885,10.70.0.159,WIC,DEN06
##@NIBU@##linux2886,10.70.0.174,WIC,DEN06
##@NIBU@##linux2887,10.70.0.188,WIC,DEN06
##@NIBU@##linux2888,10.70.0.194,WIC,DEN06
##@NIBU@##linux2889,10.70.0.201,WIC,DEN06
##@NIBU@##linux289,172.30.42.200,WIC,DEN01
##@NIBU@##linux2890,10.70.0.222,WIC,DEN06
##@NIBU@##linux2891,10.70.0.233,WIC,DEN06
##@NIBU@##linux2892,10.70.0.21,WIC,DEN06
##@NIBU@##linux2894,10.70.0.41,WIC,DEN06
##@NIBU@##linux2895,10.70.0.45,WIC,DEN06
##@NIBU@##Linux2896,10.27.194.132,WIC,OMA00
##@NIBU@##linux2897,10.27.194.133,WIC,OMA00
##@NIBU@##Linux2898,10.27.194.134,WIC,OMA00
##@NIBU@##linux29,172.30.94.108,EIT,OMA11
##@NIBU@##linux290,172.30.42.201,ITC,DEN01
##@NIBU@##linux2900,10.27.193.32,WIC,OMA00
##@NIBU@##linux2901,10.27.193.33,WIC,OMA00
##@NIBU@##linux2902,10.27.194.136,WIC,OMA00
##@NIBU@##linux2903,10.27.194.59,WIC,OMA00
##@NIBU@##linux291,172.30.42.202,ITC,DEN01
##@NIBU@##linux2914,10.27.220.73,WIC,OMA00
##@NIBU@##linux2915,75.78.1.125,ITC,SWN01
##@NIBU@##linux2916,10.64.51.39,ITC,SWN01
##@NIBU@##linux2917,75.78.1.125,ITC,SWN01
##@NIBU@##linux2918,10.27.200.50,WIC,OMA00
##@NIBU@##linux2919,10.27.200.51,WIC,OMA00
##@NIBU@##linux292,172.30.8.91,WIC,OMA10
##@NIBU@##linux2920,10.27.200.52,WIC,OMA00
##@NIBU@##linux2921,10.27.200.53,WIC,OMA00
##@NIBU@##linux2922,10.27.109.23,EIT,OMA00
##@NIBU@##linux2923,linux2923,EIT,SAT01
##@NIBU@##linux2924,10.29.100.42,WIC,DEN01
##@NIBU@##linux2925,10.28.100.26,WIC,ATL01
##@NIBU@##linux2926,10.72.1.119,ITC,DEN06
##@NIBU@##linux2927,10.70.0.11,ITC,DEN06
##@NIBU@##linux2928,10.72.0.12,ITC,DEN06
##@NIBU@##linux293,172.30.8.92,WIC,OMA10
##@NIBU@##Linux2930,10.28.103.20,WIC,ATL01
##@NIBU@##Linux2931,10.28.103.21,WIC,ATL01
##@NIBU@##linux2932,10.70.0.253,WIC,DEN06
##@NIBU@##linux2933,10.27.110.61,WIC,OMA00
##@NIBU@##linux2934,10.27.200.54,WIC,OMA00
##@NIBU@##linux2935,10.27.200.55,WIC,OMA00
##@NIBU@##linux2936,10.27.200.56,WIC,OMA00
##@NIBU@##linux2937,10.27.200.57,WIC,OMA00
##@NIBU@##linux2938,10.27.200.58,WIC,OMA00
##@NIBU@##linux2939,10.27.200.59,WIC,OMA00
##@NIBU@##linux294,172.30.2.60,WIC,OMA01
##@NIBU@##linux2940,10.27.200.60,WIC,OMA00
##@NIBU@##linux2941,10.27.200.61,WIC,OMA00
##@NIBU@##linux2942,10.27.200.62,WIC,OMA00
##@NIBU@##linux2943,10.27.200.63,WIC,OMA00
##@NIBU@##linux2944,10.27.200.64,WIC,OMA00
##@NIBU@##linux2945,10.27.200.65,WIC,OMA00
##@NIBU@##linux2946,10.27.200.66,WIC,OMA00
##@NIBU@##linux2947,10.27.200.67,WIC,OMA00
##@NIBU@##linux2948,10.27.200.68,WIC,OMA00
##@NIBU@##linux2949,10.27.200.69,WIC,OMA00
##@NIBU@##linux295,172.30.2.61,WIC,OMA01
##@NIBU@##linux2950,10.27.200.70,WIC,OMA00
##@NIBU@##linux2951,10.27.200.71,WIC,OMA00
##@NIBU@##linux2952,10.27.200.72,WIC,OMA00
##@NIBU@##linux2953,10.27.200.73,WIC,OMA00
##@NIBU@##linux2954,10.27.127.43,WNG,OMA00
##@NIBU@##linux2955,10.27.127.44,WNG,OMA00
##@NIBU@##linux2956,10.27.126.34,WNG,OMA00
##@NIBU@##linux2957,10.70.64.36,WNG,DEN01
##@NIBU@##linux2958,10.70.64.37,WNG,DEN01
##@NIBU@##linux2959,10.27.126.35,WNG,OMA00
##@NIBU@##linux296,172.30.78.22,WIC,OMA00
##@NIBU@##linux2960,10.27.200.74,WIC,OMA00
##@NIBU@##linux2961,10.27.200.75,WIC,OMA00
##@NIBU@##linux2962,10.27.200.76,WIC,OMA00
##@NIBU@##linux2963,10.27.200.77,WIC,OMA00
##@NIBU@##linux2964,10.27.200.78,WIC,OMA00
##@NIBU@##linux2965,10.27.200.79,WIC,OMA00
##@NIBU@##linux2966,10.27.200.80,WIC,OMA00
##@NIBU@##linux2967,10.27.200.81,WIC,OMA00
##@NIBU@##linux2968,10.27.200.82,WIC,OMA00
##@NIBU@##linux2969,10.27.200.83,WIC,OMA00
##@NIBU@##linux297,10.29.224.27,ITC,DEN01
##@NIBU@##linux2970,10.27.200.84,WIC,OMA00
##@NIBU@##linux2971,10.27.200.85,WIC,OMA00
##@NIBU@##linux2972,10.27.200.86,WIC,OMA00
##@NIBU@##linux2973,10.27.200.87,WIC,OMA00
##@NIBU@##linux2974,10.27.200.88,WIC,OMA00
##@NIBU@##linux2975,10.27.200.89,WIC,OMA00
##@NIBU@##linux2976,10.27.200.90,WIC,OMA00
##@NIBU@##linux2977,10.27.200.91,WIC,OMA00
##@NIBU@##linux2978,10.27.200.92,WIC,OMA00
##@NIBU@##linux2979,10.27.200.93,WIC,OMA00
##@NIBU@##linux298,10.29.224.28,ITC,DEN01
##@NIBU@##linux2980,75.78.1.162,ITC,SWN01
##@NIBU@##linux2981,75.78.1.163,ITC,SWN01
##@NIBU@##linux2982,75.78.1.164,ITC,SWN01
##@NIBU@##linux299,172.30.53.61,ITC,DEN01
##@NIBU@##linux2998,10.28.124.78,WIC,ATL01
##@NIBU@##linux2999,10.28.124.79,WIC,ATL01
##@NIBU@##linux300,172.30.75.130,ITC,ATL01
##@NIBU@##linux3000,10.29.105.21,WIC,DEN01
##@NIBU@##linux3001,10.29.105.22,WIC,DEN01
##@NIBU@##linux3002,10.72.224.151,ITC,DEN06
##@NIBU@##linux3003,10.72.224.152,ITC,DEN06
##@NIBU@##linux3004,10.70.2.37,WIC,DEN06
##@NIBU@##linux3005,10.70.2.38,WIC,DEN06
##@NIBU@##linux3006,75.78.1.156,ITC,SWN01
##@NIBU@##linux3007,10.72.200.69,ITC,DEN06
##@NIBU@##linux3008,10.72.200.70,ITC,DEN06
##@NIBU@##linux3009,10.72.200.71,ITC,DEN06
##@NIBU@##linux301,172.30.75.129,ITC,ATL01
##@NIBU@##linux3010,10.72.200.72,ITC,DEN06
##@NIBU@##linux3011,10.72.200.73,ITC,DEN06
##@NIBU@##linux3012,10.72.200.74,ITC,DEN06
##@NIBU@##linux3013,10.72.200.83,ITC,DEN06
##@NIBU@##linux3014,10.72.200.76,ITC,DEN06
##@NIBU@##linux3015,10.72.200.77,ITC,DEN06
##@NIBU@##linux3016,10.72.200.78,ITC,DEN06
##@NIBU@##linux3017,10.72.200.79,ITC,DEN06
##@NIBU@##linux3018,10.72.200.80,ITC,DEN06
##@NIBU@##linux3019,10.18.150.52,WIC,DEN06
##@NIBU@##linux302,172.30.75.132,ITC,ATL01
##@NIBU@##linux3020,10.18.150.53,WIC,DEN06
##@NIBU@##linux3021,10.27.60.126,EIT,OMA00
##@NIBU@##linux3022,75.78.1.165,ITC,SWN01
##@NIBU@##linux3023,75.78.1.228,ITC,SWN01
##@NIBU@##linux3024,75.78.1.229,ITC,SWN01
##@NIBU@##linux3025,75.78.1.230,ITC,SWN01
##@NIBU@##linux3026,75.78.1.231,ITC,SWN01
##@NIBU@##linux3027,10.28.103.22,WIC,ATL01
##@NIBU@##linux3028,10.28.103.23,WIC,ATL01
##@NIBU@##linux3029,10.18.131.37,WIC,OMA11
##@NIBU@##linux303,172.30.75.131,ITC,ATL01
##@NIBU@##linux3030,10.18.131.38,WIC,OMA11
##@NIBU@##linux3031,10.18.131.39,WIC,OMA11
##@NIBU@##linux3032,10.18.131.40,WIC,OMA11
##@NIBU@##linux3033,10.18.131.41,WIC,OMA11
##@NIBU@##linux3034,10.18.131.42,WIC,OMA11
##@NIBU@##linux3036,10.18.131.44,WIC,OMA11
##@NIBU@##linux3037,10.18.131.45,WIC,OMA11
##@NIBU@##linux3038,10.18.131.46,WIC,OMA11
##@NIBU@##linux3039,10.64.51.40,ITC,SWN01
##@NIBU@##linux304,172.30.75.134,ITC,ATL01
##@NIBU@##linux3040,10.64.51.41,ITC,SWN01
##@NIBU@##linux3041,10.64.2.166,ITC,SWN01
##@NIBU@##linux3042,10.64.2.167,ITC,SWN01
##@NIBU@##linux3043,10.64.2.168,ITC,SWN01
##@NIBU@##linux3044,10.64.2.169,ITC,SWN01
##@NIBU@##linux3045,10.72.0.14,ITC,DEN06
##@NIBU@##linux3046,10.64.2.170,ITC,SWN01
##@NIBU@##linux3047,10.27.109.42,EIT,OMA00
##@NIBU@##linux3048,10.64.80.41,ITC,WPT03
##@NIBU@##linux3049,10.64.80.42,ITC,WPT03
##@NIBU@##linux305,172.30.75.133,ITC,ATL01
##@NIBU@##linux3050,10.64.80.43,ITC,WPT03
##@NIBU@##linux3051,10.64.80.44,ITC,WPT03
##@NIBU@##linux3052,10.64.80.45,ITC,WPT03
##@NIBU@##linux3053,10.64.80.46,ITC,WPT03
##@NIBU@##linux3054,10.64.80.47,ITC,WPT03
##@NIBU@##linux3055,10.64.80.48,ITC,WPT03
##@NIBU@##linux3056,10.64.80.49,ITC,WPT03
##@NIBU@##linux3057,10.64.80.51,ITC,WPT03
##@NIBU@##linux3058,10.64.80.52,ITC,WPT03
##@NIBU@##linux3059,10.27.117.59,EIT,OMA00
##@NIBU@##linux306,172.30.75.136,ITC,ATL01
##@NIBU@##linux3061,10.64.80.35,ITC,WPT03
##@NIBU@##linux3062,10.64.80.36,ITC,WPT03
##@NIBU@##linux3063,10.64.80.37,ITC,WPT03
##@NIBU@##linux3064,10.64.80.33,ITC,WPT03
##@NIBU@##linux3065,10.62.33.23,EIT,WPT02
##@NIBU@##linux3066,10.27.220.110,WIC,OMA00
##@NIBU@##linux3067,10.27.220.111,WIC,OMA00
##@NIBU@##linux3068,10.27.220.112,WIC,OMA00
##@NIBU@##linux3069,10.27.220.113,WIC,OMA00
##@NIBU@##linux307,172.30.75.135,ITC,ATL01
##@NIBU@##linux3070,10.27.220.114,WIC,OMA00
##@NIBU@##linux3071,10.28.128.33,ITC,ATL01
##@NIBU@##linux3072,10.67.24.51,ITC,WPT03
##@NIBU@##linux3073,10.28.128.35,ITC,ATL01
##@NIBU@##linux3074,10.28.128.43,ITC,ATL01
##@NIBU@##linux3075,10.28.128.45,ITC,ATL01
##@NIBU@##linux3076,10.28.128.47,ITC,ATL01
##@NIBU@##linux3077,10.28.128.49,ITC,ATL01
##@NIBU@##linux3078,10.28.128.51,ITC,ATL01
##@NIBU@##linux3079,10.28.128.52,ITC,ATL01
##@NIBU@##linux308,172.30.75.138,ITC,ATL01
##@NIBU@##linux3080,10.28.128.37,ITC,ATL01
##@NIBU@##linux3081,10.67.24.61,ITC,WPT03
##@NIBU@##linux3082,10.67.24.63,ITC,WPT03
##@NIBU@##linux3083,10.67.24.65,ITC,WPT03
##@NIBU@##linux3084,10.67.24.67,ITC,WPT03
##@NIBU@##linux3085,10.67.24.69,ITC,WPT03
##@NIBU@##linux3086,10.67.24.71,ITC,WPT03
##@NIBU@##linux3087,10.27.128.53,WIC,OMA00
##@NIBU@##linux3088,10.27.128.54,WIC,OMA00
##@NIBU@##linux3089,10.27.128.55,WIC,OMA00
##@NIBU@##linux309,172.30.75.137,ITC,ATL01
##@NIBU@##linux3090,10.27.128.56,WIC,OMA00
##@NIBU@##linux3091,10.27.128.57,WIC,OMA00
##@NIBU@##linux3092,10.27.128.58,WIC,OMA00
##@NIBU@##linux3093,10.27.128.59,WIC,OMA00
##@NIBU@##linux3094,10.27.128.60,WIC,OMA00
##@NIBU@##linux3095,10.27.128.61,WIC,OMA00
##@NIBU@##linux3096,10.27.128.62,WIC,OMA00
##@NIBU@##linux3097,10.27.128.63,WIC,OMA00
##@NIBU@##linux3098,10.27.128.64,WIC,OMA00
##@NIBU@##linux3099,10.27.128.65,WIC,OMA00
##@NIBU@##linux310,172.30.75.140,ITC,ATL01
##@NIBU@##linux3100,10.27.128.66,WIC,OMA00
##@NIBU@##linux3101,10.27.128.67,WIC,OMA00
##@NIBU@##linux3102,10.27.128.68,WIC,OMA00
##@NIBU@##linux3103,10.27.128.69,WIC,OMA00
##@NIBU@##linux3104,10.27.128.70,WIC,OMA00
##@NIBU@##linux3105,10.27.128.71,WIC,OMA00
##@NIBU@##linux3106,10.27.128.72,WIC,OMA00
##@NIBU@##linux3107,10.27.128.73,WIC,OMA00
##@NIBU@##linux3108,10.27.128.74,WIC,OMA00
##@NIBU@##linux3109,10.27.128.75,WIC,OMA00
##@NIBU@##linux311,172.30.75.139,ITC,ATL01
##@NIBU@##linux3110,10.27.128.76,WIC,OMA00
##@NIBU@##linux3111,10.27.128.77,WIC,OMA00
##@NIBU@##linux3112,10.27.128.78,WIC,OMA00
##@NIBU@##linux3113,10.27.128.79,WIC,OMA00
##@NIBU@##linux3114,10.27.128.80,WIC,OMA00
##@NIBU@##linux3115,10.27.128.81,WIC,OMA00
##@NIBU@##linux3116,10.27.128.82,WIC,OMA00
##@NIBU@##linux3117,10.27.128.83,WIC,OMA00
##@NIBU@##linux3118,10.27.128.84,WIC,OMA00
##@NIBU@##linux3119,10.27.128.85,WIC,OMA00
##@NIBU@##linux312,172.30.75.142,ITC,ATL01
##@NIBU@##linux3120,10.27.128.86,WIC,OMA00
##@NIBU@##linux3121,10.27.128.87,WIC,OMA00
##@NIBU@##linux3124,10.64.2.171,ITC,SWN01
##@NIBU@##linux3125,10.64.2.173,ITC,SWN01
##@NIBU@##linux3126,75.78.1.200,ITC,SWN01
##@NIBU@##linux3127,75.78.1.201,ITC,SWN01
##@NIBU@##linux3128,10.67.24.53,ITC,WPT03
##@NIBU@##linux3129,10.67.24.55,ITC,WPT03
##@NIBU@##linux313,172.30.75.141,ITC,ATL01
##@NIBU@##linux3130,10.229.213.216,WIC,DEN01
##@NIBU@##linux3131,10.29.213.217,WIC,DEN01
##@NIBU@##linux3132,10.19.122.144,EIT,OMA01
##@NIBU@##linux3133,10.17.125.22,EIT,OMA10
##@NIBU@##linux3134,10.29.115.75,EIT,DEN01
##@NIBU@##linux3135,10.29.97.178,WIC,DEN01
##@NIBU@##linux3136,10.29.97.179,WIC,DEN01
##@NIBU@##Linux3137,10.28.103.24,WIC,ATL01
##@NIBU@##Linux3138,10.28.103.25,WIC,ATL01
##@NIBU@##linux3139,10.27.110.37,ITC,OMA00
##@NIBU@##linux314,172.30.75.144,ITC,ATL01
##@NIBU@##linux3140,linux3140,ITC,DEN06
##@NIBU@##linux3141,10.27.110.38,ITC,OMA00
##@NIBU@##linux3142,linux3142,ITC,DEN06
##@NIBU@##linux3143,linux3143,ITC,OMA00
##@NIBU@##linux3144,linux3144,ITC,OMA00
##@NIBU@##linux3145,linux3145,ITC,SIN04
##@NIBU@##linux3146,linux3146,ITC,LON09
##@NIBU@##linux315,172.30.75.143,ITC,ATL01
##@NIBU@##linux3150,10.55.34.41,WCMG,GDL02
##@NIBU@##linux3151,linux3151,WCMG,GDL02
##@NIBU@##linux3152,10.62.217.22,ITC,SHG01
##@NIBU@##linux3153,10.62.217.24,ITC,SHG01
##@NIBU@##linux3154,10.62.217.21,ITC,SHG01
##@NIBU@##linux3155,10.62.217.23,ITC,SHG01
##@NIBU@##linux3156,10.70.64.94,WNG,DEN01
##@NIBU@##linux3157,10.70.64.95,WNG,DEN01
##@NIBU@##linux3158,10.70.64.96,WNG,DEN01
##@NIBU@##linux316,172.30.75.146,ITC,ATL01
##@NIBU@##linux3160,10.232.10.68,WIC,SJC01
##@NIBU@##linux3161,10.232.10.69,WIC,SJC01
##@NIBU@##linux3162,10.232.10.70,WIC,SJC01
##@NIBU@##linux3163,10.232.10.71,WIC,SJC01
##@NIBU@##linux3164,10.232.10.72,WIC,SJC01
##@NIBU@##linux3165,10.232.10.73,WIC,SJC01
##@NIBU@##linux3166,10.232.10.74,WIC,SJC01
##@NIBU@##linux3167,10.232.10.75,WIC,SJC01
##@NIBU@##linux3168,10.232.10.76,WIC,SJC01
##@NIBU@##linux3169,10.232.10.77,WIC,SJC01
##@NIBU@##linux317,172.30.75.145,ITC,ATL01
##@NIBU@##linux3170,10.232.10.78,WIC,SJC01
##@NIBU@##linux3171,10.232.10.79,WIC,SJC01
##@NIBU@##linux3172,10.72.1.29,ITC,DEN06
##@NIBU@##linux3173,10.72.1.30,ITC,DEN06
##@NIBU@##linux3174,75.78.1.224,ITC,SWN01
##@NIBU@##linux3175,75.78.1.225,ITC,SWN01
##@NIBU@##linux3176,10.27.197.78,WIC,OMA00
##@NIBU@##linux3177,10.27.197.79,WIC,OMA00
##@NIBU@##linux3178,10.27.197.80,WIC,OMA00
##@NIBU@##linux3179,10.27.197.81,WIC,OMA00
##@NIBU@##linux318,172.30.75.148,ITC,ATL01
##@NIBU@##linux3180,10.27.197.82,WIC,OMA00
##@NIBU@##linux3181,10.27.197.83,WIC,OMA00
##@NIBU@##linux3182,10.27.197.84,WIC,OMA00
##@NIBU@##linux3183,10.27.197.85,WIC,OMA00
##@NIBU@##linux3184,10.27.197.86,WIC,OMA00
##@NIBU@##linux3185,10.27.197.87,WIC,OMA00
##@NIBU@##linux3186,10.27.197.88,WIC,OMA00
##@NIBU@##linux3187,10.27.197.89,WIC,OMA00
##@NIBU@##linux3188,10.27.197.90,WIC,OMA00
##@NIBU@##linux3189,10.27.197.91,WIC,OMA00
##@NIBU@##linux319,172.30.75.147,ITC,ATL01
##@NIBU@##linux3190,10.27.197.92,WIC,OMA00
##@NIBU@##linux3191,10.27.197.93,WIC,OMA00
##@NIBU@##linux3192,10.27.197.94,WIC,OMA00
##@NIBU@##linux3193,10.27.197.95,WIC,OMA00
##@NIBU@##linux3194,10.27.197.96,WIC,OMA00
##@NIBU@##linux3195,10.27.197.97,WIC,OMA00
##@NIBU@##linux3196,10.72.0.24,ITC,DEN06
##@NIBU@##linux3197,10.28.200.100,ITC,ATL01
##@NIBU@##linux3198,10.184.16.64,ITC,WDC03
##@NIBU@##linux3199,10.28.128.50,ITC,ATL01
##@NIBU@##linux320,172.30.75.150,ITC,ATL01
##@NIBU@##linux3200,10.67.24.73,ITC,WPT03
##@NIBU@##linux3201,10.67.24.74,ITC,WPT03
##@NIBU@##linux3202,10.67.24.75,ITC,WPT03
##@NIBU@##linux3203,10.67.24.76,ITC,WPT03
##@NIBU@##linux3204,10.67.24.77,ITC,WPT03
##@NIBU@##linux3205,10.67.24.78,ITC,WPT03
##@NIBU@##linux3206,10.67.24.79,ITC,WPT03
##@NIBU@##linux3207,10.67.24.80,ITC,WPT03
##@NIBU@##linux3208,216.57.102.235,WIC,OMA01
##@NIBU@##linux3209,75.78.177.126,WIC,DEN06
##@NIBU@##linux321,172.30.75.149,ITC,ATL01
##@NIBU@##linux3210,10.27.197.98,WIC,OMA00
##@NIBU@##linux3211,10.18.132.43,WIC,OMA11
##@NIBU@##linux3212,10.18.132.44,WIC,OMA11
##@NIBU@##linux3215,10.18.132.47,WIC,OMA11
##@NIBU@##linux3216,10.18.132.48,WIC,OMA11
##@NIBU@##linux3217,10.18.132.49,WIC,OMA11
##@NIBU@##linux3218,10.18.132.58,WIC,OMA11
##@NIBU@##linux3219,10.18.132.59,WIC,OMA11
##@NIBU@##linux322,172.30.75.152,ITC,ATL01
##@NIBU@##linux3220,10.18.132.60,WIC,OMA11
##@NIBU@##linux3221,10.18.132.61,WIC,OMA11
##@NIBU@##linux3222,10.18.132.62,WIC,OMA11
##@NIBU@##linux3225,10.18.132.65,WIC,OMA11
##@NIBU@##linux3229,10.18.132.69,WIC,OMA11
##@NIBU@##linux323,172.30.75.151,ITC,ATL01
##@NIBU@##linux3230,10.18.132.70,WIC,OMA11
##@NIBU@##linux3231,10.27.130.29,WIC,OMA00
##@NIBU@##linux3232,10.27.130.30,WIC,OMA00
##@NIBU@##linux3233,10.27.130.31,WIC,OMA00
##@NIBU@##linux3234,10.27.130.32,WIC,OMA00
##@NIBU@##linux3235,10.27.130.33,WIC,OMA00
##@NIBU@##linux3236,10.27.130.34,WIC,OMA00
##@NIBU@##linux3237,10.27.130.35,WIC,OMA00
##@NIBU@##linux3238,10.27.130.36,WIC,OMA00
##@NIBU@##linux3239,10.27.130.37,WIC,OMA00
##@NIBU@##linux324,172.30.75.154,ITC,ATL01
##@NIBU@##linux3240,10.27.130.38,WIC,OMA00
##@NIBU@##linux3241,10.27.130.39,WIC,OMA00
##@NIBU@##linux3242,10.27.130.40,WIC,OMA00
##@NIBU@##linux3243,10.27.130.41,WIC,OMA00
##@NIBU@##linux3244,10.27.130.42,WIC,OMA00
##@NIBU@##linux3245,10.27.130.43,WIC,OMA00
##@NIBU@##linux3246,10.27.130.44,WIC,OMA00
##@NIBU@##linux3247,10.27.130.45,WIC,OMA00
##@NIBU@##linux3248,10.27.130.46,WIC,OMA00
##@NIBU@##linux3249,10.27.130.47,WIC,OMA00
##@NIBU@##linux325,172.30.75.153,ITC,ATL01
##@NIBU@##linux3250,10.27.130.48,WIC,OMA00
##@NIBU@##linux3251,linux3251,WIC,OMA00
##@NIBU@##linux3252,linux3252,WIC,OMA00
##@NIBU@##linux3253,10.27.96.24,WIC,OMA00
##@NIBU@##linux3254,10.27.96.25,WIC,OMA00
##@NIBU@##linux3258,10.27.126.21,WIC,OMA00
##@NIBU@##linux3259,10.64.49.97,ITC,SWN01
##@NIBU@##linux326,172.30.75.156,ITC,ATL01
##@NIBU@##linux3260,10.64.49.98,ITC,SWN01
##@NIBU@##linux3261,10.65.36.60,ITC,SWN01
##@NIBU@##linux3262,10.65.36.66,ITC,SWN01
##@NIBU@##linux3263,10.65.36.69,ITC,SWN01
##@NIBU@##linux3264,10.65.36.72,ITC,SWN01
##@NIBU@##linux3265,10.65.36.59,ITC,SWN01
##@NIBU@##linux3266,10.112.8.21,ITC,MUM03
##@NIBU@##linux3267,10.112.8.22,ITC,MUM03
##@NIBU@##linux3268,10.112.8.23,ITC,MUM03
##@NIBU@##linux3269,10.112.8.24,ITC,MUM03
##@NIBU@##linux3270,10.65.40.48,ITC,SWN01
##@NIBU@##linux3271,10.72.216.21linux3271,ITC,DEN06
##@NIBU@##linux3272,10.72.216.22,ITC,DEN06
##@NIBU@##linux3273,10.72.216.23,ITC,DEN06
##@NIBU@##linux3274,10.72.216.24,ITC,DEN06
##@NIBU@##linux3275,10.72.216.25,ITC,DEN06
##@NIBU@##linux3276,10.72.216.68,ITC,DEN06
##@NIBU@##linux3277,10.166.168.25,ITC,LON13
##@NIBU@##linux3278,10.65.40.49,ITC,SWN01
##@NIBU@##linux3279,10.65.40.50,ITC,SWN01
##@NIBU@##linux328,172.30.75.24,ITC,ATL01
##@NIBU@##linux3280,10.72.216.67,ITC,DEN06
##@NIBU@##linux3281,10.72.216.38,ITC,DEN06
##@NIBU@##linux3282,10.72.216.39,ITC,DEN06
##@NIBU@##linux3283,10.72.216.40,ITC,DEN06
##@NIBU@##linux3284,10.72.216.41,ITC,DEN06
##@NIBU@##linux3285,10.72.216.42,ITC,DEN06
##@NIBU@##linux3286,10.72.216.64,ITC,DEN06
##@NIBU@##linux3287,10.72.216.65,ITC,DEN06
##@NIBU@##linux3288,10.72.212.66,ITC,DEN06
##@NIBU@##linux3289,10.65.36.65,ITC,SWN01
##@NIBU@##linux329,172.30.75.27,ITC,ATL01
##@NIBU@##linux3290,10.65.36.68,ITC,SWN01
##@NIBU@##linux3291,10.65.36.71,ITC,SWN01
##@NIBU@##linux3292,10.65.36.58,ITC,SWN01
##@NIBU@##linux3293,10.65.36.64,ITC,SWN01
##@NIBU@##linux3294,10.112.8.26,ITC,MUM03
##@NIBU@##linux3295,10.112.8.27,ITC,MUM03
##@NIBU@##linux3296,10.112.8.28,ITC,MUM03
##@NIBU@##linux3297,10.112.8.29,ITC,MUM03
##@NIBU@##linux3298,10.166.168.30,ITC,LON13
##@NIBU@##linux3299,10.72.216.26,ITC,DEN06
##@NIBU@##linux33,172.30.94.111,WIC,OMA11
##@NIBU@##linux330,172.30.75.26,ITC,ATL01
##@NIBU@##linux3300,10.72.216.27,ITC,DEN06
##@NIBU@##linux3301,10.72.216.28,ITC,DEN06
##@NIBU@##linux3302,10.72.216.29,ITC,DEN06
##@NIBU@##linux3303,10.72.216.30,ITC,DEN06
##@NIBU@##linux3304,10.72.216.73,ITC,DEN06
##@NIBU@##linux3305,10.72.7.33,ITC,DEN06
##@NIBU@##linux3306,10.72.7.34,ITC,DEN06
##@NIBU@##linux3307,10.72.7.35,ITC,DEN06
##@NIBU@##linux3308,10.72.216.72,ITC,DEN06
##@NIBU@##linux3309,10.72.216.43,ITC,DEN06
##@NIBU@##linux331,172.30.75.29,ITC,ATL01
##@NIBU@##linux3310,10.72.216.44,ITC,DEN06
##@NIBU@##linux3311,10.72.216.45,ITC,DEN06
##@NIBU@##linux3312,10.72.216.46,ITC,DEN06
##@NIBU@##linux3313,10.72.216.47,ITC,DEN06
##@NIBU@##linux3314,10.72.216.69,ITC,DEN06
##@NIBU@##linux3315,10.72.216.70,ITC,DEN06
##@NIBU@##linux3316,10.72.216.71,ITC,DEN06
##@NIBU@##linux3317,10.64.49.105,ITC,SWN01
##@NIBU@##linux3318,10.64.49.106,ITC,SWN01
##@NIBU@##linux3319,10.28.128.53,ITC,ATL01
##@NIBU@##linux332,172.30.53.30,ITC,DEN01
##@NIBU@##linux3320,10.28.128.54,ITC,ATL01
##@NIBU@##linux3321,10.28.128.55,ITC,ATL01
##@NIBU@##linux3322,10.28.128.56,ITC,ATL01
##@NIBU@##linux3323,10.64.49.108,ITC,SWN01
##@NIBU@##linux3324,10.18.129.181,WIC,OMA11
##@NIBU@##linux3325,10.18.129.171,WIC,OMA11
##@NIBU@##linux3326,10.18.129.172,WIC,OMA11
##@NIBU@##linux3327,10.18.129.173,WIC,OMA11
##@NIBU@##linux3328,10.18.129.174,WIC,OMA11
##@NIBU@##linux3329,10.18.129.182,WIC,OMA11
##@NIBU@##linux333,172.30.53.31,ITC,DEN01
##@NIBU@##linux3330,10.18.129.183,WIC,OMA11
##@NIBU@##linux3331,10.18.129.184,WIC,OMA11
##@NIBU@##linux3332,10.64.49.111,ITC,SWN01
##@NIBU@##linux3333,10.64.49.112,ITC,SWN01
##@NIBU@##linux3334,10.64.49.113,ITC,SWN01
##@NIBU@##linux3335,10.64.49.114,ITC,SWN01
##@NIBU@##linux3336,10.64.49.115,ITC,SWN01
##@NIBU@##linux3337,10.64.49.116,ITC,SWN01
##@NIBU@##linux3338,10.64.49.117,ITC,SWN01
##@NIBU@##linux3339,10.64.49.118,ITC,SWN01
##@NIBU@##linux334,172.30.53.32,ITC,DEN01
##@NIBU@##linux3340,10.64.49.119,ITC,SWN01
##@NIBU@##linux3341,10.64.49.120,ITC,SWN01
##@NIBU@##linux3342,10.64.49.121,ITC,SWN01
##@NIBU@##linux3343,10.64.49.122,ITC,SWN01
##@NIBU@##linux3344,10.64.49.123,ITC,SWN01
##@NIBU@##linux3345,10.64.49.124,ITC,SWN01
##@NIBU@##linux3346,75.78.1.178,ITC,SWN01
##@NIBU@##linux3347,75.78.1.179,ITC,SWN01
##@NIBU@##linux3348,75.78.1.211,ITC,SWN01
##@NIBU@##linux3349,75.78.1.212,ITC,SWN01
##@NIBU@##linux335,172.30.53.33,ITC,DEN01
##@NIBU@##linux3350,75.78.1.247,ITC,SWN01
##@NIBU@##linux3351,75.78.1.248,ITC,SWN01
##@NIBU@##linux3352,75.78.1.222,ITC,SWN01
##@NIBU@##linux3353,75.78.1.223,ITC,SWN01
##@NIBU@##linux3354,linux3354,WIC,OMA00
##@NIBU@##linux3355,10.67.24.81,ITC,WPT03
##@NIBU@##linux3356,10.67.24.82,ITC,WPT03
##@NIBU@##linux3357,10.67.24.83,ITC,WPT03
##@NIBU@##linux3358,10.166.168.21,ITC,LON13
##@NIBU@##linux3359,10.166.168.22,ITC,LON13
##@NIBU@##linux336,172.30.1.134,WIC,OMA01
##@NIBU@##linux3360,10.166.168.23,ITC,LON13
##@NIBU@##linux3361,10.166.168.24,ITC,LON13
##@NIBU@##linux3362,10.166.168.26,ITC,LON13
##@NIBU@##linux3363,10.166.168.27,ITC,LON13
##@NIBU@##linux3364,10.166.168.28,ITC,LON13
##@NIBU@##linux3365,10.166.168.29,ITC,LON13
##@NIBU@##linux3366,10.112.8.31,ITC,MUM03
##@NIBU@##linux3367,10.112.8.32,ITC,MUM03
##@NIBU@##linux3368,10.112.8.33,ITC,MUM03
##@NIBU@##linux3369,10.112.8.34,ITC,MUM03
##@NIBU@##linux3370,linux3370,EIT,MUM03
##@NIBU@##linux3371,10.112.8.81,EIT,MUM03
##@NIBU@##linux3372,10.112.8.37,ITC,MUM03
##@NIBU@##linux3373,75.78.162.17,WIC,DEN06
##@NIBU@##linux3374,10.27.162.21,WIC,OMA00
##@NIBU@##linux3375,10.27.162.23,WIC,OMA00
##@NIBU@##linux3376,10.27.162.25,WIC,OMA00
##@NIBU@##linux3377,10.27.162.27,WIC,OMA00
##@NIBU@##linux3378,10.27.162.29,WIC,OMA00
##@NIBU@##linux3379,10.27.162.31,WIC,OMA00
##@NIBU@##linux3382,10.28.106.53,WIC,ATL01
##@NIBU@##linux3383,10.28.106.55,WIC,ATL01
##@NIBU@##linux3384,10.70.2.41,WIC,DEN06
##@NIBU@##linux3385,10.70.2.42,WIC,DEN06
##@NIBU@##linux3386,10.27.128.89,WIC,OMA00
##@NIBU@##linux3387,10.27.128.90,WIC,OMA00
##@NIBU@##linux3389,10.27.128.92,WIC,OMA00
##@NIBU@##linux3390,10.27.128.93,WIC,OMA00
##@NIBU@##linux3391,10.27.128.94,WIC,OMA00
##@NIBU@##Linux3392,10.70.71.22,ITC,DEN06
##@NIBU@##linux3393,linux3393,ITC,OMA11
##@NIBU@##linux3394,10.64.138.31,ITC,WPT03
##@NIBU@##linux3395,10.27.117.63,EIT,OMA00
##@NIBU@##linux3396,10.27.117.64,EIT,OMA00
##@NIBU@##Linux3398,10.72.1.120,ITC,DEN06
##@NIBU@##Linux3399,75.78.177.120,WIC,DEN06
##@NIBU@##linux34,Not here,CORP,OMA00
##@NIBU@##Linux3400,75.78.177.121,WIC,DEN06
##@NIBU@##Linux3401,75.78.177.122,WIC,DEN06
##@NIBU@##Linux3402,10.29.104.118,WIC,DEN01
##@NIBU@##Linux3403,75.78.161.63,WIC,DEN06
##@NIBU@##Linux3404,10.27.126.38,WIC,OMA00
##@NIBU@##Linux3405,10.17.125.28,WIC,OMA10
##@NIBU@##Linux3406,10.28.107.158,WIC,ATL01
##@NIBU@##linux3407,10.70.2.43,WNG,DEN06
##@NIBU@##linux341,172.30.56.20,EIT,DEN01
##@NIBU@##Linux3411,75.78.161.25,WIC,DEN06
##@NIBU@##linux3412,10.64.16.62,ITC,SWN01
##@NIBU@##Linux3413,10.64.18.23,ITC,SWN01
##@NIBU@##linux3414,10.64.18.54,ITC,SWN01
##@NIBU@##linux3415,10.64.18.74,ITC,SWN01
##@NIBU@##linux3416,10.64.18.76,ITC,SWN01
##@NIBU@##linux3417,10.64.18.80,ITC,SWN01
##@NIBU@##linux3418,10.64.2.200,ITC,SWN01
##@NIBU@##linux3419,10.64.2.201,ITC,SWN01
##@NIBU@##linux342,172.30.53.62,ITC,DEN01
##@NIBU@##linux3420,10.64.2.202,ITC,SWN01
##@NIBU@##linux3421,10.64.2.203,ITC,SWN01
##@NIBU@##linux3422,10.64.2.204,ITC,SWN01
##@NIBU@##linux3423,10.64.2.210,ITC,SWN01
##@NIBU@##linux3424,10.64.51.60,ITC,SWN01
##@NIBU@##linux3425,10.64.51.61,ITC,SWN01
##@NIBU@##linux3426,10.64.51.62,ITC,SWN01
##@NIBU@##linux3427,10.64.51.63,ITC,SWN01
##@NIBU@##linux3428,10.64.51.64,ITC,SWN01
##@NIBU@##linux3429,10.64.21.98,ITC,SWN01
##@NIBU@##linux343,172.30.53.63,ITC,DEN01
##@NIBU@##linux3430,10.64.21.99,ITC,SWN01
##@NIBU@##linux3431,10.64.8.34,ITC,SWN01
##@NIBU@##linux3432,10.64.21.100,ITC,SWN01
##@NIBU@##linux3433,10.64.4.44,ITC,SWN01
##@NIBU@##linux3434,10.64.224.37,ITC,SWN01
##@NIBU@##linux3435,10.64.224.38,ITC,DEN06
##@NIBU@##linux3436,10.64.16.63,ITC,SWN01
##@NIBU@##linux3437,10.64.18.55,ITC,SWN01
##@NIBU@##linux3438,10.64.18.75,ITC,SWN01
##@NIBU@##linux3439,10.64.18.77,ITC,SWN01
##@NIBU@##linux344,172.30.53.64,ITC,DEN01
##@NIBU@##linux3440,10.64.18.81,ITC,SWN01
##@NIBU@##linux3441,10.64.2.205,ITC,SWN01
##@NIBU@##linux3442,10.64.2.206,ITC,SWN01
##@NIBU@##linux3443,10.64.2.207,ITC,SWN01
##@NIBU@##linux3444,10.72.0.13,ITC,DEN06
##@NIBU@##linux3446,10.27.197.102,WIC,OMA00
##@NIBU@##linux3447,10.27.130.49,WIC,OMA00
##@NIBU@##linux3448,10.27.130.50,WIC,OMA00
##@NIBU@##linux3449,10.27.130.8,WIC,OMA00
##@NIBU@##linux345,172.30.53.65,ITC,DEN01
##@NIBU@##Linux3450,10.64.2.198,ITC,SWN01
##@NIBU@##Linux3451,10.64.2.199,ITC,SWN01
##@NIBU@##Linux3454,10.72.216.31,ITC,DEN06
##@NIBU@##Linux3456,10.72.216.48,ITC,DEN06
##@NIBU@##Linux3457,10.72.216.49,ITC,DEN06
##@NIBU@##linux3458,10.72.216.74,ITC,DEN06
##@NIBU@##linux3459,10.72.216.75,ITC,DEN06
##@NIBU@##linux346,172.30.53.66,ITC,DEN01
##@NIBU@##linux3460,10.72.216.33,ITC,DEN06
##@NIBU@##Linux3461,10.72.216.34,ITC,DEN06
##@NIBU@##Linux3462,10.72.216.50,ITC,DEN06
##@NIBU@##linux3463,10.72.216.51,ITC,DEN06
##@NIBU@##linux3464,10.72.216.76,ITC,DEN06
##@NIBU@##linux3465,10.72.216.77,ITC,DEN06
##@NIBU@##linux3466,10.72.216.37,ITC,DEN06
##@NIBU@##linux3467,10.169.200.34,ITC,TOR03
##@NIBU@##linux347,172.30.53.67,ITC,DEN01
##@NIBU@##linux3478,10.27.128.114,WIC,OMA00
##@NIBU@##linux3479,10.27.128.115,WIC,OMA00
##@NIBU@##linux348,172.30.53.68,ITC,DEN01
##@NIBU@##linux3480,10.27.128.116,WIC,OMA00
##@NIBU@##linux3481,10.27.128.117,WIC,OMA00
##@NIBU@##linux3486,10.232.10.67,WIC,SJC01
##@NIBU@##linux3488,172.16.2.130,EIT,MIA01
##@NIBU@##linux349,172.30.53.69,ITC,DEN01
##@NIBU@##Linux3490,10.27.126.36,WIC,OMA00
##@NIBU@##Linux3491,10.27.126.37,WIC,OMA00
##@NIBU@##linux3496,10.72.1.50,ITC,DEN06
##@NIBU@##linux3497,10.72.1.51,ITC,DEN06
##@NIBU@##linux3498,10.27.130.55,WIC,OMA00
##@NIBU@##linux350,172.30.184.20,EIT,OMA10
##@NIBU@##linux3500,10.64.8.36,ITC,SWN01
##@NIBU@##linux3501,10.64.8.37,ITC,SWN01
##@NIBU@##linux3502,10.64.8.38,ITC,SWN01
##@NIBU@##linux3503,10.64.8.39,ITC,SWN01
##@NIBU@##linux3504,10.64.8.40,ITC,SWN01
##@NIBU@##linux3505,10.64.8.41,ITC,SWN01
##@NIBU@##linux3506,10.64.8.42,ITC,SWN01
##@NIBU@##linux3507,10.64.8.43,ITC,SWN01
##@NIBU@##linux3508,10.64.8.44,ITC,SWN01
##@NIBU@##linux3509linux3509,75.78.162.29,ITC,DEN06
##@NIBU@##linux351,172.30.184.21,WIC,OMA10
##@NIBU@##linux3510,75.78.162.30,ITC,DEN06
##@NIBU@##linux3511,75.78.162.31,ITC,DEN06
##@NIBU@##linux3512,75.78.162.32,ITC,DEN06
##@NIBU@##linux3513,75.78.162.33,ITC,DEN06
##@NIBU@##linux3514,75.78.162.34,ITC,DEN06
##@NIBU@##linux3515,75.78.162.35,ITC,DEN06
##@NIBU@##linux3516,72.78.162.36,ITC,DEN06
##@NIBU@##linux3517,10.27.193.54,WIC,OMA00
##@NIBU@##linux3518,10.27.193.55,WIC,OMA00
##@NIBU@##Linux3519,10.27.128.111,WIC,OMA00
##@NIBU@##linux3520,10.27.128.112,WIC,OMA00
##@NIBU@##linux3521,10.18.132.117,WIC,OMA11
##@NIBU@##linux3522,10.29.114.90,WIC,DEN01
##@NIBU@##Linux3523,10.28.124.85,WIC,ATL01
##@NIBU@##linux3524,10.70.2.46,WIC,DEN06
##@NIBU@##Linux3528,10.63.100.176,ITC,DEN05
##@NIBU@##linux3529,75.78.161.31 ,ITC,DEN06
##@NIBU@##linux353,172.30.53.71,ITC,DEN01
##@NIBU@##linux3530,75.78.161.32,ITC,DEN06
##@NIBU@##linux3531,10.72.1.41,ITC,DEN06
##@NIBU@##linux3532,10.72.1.42,ITC,DEN06
##@NIBU@##linux3535,10.72.1.45,ITC,DEN06
##@NIBU@##linux354,10.27.193.47,WIC,OMA00
##@NIBU@##linux3543,10.27.130.131,WIC,OMA00
##@NIBU@##linux3545,10.72.1.44,ITC,DEN06
##@NIBU@##linux3546,10.18.132.98,WIC,OMA11
##@NIBU@##linux3547,10.18.132.99,WIC,OMA11
##@NIBU@##linux355,10.27.193.48,WIC,OMA00
##@NIBU@##linux3551,10.28.107.29,WIC,ATL01
##@NIBU@##linux3552,10.29.107.21,WIC,DEN01
##@NIBU@##linux3553,10.19.112.52,WCMG,OMA01
##@NIBU@##linux3554,10.19.112.53,WCMG,OMA01
##@NIBU@##linux3555,10.29.99.176,WIC,DEN01
##@NIBU@##linux3556,10.29.99.205,WIC,DEN01
##@NIBU@##linux3557,10.29.99.178,WIC,DEN01
##@NIBU@##linux3558,10.29.99.179,WIC,DEN01
##@NIBU@##linux3559,10.29.99.177,WIC,DEN01
##@NIBU@##linux356,10.27.193.88,WIC,OMA00
##@NIBU@##linux3560,10.29.99.206,WIC,DEN01
##@NIBU@##Linux3561,10.29.99.208,WIC,DEN01
##@NIBU@##Linux3562,75.78.1.190,ITC,SWN01
##@NIBU@##linux3563,75.78.1.191,ITC,SWN01
##@NIBU@##Linux3564,10.64.49.233,ITC,SWN01
##@NIBU@##Linux3565,10.64.49.234,ITC,SWN01
##@NIBU@##Linux3566,10.64.49.235,ITC,SWN01
##@NIBU@##Linux3567,10.64.49.236 ,ITC,SWN01
##@NIBU@##Linux3568,10.64.49.237,ITC,SWN01
##@NIBU@##Linux3569,10.64.49.238,ITC,SWN01
##@NIBU@##Linux3570,10.64.4.26,ITC,SWN01
##@NIBU@##linux3571,10.28.103.43,WIC,ATL01
##@NIBU@##linux3572,10.28.107.83,WIC,ATL01
##@NIBU@##linux3573,10.28.103.44,WIC,ATL01
##@NIBU@##linux3574,10.28.107.84,WIC,ATL01
##@NIBU@##linux3575,10.28.103.45,WIC,ATL01
##@NIBU@##linux3576,10.28.107.85,WIC,ATL01
##@NIBU@##linux3577,10.28.103.46,WIC,ATL01
##@NIBU@##linux3578,10.70.64.115,WIC,DEN01
##@NIBU@##linux3579,10.28.107.111,WIC,ATL01
##@NIBU@##linux3580,10.27.130.133,WIC,OMA00
##@NIBU@##linux3581,10.27.130.134,WIC,OMA00
##@NIBU@##linux3582,10.27.130.135,WIC,OMA00
##@NIBU@##linux3583,10.27.130.136,WIC,OMA00
##@NIBU@##linux3584,10.27.130.137,WIC,OMA00
##@NIBU@##linux3585,10.27.130.138,WIC,OMA00
##@NIBU@##linux3586,10.70.0.50,WIC,DEN06
##@NIBU@##linux3587,10.70.0.60,WIC,DEN06
##@NIBU@##linux3589,10.27.130.173,WIC,OMA00
##@NIBU@##linux3590,10.18.154.15,WIC,OMA11
##@NIBU@##linux3592,10.18.154.17,WIC,OMA11
##@NIBU@##linux3593,10.18.154.18,WIC,OMA11
##@NIBU@##linux3594,10.18.154.19,WIC,OMA11
##@NIBU@##linux3595,10.18.154.20,WIC,OMA11
##@NIBU@##linux3597,10.27.130.175,WIC,OMA00
##@NIBU@##linux3599,10.72.1.54,ITC,DEN06
##@NIBU@##linux36,172.30.1.102,WIC,OMA01
##@NIBU@##linux360,172.30.113.85,WCMG,OMA00
##@NIBU@##linux3600,10.72.1.55,ITC,DEN06
##@NIBU@##linux3601,10.70.0.218,WIC,DEN06
##@NIBU@##linux3602,10.18.132.119,WIC,OMA11
##@NIBU@##linux3603,10.18.132.120,WIC,OMA11
##@NIBU@##linux3604,10.18.132.104,WIC,OMA11
##@NIBU@##linux3605,10.18.132.105,WIC,OMA11
##@NIBU@##linux3606,10.18.132.106,WIC,OMA11
##@NIBU@##linux3607,10.18.132.107 ,WIC,OMA11
##@NIBU@##linux3608,10.18.132.108,WIC,OMA11
##@NIBU@##linux3609,10.18.132.109,WIC,OMA11
##@NIBU@##linux361,172.30.113.252,WCMG,OMA00
##@NIBU@##linux3610,10.18.132.110 ,WIC,OMA11
##@NIBU@##linux3611,10.18.132.111,WIC,OMA11
##@NIBU@##linux3612,10.18.132.115 ,WIC,OMA11
##@NIBU@##linux3613,10.18.132.116 ,WIC,OMA11
##@NIBU@##linux3614,10.27.130.171,WIC,OMA00
##@NIBU@##linux3615,10.27.130.172,WIC,OMA00
##@NIBU@##linux3616,10.27.130.140,WIC,OMA00
##@NIBU@##linux3617,10.27.130.141,WIC,OMA00
##@NIBU@##linux3618,10.27.130.142,WIC,OMA00
##@NIBU@##linux3619,10.27.130.143,WIC,OMA00
##@NIBU@##linux362,172.30.113.6,WCMG,OMA00
##@NIBU@##linux3620,10.27.130.144,WIC,OMA00
##@NIBU@##linux3621,10.27.130.145,WIC,OMA00
##@NIBU@##linux3622,10.27.130.146,WIC,OMA00
##@NIBU@##linux3623,10.27.130.147,WIC,OMA00
##@NIBU@##Linux3624,10.27.130.151,WIC,OMA00
##@NIBU@##Linux3625,10.27.130.152,WIC,OMA00
##@NIBU@##linux3626,10.27.130.154,WIC,OMA00
##@NIBU@##linux3627,10.27.130.155,WIC,OMA00
##@NIBU@##linux3628,10.27.130.156,WIC,OMA00
##@NIBU@##linux3629,10.27.130.157,WIC,OMA00
##@NIBU@##linux3630,10.27.130.158,WIC,OMA00
##@NIBU@##linux3631,10.27.130.159,WIC,OMA00
##@NIBU@##linux3632,10.27.130.160,WIC,OMA00
##@NIBU@##linux3633,10.27.130.161,WIC,OMA00
##@NIBU@##Linux3636,10.27.117.69,EIT,OMA00
##@NIBU@##Linux3637,10.27.117.70,EIT,OMA00
##@NIBU@##linux3638,10.27.117.71,EIT,OMA00
##@NIBU@##linux3641,10.29.107.73,WIC,DEN01
##@NIBU@##linux3642,10.29.107.74,WIC,DEN01
##@NIBU@##linux3643,10.29.107.75,WIC,DEN01
##@NIBU@##linux3644,10.29.107.76,WIC,DEN01
##@NIBU@##linux3645,10.29.107.77,WIC,DEN01
##@NIBU@##linux3646,10.29.107.78,WIC,DEN01
##@NIBU@##linux3647,10.29.107.86,WIC,DEN01
##@NIBU@##linux3648 ,10.29.107.87,WIC,DEN01
##@NIBU@##linux3649 ,10.29.107.88,WIC,DEN01
##@NIBU@##linux3650 ,10.29.107.89,WIC,DEN01
##@NIBU@##linux3651,10.29.107.90,WIC,DEN01
##@NIBU@##linux3652 ,10.29.107.91,WIC,DEN01
##@NIBU@##linux3653 ,10.29.107.92,WIC,DEN01
##@NIBU@##linux3654 ,10.29.107.93,WIC,DEN01
##@NIBU@##linux3655 ,10.29.107.94,WIC,DEN01
##@NIBU@##linux3656 ,10.29.107.95,WIC,DEN01
##@NIBU@##linux3661,10.27.197.73,WIC,OMA00
##@NIBU@##linux3662,10.27.197.124,WIC,OMA00
##@NIBU@##linux3663,10.27.197.71,WIC,OMA00
##@NIBU@##linux3664,10.27.130.176 ,WIC,OMA00
##@NIBU@##linux3665,10.27.130.181,WIC,OMA00
##@NIBU@##linux3666,10.72.1.60,ITC,DEN06
##@NIBU@##linux3667,10.72.1.61,ITC,DEN06
##@NIBU@##linux3668,10.27.130.178,WIC,OMA00
##@NIBU@##linux3669,10.27.130.168,WIC,OMA00
##@NIBU@##linux367,10.27.193.42,WIC,OMA00
##@NIBU@##linux3670,10.27.130.169,WIC,OMA00
##@NIBU@##linux3673,10.29.107.101,WIC,DEN01
##@NIBU@##linux3674,10.27.107.127,WIC,ATL01
##@NIBU@##linux3675,10.64.12.97,ITC,SWN01
##@NIBU@##linux3676,10.64.12.98,ITC,SWN01
##@NIBU@##linux3677,10.29.107.85,WIC,OMA00
##@NIBU@##linux3678,10.29.107.100,WIC,OMA00
##@NIBU@##linux3679,10.29.107.98,WIC,OMA00
##@NIBU@##linux368,10.27.193.43,WIC,OMA00
##@NIBU@##linux3680,10.29.107.99,WIC,OMA00
##@NIBU@##linux3681,10.27.130.170,WIC,OMA00
##@NIBU@##Linux3683,10.27.130.164,WIC,OMA00
##@NIBU@##Linux3684,10.27.130.165,WIC,OMA00
##@NIBU@##linux3685,10.28.107.112,WIC,ATL01
##@NIBU@##linux3686,10.28.107.113,WIC,ATL01
##@NIBU@##linux3687,10.28.107.114,WIC,ATL01
##@NIBU@##linux3688,10.28.107.115,WIC,ATL01
##@NIBU@##linux3689,10.28.107.116,WIC,ATL01
##@NIBU@##linux369,10.27.193.44,WIC,OMA00
##@NIBU@##linux3690,10.28.107.117,WIC,ATL01
##@NIBU@##linux3691,10.28.107.118,WIC,ATL01
##@NIBU@##linux3692,10.28.107.119,WIC,ATL01
##@NIBU@##linux3693,10.28.107.120,WIC,ATL01
##@NIBU@##linux3694,10.28.107.121,WIC,ATL01
##@NIBU@##linux3695,10.27.130.184,WIC,OMA00
##@NIBU@##linux3696,10.27.130.185,WIC,OMA00
##@NIBU@##Linux3697,10.70.2.55,WIC,DEN06
##@NIBU@##linux3698,10.29.107.102,WIC,DEN01
##@NIBU@##linux3699,10.28.107.30,WIC,ATL01
##@NIBU@##linux37,172.30.1.103,WIC,OMA01
##@NIBU@##linux370,172.30.113.79,WIC,OMA00
##@NIBU@##linux3700,10.29.107.103,WIC,DEN01
##@NIBU@##linux3701,10.28.107.128,WIC,ATL01
##@NIBU@##linux3703,10.28.107.129,WIC,ATL01
##@NIBU@##linux3704,10.29.104.69,WIC,DEN01
##@NIBU@##linux3705,10.29.104.70,WIC,DEN01
##@NIBU@##linux3706,10.29.104.71,WIC,DEN01
##@NIBU@##linux3707,10.29.104.79,WIC,DEN01
##@NIBU@##linux3708,10.29.104.80,WIC,DEN01
##@NIBU@##linux3709,10.29.104.81,WIC,DEN01
##@NIBU@##linux371,172.30.113.8,WIC,OMA00
##@NIBU@##linux3710,10.29.104.82,WIC,DEN01
##@NIBU@##linux3711,10.29.104.85,WIC,DEN01
##@NIBU@##linux3712,10.29.104.86,WIC,DEN01
##@NIBU@##linux3713,10.29.104.87,WIC,DEN01
##@NIBU@##linux3714,10.29.104.88,WIC,DEN01
##@NIBU@##linux3715,10.29.104.95,WIC,DEN01
##@NIBU@##linux3716,10.29.104.96,WIC,DEN01
##@NIBU@##linux3717,10.29.104.97,WIC,DEN01
##@NIBU@##linux3718,10.29.104.98,WIC,DEN01
##@NIBU@##linux3719,10.28.107.130,WIC,ATL01
##@NIBU@##linux372,172.30.113.82,WIC,OMA00
##@NIBU@##linux3720,10.29.107.104,WIC,DEN01
##@NIBU@##linux3721,10.27.130.217,WIC,OMA00
##@NIBU@##linux3722,10.29.107.108,WIC,DEN01
##@NIBU@##linux3723,10.28.107.97,WIC,ATL01
##@NIBU@##linux3726,10.28.107.124,WIC,ATL01
##@NIBU@##linux3727,10.28.107.125,WIC,ATL01
##@NIBU@##linux3728,10.28.107.110,WIC,ATL01
##@NIBU@##linux3729,10.28.107.126,WIC,ATL01
##@NIBU@##linux373,172.30.113.83,WIC,OMA00
##@NIBU@##linux3730,10.28.107.106,WIC,ATL01
##@NIBU@##linux3731,10.28.107.107,WIC,ATL01
##@NIBU@##linux3732,10.28.107.108,WIC,ATL01
##@NIBU@##linux3733,10.28.107.109,WIC,ATL01
##@NIBU@##linux3734,10.28.107.100,WIC,ATL01
##@NIBU@##linux3735,10.28.107.101,WIC,ATL01
##@NIBU@##linux3736,10.28.107.102,WIC,ATL01
##@NIBU@##linux3737,10.28.107.103,WIC,ATL01
##@NIBU@##linux3738,10.28.107.104,WIC,ATL01
##@NIBU@##linux3739,10.28.107.105,WIC,ATL01
##@NIBU@##linux374,172.30.0.108,WIC,OMA01
##@NIBU@##linux3741,10.28.103.47,WIC,ATL01
##@NIBU@##linux3742,10.28.103.48,WIC,ATL01
##@NIBU@##linux3743,10.28.103.49,WIC,ATL01
##@NIBU@##linux3744,10.28.103.52,WIC,ATL01
##@NIBU@##linux3745,10.28.103.53,WIC,ATL01
##@NIBU@##linux3746,10.28.103.54,WIC,ATL01
##@NIBU@##linux3747,10.28.103.55,WIC,ATL01
##@NIBU@##Linux3748,10.28.107.86,WIC,ATL01
##@NIBU@##linux3749,10.28.107.87,WIC,ATL01
##@NIBU@##linux375,172.30.0.11,WIC,OMA01
##@NIBU@##linux3750,10.28.107.88,WIC,ATL01
##@NIBU@##linux3751,10.28.107.89,WIC,ATL01
##@NIBU@##linux3752,10.28.107.92,WIC,ATL01
##@NIBU@##linux3753,10.28.107.93,WIC,ATL01
##@NIBU@##linux3754,10.28.107.94,WIC,ATL01
##@NIBU@##linux3755,10.28.10795,WIC,ATL01
##@NIBU@##linux3756,10.64.51.84,ITC,SWN01
##@NIBU@##linux3757,10.64.51.83,ITC,SWN01
##@NIBU@##linux3758,10.64.49.87,ITC,SWN01
##@NIBU@##Linux3759,10.29.107.105,WIC,DEN01
##@NIBU@##linux376,172.30.0.113,WIC,OMA01
##@NIBU@##linux3760,10.29.107.106,WIC,DEN01
##@NIBU@##linux3761,10.29.107.107,WIC,DEN01
##@NIBU@##linux3763,10.64.49.148,ITC,SWN01
##@NIBU@##linux3764,10.64.49.149 ,ITC,SWN01
##@NIBU@##linux3765,10.64.49.150,ITC,SWN01
##@NIBU@##linux3766,10.72.1.68,ITC,DEN06
##@NIBU@##linux3767,10.72.1.69,ITC,DEN06
##@NIBU@##linux3768,10.72.1.70,ITC,DEN06
##@NIBU@##linux3769,10.72.1.71,ITC,DEN06
##@NIBU@##linux377,172.30.0.114,WIC,OMA01
##@NIBU@##linux3770,10.72.1.72,ITC,DEN06
##@NIBU@##linux3771,75.78.161.38,ITC,DEN06
##@NIBU@##linux3772,75.78.161.39,ITC,DEN06
##@NIBU@##linux3773,10.28.107.132,WIC,ATL01
##@NIBU@##linux3774,10.28.107.133,WIC,ATL01
##@NIBU@##linux3775,10.28.107.134,WIC,ATL01
##@NIBU@##linux3776,10.28.107.135,WIC,SWN01
##@NIBU@##linux3777,10.27.130.218,WIC,OMA00
##@NIBU@##Linux3778,10.70.229.21,WNG,DEN06
##@NIBU@##Linux3779,10.70.229.22,WNG,DEN06
##@NIBU@##Linux3780,10.70.229.23,WNG,DEN06
##@NIBU@##Linux3781,10.70.229.24,WNG,DEN06
##@NIBU@##Linux3782,10.70.229.25,WNG,DEN06
##@NIBU@##Linux3783,10.70.229.26,WNG,DEN06
##@NIBU@##linux3784,10.70.229.27,WNG,DEN06
##@NIBU@##linux3786,10.166.168.31,ITC,LON13
##@NIBU@##linux3787,10.166.168.32,ITC,LON13
##@NIBU@##linux3788,10.166.168.33,ITC,LON13
##@NIBU@##linux3789,10.166.168.34,ITC,LON13
##@NIBU@##linux3790,10.29.107.110,WIC,DEN01
##@NIBU@##linux3793,10.64.51.88,ITC,SWN01
##@NIBU@##linux3794,10.64.51.89,ITC,SWN01
##@NIBU@##linux3795,10.64.2.185,ITC,SWN01
##@NIBU@##linux3797,75.78.2.176,ITC,SWN01
##@NIBU@##linux3798,75.78.2.177,ITC,SWN01
##@NIBU@##Linux3799,10.27.193.97,ITC,OMA00
##@NIBU@##Linux3800,10.27.110.39,ITC,OMA00
##@NIBU@##Linux3801,10.72.2.30,ITC,DEN06
##@NIBU@##Linux3802,10.31.135.51,ITC,PHX01
##@NIBU@##Linux3803,10.166.168.54,ITC,LON13
##@NIBU@##linux3804,10.170.200.45,ITC,SYD07
##@NIBU@##Linux3805,10.70.71.34,EIT,DEN06
##@NIBU@##Linux3806,10.27.109.66 ,EIT,OMA00
##@NIBU@##linux3807,10.29.115.44,EIT,DEN01
##@NIBU@##linux381,172.30.75.33,ITC,ATL01
##@NIBU@##linux382,172.30.75.34,ITC,ATL01
##@NIBU@##linux3828,10.18.132.114,WIC,OMA11
##@NIBU@##linux3829,10.18.132.121,WIC,OMA11
##@NIBU@##linux383,172.30.75.35,ITC,ATL01
##@NIBU@##linux3831,10.28.107.136,WIC,ATL01
##@NIBU@##linux3832,10.28.107.137,WIC,ATL01
##@NIBU@##linux3833,10.27.130.235,WIC,OMA00
##@NIBU@##linux3834,10.28.107.138,WIC,ATL01
##@NIBU@##linux3835,10.70.2.56,WIC,DEN06
##@NIBU@##linux3836,10.46.1.30,WCMG,MNL01
##@NIBU@##Linux3837,10.27.110.93,ITC,OMA00
##@NIBU@##linux3838,10.27.110.95,ITC,OMA00
##@NIBU@##Linux3839,10.72.0.44,ITC,DEN06
##@NIBU@##linux384,172.30.75.36,ITC,ATL01
##@NIBU@##Linux3840,10.72.0.46,ITC,DEN06
##@NIBU@##linux385,172.30.75.37,ITC,ATL01
##@NIBU@##linux3859,10.166.128.21,WIC,LON13
##@NIBU@##linux386,172.30.75.38,ITC,ATL01
##@NIBU@##linux3860,10.166.128.25,WIC,LON13
##@NIBU@##linux3861,10.166.128.26,WIC,LON13
##@NIBU@##linux3862,10.166.128.27,WIC,LON13
##@NIBU@##linux3863,10.166.128.28,WIC,LON13
##@NIBU@##linux3864,10.166.128.29,WIC,LON13
##@NIBU@##linux3865,10.166.128.30,WIC,LON13
##@NIBU@##linux3866,10.166.128.32,WIC,LON13
##@NIBU@##linux3867 ,10.64.2.190 ,ITC,SWN01
##@NIBU@##linux3868,10.64.2.191,ITC,SWN01
##@NIBU@##linux3869,10.64.2.192,ITC,SWN01
##@NIBU@##linux3870,10.64.2.193,ITC,SWN01
##@NIBU@##linux3871,10.64.2.194,ITC,SWN01
##@NIBU@##linux3872,10.64.2.195,ITC,SWN01
##@NIBU@##linux3874,216.57.100.104,WCMG,OMA01
##@NIBU@##linux3875,10.27.197.75,WIC,OMA00
##@NIBU@##Linux3876,10.27.216.225,ITC,OMA00
##@NIBU@##linux3877,10.27.216.226,ITC,OMA00
##@NIBU@##linux3878,10.27.216.227,ITC,OMA00
##@NIBU@##linux3879,10.27.216.228,ITC,OMA00
##@NIBU@##linux388,172.30.75.40,ITC,ATL01
##@NIBU@##Linux3880,10.27.216.229,ITC,OMA00
##@NIBU@##Linux3881,10.27.216.230,ITC,OMA00
##@NIBU@##linux3882,10.72.8.55,ITC,DEN06
##@NIBU@##linux3883,10.72.1.32,ITC,DEN06
##@NIBU@##Linux3884,10.27.201.27,ITC,OMA00
##@NIBU@##Linux3885,10.64.49.40,ITC,SWN01
##@NIBU@##Linux3886,10.64.49.41,ITC,SWN01
##@NIBU@##Linux3887,10.64.49.42,ITC,SWN01
##@NIBU@##Linux3888,10.64.49.43,ITC,SWN01
##@NIBU@##linux3889,10.70.224.96,WIC,DEN06
##@NIBU@##linux389,172.30.75.41,ITC,ATL01
##@NIBU@##linux3890,10.70.224.91,WIC,DEN06
##@NIBU@##linux3891,10.70.224.92,WIC,DEN06
##@NIBU@##linux3892,10.70.224.93,WIC,DEN06
##@NIBU@##Linux3893,10.70.224.94,WIC,DEN06
##@NIBU@##Linux3894,10.70.224.95,WIC,DEN06
##@NIBU@##linux3895,10.27.68.73,WIC,OMA00
##@NIBU@##linux3896,10.27.68.74,WIC,OMA00
##@NIBU@##linux3897,10.27.68.75,WIC,OMA00
##@NIBU@##linux3898,10.27.68.76,WIC,OMA00
##@NIBU@##Linux3899,10.27.68.77,WIC,OMA00
##@NIBU@##linux39,172.30.1.105,WIC,OMA01
##@NIBU@##linux390,172.30.75.42,ITC,ATL01
##@NIBU@##Linux3900,10.27.68.78,WIC,OMA00
##@NIBU@##linux3901,10.29.97.209,WIC,DEN01
##@NIBU@##linux3902,10.29.97.210,WIC,DEN01
##@NIBU@##Linux3903,10.29.97.211,WIC,DEN01
##@NIBU@##linux3904,10.28.103.50,WIC,ATL01
##@NIBU@##linux3905,10.28.103.51,WIC,ATL01
##@NIBU@##linux3906,10.28.107.90,WIC,ATL01
##@NIBU@##linux3907,10.27.130.220,EIT,OMA00
##@NIBU@##Linux3908,10.65.36.62,ITC,SWN01
##@NIBU@##Linux3909,10.65.36.67,ITC,SWN01
##@NIBU@##linux391,172.30.75.43,ITC,ATL01
##@NIBU@##Linux3910,10.65.36.70,ITC,SWN01
##@NIBU@##Linux3911,10.65.36.57,ITC,SWN01
##@NIBU@##Linux3912,10.65.36.63,ITC,SWN01
##@NIBU@##Linux3913,10.65.40.80,ITC,SWN01
##@NIBU@##linux3914,10.29.107.115,WIC,DEN06
##@NIBU@##linux3915,10.29.107.116,WIC,DEN06
##@NIBU@##Linux3916,10.29.107.117,WIC,DEN06
##@NIBU@##linux3917,10.29.107.118,WIC,DEN06
##@NIBU@##linux3918,10.29.107.119,WIC,DEN06
##@NIBU@##linux3919,10.70.2.80,WIC,DEN06
##@NIBU@##linux392,172.30.75.44,ITC,ATL01
##@NIBU@##linux3920,10.70.2.81,WIC,DEN06
##@NIBU@##linux3921,10.70.2.82,WIC,DEN06
##@NIBU@##linux3922,10.70.2.83,WIC,DEN06
##@NIBU@##linux3923,10.70.2.84,WIC,DEN06
##@NIBU@##linux3924,10.28.107.150,WIC,DEN06
##@NIBU@##linux3925,10.28.107.151,WIC,DEN06
##@NIBU@##linux3926,10.28.107.152,WIC,DEN06
##@NIBU@##linux3927,10.28.107.153,WIC,DEN06
##@NIBU@##linux3928,10.28.107.154,WIC,ATL01
##@NIBU@##Linux3929,10.64.4.51,ITC,SWN01
##@NIBU@##linux393,172.30.75.45,ITC,ATL01
##@NIBU@##linux3930,10.64.4.52,ITC,SWN01
##@NIBU@##Linux3931,75.78.1.202,ITC,SWN01
##@NIBU@##Linux3932,10.64.49.168,ITC,SWN01
##@NIBU@##linux3933,10.64.49.177,ITC,SWN01
##@NIBU@##Linux3934,75.78.1.192,ITC,SWN01
##@NIBU@##linux3935,75.78.1.194,ITC,SWN01
##@NIBU@##Linux3936,75.78.1.196,ITC,SWN01
##@NIBU@##Linux3937,75.78.1.198,ITC,SWN01
##@NIBU@##linux3939,10.64.51.101,ITC,SWN01
##@NIBU@##linux394,172.30.75.46,ITC,ATL01
##@NIBU@##linux3940,10.64.51.103,ITC,SWN01
##@NIBU@##linux3941,10.64.4.50,ITC,SWN01
##@NIBU@##linux3942,10.64.51.102,ITC,SWN01
##@NIBU@##linux3943,10.29.107.120,WIC,DEN01
##@NIBU@##linux3944,10.27.193.130,WIC,OMA00
##@NIBU@##linux3945,10.27.193.131,WIC,OMA00
##@NIBU@##linux3946,10.27.193.132,WIC,OMA00
##@NIBU@##linux3947,10.27.193.133,WIC,OMA00
##@NIBU@##linux395,172.30.75.47,ITC,ATL01
##@NIBU@##linux396,172.30.75.48,ITC,ATL01
##@NIBU@##linux397,172.30.75.49,ITC,ATL01
##@NIBU@##linux3971,10.64.19.45,ITC,SWN01
##@NIBU@##linux3972,10.64.19.46,ITC,SWN01
##@NIBU@##linux3975,10.29.107.121,WIC,DEN06
##@NIBU@##linux3976,10.65.40.53,ITC,SWN01
##@NIBU@##linux3977,10.65.40.54,ITC,SWN01
##@NIBU@##linux3978,10.65.40.55,ITC,SWN01
##@NIBU@##linux3979,10.64.51.104,ITC,SWN01
##@NIBU@##linux398,172.30.184.24,WIC,OMA10
##@NIBU@##linux3980,10.64.51.105,ITC,SWN01
##@NIBU@##linux3981,10.64.51.106,ITC,SWN01
##@NIBU@##linux3982,10.64.51.107,ITC,SWN01
##@NIBU@##linux3983,10.64.51.108,ITC,SWN01
##@NIBU@##linux3984,10.72.1.100,ITC,DEN06
##@NIBU@##linux3985,10.72.1.101,ITC,DEN06
##@NIBU@##linux3986,10.72.1.102,ITC,DEN06
##@NIBU@##linux3987,10.72.1.103,ITC,DEN06
##@NIBU@##linux3988,10.72.1.104,ITC,DEN06
##@NIBU@##linux399,172.30.184.25,WIC,OMA10
##@NIBU@##linux3990,10.72.8.80,ITC,DEN06
##@NIBU@##Linux3991,10.28.170.23,ITC,ATL01
##@NIBU@##linux3992,10.28.170.24,ITC,ATL01
##@NIBU@##linux3993,10.27.115.105,WCMG,OMA00
##@NIBU@##linux3994,10.27.130.237,WIC,OMA00
##@NIBU@##linux3995,10.27.130.238,WIC,OMA00
##@NIBU@##Linux3996,10.65.36.73,ITC,SWN01
##@NIBU@##linux3997,10.70.2.85,WIC,DEN06
##@NIBU@##linux3998,10.70.2.86,WIC,DEN06
##@NIBU@##linux3999,10.70.2.87,WIC,DEN06
##@NIBU@##linux40,172.30.2.214,EIT,OMA01
##@NIBU@##linux400,172.30.184.26,WIC,OMA10
##@NIBU@##linux4000,10.70.2.88,WIC,DEN06
##@NIBU@##Linux4003,10.65.4069,ITC,SWN01
##@NIBU@##Linux4004,10.65.40.70,ITC,SWN01
##@NIBU@##Linux4005,10.65.40.71,ITC,SWN01
##@NIBU@##Linux4006,10.65.40.72,ITC,SWN01
##@NIBU@##Linux4007,10.65.40.73,ITC,SWN01
##@NIBU@##Linux4008,10.65.40.76,ITC,SWN01
##@NIBU@##Linux4009,10.65.40.77,ITC,SWN01
##@NIBU@##linux401,172.30.184.27,WIC,OMA10
##@NIBU@##Linux4010,10.65.40.74,ITC,SWN01
##@NIBU@##Linux4011,10.65.40.75,ITC,SWN01
##@NIBU@##Linux4012,10.65.40.64,ITC,SWN01
##@NIBU@##Linux4013,10.65.40.65,ITC,SWN01
##@NIBU@##Linux4014,10.65.40.66,ITC,SWN01
##@NIBU@##Linux4015,10.65.40.67,ITC,SWN01
##@NIBU@##Linux4016,10.65.40.68,ITC,SWN01
##@NIBU@##Linux4017,10.65.40.58,ITC,SWN01
##@NIBU@##Linux4018,10.65.40.59,ITC,SWN01
##@NIBU@##Linux4019,10.65.40.60,ITC,SWN01
##@NIBU@##Linux402,172.30.9.204,WIC,OMA10
##@NIBU@##Linux4020,10.65.40.61,ITC,SWN01
##@NIBU@##Linux4021,10.65.40.57,ITC,SWN01
##@NIBU@##Linux4022,10.65.40.51,ITC,SWN01
##@NIBU@##Linux4023,10.65.40.52,ITC,SWN01
##@NIBU@##Linux4024,10.65.40.56,ITC,SWN01
##@NIBU@##linux4025,10.64.51.95,ITC,SWN01
##@NIBU@##linux4028,10.64.4.55,ITC,SWN01
##@NIBU@##linux4029,10.64.4.56,ITC,SWN01
##@NIBU@##Linux403,172.30.9.205,WIC,OMA10
##@NIBU@##Linux4030,10.17.125.24,WIC,OMA10
##@NIBU@##linux4031,10.28.107.140,WIC,ATL01
##@NIBU@##linux4034,10.17.125.40,WIC,OMA10
##@NIBU@##linux4035,10.17.125.41,WIC,OMA10
##@NIBU@##linux4036,10.17.125.42,WIC,OMA10
##@NIBU@##linux4037,10.17.125.43,WIC,OMA10
##@NIBU@##linux4038,10.17.125.44,WIC,OMA10
##@NIBU@##linux4039,10.17.125.45,WIC,OMA10
##@NIBU@##Linux404,10.17.61.21,WIC,OMA10
##@NIBU@##linux4040,10.17.125.46,WIC,OMA10
##@NIBU@##linux4042,10.17.125.48,WIC,OMA10
##@NIBU@##linux4043,10.17.125.49,WIC,OMA10
##@NIBU@##linux4044,10.17.1256.50,WIC,OMA10
##@NIBU@##linux4046,10.17.125.52,WIC,OMA10
##@NIBU@##linux4047,10.17.125.54,WIC,OMA10
##@NIBU@##linux4048,10.17.125.55,WIC,OMA10
##@NIBU@##linux4049,10.17.125.56,WIC,OMA10
##@NIBU@##Linux405,172.30.10.9,WIC,OMA10
##@NIBU@##linux4050,10.17.125.57,WIC,OMA10
##@NIBU@##linux4051,10.17.125.58,WIC,OMA10
##@NIBU@##linux4054,10.17.125.61,WIC,OMA10
##@NIBU@##linux4056,10.17.125.63,WIC,OMA10
##@NIBU@##linux4057,10.17.125.60,WIC,OMA10
##@NIBU@##linux4059,10.64.2.188,ITC,DEN06
##@NIBU@##linux406,172.30.9.208,WIC,OMA10
##@NIBU@##linux4060,10.64.2.187,ITC,DEN06
##@NIBU@##linux4061,10.64.2.186,ITC,SWN01
##@NIBU@##linux4062,10.28.96.150,WIC,ATL01
##@NIBU@##linux4063,10.28.96.151,WIC,ATL01
##@NIBU@##linux4064,10.28.96.180,WIC,ATL01
##@NIBU@##linux4065,10.28.96.181,WIC,ATL01
##@NIBU@##linux4066,10.29.99.180,WIC,DEN01
##@NIBU@##linux4067,10.29.99.181,WIC,DEN01
##@NIBU@##linux4068,10.29.99.209,WIC,DEN01
##@NIBU@##linux4069,10.29.99.210,WIC,DEN01
##@NIBU@##linux407,172.30.9.209,WIC,OMA10
##@NIBU@##linux4070,10.64.16.108,ITC,SWN01
##@NIBU@##linux4073,10.64.2.222,ITC,SWN01
##@NIBU@##linux4079,10.64.51.109,ITC,SWN01
##@NIBU@##linux408,10.35.88.24,EIT,PNS01
##@NIBU@##linux4080,10.64.51.110,ITC,SWN01
##@NIBU@##linux4081,10.64.51.111,ITC,SWN01
##@NIBU@##linux4082,10.64.51.112,ITC,SWN01
##@NIBU@##linux4083,10.27.128.124,WIC,OMA00
##@NIBU@##linux4084,10.27.128.125,WIC,OMA00
##@NIBU@##linux4085,10.27.130.242,WIC,OMA00
##@NIBU@##linux4086,10.27.130.243,WIC,OMA00
##@NIBU@##linux4088,10.18.132.122,WIC,OMA11
##@NIBU@##linux4089,10.18.132.123,WIC,OMA11
##@NIBU@##linux409,10.19.121.21,EIT,OMA01
##@NIBU@##linux4090,10.18.132.124,WIC,OMA11
##@NIBU@##linux4091,10.18.132.125,WIC,OMA11
##@NIBU@##linux4092,10.64.51.114,ITC,SWN01
##@NIBU@##linux4095,10.27.130.245,WIC,OMA00
##@NIBU@##linux4096,10.27.130.246,WIC,OMA00
##@NIBU@##linux4097,10.27.130.247,WIC,OMA00
##@NIBU@##linux41,10.31.40.52,EIT,PHX01
##@NIBU@##linux410,10.26.111.104,EIT,RNO01
##@NIBU@##linux4105,10.70.72.84,TFCC,DEN06
##@NIBU@##linux4106,10.70.72.85,TFCC,DEN06
##@NIBU@##linux4107,10.70.72.86,TFCC,DEN06
##@NIBU@##linux4108,10.28.104.34,WNG,ATL01
##@NIBU@##linux4109,10.28.104.35,WNG,ATL01
##@NIBU@##linux411,10.46.1.207,EIT,MNL01
##@NIBU@##linux4110,10.28.104.36,WNG,ATL01
##@NIBU@##Linux4111,10.29.107.154,WNG,DEN01
##@NIBU@##Linux4112,10.29.107.155,WNG,DEN01
##@NIBU@##Linux4113,10.29.107.156,WNG,DEN01
##@NIBU@##Linux4114,10.70.64.177,WNG,DEN06
##@NIBU@##Linux4115,10.70.64.178,WNG,DEN06
##@NIBU@##Linux4116,10.70.64.179,WNG,DEN06
##@NIBU@##Linux4117,10.28.102.44,WNG,ATL01
##@NIBU@##Linux4118,10.28.102.45,WNG,ATL01
##@NIBU@##Linux4119,10.28.102.46,WNG,ATL01
##@NIBU@##linux4125,10.29.107.122,WIC,DEN01
##@NIBU@##linux4126,10.29.107.123,WIC,DEN01
##@NIBU@##linux4127,10.28.107.156,WIC,ATL01
##@NIBU@##linux4128,10.28.107.157,WIC,ATL01
##@NIBU@##linux4135,10.27.68.155,WIC,OMA00
##@NIBU@##linux4136,10.27.68.156,WIC,OMA00
##@NIBU@##linux4137,10.27.68.157,WIC,OMA00
##@NIBU@##linux4138,10.27.68.158,WIC,OMA00
##@NIBU@##linux4140,10.27.68.160,WIC,OMA00
##@NIBU@##linux4141,10.27.68.161,WIC,OMA00
##@NIBU@##linux4142,10.27.68.162,WIC,OMA00
##@NIBU@##linux4143,10.27.68.163,WIC,OMA00
##@NIBU@##linux4147,10.27.68.167,WIC,OMA00
##@NIBU@##linux4148,10.27.68.168,WIC,OMA00
##@NIBU@##linux4149,10.27.68.169,WIC,OMA00
##@NIBU@##linux4153,10.27.68.173,WIC,OMA00
##@NIBU@##linux4154,10.27.68.174,WIC,OMA00
##@NIBU@##linux4155,10.27.68.175,WIC,OMA00
##@NIBU@##Linux4159,10.112.8.25,ITC,MUM03
##@NIBU@##Linux416,172.30.53.70,WIC,DEN01
##@NIBU@##linux4160,10.112.8.30,ITC,MUM03
##@NIBU@##linux4161,10.64.51.116,ITC,SWN01
##@NIBU@##linux4162,10.64.51.117,ITC,SWN01
##@NIBU@##linux4163,10.64.51.118,ITC,SWN01
##@NIBU@##linux4164,10.72.1.86,ITC,DEN06
##@NIBU@##linux4165,10.72.1.87,ITC,DEN06
##@NIBU@##linux4166,10.28.107.162,WIC,OMA00
##@NIBU@##linux4167,10.29.107.124,WIC,OMA00
##@NIBU@##linux4168,10.70.2.89,WIC,DEN06
##@NIBU@##linux4169,10.28.107.163,WIC,ATL01
##@NIBU@##Linux417,172.30.39.126,WIC,DEN01
##@NIBU@##linux4170,10.29.107.125,WIC,DEN01
##@NIBU@##linux4171,10.70.2.90,WIC,DEN06
##@NIBU@##linux4172,10.28.107.164,WIC,OMA00
##@NIBU@##linux4173,10.29.107.126,WIC,DEN01
##@NIBU@##linux4174,10.70.2.91,WIC,DEN06
##@NIBU@##linux4177,10.70.224.116,WIC,DEN06
##@NIBU@##linux4178,10.70.224.117,WIC,DEN06
##@NIBU@##linux4179,10.70.224.118,WIC,DEN06
##@NIBU@##Linux418,10.29.115.115,WIC,DEN01
##@NIBU@##linux4180,10.70.224.119,WIC,DEN06
##@NIBU@##linux4183,10.70.224.122,WIC,DEN06
##@NIBU@##linux4184,10.70.224.123,WIC,DEN06
##@NIBU@##linux4185,10.70.224.124,WIC,DEN06
##@NIBU@##linux4189,10.70.224.128,WIC,DEN06
##@NIBU@##Linux419,10.29.115.116,WIC,DEN01
##@NIBU@##linux4190,10.70.224.129,WIC,DEN06
##@NIBU@##linux4191,10.70.224.130,WIC,DEN06
##@NIBU@##linux4195,10.70.224.134,WIC,DEN06
##@NIBU@##linux4196,10.70.224.135,WIC,DEN06
##@NIBU@##linux4197,10.70.224.136,WIC,DEN06
##@NIBU@##linux4198,10.70.224.137,WIC,DEN06
##@NIBU@##linux42,172.30.1.106,WIC,OMA01
##@NIBU@##linux4200,10.70.224.139,WIC,DEN06
##@NIBU@##linux4205,10.72.1.108,ITC,DEN06
##@NIBU@##linux4206,10.64.51.119,ITC,SWN01
##@NIBU@##linux4207,10.72.1.109,ITC,DEN06
##@NIBU@##linux4208,10.64.2.235,ITC,SWN01
##@NIBU@##linux4209,10.64.51.120,ITC,SWN01
##@NIBU@##linux421,10.29.115.103,WIC,DEN01
##@NIBU@##linux4210,10.64.51.121,ITC,SWN01
##@NIBU@##linux4211,10.72.1.110,ITC,DEN06
##@NIBU@##linux4212,10.64.2.236,ITC,SWN01
##@NIBU@##linux4213,10.72.1.111,ITC,DEN06
##@NIBU@##linux4214,10.70.2.92,WIC,DEN06
##@NIBU@##linux4215,10.70.2.93,WIC,DEN06
##@NIBU@##linux4216,10.70.2.94,WIC,DEN06
##@NIBU@##linux4217,10.70.2.95,WIC,DEN06
##@NIBU@##linux4219,10.70.0.170,WIC,DEN06
##@NIBU@##linux422,172.30.152.22,WIC,OMA01
##@NIBU@##linux4220,10.70.0.198,WIC,DEN06
##@NIBU@##linux4221,10.70.0.205,WIC,DEN06
##@NIBU@##linux4222,10.70.0.212,WIC,DEN06
##@NIBU@##linux4228,10.27.130.252,WIC,OMA00
##@NIBU@##linux423,10.27.193.126,ITC,OMA00
##@NIBU@##linux4231,75.78.162.89,ITC,DEN06
##@NIBU@##linux4232,75.78.162.90,ITC,DEN06
##@NIBU@##linux4233,75.78.162.91,ITC,DEN06
##@NIBU@##linux4234,75.78.162.92,ITC,DEN06
##@NIBU@##linux4235,10.29.107.127,WIC,DEN01
##@NIBU@##linux4236,10.29.107.128,WIC,DEN01
##@NIBU@##linux4237,10.29.107.129,WIC,DEN01
##@NIBU@##linux4238,10.29.107.130,WIC,DEN01
##@NIBU@##linux4239,10.29.107.131,WIC,DEN01
##@NIBU@##linux424,10.27.193.127,ITC,OMA00
##@NIBU@##linux4240,10.29.107.132,WIC,DEN01
##@NIBU@##linux4241,10.29.107.133,WIC,DEN01
##@NIBU@##linux4242,10.29.107.134,WIC,DEN01
##@NIBU@##linux4243,10.29.107.135,WIC,DEN01
##@NIBU@##linux4244,10.29.107.136,WIC,DEN01
##@NIBU@##linux4245,10.29.107.137,WIC,DEN01
##@NIBU@##linux4246,10.29.107.138,WIC,DEN01
##@NIBU@##linux4247,10.29.107.139,WIC,DEN01
##@NIBU@##linux4248,10.29.107.140,WIC,DEN01
##@NIBU@##linux4249,10.29.107.141,WIC,DEN01
##@NIBU@##linux425,10.27.193.128,ITC,OMA00
##@NIBU@##linux4250,10.29.107.142,WIC,DEN01
##@NIBU@##linux4251,10.29.107.143,WIC,DEN01
##@NIBU@##linux4252,10.70.2.96,WIC,DEN06
##@NIBU@##linux4253,10.70.2.97,WIC,DEN06
##@NIBU@##linux4254,10.70.2.98,WIC,DEN06
##@NIBU@##linux4255,10.70.2.99,WIC,DEN06
##@NIBU@##linux4256,10.70.2.100,WIC,DEN06
##@NIBU@##linux4257,10.28.107.165,WIC,ATL01
##@NIBU@##linux4258,10.28.107.166,WIC,ATL01
##@NIBU@##linux4259,10.28.107.167,WIC,ATL01
##@NIBU@##linux426,10.27.193.129,ITC,OMA00
##@NIBU@##linux4260,10.28.107.168,WIC,ATL01
##@NIBU@##linux4261,10.28.107.169,WIC,ATL01
##@NIBU@##linux4262,10.28.107.170,WIC,ATL01
##@NIBU@##linux4263,10.28.107.171,WIC,ATL01
##@NIBU@##linux4264,10.28.107.172,WIC,ATL01
##@NIBU@##linux4265,10.28.107.173,WIC,ATL01
##@NIBU@##linux4266,10.28.107.174,WIC,ATL01
##@NIBU@##linux4267,10.28.107.175,WIC,ATL01
##@NIBU@##linux4268,10.28.107.176,WIC,ATL01
##@NIBU@##linux4269,10.28.107.177,WIC,ATL01
##@NIBU@##linux427,10.27.193.144,ITC,OMA00
##@NIBU@##linux4270,10.28.107.178,WIC,ATL01
##@NIBU@##linux4271,10.28.107.179,WIC,ATL01
##@NIBU@##linux4272,10.28.107.180,WIC,ATL01
##@NIBU@##linux4273,10.29.107.144,WIC,DEN01
##@NIBU@##linux4274,10.29.107.145,WIC,DEN01
##@NIBU@##linux4275,10.29.107.146 ,WIC,DEN01
##@NIBU@##linux4276,10.29.107.147,WIC,DEN01
##@NIBU@##linux4277,10.29.107.148,WIC,DEN01
##@NIBU@##linux4278,10.29.107.149,WIC,DEN01
##@NIBU@##linux4279,10.29.107.150,WIC,DEN01
##@NIBU@##linux428,10.27.193.145,ITC,OMA00
##@NIBU@##linux4280,10.29.107.151,WIC,DEN01
##@NIBU@##linux4281,10.29.107.152,WIC,DEN01
##@NIBU@##linux4282,10.29.107.153,WIC,DEN01
##@NIBU@##linux4283,10.70.2.101,WIC,DEN06
##@NIBU@##linux4284,10.70.2.102,WIC,DEN06
##@NIBU@##linux4285,10.70.2.103,WIC,DEN06
##@NIBU@##linux4286,10.70.2.104,WIC,DEN06
##@NIBU@##linux4287,10.70.2.105,WIC,DEN06
##@NIBU@##linux4288,10.70.2.106,WIC,DEN06
##@NIBU@##linux4289,10.70.2.107,WIC,DEN06
##@NIBU@##linux429,10.27.193.146,ITC,OMA00
##@NIBU@##linux4290,10.70.2.108,WIC,DEN06
##@NIBU@##linux4291,10.70.2.109,WIC,DEN06
##@NIBU@##linux4292,10.70.2.110,WIC,DEN06
##@NIBU@##linux4293,10.28.107.181,WIC,DEN06
##@NIBU@##linux4294,10.28.107.182,WIC,ATL01
##@NIBU@##linux4295,10.28.107.183,WIC,ATL01
##@NIBU@##linux4296,10.28.107.184,WIC,ATL01
##@NIBU@##linux4297,10.28.107.185,WIC,ATL01
##@NIBU@##linux4298,10.28.107.186,WIC,ATL01
##@NIBU@##linux4299,10.28.107.187,WIC,ATL01
##@NIBU@##linux43,172.30.9.200,EIT,OMA10
##@NIBU@##linux430,10.27.193.147,ITC,OMA00
##@NIBU@##linux4300,10.28.107.188,WIC,DEN06
##@NIBU@##linux4301,10.28.107.189,WIC,DEN06
##@NIBU@##linux4302,10.28.107.190,WIC,DEN06
##@NIBU@##linux4304,10.64.51.124,ITC,SWN01
##@NIBU@##linux4305,75.78.1.204,ITC,SWN01
##@NIBU@##linux4307,75.78.162.97,ITC,DEN06
##@NIBU@##linux4308,10.72.1.112,ITC,DEN06
##@NIBU@##linux4309,10.72.224.41 ,ITC,DEN06
##@NIBU@##linux4310,75.78.162.93,ITC,DEN06
##@NIBU@##linux4311,75.78.162.94,ITC,DEN06
##@NIBU@##linux4312,75.78.162.95,ITC,DEN06
##@NIBU@##linux4313,75.78.162.96,ITC,DEN06
##@NIBU@##linux4314,10.70.2.111,WIC,DEN06
##@NIBU@##linux4315,10.70.2.112,WIC,DEN06
##@NIBU@##linux4316,10.70.2.113,WIC,DEN06
##@NIBU@##linux4317,10.70.2.114,WIC,DEN06
##@NIBU@##linux4318,10.70.2.115,WIC,DEN06
##@NIBU@##linux4319,10.70.2.116,WIC,DEN06
##@NIBU@##linux432,10.27.193.67,ITC,OMA00
##@NIBU@##linux4320,10.70.2.117,WIC,DEN06
##@NIBU@##linux4321,10.70.2.118,WIC,DEN06
##@NIBU@##linux4322,10.70.2.119,WIC,DEN06
##@NIBU@##linux4323,10.70.2.120,WIC,DEN06
##@NIBU@##linux4324,10.70.2.121,WIC,DEN06
##@NIBU@##linux4325,10.70.2.122,WIC,DEN06
##@NIBU@##linux4326,10.70.2.123,WIC,DEN06
##@NIBU@##linux4327,10.70.2.124,WIC,DEN06
##@NIBU@##linux4328,10.64.2.237,ITC,SWN01
##@NIBU@##linux4329,10.64.2.238,ITC,SWN01
##@NIBU@##linux433,10.51.253.74,EIT,OMA11
##@NIBU@##linux4330,10.64.2.239,ITC,SWN01
##@NIBU@##linux4331,10.64.2.240,ITC,SWN01
##@NIBU@##linux4332,10.64.2.241,ITC,SWN01
##@NIBU@##linux4333,10.64.2.242,ITC,SWN01
##@NIBU@##linux4334,10.64.51.125,ITC,SWN01
##@NIBU@##linux4335,10.64.51.126,ITC,SWN01
##@NIBU@##linux4336,10.64.51.127,ITC,SWN01
##@NIBU@##linux4338,10.64.2.243,ITC,SWN01
##@NIBU@##linux4339,10.64.51.128,ITC,SWN01
##@NIBU@##linux434,10.20.56.207,EIT,UNC01
##@NIBU@##linux4340,10.64.51.129,ITC,SWN01
##@NIBU@##linux4341,10.70.2.125,WIC,OMA00
##@NIBU@##linux4342,10.70.2.126,WIC,OMA00
##@NIBU@##linux4343,10.70.2.127,WIC,DEN06
##@NIBU@##linux4344,10.70.2.128,WIC,DEN06
##@NIBU@##linux4345,10.70.2.129,WIC,DEN06
##@NIBU@##linux4346,10.70.2.130,WIC,DEN06
##@NIBU@##linux4347,10.70.2.131,WIC,DEN06
##@NIBU@##linux4348,10.70.2.132,WIC,DEN06
##@NIBU@##linux4349,10.70.2.133,WIC,DEN06
##@NIBU@##linux435,172.30.116.103,WCMG,OMA00
##@NIBU@##linux4350,10.70.2.134,WIC,DEN06
##@NIBU@##linux4351,10.70.2.135,WIC,DEN06
##@NIBU@##linux4352,10.70.2.136,WIC,DEN06
##@NIBU@##linux4353,10.70.2.137,WIC,DEN06
##@NIBU@##linux4354,10.70.2.138,WIC,DEN06
##@NIBU@##linux4358,75.78.1.205,ITC,SWN01
##@NIBU@##linux4359,75.78.1.206,ITC,SWN01
##@NIBU@##linux4360,75.78.1.207,ITC,SWN01
##@NIBU@##linux4361,75.78.1.208,ITC,SWN01
##@NIBU@##Linux4362,172.30.186.39,WIC,OMA10
##@NIBU@##Linux4363,172.30.56.40,WIC,DEN01
##@NIBU@##Linux4364,172.30.56.41,WIC,DEN01
##@NIBU@##linux4365,172.30.56.42,WIC,DEN01
##@NIBU@##Linux4366,172.30.56.43,WIC,DEN01
##@NIBU@##Linux4367,172.30.56.44,WIC,DEN01
##@NIBU@##Linux4368,172.30.56.22,WIC,DEN01
##@NIBU@##Linux4369,172.30.56.25,WIC,DEN01
##@NIBU@##Linux4370,172.30.56.26,WIC,DEN01
##@NIBU@##Linux4371,172.30.56.27,WIC,DEN01
##@NIBU@##Linux4372,172.30.56.32,WIC,DEN01
##@NIBU@##linux438,172.30.75.158,ITC,ATL01
##@NIBU@##Linux4385,10.27.130.100,WIC,OMA00
##@NIBU@##linux4386,10.27.130.101,WIC,OMA10
##@NIBU@##linux4387,10.27.193.52,WIC,OMA00
##@NIBU@##linux4389,10.64.2.245,ITC,SWN01
##@NIBU@##linux439,172.30.75.159,ITC,ATL01
##@NIBU@##linux4390,10.64.2.246,ITC,SWN01
##@NIBU@##linux4391,10.64.2.247,ITC,SWN01
##@NIBU@##linux4392,10.64.2.248,ITC,SWN01
##@NIBU@##linux4393,10.64.2.249,ITC,SWN01
##@NIBU@##linux4394,10.64.2.250,ITC,SWN01
##@NIBU@##linux4395,10.64.2.251,ITC,SWN01
##@NIBU@##linux4396,10.64.2.252,ITC,SWN01
##@NIBU@##linux4397,10.64.2.253,ITC,SWN01
##@NIBU@##linux4398,10.64.51.134,ITC,SWN01
##@NIBU@##linux4399,10.64.15.135,ITC,SWN01
##@NIBU@##linux44,172.30.41.172,EIT,DEN01
##@NIBU@##linux440,172.30.75.160,ITC,ATL01
##@NIBU@##linux4400,10.64.51.136,ITC,SWN01
##@NIBU@##linux4401,10.64.51.137,ITC,SWN01
##@NIBU@##Linux4402,216.57.98.119,WIC,OMA01
##@NIBU@##Linux4403,216.57.98.51,WIC,OMA01
##@NIBU@##Linux4404,216.57.98.52,WIC,OMA01
##@NIBU@##Linux4405,216.57.98.53,WIC,OMA01
##@NIBU@##Linux4406,216.57.102.65,WIC,OMA01
##@NIBU@##Linux4407,216.57.102.66,WIC,OMA01
##@NIBU@##Linux4408,216.57.102.67,WIC,OMA01
##@NIBU@##Linux4409,216.57.102.68,WIC,OMA01
##@NIBU@##linux441,172.30.75.161,ITC,ATL01
##@NIBU@##linux4410,10.27.197.112,WIC,OMA00
##@NIBU@##Linux4411,10.64.49.180,ITC,SWN01
##@NIBU@##linux4412,10.70.71.68,EIT,DEN06
##@NIBU@##linux4415,10.27.197.113,WIC,OMA00
##@NIBU@##linux4416,10.166.168.57,ITC,LON13
##@NIBU@##linux4417,10.166.168.58,ITC,LON13
##@NIBU@##linux4418,10.166.168.59,ITC,LON13
##@NIBU@##linux4419,10.166.168.60,ITC,LON13
##@NIBU@##linux442,10.27.110.80,ITC,OMA00
##@NIBU@##linux4420,10.166.168.61,ITC,LON13
##@NIBU@##linux4421,10.166.168.62,ITC,LON13
##@NIBU@##linux4422,10.166.168.63,ITC,LON13
##@NIBU@##linux4423,10.166.168.64,ITC,LON13
##@NIBU@##linux4424,10.166.168.65,ITC,LON13
##@NIBU@##linux4425,10.166.168.66,ITC,LON13
##@NIBU@##linux4426,10.166.168.67,ITC,LON13
##@NIBU@##linux4427,10.166.168.68,ITC,LON13
##@NIBU@##linux4428,10.166.168.69,ITC,LON13
##@NIBU@##linux4429,10.166.168.70,ITC,LON13
##@NIBU@##linux443,10.27.193.45,WIC,OMA00
##@NIBU@##linux4430,10.166.168.71,ITC,LON13
##@NIBU@##linux4431,10.166.168.72,ITC,LON13
##@NIBU@##linux4432,10.166.168.75,ITC,LON13
##@NIBU@##linux4435,10.166.128.42,WIC,LON13
##@NIBU@##Linux4436,75.78.177.127,WIC,DEN06
##@NIBU@##Linux4437,75.78.177.131,WIC,DEN06
##@NIBU@##linux4440,10.29.107.160,WIC,DEN01
##@NIBU@##linux4441,10.29.107.161,WIC,DEN01
##@NIBU@##linux4442,10.166.136.50,WIC,LON13
##@NIBU@##linux4443,10.166.136.51,WIC,LON13
##@NIBU@##linux4444,10.166.136.52,WIC,LON13
##@NIBU@##linux4445,10.166.136.53,WIC,LON13
##@NIBU@##linux4446,10.166.136.54,WIC,LON13
##@NIBU@##linux4447,10.166.136.55,WIC,LON13
##@NIBU@##linux4448,10.166.136.57,WIC,LON13
##@NIBU@##linux4449,10.166.136.56,WIC,LON13
##@NIBU@##linux4450,10.166.136.58,WIC,LON13
##@NIBU@##linux4451,10.166.136.59,WIC,LON13
##@NIBU@##linux4452,10.166.136.60,WIC,LON13
##@NIBU@##linux4453,10.166.136.61,WIC,LON13
##@NIBU@##linux4454,10.166.136.62,WIC,LON13
##@NIBU@##linux4455,10.166.136.63,WIC,LON13
##@NIBU@##linux4456,10.166.136.64,WIC,LON13
##@NIBU@##linux4457,10.166.136.65,WIC,LON13
##@NIBU@##linux4458,10.166.136.66 ,WIC,LON13
##@NIBU@##linux4459,10.166.136.67,WIC,LON13
##@NIBU@##linux4460,10.166.136.68,WIC,LON13
##@NIBU@##linux4461,10.166.136.69,WIC,LON13
##@NIBU@##linux4462,10.166.136.70,WIC,LON13
##@NIBU@##linux4463,10.166.136.71,WIC,LON13
##@NIBU@##linux4464,10.166.136.72,WIC,LON13
##@NIBU@##linux4465,10.166.136.73,WIC,LON13
##@NIBU@##linux4466,10.166.136.74,WIC,LON13
##@NIBU@##linux4467,10.166.136.75,WIC,LON13
##@NIBU@##linux4468,10.166.136.76,WIC,LON13
##@NIBU@##linux4469,10.166.136.77,WIC,LON13
##@NIBU@##linux447,10.100.0.122,CORP,DEN01
##@NIBU@##linux4470,10.166.136.78,WIC,LON13
##@NIBU@##linux4471,10.166.136.79,WIC,LON13
##@NIBU@##linux4472,10.166.136.80,WIC,LON13
##@NIBU@##linux4473,10.166.136.81,WIC,LON13
##@NIBU@##linux4474,10.166.136.82,WIC,LON13
##@NIBU@##linux4475,10.166.136.83,WIC,LON13
##@NIBU@##linux448,10.100.0.123,CORP,DEN01
##@NIBU@##linux4482,10.72.1.113,ITC,DEN06
##@NIBU@##linux4483,10.72.1.114,ITC,DEN06
##@NIBU@##linux4486,10.64.49.44,ITC,SWN01
##@NIBU@##Linux4487,10.29.107.162,WIC,DEN01
##@NIBU@##Linux4490,10.166.125.54,WIC,LON13
##@NIBU@##Linux4491,10.166.128.43,WIC,LON13
##@NIBU@##linux4492,10.27.1.41,ITC,OMA00
##@NIBU@##Linux4493,10.27.1.41,ITC,OMA00
##@NIBU@##linux4494,10.29.107.111,WIC,DEN01
##@NIBU@##linux4495,10.70.2.71,WIC,OMA00
##@NIBU@##linux4496,10.27.216.239,WIC,OMA00
##@NIBU@##linux4497,10.70.2.141,WIC,DEN06
##@NIBU@##linux4498,10.70.2.142,WIC,DEN06
##@NIBU@##linux4499,10.70.2.143,WIC,DEN06
##@NIBU@##linux45,172.30.1.107,WIC,OMA01
##@NIBU@##linux4540,10.29.107.164,WIC,OMA00
##@NIBU@##linux4541,10.29.107.165,WIC,DEN01
##@NIBU@##Linux4542,10.17.64.58,WIC,OMA10
##@NIBU@##linux4543,10.17.64.59,WIC,OMA10
##@NIBU@##linux4544,10.17.64.60,WIC,OMA10
##@NIBU@##linux4545,10.17.64.65,WIC,OMA10
##@NIBU@##linux4546,10.17.64.66,WIC,OMA10
##@NIBU@##linux4547,10.17.64.67,WIC,OMA10
##@NIBU@##linux4548,10.17.64.72,WIC,OMA10
##@NIBU@##linux4549,10.17.64.73,WIC,OMA10
##@NIBU@##linux4550,10.17.64.74,WIC,OMA10
##@NIBU@##linux4551,10.17.64.79,WIC,OMA10
##@NIBU@##linux4552,10.17.64.56,WIC,OMA10
##@NIBU@##linux4553,10.29.107.174,WIC,DEN01
##@NIBU@##linux4554,10.29.107.175,WIC,DEN01
##@NIBU@##linux4555,10.28.107.191,WIC,ATL01
##@NIBU@##linux4556,10.28.107.192,WIC,ATL01
##@NIBU@##linux4557,10.27.130.19,WIC,OMA00
##@NIBU@##linux4558,10.27.130.20,WIC,OMA00
##@NIBU@##linux4569,10.29.107.166,WIC,DEN01
##@NIBU@##linux4570,10.29.107.167,WIC,DEN01
##@NIBU@##linux4571,10.29.107.168,WIC,DEN01
##@NIBU@##linux4572,10.29.107.169,WIC,DEN01
##@NIBU@##linux4573,10.29.107.170,WIC,DEN01
##@NIBU@##linux4574,10.29.107.171,WIC,DEN01
##@NIBU@##linux4575,10.29.107.172,WIC,DEN01
##@NIBU@##linux4576,10.29.107.173,WIC,DEN01
##@NIBU@##linux4577,10.28.107.196,WIC,ATL01
##@NIBU@##linux4578,10.28.107.197,WIC,ATL01
##@NIBU@##linux4579,10.28.107.198,WIC,ATL01
##@NIBU@##linux4580,10.28.107.199,WIC,ATL01
##@NIBU@##linux4581,10.28.107.200,WIC,ATL01
##@NIBU@##linux4582,10.28.107.201,WIC,ATL01
##@NIBU@##linux4583,10.28.107.202,WIC,ATL01
##@NIBU@##linux4584,10.28.107.203,WIC,ATL01
##@NIBU@##Linux4585,10.27.116.122,EIT,OMA00
##@NIBU@##linux4586,75.78.162.23,WIC,DEN06
##@NIBU@##linux4587,75.78.162.24,WIC,DEN06
##@NIBU@##linux4588,10.64.49.182,ITC,SWN01
##@NIBU@##linux459,172.30.53.73,ITC,DEN01
##@NIBU@##linux4591,10.27.130.15,WIC,OMA00
##@NIBU@##linux4592,10.27.130.16,WIC,OMA00
##@NIBU@##linux4593,10.27.130.18,WIC,OMA00
##@NIBU@##linux4594,10.27.130.17,WIC,OMA00
##@NIBU@##linux4595,10.28.107.206,WIC,ATL01
##@NIBU@##linux4596,10.28.107.207,WIC,ATL01
##@NIBU@##linux4597,10.29.107.176,WIC,DEN01
##@NIBU@##linux4598,10.29.107.177,WIC,DEN01
##@NIBU@##linux460,172.30.53.72,ITC,DEN01
##@NIBU@##linux4600,216.57.109.86,TVX,ATL01
##@NIBU@##linux4601,10.64.2.196,ITC,SWN01
##@NIBU@##linux4602,75.78.1.214,ITC,SWN01
##@NIBU@##linux4603,75.78.1.215,ITC,SWN01
##@NIBU@##linux4604,10.64.51.146,ITC,SWN01
##@NIBU@##linux4605,10.64.51.147,ITC,SWN01
##@NIBU@##linux4606,10.64.51.148,ITC,SWN01
##@NIBU@##linux4607,10.168.216.31,ITC,SIN10
##@NIBU@##linux4608,10.168.216.32,ITC,SIN10
##@NIBU@##linux4609,10.168.216.33,ITC,SIN10
##@NIBU@##linux461,172.30.53.75,ITC,DEN01
##@NIBU@##linux4610,10.168.216.34,ITC,SIN10
##@NIBU@##linux4611,10.168.216.37,ITC,SIN10
##@NIBU@##linux4612,10.168.216.26,ITC,SIN10
##@NIBU@##linux4613,10.168.216.27,ITC,SIN10
##@NIBU@##linux4614,10.168.216.28,ITC,SIN10
##@NIBU@##linux4615,10.168.216.29,ITC,SIN10
##@NIBU@##linux4617,10.168.216.22,ITC,SIN10
##@NIBU@##linux4618,10.168.216.23,ITC,SIN10
##@NIBU@##linux4619,10.168.216.24,ITC,SIN10
##@NIBU@##linux4622,10.27.130.14,WIC,OMA00
##@NIBU@##Linux4623,10.19.112.76,WIC,OMA01
##@NIBU@##Linux4624,10.19.112.77,WIC,OMA01
##@NIBU@##linux4625,10.166.136.90,WIC,LON13
##@NIBU@##linux4626,10.27.130.12,WIC,OMA00
##@NIBU@##linux4627,10.27.130.13,WIC,OMA00
##@NIBU@##linux4628,10.28.106.68,WIC,ATL01
##@NIBU@##linux4629,10.28.106.69,WIC,ATL01
##@NIBU@##linux463,172.30.53.77,ITC,DEN01
##@NIBU@##linux4630,10.28.106.70,WIC,ATL01
##@NIBU@##linux4631,10.28.106.71,WIC,ATL01
##@NIBU@##linux4632,10.28.106.72,WIC,ATL01
##@NIBU@##linux4633,10.28.106.73,WIC,ATL01
##@NIBU@##linux4634,10.28.106.74,WIC,ATL01
##@NIBU@##linux4635,10.28.106.75,WIC,ATL01
##@NIBU@##linux4636,10.28.106.76,WIC,ATL01
##@NIBU@##linux4637,10.28.106.77,WIC,ATL01
##@NIBU@##linux4638,10.28.106.78,WIC,ATL01
##@NIBU@##linux4639,10.70.1.43,WIC,DEN06
##@NIBU@##linux464,172.30.53.76,ITC,DEN01
##@NIBU@##linux4640,10.70.1.44,WIC,DEN06
##@NIBU@##linux4641,10.70.1.45,WIC,DEN06
##@NIBU@##linux4642,10.70.1.46,WIC,DEN06
##@NIBU@##linux4643,10.70.1.47,WIC,DEN06
##@NIBU@##linux4644,10.70.1.48,WIC,DEN06
##@NIBU@##linux4645,10.70.1.49,WIC,DEN06
##@NIBU@##linux4646,10.70.1.50,WIC,DEN06
##@NIBU@##linux4647,10.70.1.51,WIC,DEN06
##@NIBU@##linux4648,10.70.1.52,WIC,DEN06
##@NIBU@##linux4649,10.70.1.53,WIC,DEN06
##@NIBU@##linux465,172.30.53.79,ITC,DEN01
##@NIBU@##linux4650,10.29.105.29,WIC,DEN01
##@NIBU@##linux4651,10.29.105.30,WIC,DEN01
##@NIBU@##linux4652,10.29.105.31,WIC,DEN01
##@NIBU@##linux4653,10.29.105.32,WIC,DEN01
##@NIBU@##linux4654,10.29.105.33,WIC,DEN01
##@NIBU@##linux4655,10.29.105.34,WIC,DEN01
##@NIBU@##linux4656,10.29.105.35,WIC,DEN01
##@NIBU@##linux4657,10.29.105.36,WIC,DEN01
##@NIBU@##linux4658,10.29.105.37,WIC,DEN01
##@NIBU@##linux4659,10.29.105.38,WIC,DEN01
##@NIBU@##linux466,172.30.53.78,ITC,DEN01
##@NIBU@##linux4660,10.29.105.39,WIC,DEN01
##@NIBU@##Linux4661,10.71.114.30,ITC,DEN06
##@NIBU@##Linux4662,10.71.114.31,ITC,DEN06
##@NIBU@##Linux4663,10.71.114.32,ITC,DEN06
##@NIBU@##Linux4664,10.72.10.33,ITC,DEN06
##@NIBU@##Linux4665,10.72.10.34,ITC,DEN06
##@NIBU@##Linux4666,10.72.10.35,ITC,DEN06
##@NIBU@##Linux4667,10.72.10.36,ITC,DEN06
##@NIBU@##Linux4668,10.72.10.37,ITC,DEN06
##@NIBU@##Linux4669,10.72.10.50,ITC,DEN06
##@NIBU@##linux467,172.30.53.81,ITC,DEN01
##@NIBU@##Linux4670,10.72.10.51,ITC,DEN06
##@NIBU@##linux4671,10.166.128.33,WIC,LON13
##@NIBU@##linux4672,10.166.128.51,WIC,LON13
##@NIBU@##Linux4673,10.28.102.48,WIC,ATL01
##@NIBU@##Linux4674,10.28.102.49,WIC,ATL01
##@NIBU@##Linux4675,10.28.102.50,WIC,ATL01
##@NIBU@##Linux4676,10.28.102.51,WIC,ATL01
##@NIBU@##Linux4677,10.28.102.52,WIC,ATL01
##@NIBU@##Linux4678,10.28.102.53,WIC,ATL01
##@NIBU@##Linux4679,10.28.102.54,WIC,ATL01
##@NIBU@##linux468,172.30.53.80,ITC,DEN01
##@NIBU@##Linux4680,10.28.102.55,WIC,ATL01
##@NIBU@##Linux4681,10.28.102.56,WIC,ATL01
##@NIBU@##Linux4682,10.28.102.57,WIC,ATL01
##@NIBU@##Linux4683,10.28.102.58,WIC,ATL01
##@NIBU@##Linux4684,10.28.102.59,WIC,ATL01
##@NIBU@##Linux4685,10.28.102.60,WIC,ATL01
##@NIBU@##Linux4686,10.28.102.61,WIC,ATL01
##@NIBU@##Linux4687,10.28.102.62,WIC,ATL01
##@NIBU@##Linux4688,10.28.102.63,WIC,ATL01
##@NIBU@##Linux4689,10.28.102.64,WIC,ATL01
##@NIBU@##linux469,172.30.53.83,ITC,DEN01
##@NIBU@##Linux4690,10.28.102.65,WIC,ATL01
##@NIBU@##Linux4691,10.28.102.66,WIC,ATL01
##@NIBU@##Linux4692,10.28.102.67,WIC,ATL01
##@NIBU@##Linux4693,10.28.102.68,WIC,ATL01
##@NIBU@##Linux4694,10.28.102.69,WIC,ATL01
##@NIBU@##Linux4695,10.28.102.70,WIC,ATL01
##@NIBU@##Linux4696,10.28.102.71,WIC,ATL01
##@NIBU@##Linux4697,10.28.102.72,WIC,ATL01
##@NIBU@##linux4698,10.17.64.57,WIC,OMA10
##@NIBU@##linux4699,10.17.64.80,WIC,OMA10
##@NIBU@##linux470,172.30.53.82,ITC,DEN01
##@NIBU@##linux4701,10.17.64.86,WIC,OMA10
##@NIBU@##linux4702,10.17.64.87,WIC,OMA10
##@NIBU@##linux4703,10.17.64.88,WIC,OMA10
##@NIBU@##linux4704,10.17.64.93,WIC,OMA10
##@NIBU@##linux4705,10.17.64.94,WIC,OMA10
##@NIBU@##linux4706,10.17.64.95,WIC,OMA10
##@NIBU@##linux4707,10.17.64.114,WIC,OMA10
##@NIBU@##linux4708,10.17.64.115,WIC,OMA10
##@NIBU@##linux4709,10.17.64.116,WIC,OMA10
##@NIBU@##linux471,172.30.53.85,ITC,DEN01
##@NIBU@##linux4710,10.17.64.117,WIC,OMA10
##@NIBU@##linux4711,10.17.64.121,WIC,OMA10
##@NIBU@##linux4712,10.17.64.122,WIC,OMA10
##@NIBU@##linux4713,10.17.64.123,WIC,OMA10
##@NIBU@##linux472,172.30.53.84,ITC,DEN01
##@NIBU@##linux4720,10.27.130.11,WIC,OMA00
##@NIBU@##linux4721,10.27.130.10,WIC,OMA00
##@NIBU@##linux4722,10.27.130.43,WIC,DEN06
##@NIBU@##linux4723,10.70.2.152,WIC,DEN06
##@NIBU@##linux4724,10.70.2.153,WIC,DEN06
##@NIBU@##linux4725,10.70.2.154,WIC,DEN06
##@NIBU@##linux4726,10.70.2.155,WIC,DEN06
##@NIBU@##linux4727,10.70.2.156,WIC,DEN06
##@NIBU@##linux4728,10.70.2.157,WIC,DEN06
##@NIBU@##linux4729,10.70.2.158,WIC,DEN06
##@NIBU@##linux473,172.30.53.87,ITC,DEN01
##@NIBU@##linux4730,10.70.2.159,WIC,DEN06
##@NIBU@##linux4731,10.70.2.160,WIC,DEN06
##@NIBU@##linux4732,10.70.2.161,WIC,DEN06
##@NIBU@##linux4733,10.70.2.162,WIC,DEN06
##@NIBU@##linux4734,10.18.132.126,WIC,OMA11
##@NIBU@##linux4735,10.18.132.127,WIC,OMA11
##@NIBU@##linux4736 ,10.18.132.128,WIC,OMA11
##@NIBU@##linux4737,10.18.132.129,WIC,OMA11
##@NIBU@##linux4738,10.18.132.130,WIC,OMA11
##@NIBU@##linux4739,10.18.132.131,WIC,OMA11
##@NIBU@##linux474,172.30.53.86,ITC,DEN01
##@NIBU@##linux4740,10.18.132.132,WIC,OMA11
##@NIBU@##linux4741,10.18.132.133,WIC,OMA11
##@NIBU@##linux4742,10.18.132.134,WIC,OMA11
##@NIBU@##linux4743,10.18.132.135,WIC,OMA11
##@NIBU@##linux4744,10.18.132.136,WIC,OMA11
##@NIBU@##linux4745,10.18.132.137,WIC,OMA11
##@NIBU@##linux4746,10.18.132.138,WIC,OMA11
##@NIBU@##linux4747,10.18.132.139,WIC,OMA11
##@NIBU@##linux4748,10.18.132.140,WIC,OMA11
##@NIBU@##linux4749,10.18.132.141,WIC,OMA11
##@NIBU@##linux475,172.30.53.89,ITC,DEN01
##@NIBU@##Linux4750,10.28.102.76,WIC,ATL01
##@NIBU@##linux4751,10.27.108.124,EIT,OMA00
##@NIBU@##linux4752,10.70.1.105,EIT,DEN06
##@NIBU@##Linux4753,10.17.125.29,EIT,OMA10
##@NIBU@##Linux4754,10.31.2.104,EIT,PHX01
##@NIBU@##linux4755,10.28.106.93,EIT,ATL01
##@NIBU@##linux4756,10.42.110.25,EIT,SAT01
##@NIBU@##linux4757,10.27.108.126,EIT,OMA00
##@NIBU@##linux4759,10.70.0.14,WIC,DEN06
##@NIBU@##linux476,172.30.53.88,ITC,DEN01
##@NIBU@##linux4760,10.70.0.24,WIC,DEN06
##@NIBU@##linux4761,10.70.0.34,WIC,DEN06
##@NIBU@##linux4762,10.70.0.39,WIC,DEN06
##@NIBU@##linux4766,10.64.2.60,ITC,SWN01
##@NIBU@##Linux4767,10.65.56.26,ITC,SWN01
##@NIBU@##Linux4768,10.65.56.27,ITC,SWN01
##@NIBU@##Linux4769,10.65.56.28,ITC,SWN01
##@NIBU@##Linux477,10.17.61.22,WIC,OMA10
##@NIBU@##Linux4770,10.65.56.29,ITC,SWN01
##@NIBU@##Linux4771,10.65.56.30,ITC,SWN01
##@NIBU@##Linux4772,10.65.56.33,ITC,SWN01
##@NIBU@##Linux4773,10.65.56.34,ITC,SWN01
##@NIBU@##Linux4774,10.65.56.31,ITC,SWN01
##@NIBU@##Linux4775,10.65.56.32,ITC,SWN01
##@NIBU@##Linux4776,10.65.56.37,ITC,SWN01
##@NIBU@##Linux4777,10.65.56.21,ITC,SWN01
##@NIBU@##Linux4778,10.65.56.22,ITC,SWN01
##@NIBU@##Linux4779,10.65.56.23,ITC,SWN01
##@NIBU@##Linux478,10.17.61.23,WIC,OMA10
##@NIBU@##linux4780,10.65.56.24,ITC,SWN01
##@NIBU@##Linux4781,10.65.56.25,ITC,SWN01
##@NIBU@##linux4782,10.65.56.43,ITC,SWN01
##@NIBU@##linux4783,(10.65.56.44,ITC,SWN01
##@NIBU@##linux4784,10.65.56.45,ITC,SWN01
##@NIBU@##linux4785,10.65.56.46,ITC,SWN01
##@NIBU@##linux4786,10.65.56.47,ITC,SWN01
##@NIBU@##linux4787,10.65.56.50,ITC,SWN01
##@NIBU@##linux4788,10.65.56.51,ITC,SWN01
##@NIBU@##linux4789,10.65.56.48,ITC,SWN01
##@NIBU@##Linux479,172.30.10.116,WIC,OMA10
##@NIBU@##linux4790,10.65.56.49,ITC,SWN01
##@NIBU@##linux4791,10.65.56.38,ITC,SWN01
##@NIBU@##linux4792,10.65.56.39,ITC,SWN01
##@NIBU@##linux4793,10.65.56.40,ITC,SWN01
##@NIBU@##linux4794,10.65.56.41,ITC,SWN01
##@NIBU@##linux4795,10.65.56.42,ITC,SWN01
##@NIBU@##linux4796,10.65.56.59,ITC,SWN01
##@NIBU@##linux4797,10.65.56.60,ITC,SWN01
##@NIBU@##linux4798,10.65.56.61,ITC,SWN01
##@NIBU@##linux4799,10.65.56.62,ITC,SWN01
##@NIBU@##Linux480,172.30.10.117,WIC,OMA10
##@NIBU@##linux4800,10.65.56.63,ITC,SWN01
##@NIBU@##linux4801,10.65.56.66,ITC,SWN01
##@NIBU@##linux4802,10.65.56.67,ITC,SWN01
##@NIBU@##linux4803,10.65.56.64,ITC,SWN01
##@NIBU@##linux4804,10.65.56.65,ITC,SWN01
##@NIBU@##linux4805,10.65.56.54,ITC,SWN01
##@NIBU@##linux4806,10.65.56.55,ITC,SWN01
##@NIBU@##linux4807,10.65.56.56,ITC,SWN01
##@NIBU@##linux4808,10.65.56.57,ITC,SWN01
##@NIBU@##linux4809,10.65.56.58,ITC,SWN01
##@NIBU@##Linux4816,10.72.0.61,ITC,DEN06
##@NIBU@##Linux4817,10.72.0.62,ITC,DEN06
##@NIBU@##Linux4818,10.72.0.63,ITC,DEN06
##@NIBU@##Linux4819,10.28.102.77,WIC,ATL01
##@NIBU@##linux482,172.30.10.119,WIC,OMA10
##@NIBU@##Linux4820,10.28.102.78,WIC,ATL01
##@NIBU@##Linux4821,10.29.104.123,WIC,DEN01
##@NIBU@##Linux4822,10.29.104.124,WIC,DEN01
##@NIBU@##linux4823,10.64.51.98,ITC,SWN01
##@NIBU@##linux4824,10.64.51.99,ITC,SWN01
##@NIBU@##linux4825,10.27.131.51,WIC,OMA00
##@NIBU@##linux4826,10.27.131.52,WIC,OMA00
##@NIBU@##linux4827,10.27.131.53,WIC,OMA00
##@NIBU@##linux4828,10.27.131.54,WIC,OMA00
##@NIBU@##Linux483,172.30.53.95,WIC,DEN01
##@NIBU@##Linux485,172.30.39.133,WIC,DEN01
##@NIBU@##Linux486,172.30.39.134,WIC,DEN01
##@NIBU@##linux487,172.30.39.135,WIC,DEN01
##@NIBU@##linux488,172.30.39.136,WIC,DEN01
##@NIBU@##linux489,172.30.116.119,WIC,OMA00
##@NIBU@##linux4891,10.28.107.211,WIC,ATL01
##@NIBU@##linux4892,10.28.107.212,WIC,ATL01
##@NIBU@##linux4893,10.28.107.213,WIC,ATL01
##@NIBU@##linux4894,10.28.107.214,WIC,ATL01
##@NIBU@##linux4895,10.28.107.215,WIC,ATL01
##@NIBU@##linux4896,10.28.107.216,WIC,ATL01
##@NIBU@##linux4897,10.28.107.217,WIC,ATL01
##@NIBU@##linux4898,10.28.107.218,WIC,ATL01
##@NIBU@##linux4899,10.28.107.219,WIC,ATL01
##@NIBU@##linux4900,10.28.107.220,WIC,ATL01
##@NIBU@##linux4901,10.28.107.221,WIC,ATL01
##@NIBU@##linux4902,10.28.107.222,WIC,ATL01
##@NIBU@##linux4903,10.29.107.181,WIC,DEN01
##@NIBU@##linux4904,10.29.107.182,WIC,DEN01
##@NIBU@##linux4905,10.29.107.183,WIC,DEN01
##@NIBU@##linux4906,10.29.107.184,WIC,DEN01
##@NIBU@##linux4907,10.29.107.185,WIC,DEN01
##@NIBU@##linux4908,10.29.107.186,WIC,DEN01
##@NIBU@##linux4909,10.29.107.187,WIC,DEN01
##@NIBU@##linux4910,10.29.107.188,WIC,DEN01
##@NIBU@##linux4911,10.29.107.189,WIC,DEN01
##@NIBU@##linux4912,10.29.107.190,WIC,DEN01
##@NIBU@##linux4913,10.29.107.191,WIC,DEN01
##@NIBU@##linux4914,10.29.107.192,WIC,DEN01
##@NIBU@##linux4915,10.64.51.159,ITC,SWN01
##@NIBU@##linux4916,10.64.2.62,ITC,SWN01
##@NIBU@##linux4917,10.64.2.18,ITC,SWN01
##@NIBU@##linux4918,10.64.2.19,ITC,SWN01
##@NIBU@##linux4919,10.64.51.161,ITC,SWN01
##@NIBU@##linux4920,10.64.51.162,ITC,SWN01
##@NIBU@##linux4921,10.17.66.21,WIC,OMA10
##@NIBU@##linux4922,10.17.66.22,WIC,OMA10
##@NIBU@##linux4923,10.17.66.43,WIC,OMA10
##@NIBU@##linux4924,10.17.66.44,WIC,OMA10
##@NIBU@##linux4925,10.17.66.45,WIC,OMA10
##@NIBU@##linux4926,10.17.66.46,WIC,OMA10
##@NIBU@##linux4927,10.17.66.47,WIC,OMA10
##@NIBU@##linux4928,10.17.66.48,WIC,OMA10
##@NIBU@##linux4929,10.17.66.49,WIC,OMA10
##@NIBU@##linux493,172.30.94.37,WIC,OMA11
##@NIBU@##linux4930,10.17.66.50,WIC,OMA10
##@NIBU@##linux4931,10.17.66.51,WIC,OMA10
##@NIBU@##linux4932,10.17.66.52,WIC,OMA10
##@NIBU@##linux4933,10.17.66.53,WIC,OMA10
##@NIBU@##linux4934,10.17.66.54,WIC,OMA10
##@NIBU@##linux4935,10.17.66.55,WIC,OMA10
##@NIBU@##linux4936,10.17.66.115,WIC,OMA10
##@NIBU@##linux4937,10.17.66.116,WIC,OMA10
##@NIBU@##linux4938,10.17.66.56,WIC,OMA10
##@NIBU@##linux4939,10.17.66.57,WIC,OMA10
##@NIBU@##linux494,linux494,EIT,OMA00
##@NIBU@##linux4940,10.17.66.58,WIC,OMA10
##@NIBU@##linux4941,10.17.66.59,WIC,OMA10
##@NIBU@##linux4942,10.17.66.60,WIC,OMA10
##@NIBU@##linux4943,10.17.66.61,WIC,OMA10
##@NIBU@##linux4944,10.17.66.62,WIC,OMA10
##@NIBU@##linux4945,10.17.66.63,WIC,OMA10
##@NIBU@##linux4946,10.17.66.64,WIC,OMA10
##@NIBU@##linux4947,10.17.66.65,WIC,OMA10
##@NIBU@##linux4948,10.17.66.66,WIC,OMA10
##@NIBU@##linux4949,10.17.66.67,WIC,OMA10
##@NIBU@##linux495,linux495,WIC,OMA00
##@NIBU@##linux4950,10.17.66.68,WIC,OMA10
##@NIBU@##linux4951,10.17.66.69,WIC,OMA10
##@NIBU@##linux4952,10.17.66.70,WIC,OMA10
##@NIBU@##linux4953,10.17.66.71,WIC,OMA10
##@NIBU@##linux4954,10.17.66.72,WIC,OMA10
##@NIBU@##linux4955,10.17.66.73,WIC,OMA10
##@NIBU@##linux4956,10.17.66.74,WIC,OMA10
##@NIBU@##linux4957,10.17.66.75,WIC,OMA10
##@NIBU@##linux4958,10.17.66.76,WIC,OMA10
##@NIBU@##linux4959,10.17.66.77,WIC,OMA10
##@NIBU@##linux4960,10.17.66.78,WIC,OMA10
##@NIBU@##linux4961,10.17.66.79,WIC,OMA10
##@NIBU@##linux4962,10.17.66.80,WIC,OMA10
##@NIBU@##linux4963,10.17.66.81,WIC,OMA10
##@NIBU@##linux4964,10.17.66.82,WIC,OMA10
##@NIBU@##linux4965,10.17.66.83,WIC,OMA10
##@NIBU@##linux498,172.30.92.41,WIC,OMA11
##@NIBU@##linux4991,10.17.66.109,WIC,OMA10
##@NIBU@##linux4992,10.17.66.110,WIC,OMA10
##@NIBU@##linux4993,10.17.66.111,WIC,OMA10
##@NIBU@##linux4994,10.17.66.112,WIC,OMA10
##@NIBU@##linux4995,10.17.66.113,WIC,OMA10
##@NIBU@##linux4996,10.17.66.114,WIC,OMA10
##@NIBU@##linux5000,75.78.176.24,ITC,DEN06
##@NIBU@##linux5001,10.72.10.56,ITC,DEN06
##@NIBU@##linux5002,10.72.10.57,ITC,DEN06
##@NIBU@##linux5003,10.72.10.60,ITC,DEN06
##@NIBU@##linux5004,10.72.10.61,ITC,DEN06
##@NIBU@##linux5005,10.72.10.62,ITC,DEN06
##@NIBU@##linux5006,10.72.10.63,ITC,DEN06
##@NIBU@##linux5007,75.78.176.25,ITC,DEN06
##@NIBU@##linux5008,75.78.176.26,ITC,DEN06
##@NIBU@##linux5009,75.78.176.27,ITC,DEN06
##@NIBU@##linux5010,75.78.176.28,ITC,DEN06
##@NIBU@##linux5011,10.72.20.66,ITC,DEN06
##@NIBU@##linux5012,10.72.20.68,ITC,DEN06
##@NIBU@##linux5013,10.72.20.69,ITC,DEN06
##@NIBU@##linux5014,216.57.109.109,TVX,ATL01
##@NIBU@##linux5015,216.57.109.110,TVX,ATL01
##@NIBU@##linux5016,216.57.109.111,TVX,ATL01
##@NIBU@##linux5017,75.78.102.21,WIC,ATL01
##@NIBU@##linux5018,75.78.102.22,WIC,ATL01
##@NIBU@##linux5019,10.70.71.48,WIC,DEN06
##@NIBU@##linux5020,10.70.71.49,WIC,DEN06
##@NIBU@##linux5021,10.28.107.223,WIC,ATL01
##@NIBU@##linux5022,10.28.107.224,WIC,ATL01
##@NIBU@##linux5023,10.28.107.225,WIC,ATL01
##@NIBU@##linux5024,10.28.107.226,WIC,ATL01
##@NIBU@##linux5025,10.28.107.227,WIC,ATL01
##@NIBU@##linux5026,10.28.107.228,WIC,ATL01
##@NIBU@##linux5027,10.28.107.229,WIC,ATL01
##@NIBU@##linux5028,10.28.107.230,WIC,ATL01
##@NIBU@##linux5029,10.28.107.231,WIC,ATL01
##@NIBU@##linux5030,10.28.107.232,WIC,ATL01
##@NIBU@##linux5031,10.28.107.233,WIC,ATL01
##@NIBU@##linux5032,10.28.107.234,WIC,ATL01
##@NIBU@##linux5033,10.28.107.235,WIC,ATL01
##@NIBU@##linux5034,10.28.107.236,WIC,ATL01
##@NIBU@##linux5035,10.28.107.237,WIC,ATL01
##@NIBU@##linux5036,10.28.107.238,WIC,ATL01
##@NIBU@##linux5037,10.28.107.239,WIC,ATL01
##@NIBU@##linux5038,10.28.107.240,WIC,ATL01
##@NIBU@##linux5039,10.28.107.241,WIC,ATL01
##@NIBU@##linux504,10.27.193.82,WIC,OMA00
##@NIBU@##linux5040,10.28.107.242,WIC,ATL01
##@NIBU@##linux5041,10.28.107.243,WIC,ATL01
##@NIBU@##linux5042,10.28.107.244,WIC,ATL01
##@NIBU@##linux5043,10.28.107.245,WIC,ATL01
##@NIBU@##linux5044,10.28.107.246,WIC,ATL01
##@NIBU@##linux5045,10.28.107.147,WIC,ATL01
##@NIBU@##linux5046,10.17.66.117,WIC,OMA10
##@NIBU@##linux5047,10.64.8.19,ITC,SWN01
##@NIBU@##linux5048,10.64.8.20,ITC,SWN01
##@NIBU@##linux5049,10.27.108.150,WNG,OMA00
##@NIBU@##linux505,10.27.193.83,WIC,OMA00
##@NIBU@##linux5050,10.27.108.151,WNG,OMA00
##@NIBU@##linux5051,10.70.64.208,WNG,DEN06
##@NIBU@##linux5052,10.28.102.81,WNG,ATL01
##@NIBU@##linux5053,10.27.131.55,WIC,OMA00
##@NIBU@##linux5054,10.27.131.56,WIC,OMA00
##@NIBU@##linux5055,10.27.131.57,WIC,OMA00
##@NIBU@##linux5056,10.27.131.58,WIC,OMA00
##@NIBU@##linux5057,10.17.100.78,WIC,OMA10
##@NIBU@##linux5058,10.72.10.58,ITC,DEN06
##@NIBU@##linux5059,10.72.10.59,ITC,DEN06
##@NIBU@##linux506,10.27.193.119,WIC,OMA00
##@NIBU@##linux5060,10.72.20.67,ITC,DEN06
##@NIBU@##linux5061,10.28.107.6,WIC,ATL01
##@NIBU@##linux5062,10.28.107.7,WIC,ATL01
##@NIBU@##linux5063,10.28.107.8,WIC,ATL01
##@NIBU@##linux5064,10.28.107.9,WIC,ATL01
##@NIBU@##linux5065,10.28.107.10,WIC,ATL01
##@NIBU@##linux5066,10.28.107.11,WIC,ATL01
##@NIBU@##linux5067,10.28.107.12,WIC,ATL01
##@NIBU@##linux5068,10.28.107.13,WIC,ATL01
##@NIBU@##linux5069,10.28.107.14,WIC,ATL01
##@NIBU@##linux507,10.27.193.120,WIC,OMA00
##@NIBU@##linux5070,10.28.107.15,WIC,ATL01
##@NIBU@##linux5071,10.28.107.16,WIC,ATL01
##@NIBU@##linux5072,10.28.107.17,WIC,ATL01
##@NIBU@##linux5073,10.28.107.18,WIC,ATL01
##@NIBU@##linux5074,10.28.107.19,WIC,ATL01
##@NIBU@##linux5075,10.28.107.20,WIC,ATL01
##@NIBU@##linux5076,10.28.107.148,WIC,ATL01
##@NIBU@##linux5077,10.28.107.149,WIC,ATL01
##@NIBU@##linux5078,10.28.107.159,WIC,ATL01
##@NIBU@##linux5079,10.28.107.160,WIC,ATL01
##@NIBU@##linux5080,10.28.107.193,WIC,ATL01
##@NIBU@##linux5081,10.28.107.247,WIC,ATL01
##@NIBU@##linux5082,10.28.107.248,WIC,ATL01
##@NIBU@##linux5083,10.28.107.249,WIC,ATL01
##@NIBU@##linux5084,10.28.107.250,WIC,ATL01
##@NIBU@##linux5085,10.28.107.251,WIC,ATL01
##@NIBU@##linux5086,10.28.107.252,WIC,ATL01
##@NIBU@##linux5087,10.28.114.25,WIC,ATL01
##@NIBU@##linux5088,10.28.114.20,WIC,ATL01
##@NIBU@##linux5089,10.28.114.21,WIC,ATL01
##@NIBU@##linux5090,10.28.114.22,WIC,ATL01
##@NIBU@##linux5091,10.28.114.23,WIC,ATL01
##@NIBU@##linux5092,10.28.114.24,WIC,ATL01
##@NIBU@##linux5093,10.28.107.253,WIC,ATL01
##@NIBU@##linux5094,75.78.1.226,ITC,SWN01
##@NIBU@##linux5095,75.78.1.227,ITC,SWN01
##@NIBU@##linux5097,10.64.51.164,ITC,SWN01
##@NIBU@##linux5098,10.64.51.176,ITC,SWN01
##@NIBU@##linux5099,10.64.51.177,ITC,SWN01
##@NIBU@##linux5100,10.64.51.178,ITC,SWN01
##@NIBU@##linux5102,10.64.2.20,ITC,SWN01
##@NIBU@##linux5103,10.166.232.25,ITC,LON13
##@NIBU@##linux5104,10.70.2.59,WIC,DEN01
##@NIBU@##linux5105,10.28.114.26,WIC,ATL01
##@NIBU@##linux5109,10.17.66.119,WIC,OMA00
##@NIBU@##linux5123,10.166.136.100,WIC,LON13
##@NIBU@##linux5126,10.19.124.28,CORP,OMA01
##@NIBU@##linux5131,10.29.107.193,WIC,DEN01
##@NIBU@##linux5132,10.29.107.194,WIC,DEN01
##@NIBU@##linux5133,10.29.107.195,WIC,DEN01
##@NIBU@##linux5134,10.29.107.196,WIC,DEN01
##@NIBU@##linux5135,10.29.107.197,WIC,DEN01
##@NIBU@##linux5136,10.29.107.198,WIC,DEN01
##@NIBU@##linux5137,10.29.107.199,WIC,DEN01
##@NIBU@##linux5138,10.29.107.200,WIC,DEN01
##@NIBU@##linux5139,10.29.107.201,WIC,DEN01
##@NIBU@##linux5140,10.29.107.202,WIC,DEN01
##@NIBU@##linux5141,10.29.107.203,WIC,DEN01
##@NIBU@##linux5142,10.29.107.204,WIC,DEN01
##@NIBU@##linux5143,10.29.107.205,WIC,DEN01
##@NIBU@##linux5144,10.29.107.206,WIC,DEN01
##@NIBU@##linux5145,10.29.107.207,WIC,DEN01
##@NIBU@##linux5146,10.29.107.208,WIC,DEN01
##@NIBU@##linux5147,10.29.107.209,WIC,DEN01
##@NIBU@##linux5148,10.28.114.27,WIC,ATL01
##@NIBU@##linux5149,10.28.114.28,WIC,ATL01
##@NIBU@##linux5150,10.28.114.29,WIC,ATL01
##@NIBU@##linux5151,10.28.114.30,WIC,ATL01
##@NIBU@##linux5152,10.28.114.31,WIC,ATL01
##@NIBU@##linux5153,10.28.114.32,WIC,ATL01
##@NIBU@##linux5154,10.28.114.33,WIC,ATL01
##@NIBU@##linux5155,10.28.114.34,WIC,ATL01
##@NIBU@##linux5156,10.28.114.35,WIC,ATL01
##@NIBU@##linux5157,10.27.131.62,WIC,OMA00
##@NIBU@##linux5158,10.17.66.121,WIC,OMA10
##@NIBU@##linux5159,10.17.66.122,WIC,OMA10
##@NIBU@##linux516,172.30.78.2,WBS,ATL01
##@NIBU@##linux5160,10.17.66.123,WIC,OMA10
##@NIBU@##linux5161,10.70.2.170,WIC,DEN06
##@NIBU@##linux5162,10.70.2.171,WIC,DEN06
##@NIBU@##linux5163,10.70.2.172,WIC,DEN06
##@NIBU@##linux5164,10.70.2.173,WIC,DEN06
##@NIBU@##linux5165,10.70.2.174,WIC,DEN06
##@NIBU@##linux5166,10.70.2.175,WIC,DEN06
##@NIBU@##linux5167,10.70.2.176,WIC,DEN06
##@NIBU@##linux5168,10.70.2.177,WIC,DEN06
##@NIBU@##linux5169,10.70.2.178,WIC,DEN06
##@NIBU@##linux517,10.18.121.58,WCMG,OMA11
##@NIBU@##linux5170,10.70.2.179,WIC,DEN06
##@NIBU@##linux5171,10.70.2.180,WIC,DEN06
##@NIBU@##linux5172,10.70.2.181,WIC,DEN06
##@NIBU@##linux5173,10.70.2.182,WIC,DEN06
##@NIBU@##linux5174,10.70.2.183,WIC,DEN06
##@NIBU@##linux5175,10.70.2.184,WIC,DEN06
##@NIBU@##linux5176,10.70.2.185,WIC,DEN06
##@NIBU@##linux5177,10.70.2.186,WIC,DEN06
##@NIBU@##linux5178,216.57.109.113,WIC,ATL01
##@NIBU@##linux5179,10.62.2.196,ITC,WPT03
##@NIBU@##linux5184,10.27.131.61,WIC,OMA00
##@NIBU@##linux5185,216.57.109.114,WNG,ATL01
##@NIBU@##linux5186,216.57.109.115,WNG,ATL01
##@NIBU@##linux5188,10.70.64.221,WNG,DEN06
##@NIBU@##linux519,172.30.56.30,WIC,DEN01
##@NIBU@##linux5190,10.29.107.252,WIC,DEN06
##@NIBU@##linux5191,10.28.114.36,WIC,ATL01
##@NIBU@##linux5192,10.28.114.37,WIC,ATL01
##@NIBU@##linux5193,10.27.130.2,WIC,OMA00
##@NIBU@##linux5194,10.27.130.3,WIC,OMA00
##@NIBU@##linux5195,10.50.191.241,WIC,OMA00
##@NIBU@##linux5196,10.18.132.144,WIC,OMA11
##@NIBU@##linux5197,10.17.66.124,WIC,OMA10
##@NIBU@##linux5198,10.17.66.125,WIC,OMA10
##@NIBU@##linux5199,10.17.66.126,WIC,OMA10
##@NIBU@##linux5200,10.64.55.52 ,ITC,SWN01
##@NIBU@##linux5201,10.64.55.53,ITC,SWN01
##@NIBU@##linux5202,10.64.55.54,ITC,SWN01
##@NIBU@##linux5203,10.64.55.55,ITC,SWN01
##@NIBU@##linux5204,10.27.131.63,WIC,OMA10
##@NIBU@##linux5205,10.17.66.127,WIC,OMA10
##@NIBU@##linux5206,10.17.66.128,WIC,OMA10
##@NIBU@##linux5207,10.17.66.129,WIC,OMA10
##@NIBU@##linux5208,10.17.66.130,WIC,OMA10
##@NIBU@##linux5209,10.17.66.131,WIC,OMA10
##@NIBU@##linux521,10.29.115.105,WIC,DEN01
##@NIBU@##linux5210,10.17.66.132,WIC,OMA10
##@NIBU@##linux5211,10.17.66.133,WIC,OMA10
##@NIBU@##linux5212,10.17.66.134,WIC,OMA10
##@NIBU@##linux5213,10.17.66.135,WIC,OMA10
##@NIBU@##linux5214,10.17.66.136,WIC,OMA10
##@NIBU@##linux5215,10.28.106.104,WNG,ATL01
##@NIBU@##linux5216,10.28.106.105,WNG,ATL01
##@NIBU@##linux5217,10.28.106.106,WNG,ATL01
##@NIBU@##linux522,172.30.8.242,WIC,OMA10
##@NIBU@##linux5220,10.64.51.186,ITC,SWN01
##@NIBU@##Linux5221,10.31.72.94,ITC,PHX01
##@NIBU@##Linux5222,10.28.168.56,ITC,ATL01
##@NIBU@##Linux5223,10.27.220.75,ITC,OMA00
##@NIBU@##Linux5224,10.27.126.40,WIC,OMA00
##@NIBU@##Linux5225,10.17.125.79,WIC,OMA10
##@NIBU@##Linux5226,10.70.1.95,WIC,DEN06
##@NIBU@##Linux5227,10.28.102.82,WIC,ATL01
##@NIBU@##linux5228,10.17.66.137,WIC,OMA10
##@NIBU@##linux5229,10.17.66.138,WIC,OMA10
##@NIBU@##linux523,172.30.152.27,WIC,OMA01
##@NIBU@##linux5230,10.28.107.27,WIC,ATL01
##@NIBU@##linux5231,10.28.107.28,WIC,ATL01
##@NIBU@##linux5232,10.70.2.72,WIC,DEN06
##@NIBU@##linux5233,10.70.2.73,WIC,ATL01
##@NIBU@##linux5234,10.17.66.120,WIC,OMA10
##@NIBU@##linux5235,10.27.131.65,WIC,OMA00
##@NIBU@##linux5236,10.27.131.66,WIC,OMA00
##@NIBU@##linux5237,10.27.131.69,WIC,OMA00
##@NIBU@##linux5238,10.29.107.210,WIC,DEN01
##@NIBU@##linux5239,10.29.107.211,WIC,DEN01
##@NIBU@##linux524,172.30.10.46,WIC,OMA10
##@NIBU@##linux5240,10.29.107.212,WIC,DEN01
##@NIBU@##linux5241,10.29.107.213,WIC,DEN01
##@NIBU@##linux5242,10.29.107.214,WIC,DEN01
##@NIBU@##linux5243,10.29.107.215,WIC,DEN01
##@NIBU@##linux5244,10.29.107.216,WIC,DEN01
##@NIBU@##linux5245,10.29.107.217,WIC,DEN01
##@NIBU@##linux5246,10.29.107.218,WIC,DEN01
##@NIBU@##linux5247,10.29.107.219,WIC,DEN01
##@NIBU@##linux5248,10.29.107.220,WIC,DEN01
##@NIBU@##linux5249,10.29.107.221,WIC,DEN01
##@NIBU@##linux525,172.30.10.47,WIC,OMA10
##@NIBU@##linux5250,10.17.66.139,WIC,OMA10
##@NIBU@##linux5251,10.17.66.140,WIC,OMA10
##@NIBU@##linux5252,10.17.66.141,WIC,OMA10
##@NIBU@##Linux5253,10.72.1.116,ITC,DEN06
##@NIBU@##Linux5254,10.27.35.18,ITC,OMA00
##@NIBU@##Linux5255,10.64.49.183,ITC,SWN01
##@NIBU@##Linux5256,10.64.49.184,ITC,SWN01
##@NIBU@##linux5257,10.27.131.68,WIC,OMA00
##@NIBU@##linux5258,10.27.131.69,WIC,OMA00
##@NIBU@##linux5259,10.27.131.70,WIC,OMA00
##@NIBU@##linux5260,10.18.132.145,WIC,OMA11
##@NIBU@##linux5261,10.18.132.146,WIC,OMA11
##@NIBU@##linux5262,10.18.132.147,WIC,OMA11
##@NIBU@##linux5263,10.27.197.220,WIC,OMA00
##@NIBU@##linux5264,10.27.197.221,WIC,OMA00
##@NIBU@##linux5265,10.27.197.222,WIC,OMA00
##@NIBU@##Linux5266,10.70.2.204,WIC,DEN06
##@NIBU@##Linux5267,10.70.2.205,WIC,DEN06
##@NIBU@##linux5268,10.27.131.71,WIC,OMA00
##@NIBU@##linux5269,10.27.197.223,WIC,OMA00
##@NIBU@##linux527,linux527,WIC,OMA00
##@NIBU@##linux5270,10.18.132.148,WIC,OMA00
##@NIBU@##linux5274,10.28.107.141,WIC,ATL01
##@NIBU@##linux5275,10.28.107.142,WIC,ATL01
##@NIBU@##linux5276,10.28.107.143,WIC,ATL01
##@NIBU@##linux5277,10.28.107.144,WIC,ATL01
##@NIBU@##linux5278,10.29.107.222,WIC,DEN01
##@NIBU@##linux5279,10.29.107.223,WIC,DEN01
##@NIBU@##linux528,172.30.10.49,WIC,OMA10
##@NIBU@##linux5280,10.29.107.224,WIC,DEN01
##@NIBU@##linux5281,10.29.107.225,WIC,DEN01
##@NIBU@##linux5282,10.29.107.226,WIC,DEN01
##@NIBU@##linux5283,10.17.66.142,WIC,OMA10
##@NIBU@##linux5284,10.17.66.143,WIC,OMA10
##@NIBU@##linux5285,75.78.177.64,WIC,DEN06
##@NIBU@##linux5286,75.78.177.65,WIC,DEN06
##@NIBU@##linux529,172.30.1.205,WIC,OMA01
##@NIBU@##linux5291,75.78.177.29,WIC,DEN06
##@NIBU@##linux5292,75.78.177.30,WIC,DEN06
##@NIBU@##linux5293,75.78.177.67,WIC,DEN06
##@NIBU@##linux5294,75.78.177.66,WIC,DEN06
##@NIBU@##linux5295,10.70.2.187,WIC,DEN06
##@NIBU@##linux5296,10.70.2.188,WIC,DEN06
##@NIBU@##linux5298,10.166.136.101,WIC,LON13
##@NIBU@##Linux531,10.29.115.119,WIC,DEN01
##@NIBU@##linux5311,10.27.68.190,WIC,OMA00
##@NIBU@##linux5312,10.27.68.191,WIC,OMA01
##@NIBU@##linux5313,10.64.8.4,ITC,SWN01
##@NIBU@##linux5314,10.64.8.5,ITC,SWN01
##@NIBU@##linux5315,10.64.8.6,ITC,SWN01
##@NIBU@##linux5316,10.64.8.7,ITC,SWN01
##@NIBU@##linux5317,10.64.8.8,ITC,SWN01
##@NIBU@##linux5318,10.64.8.9,ITC,SWN01
##@NIBU@##linux5321,10.166.136.102,WIC,LON13
##@NIBU@##linux5323,75.78.177.31,WIC,DEN06
##@NIBU@##linux5324,75.78.177.32,WIC,DEN06
##@NIBU@##linux5325,10.70.2.189,WIC,DEN06
##@NIBU@##linux5326,10.70.2.190,WIC,DEN06
##@NIBU@##linux5327,10.70.2.191,WIC,DEN06
##@NIBU@##linux5328,10.70.2.192,WIC,DEN06
##@NIBU@##linux5329,10.70.2.193,WIC,DEN06
##@NIBU@##linux5330,10.70.2.194,WIC,DEN06
##@NIBU@##linux5333,10.28.107.21,WIC,ATL01
##@NIBU@##linux5334,10.28.107.22,WIC,ATL01
##@NIBU@##linux5335,10.28.107.23,WIC,ATL01
##@NIBU@##linux5336,10.28.107.24,WIC,ATL01
##@NIBU@##linux5337,10.28.107.25,WIC,ATL01
##@NIBU@##linux5338,10.28.107.26,WIC,ATL01
##@NIBU@##linux5346,10.17.66.145,WIC,OMA10
##@NIBU@##linux5347,10.29.107.228,WIC,DEN01
##@NIBU@##linux5348,10.29.107.229,WIC,DEN01
##@NIBU@##linux5349,10.17.66.146,WIC,OMA10
##@NIBU@##linux5350,10.17.66.147,WIC,OMA10
##@NIBU@##linux5351,10.28.226.26,WIC,ATL01
##@NIBU@##linux5352,10.28.226.27,WIC,ATL01
##@NIBU@##linux5353,10.28.226.28,WIC,ATL01
##@NIBU@##linux5354,10.28.226.29,WIC,ATL01
##@NIBU@##linux5355,10.28.226.30,WIC,ATL01
##@NIBU@##linux5356,10.28.226.31,WIC,ATL01
##@NIBU@##linux5357,10.28.226.32,WIC,ATL01
##@NIBU@##linux5358,10.29.99.203,WIC,DEN01
##@NIBU@##linux5359,10.29.99.207,WIC,DEN01
##@NIBU@##linux5360,10.29.99.211,WIC,DEN01
##@NIBU@##linux5361,10.29.99.213,WIC,DEN01
##@NIBU@##linux5362,10.29.99.235,WIC,DEN01
##@NIBU@##linux5363,10.29.99.236,WIC,DEN01
##@NIBU@##linux5364,10.29.99.245,WIC,DEN01
##@NIBU@##linux5365,10.70.230.26,WIC,DEN06
##@NIBU@##linux5366,10.70.230.27,WIC,DEN06
##@NIBU@##linux5367,10.70.230.28,WIC,DEN06
##@NIBU@##linux5368,10.70.230.29,WIC,DEN06
##@NIBU@##linux5369,10.70.230.30,WIC,DEN06
##@NIBU@##linux5370,10.70.230.31,WIC,DEN06
##@NIBU@##linux5371,10.70.230.32,WIC,DEN06
##@NIBU@##linux5372,75.78.177.62,WIC,DEN06
##@NIBU@##Linux5373,10.70.1.63,WIC,DEN06
##@NIBU@##Linux5374,10.70.1.64,WIC,DEN06
##@NIBU@##Linux5375,10.70.1.65,WIC,DEN06
##@NIBU@##Linux5376,10.70.1.66,WIC,DEN06
##@NIBU@##Linux5377,10.70.1.67,WIC,DEN06
##@NIBU@##Linux5378,10.70.1.68,WIC,DEN06
##@NIBU@##Linux5379,10.70.1.69,WIC,DEN06
##@NIBU@##Linux5380,10.70.1.70,WIC,DEN06
##@NIBU@##Linux5381,10.70.1.71,WIC,DEN06
##@NIBU@##Linux5382,10.70.1.72,WIC,DEN06
##@NIBU@##Linux5383,10.70.1.77,WIC,DEN06
##@NIBU@##Linux5384,10.70.1.78,WIC,DEN06
##@NIBU@##Linux5385,10.70.1.79,WIC,DEN06
##@NIBU@##Linux5386,10.70.1.80,WIC,DEN06
##@NIBU@##Linux5387,10.70.1.81,WIC,DEN06
##@NIBU@##Linux5388,10.70.1.82,WIC,DEN06
##@NIBU@##Linux5389,10.70.1.83,WIC,DEN06
##@NIBU@##linux539,10.29.115.106,WIC,DEN01
##@NIBU@##Linux5390,10.70.1.84,WIC,DEN06
##@NIBU@##Linux5391,10.70.1.85,WIC,DEN06
##@NIBU@##Linux5392,10.70.1.86,WIC,DEN06
##@NIBU@##linux5393,10.29.110.74,WNG,DEN01
##@NIBU@##linux5394,10.29.110.75,WNG,DEN01
##@NIBU@##linux5395,10.29.110.76,WNG,DEN01
##@NIBU@##linux5398,10.17.66.150,WIC,OMA10
##@NIBU@##linux5399,10.17.66.151,WIC,OMA10
##@NIBU@##linux540,10.29.115.107,WIC,DEN01
##@NIBU@##linux5400,10.17.66.152,WIC,OMA10
##@NIBU@##linux5401,10.17.66.153,WIC,OMA10
##@NIBU@##linux5402,10.17.66.154,WIC,OMA10
##@NIBU@##linux5403,10.17.66.155,WIC,OMA10
##@NIBU@##linux5404,10.17.66.156,WIC,OMA10
##@NIBU@##linux5405,10.17.66.157,WIC,OMA10
##@NIBU@##linux5406,10.70.2.195,WIC,DEN06
##@NIBU@##linux5407,10.70.2.196,WIC,DEN06
##@NIBU@##linux5408,10.70.2.197,WIC,DEN06
##@NIBU@##linux5409,10.70.2.198,WIC,DEN06
##@NIBU@##linux541,10.29.115.108,WIC,DEN01
##@NIBU@##linux5410,10.70.2.199,WIC,DEN06
##@NIBU@##linux5411,10.70.2.200,WIC,DEN06
##@NIBU@##linux5412,10.70.2.201,WIC,DEN06
##@NIBU@##linux5414,10.70.2.203,WIC,DEN06
##@NIBU@##linux5419,10.17.66.164,WIC,OMA10
##@NIBU@##linux5421,10.168.200.203,ITC,SIN04
##@NIBU@##linux5422,10.168.200.208,ITC,SIN04
##@NIBU@##linux5423,10.168.200.204,ITC,SIN04
##@NIBU@##linux5424,10.168.200.209,ITC,SIN04
##@NIBU@##linux5425,10.168.200.205,ITC,SIN04
##@NIBU@##linux5426,10.168.200.200,ITC,SIN04
##@NIBU@##linux5427,10.168.200.206,ITC,SIN04
##@NIBU@##linux5428,10.168.200.201,ITC,SIN04
##@NIBU@##linux5429,10.168.200.207,ITC,SIN04
##@NIBU@##linux5430,10.168.200.202,ITC,SIN04
##@NIBU@##linux5433,75.78.200.50,ITC,SIN10
##@NIBU@##linux5434,75.78.200.51,ITC,SIN10
##@NIBU@##linux5435,10.168.120.50,ITC,SIN10
##@NIBU@##linux5436,10.168.120.51,ITC,SIN10
##@NIBU@##linux5437,75.78.200.52,ITC,SIN10
##@NIBU@##linux5438,75.78.200.53,ITC,SIN10
##@NIBU@##linux5439,10.168.120.52,ITC,SIN10
##@NIBU@##linux5440,10.168.120.53,ITC,SIN10
##@NIBU@##linux5441,10.168.120.54,ITC,SIN10
##@NIBU@##linux5442,10.168.120.55,ITC,SIN10
##@NIBU@##linux5443,10.168.237.50,ITC,SIN10
##@NIBU@##linux5444,10.168.237.51,ITC,SIN10
##@NIBU@##linux5445,75.78.192.57,ITC,LON13
##@NIBU@##linux5446,75.78.192.58,ITC,LON13
##@NIBU@##linux5447,10.166.120.50,ITC,LON13
##@NIBU@##linux5448,10.166.120.51,ITC,LON13
##@NIBU@##linux5449,75.78.192.59,ITC,LON13
##@NIBU@##linux545,172.30.42.164,WIC,DEN01
##@NIBU@##linux5450,75.78.192.60,ITC,LON13
##@NIBU@##linux5451,10.166.120.52,ITC,LON13
##@NIBU@##linux5452,10.166.120.53,ITC,LON13
##@NIBU@##linux5453,10.166.120.54,ITC,LON13
##@NIBU@##linux5454,10.166.120.55,ITC,LON13
##@NIBU@##linux5455,10.166.232.23,ITC,LON13
##@NIBU@##linux5456,10.166.232.24,ITC,LON13
##@NIBU@##linux5457,10.17.100.50,WIC,OMA10
##@NIBU@##linux5458,10.72.8.63,ITC,DEN06
##@NIBU@##linux5459,10.72.8.64,ITC,DEN06
##@NIBU@##linux5460,10.27.107.42,WNG,OMA00
##@NIBU@##linux5461,10.27.107.43,WNG,OMA00
##@NIBU@##linux5462,10.64.2.6,ITC,SWN01
##@NIBU@##linux5463,10.64.2.7,ITC,SWN01
##@NIBU@##linux5464,10.64.2.12,ITC,SWN01
##@NIBU@##linux5465,10.64.51.190,ITC,SWN01
##@NIBU@##linux5466,10.64.51.191,ITC,SWN01
##@NIBU@##linux5467,10.64.2.14,ITC,SWN01
##@NIBU@##linux5468,10.64.2.15,ITC,SWN01
##@NIBU@##linux5469,10.64.2.16,ITC,SWN01
##@NIBU@##linux5470,10.64.2.17,ITC,SWN01
##@NIBU@##linux5471,10.17.66.168,WIC,OMA10
##@NIBU@##linux5473,216.57.102.226,WIC,OMA01
##@NIBU@##linux5474,10.17.66.169,WIC,OMA10
##@NIBU@##linux5475,216.57.109.117,WIC,ATL01
##@NIBU@##linux5476,10.64.2.8,ITC,SWN01
##@NIBU@##linux5477,10.64.54.20,ITC,SWN01
##@NIBU@##linux5478,75.78.1.252,ITC,SWN01
##@NIBU@##linux5480,75.78.1.254,ITC,SWN01
##@NIBU@##linux5481,10.29.110.77,TFCC,DEN06
##@NIBU@##linux5482,10.27.107.79,TFCC,OMA00
##@NIBU@##linux5484,10.27.128.128,WIC,OMA00
##@NIBU@##linux5485,10.27.128.126,WIC,OMA00
##@NIBU@##linux5486,10.27.107.45,WNG,OMA00
##@NIBU@##linux5487,10.27.107.46,WNG,OMA00
##@NIBU@##linux5488,10.27.107.47,WNG,OMA00
##@NIBU@##linux5489,10.17.66.170,WIC,OMA10
##@NIBU@##linux549,172.30.56.33,WIC,DEN01
##@NIBU@##linux5490,10.29.107.158,WIC,OMA10
##@NIBU@##linux5491,10.70.2.145,WIC,DEN06
##@NIBU@##linux5492,10.70.2.146,WIC,DEN06
##@NIBU@##linux5493,10.18.132.149,WIC,OMA11
##@NIBU@##linux5494,10.18.132.150,WIC,OMA11
##@NIBU@##linux5495,10.18.132.151,WIC,OMA11
##@NIBU@##linux5496,10.18.132.152,WIC,OMA11
##@NIBU@##linux5497,10.18.132.153,WIC,OMA11
##@NIBU@##linux5498,10.18.132.154,WIC,OMA11
##@NIBU@##linux5501,10.64.22.91,ITC,SWN01
##@NIBU@##linux5502,10.64.22.92,ITC,SWN01
##@NIBU@##linux5519,10.64.54.24,ITC,SWN01
##@NIBU@##Linux552,172.30.10.31,WIC,OMA10
##@NIBU@##linux5520,10.17.66.171,WIC,OMA10
##@NIBU@##linux5521,75.78.1.19,ITC,SWN01
##@NIBU@##linux5522,75.78.1.20,ITC,SWN01
##@NIBU@##linux5523,75.78.176.100,ITC,DEN06
##@NIBU@##linux5524,75.78.176.101,ITC,DEN06
##@NIBU@##linux5525,75.78.176.102,ITC,DEN06
##@NIBU@##linux5526,75.78.104.40,ITC,SWN01
##@NIBU@##linux5527,75.78.104.41,ITC,SWN01
##@NIBU@##linux5528,75.78.104.42,ITC,SWN01
##@NIBU@##Linux553,172.30.10.12,WIC,OMA10
##@NIBU@##linux5530,10.27.131.75,WIC,OMA00
##@NIBU@##linux5533,10.28.104.52,WNG,SWN01
##@NIBU@##linux5538,10.72.1.117,ITC,SWN01
##@NIBU@##linux5539,10.72.1.118,ITC,SWN01
##@NIBU@##linux5540,10.72.1.119,ITC,SWN01
##@NIBU@##linux5541,10.72.1.120,ITC,SWN01
##@NIBU@##linux5542,75.78.1.11,ITC,SWN01
##@NIBU@##linux5543,75.78.1.12,ITC,SWN01
##@NIBU@##linux5544,10.64.51.156,ITC,SWN01
##@NIBU@##linux5545,75.78.1.13,ITC,SWN01
##@NIBU@##linux5546,75.78.1.14,ITC,SWN01
##@NIBU@##linux5547,10.64.2.24,ITC,SWN01
##@NIBU@##linux5548,10.72.10.38,WIC,DEN06
##@NIBU@##linux5549,75.78.176.90,WNG,DEN06
##@NIBU@##Linux555,172.30.10.13,WIC,OMA10
##@NIBU@##linux5550,75.78.176.91,WNG,DEN06
##@NIBU@##linux5551,75.78.176.92,WNG,DEN06
##@NIBU@##linux5553,75.78.176.94,WNG,DEN06
##@NIBU@##linux5554,75.78.176.95,WNG,DEN06
##@NIBU@##linux5555,10.64.54.25,ITC,SWN01
##@NIBU@##linux5556,10.64.51.157,ITC,SWN01
##@NIBU@##linux5557,10.27.131.77,WIC,OMA00
##@NIBU@##linux5558,10.27.131.78,WIC,OMA00
##@NIBU@##linux5559,10.27.131.79,WIC,OMA00
##@NIBU@##Linux556,172.30.10.14,WIC,OMA10
##@NIBU@##linux5560,10.27.131.80,WIC,OMA00
##@NIBU@##linux5561,10.27.131.81,WIC,OMA00
##@NIBU@##linux5562,10.18.132.155,WIC,OMA11
##@NIBU@##linux5563,"10.18.132,156",WIC,OMA11
##@NIBU@##linux5564,10.63.37.38,ITC,GLC01
##@NIBU@##linux5565,10.63.37.40,ITC,GLC01
##@NIBU@##linux5566,10.63.53.38,ITC,GLC02
##@NIBU@##linux5567,10.63.37.38,ITC,GLC02
##@NIBU@##linux5568,10.27.128.129,WIC,OMA00
##@NIBU@##linux5569,75.78.200.54,ITC,SIN10
##@NIBU@##Linux557,172.30.10.15,WIC,OMA10
##@NIBU@##linux5570,75.78.200.55,ITC,SIN10
##@NIBU@##linux5571,75.78.200.56,ITC,SIN10
##@NIBU@##linux5572,75.78.192.63,ITC,LON13
##@NIBU@##linux5573,75.78.192.64,ITC,LON13
##@NIBU@##linux5574,75.78.192.65,ITC,LON13
##@NIBU@##linux5575,10.17.66.173,WIC,OMA10
##@NIBU@##linux5576,10.18.158.40,WIC,OMA11
##@NIBU@##linux5577,10.18.158.41,WIC,OMA00
##@NIBU@##linux5578,10.18.158.42,WIC,OMA11
##@NIBU@##Linux558,172.30.10.16,WIC,OMA10
##@NIBU@##linux5581,10.64.54.26,ITC,SWN01
##@NIBU@##linux5582,10.64.54.27,ITC,SWN01
##@NIBU@##linux5583,10.27.131.82,WIC,OMA00
##@NIBU@##linux5584,75.78.177.71,WIC,DEN06
##@NIBU@##linux5585,75.78.177.72,WIC,DEN06
##@NIBU@##linux5586,10.70.2.207,WIC,DEN06
##@NIBU@##linux5587,10.7.2.208,WIC,DEN06
##@NIBU@##linux5588,10.70.2.209,WIC,DEN06
##@NIBU@##linux5589,10.70.2.210,WIC,DEN06
##@NIBU@##Linux559,172.30.10.33,WIC,OMA10
##@NIBU@##linux5590,75.78.102.33,WIC,ATL01
##@NIBU@##linux5591,75.78.102.34,WIC,ATL01
##@NIBU@##linux5592,10.28.114.38,WIC,ATL01
##@NIBU@##linux5593,10.28.114.39,WIC,ATL01
##@NIBU@##linux5594,10.28.114.40,WIC,ATL01
##@NIBU@##linux5595,10.28.114.41,WIC,ATL01
##@NIBU@##linux5596,10.64.8.109,WIC,SWN01
##@NIBU@##linux5597,10.17.66.174,WIC,OMA10
##@NIBU@##linux5598,10.29.107.230,WIC,DEN01
##@NIBU@##linux5599,10.64.18.18,ITC,SWN01
##@NIBU@##linux56,172.30.78.156,ITC,ATL01
##@NIBU@##linux560,172.30.10.81,WIC,OMA10
##@NIBU@##linux5600,10.64.18.19,ITC,SWN01
##@NIBU@##linux5602,75.78.1.18,ITC,SWN01
##@NIBU@##linux5603,10.62.223.25,ITC,SYD03
##@NIBU@##linux5604,10.62.223.26,ITC,SYD03
##@NIBU@##linux5605,10.166.168.105,ITC,LON13
##@NIBU@##linux5606,10.166.168.106,ITC,LON13
##@NIBU@##linux5607,10.166.168.107,ITC,LON13
##@NIBU@##linux5608,10.166.168.108,ITC,LON13
##@NIBU@##linux5609,10.166.168.109,ITC,LON13
##@NIBU@##linux561,172.30.10.22,WIC,OMA10
##@NIBU@##linux5610,10.166.168.110,ITC,LON13
##@NIBU@##linux5611,10.166.168.111,ITC,LON13
##@NIBU@##linux5612,10.166.168.112,ITC,LON13
##@NIBU@##linux5613,10.166.168.113,ITC,LON13
##@NIBU@##linux5614,10.166.168.114,ITC,LON13
##@NIBU@##linux5615,10.166.168.115,ITC,LON13
##@NIBU@##linux5616,10.166.168.116,ITC,LON13
##@NIBU@##linux5617,10.166.168.117,ITC,LON13
##@NIBU@##linux5618,10.166.168.118,ITC,LON13
##@NIBU@##linux5619,10.64.18.17,ITC,SWN01
##@NIBU@##linux5620,10.64.54.28,ITC,SWN01
##@NIBU@##linux5621,10.27.131.83,WIC,OMA00
##@NIBU@##linux5626,10.27.197.241,WIC,OMA00
##@NIBU@##linux5627,10.27.197.230,WIC,OMA00
##@NIBU@##linux5628,10.27.197.231,WIC,OMA00
##@NIBU@##linux5629,10.27.197.232,WIC,OMA00
##@NIBU@##linux563,172.30.10.82,WIC,OMA10
##@NIBU@##linux5630,10.27.197.233,WIC,OMA00
##@NIBU@##linux5631,10.27.197.234,WIC,OMA00
##@NIBU@##linux5632,10.27.197.235,WIC,OMA00
##@NIBU@##linux5633,10.27.197.236,WIC,OMA00
##@NIBU@##linux5634,10.27.197.237,WIC,OMA00
##@NIBU@##linux5635,10.27.197.238,WIC,OMA00
##@NIBU@##linux5636,10.27.197.239,WIC,OMA00
##@NIBU@##linux5637,10.27.197.240,WIC,OMA00
##@NIBU@##linux564,172.30.10.83,WIC,OMA10
##@NIBU@##linux5645,216.57.109.118,WIC,ATL01
##@NIBU@##linux5646,216.57.109.119,WIC,ATL01
##@NIBU@##linux5647,216.57.109.120,WIC,ATL01
##@NIBU@##linux5648,216.57.109.121,WIC,ATL01
##@NIBU@##linux5649,216.57.109.122,WIC,ATL01
##@NIBU@##linux565,172.30.10.84,WIC,OMA10
##@NIBU@##linux5650,216.57.109.123,WIC,ATL01
##@NIBU@##linux5651,216.57.109.124,WIC,ATL01
##@NIBU@##linux5653,10.17.66.175,WIC,OMA10
##@NIBU@##linux5654,10.29.107.231,WIC,OMA10
##@NIBU@##linux5657,10.18.132.157,WIC,OMA11
##@NIBU@##linux5658,10.27.197.243,WIC,OMA00
##@NIBU@##linux5659,10.17.66.158,WIC,OMA10
##@NIBU@##linux566,172.30.10.85,WIC,OMA10
##@NIBU@##linux5660,10.17.66.159,WIC,OMA10
##@NIBU@##linux5663,10.72.10.79,EIT,DEN06
##@NIBU@##linux5666,10.64.51.194,ITC,SWN01
##@NIBU@##linux5667,10.64.51.195,ITC,SWN01
##@NIBU@##linux5668,10.64.54.45,ITC,SWN01
##@NIBU@##linux567,172.30.10.24,WIC,OMA10
##@NIBU@##linux5673,10.27.131.97,WIC,OMA00
##@NIBU@##linux5674,10.17.66.177,WIC,OMA00
##@NIBU@##linux5675,10.64.54.46,ITC,SWN01
##@NIBU@##linux5676,10.64.54.47,ITC,SWN01
##@NIBU@##linux5677,10.64.54.48,ITC,SWN01
##@NIBU@##linux5678,10.64.54.49,ITC,SWN01
##@NIBU@##linux5679,10.64.54.50,ITC,SWN01
##@NIBU@##linux568,172.30.184.23,WIC,OMA10
##@NIBU@##linux5680,10.64.54.51,ITC,SWN01
##@NIBU@##linux5681,10.64.51.198,ITC,SWN01
##@NIBU@##linux5682,10.64.51.199,ITC,SWN01
##@NIBU@##linux5683,10.64.51.202,ITC,SWN01
##@NIBU@##linux5684,10.64.51.203,ITC,SWN01
##@NIBU@##linux5685,10.64.51.204,ITC,SWN01
##@NIBU@##linux5686,10.64.51.205,ITC,SWN01
##@NIBU@##linux5687,10.64.51.206,ITC,SWN01
##@NIBU@##linux569,172.30.184.34,WIC,OMA10
##@NIBU@##linux5690,10.27.194.125,WIC,OMA00
##@NIBU@##linux5692,10.64.51.207,ITC,SWN01
##@NIBU@##linux5693,10.64.51.208,ITC,SWN01
##@NIBU@##linux5694,10.72.1.122,ITC,DEN06
##@NIBU@##linux5695,10.72.1.123,ITC,DEN06
##@NIBU@##linux5697,10.27.131.76,WIC,OMA00
##@NIBU@##linux57,172.30.43.151,ITC,DEN01
##@NIBU@##linux570,172.30.184.31,WIC,OMA10
##@NIBU@##Linux5700,10.27.117.85,CORP,OMA00
##@NIBU@##Linux5701,10.27.117.86,CORP,OMA00
##@NIBU@##Linux5702,10.27.117.87,CORP,OMA00
##@NIBU@##Linux5703,10.42.114.60,CORP,SAT01
##@NIBU@##linux5704,10.70.1.103,CORP,DEN06
##@NIBU@##linux5705,10.28.107.39,CORP,ATL01
##@NIBU@##linux5709,75.78.176.29,ITC,DEN06
##@NIBU@##linux571,172.30.186.32,WIC,OMA10
##@NIBU@##linux5710,75.78.176.30,ITC,DEN06
##@NIBU@##linux5711,10.27.197.202,WIC,OMA00
##@NIBU@##linux5712,10.64.51.209,ITC,SWN01
##@NIBU@##linux5713,10.64.51.210,ITC,SWN01
##@NIBU@##linux5714,10.65.77.21,ITC,SWN01
##@NIBU@##linux5715,10.65.77.22,ITC,SWN01
##@NIBU@##linux5716,10.65.77.23,ITC,SWN01
##@NIBU@##linux572,172.30.184.33,WIC,OMA10
##@NIBU@##linux5720,10.65.77.29,ITC,SWN01
##@NIBU@##linux5721,10.65.77.30,ITC,SWN01
##@NIBU@##linux5722,10.65.77.31,ITC,SWN01
##@NIBU@##linux5726,10.27.197.138,WIC,OMA00
##@NIBU@##linux5727,10.28.107.34,WIC,ATL01
##@NIBU@##linux5728,10.28.107.35,WIC,ATL01
##@NIBU@##linux5729,10.28.107.36,WIC,ATL01
##@NIBU@##linux573,172.30.120.16,WIC,OMA10
##@NIBU@##linux5730,10.28.107.37,WIC,ATL01
##@NIBU@##linux5731,10.28.107.38,WIC,ATL01
##@NIBU@##linux5732,10.70.2.75,WIC,DEN06
##@NIBU@##linux5733,10.70.2.76,WIC,DEN06
##@NIBU@##linux5734,10.70.2.77,WIC,DEN06
##@NIBU@##linux5735,10.70.2.78,WIC,DEN06
##@NIBU@##linux5736,10.70.2.79,WIC,DEN06
##@NIBU@##linux5737,10.42.114.62,EIT,SAT01
##@NIBU@##linux5738,10.18.122.77,EIT,OMA11
##@NIBU@##linux5739,75.78.176.87,ITC,DEN06
##@NIBU@##linux574,172.30.120.17,WIC,OMA10
##@NIBU@##linux5741,10.64.2.26,ITC,SWN01
##@NIBU@##linux5742,10.17.66.180,ITC,OMA10
##@NIBU@##linux5743,10.29.110.79,ITC,DEN01
##@NIBU@##linux577,10.19.59.84,WIC,OMA01
##@NIBU@##linux5780,10.17.66.183,WIC,OMA10
##@NIBU@##linux5781,10.17.66.184,WIC,OMA10
##@NIBU@##linux5782,10.17.66.185,WIC,OMA10
##@NIBU@##linux5783,10.17.66.186,WIC,OMA10
##@NIBU@##linux5784,10.17.66.187,WIC,OMA10
##@NIBU@##linux5785,10.17.66.188,WIC,OMA10
##@NIBU@##linux5786,10.17.66.189,WIC,OMA10
##@NIBU@##linux5787,10.17.66.190,WIC,OMA10
##@NIBU@##linux5788,10.17.66.191,WIC,OMA10
##@NIBU@##linux5789,10.17.66.192,WIC,OMA10
##@NIBU@##linux58,172.30.112.151,WIC,OMA00
##@NIBU@##Linux5802,75.78.177.42,EIT,DEN06
##@NIBU@##Linux5803,75.78.177.43,EIT,DEN06
##@NIBU@##Linux582,10.29.115.117,WIC,DEN01
##@NIBU@##linux584,172.30.39.21,WIC,DEN01
##@NIBU@##Linux586,172.30.10.142,WIC,OMA10
##@NIBU@##linux587,172.30.10.144,WIC,OMA10
##@NIBU@##linux588,10.27.193.24,ITC,OMA00
##@NIBU@##linux589,10.27.217.19,ITC,OMA00
##@NIBU@##linux59,10.27.220.46,WIC,OMA00
##@NIBU@##linux590,10.27.193.26,ITC,OMA00
##@NIBU@##linux591,10.27.217.20,ITC,OMA00
##@NIBU@##linux5919,10.27.217.189,WIC,OMA00
##@NIBU@##linux592,10.27.193.28,ITC,OMA00
##@NIBU@##linux593,10.27.193.29,ITC,OMA00
##@NIBU@##linux594,10.27.193.30,ITC,OMA00
##@NIBU@##linux595,10.27.193.31,ITC,OMA00
##@NIBU@##linux596,10.27.217.21,ITC,OMA00
##@NIBU@##linux597,10.27.217.22,ITC,OMA00
##@NIBU@##linux598,10.27.193.34,ITC,OMA00
##@NIBU@##linux599,10.27.193.35,ITC,OMA00
##@NIBU@##linux601,10.18.153.43,WIC,OMA11
##@NIBU@##linux602,10.18.153.44,WIC,OMA11
##@NIBU@##linux603,10.18.153.45,WIC,OMA11
##@NIBU@##linux604,10.18.153.46,WIC,OMA11
##@NIBU@##linux606,10.27.194.55,WIC,OMA00
##@NIBU@##linux607,172.30.10.124,WIC,OMA10
##@NIBU@##linux608,172.30.10.126,WIC,OMA10
##@NIBU@##linux609,172.30.10.128,WIC,OMA10
##@NIBU@##linux610,172.30.126.35,WIC,OMA10
##@NIBU@##linux611,172.30.126.37,WIC,OMA10
##@NIBU@##linux614,172.30.0.12,WIC,OMA01
##@NIBU@##linux615,10.18.153.49,WIC,OMA11
##@NIBU@##linux616,10.18.153.50,WIC,OMA11
##@NIBU@##linux617,10.18.153.51,WIC,OMA11
##@NIBU@##linux618,10.18.153.52,WIC,OMA11
##@NIBU@##linux619,10.18.153.53,WIC,OMA11
##@NIBU@##linux620,10.18.153.54,WIC,OMA11
##@NIBU@##linux621,10.18.153.55,WIC,OMA11
##@NIBU@##linux622,10.18.153.56,WIC,OMA11
##@NIBU@##linux623,172.30.7.166,WIC,OMA10
##@NIBU@##linux624,10.27.194.140,WIC,OMA00
##@NIBU@##linux625,10.27.194.141,WIC,OMA00
##@NIBU@##linux63,172.30.8.122,EIT,OMA10
##@NIBU@##linux64,172.30.78.14,EIT,ATL01
##@NIBU@##linux65,172.30.24.149,EIT,SAT01
##@NIBU@##linux659,10.20.248.20,EIT,TUL01
##@NIBU@##linux66,172.30.41.154,EIT,DEN01
##@NIBU@##linux663,10.29.225.29,WIC,DEN01
##@NIBU@##linux664,10.29.225.30,WIC,DEN01
##@NIBU@##linux665,172.30.126.39,WIC,OMA10
##@NIBU@##linux667,172.30.126.43,WIC,OMA10
##@NIBU@##linux67,172.30.8.159,EIT,OMA10
##@NIBU@##linux68,172.30.0.107,EIT,OMA01
##@NIBU@##Linux680,10.17.61.203,WIC,OMA10
##@NIBU@##Linux681,10.17.61.202,WIC,OMA10
##@NIBU@##Linux682,10.17.61.201,WIC,OMA10
##@NIBU@##Linux683,10.17.61.200,WIC,DEN01
##@NIBU@##linux684,172.30.10.66,WIC,OMA10
##@NIBU@##linux685,172.30.10.67,WIC,OMA10
##@NIBU@##linux686,172.30.10.68,WIC,OMA10
##@NIBU@##linux687,172.30.10.69,WIC,OMA10
##@NIBU@##linux688,172.30.10.70,WIC,OMA10
##@NIBU@##linux69,10.27.193.98,ITC,OMA00
##@NIBU@##linux697,172.30.53.97,WIC,DEN01
##@NIBU@##Linux698,172.30.53.98,WIC,DEN01
##@NIBU@##linux700,172.30.53.100,WIC,DEN01
##@NIBU@##Linux704,10.29.124.28,WIC,DEN01
##@NIBU@##Linux705,10.29.124.29,WIC,DEN01
##@NIBU@##linux706,10.17.59.211,WIC,OMA10
##@NIBU@##linux707,172.30.126.45,WIC,OMA10
##@NIBU@##linux709,10.18.153.75,WIC,OMA11
##@NIBU@##linux71,172.30.94.126,CORP,OMA11
##@NIBU@##linux710,10.18.153.76,WIC,OMA11
##@NIBU@##linux711,10.18.153.77,WIC,OMA11
##@NIBU@##linux712,10.18.153.78,WIC,OMA11
##@NIBU@##linux713,10.18.153.79,WIC,OMA11
##@NIBU@##linux714,10.18.153.80,WIC,OMA11
##@NIBU@##linux715,10.18.153.81,WIC,OMA11
##@NIBU@##linux716,10.18.153.82,WIC,OMA11
##@NIBU@##linux717,10.18.135.40,WIC,OMA11
##@NIBU@##linux718,10.18.135.41,WIC,OMA11
##@NIBU@##linux719,10.18.135.42,WIC,OMA11
##@NIBU@##linux720,10.18.135.43,WIC,OMA11
##@NIBU@##linux721,10.18.135.44,WIC,OMA11
##@NIBU@##linux722,10.18.135.45,WIC,OMA11
##@NIBU@##linux723,10.18.153.83,WIC,OMA11
##@NIBU@##linux724,10.18.153.84,WIC,OMA11
##@NIBU@##linux725,10.18.153.85,WIC,OMA11
##@NIBU@##linux726,10.18.153.86,WIC,OMA11
##@NIBU@##linux727,10.18.153.87,WIC,OMA11
##@NIBU@##linux728,10.18.153.88,WIC,OMA11
##@NIBU@##linux729,10.18.129.53,WIC,OMA11
##@NIBU@##linux730,10.18.129.52,WIC,OMA11
##@NIBU@##linux731,10.18.129.51,WIC,OMA11
##@NIBU@##linux732,10.18.129.55,WIC,OMA11
##@NIBU@##linux733,10.18.129.56,WIC,OMA11
##@NIBU@##linux734,10.18.129.54,WIC,OMA11
##@NIBU@##linux735,207.126.129.60,ITC,SAT01
##@NIBU@##linux736,172.30.9.228,EIT,OMA10
##@NIBU@##linux737,172.30.94.116,EIT,OMA11
##@NIBU@##linux740,10.0.65.82,WIC,SAT01
##@NIBU@##linux742,10.62.10.120,ITC,SWN01
##@NIBU@##linux744,10.18.129.70,WIC,OMA11
##@NIBU@##linux745,10.18.129.71,WIC,OMA11
##@NIBU@##linux747,10.18.129.73,WIC,OMA11
##@NIBU@##linux748,10.18.129.74,WIC,OMA11
##@NIBU@##linux749,10.18.129.75,WIC,OMA11
##@NIBU@##linux750,10.27.193.138,WIC,OMA00
##@NIBU@##linux751,10.29.124.30,WIC,DEN01
##@NIBU@##linux753,172.30.9.242,WIC,OMA10
##@NIBU@##linux754,172.30.9.243,WIC,OMA10
##@NIBU@##linux755,10.29.124.31,WIC,DEN01
##@NIBU@##linux757,172.30.21.102,WIC,SAT01
##@NIBU@##linux758,172.30.21.104,WIC,SAT01
##@NIBU@##linux759,172.30.78.28,WIC,OMA00
##@NIBU@##linux76,10.27.193.104,ITC,OMA00
##@NIBU@##linux760,172.30.78.30,WIC,OMA00
##@NIBU@##linux761,10.27.124.57,WIC,OMA00
##@NIBU@##linux762,172.30.41.143,WIC,DEN01
##@NIBU@##linux764,10.25.152.21,EIT,OMA02
##@NIBU@##linux765,10.18.129.69,WIC,OMA11
##@NIBU@##linux766,10.18.129.81,WIC,OMA11
##@NIBU@##linux767,10.42.122.70,EIT,SAT01
##@NIBU@##linux768,172.30.126.50,WIC,OMA10
##@NIBU@##linux769,172.30.126.51,WIC,OMA10
##@NIBU@##linux77,10.27.193.100,ITC,OMA00
##@NIBU@##linux770,10.24.248.34,EIT,MNL01
##@NIBU@##linux774,10.19.52.144,WIC,OMA01
##@NIBU@##linux775,10.19.52.145,WIC,OMA01
##@NIBU@##linux776,10.19.52.152,WIC,OMA01
##@NIBU@##linux78,10.27.193.101,ITC,OMA00
##@NIBU@##linux780,172.30.114.51,WIC,OMA00
##@NIBU@##linux781,10.19.52.150,WIC,OMA01
##@NIBU@##linux782,10.19.52.151,WIC,OMA01
##@NIBU@##linux783,10.19.52.149,WIC,OMA01
##@NIBU@##linux784,10.19.116.32,ITC,OMA01
##@NIBU@##linux785,10.19.116.34,ITC,OMA01
##@NIBU@##linux786,10.19.116.36,ITC,OMA01
##@NIBU@##linux787,10.19.116.38,ITC,OMA01
##@NIBU@##linux788,10.19.116.40,ITC,OMA01
##@NIBU@##linux789,10.19.116.42,ITC,OMA01
##@NIBU@##linux79,10.27.193.69,ITC,OMA00
##@NIBU@##linux790,10.19.116.44,ITC,OMA01
##@NIBU@##linux791,10.64.16.70,ITC,SWN01
##@NIBU@##linux792,10.64.16.71,ITC,SWN01
##@NIBU@##linux793,10.19.116.46,ITC,OMA01
##@NIBU@##linux794,10.19.116.48,ITC,OMA01
##@NIBU@##linux795,216.57.102.38,ITC,OMA01
##@NIBU@##linux796,216.57.102.39,ITC,OMA01
##@NIBU@##linux797,10.19.116.60,ITC,OMA01
##@NIBU@##linux798,10.19.116.62,ITC,OMA01
##@NIBU@##linux799,10.19.116.64,ITC,OMA01
##@NIBU@##linux800,10.19.116.66,ITC,OMA01
##@NIBU@##linux801,10.19.116.68,ITC,OMA01
##@NIBU@##linux802,10.19.116.70,ITC,OMA01
##@NIBU@##linux803,10.19.116.72,ITC,OMA01
##@NIBU@##linux804,10.19.116.74,ITC,OMA01
##@NIBU@##linux805,10.19.116.76,ITC,OMA01
##@NIBU@##linux806,10.19.116.78,ITC,OMA01
##@NIBU@##linux807,10.19.116.80,ITC,OMA01
##@NIBU@##linux808,10.19.116.82,ITC,OMA01
##@NIBU@##linux809,10.19.116.84,ITC,OMA01
##@NIBU@##linux810,10.19.116.86,ITC,OMA01
##@NIBU@##linux811,10.19.116.88,ITC,OMA01
##@NIBU@##linux812,10.19.116.90,ITC,OMA01
##@NIBU@##linux813,10.19.116.92,ITC,OMA01
##@NIBU@##linux814,10.19.116.94,ITC,OMA01
##@NIBU@##linux815,10.19.116.96,ITC,OMA01
##@NIBU@##linux816,172.30.9.238,ITC,OMA10
##@NIBU@##linux817,172.30.9.239,WIC,OMA10
##@NIBU@##linux818,10.18.129.77,WIC,OMA11
##@NIBU@##linux819,10.18.129.79,WIC,OMA11
##@NIBU@##linux821,10.29.124.43,WIC,DEN01
##@NIBU@##linux824,10.42.116.162,EIT,SAT01
##@NIBU@##linux825,10.27.194.143,WIC,OMA00
##@NIBU@##linux826,10.27.194.144,WIC,OMA00
##@NIBU@##linux827,10.27.194.105,WIC,OMA00
##@NIBU@##linux828,10.18.153.107,WIC,OMA11
##@NIBU@##linux829,10.18.153.108,WIC,OMA11
##@NIBU@##linux83,172.30.1.139,WIC,OMA01
##@NIBU@##linux830,10.18.153.109,WIC,OMA11
##@NIBU@##linux831,10.18.153.118,WIC,OMA11
##@NIBU@##linux832,10.18.153.119,WIC,OMA11
##@NIBU@##linux833,10.18.153.120,WIC,OMA11
##@NIBU@##linux836,10.31.40.55,ITC,PHX01
##@NIBU@##linux837,10.31.40.56,ITC,PHX01
##@NIBU@##linux84,172.30.9.165,WIC,OMA10
##@NIBU@##linux840,10.31.40.45,ITC,PHX01
##@NIBU@##linux841,10.31.40.46,ITC,PHX01
##@NIBU@##linux848,10.19.52.139,WIC,OMA01
##@NIBU@##linux849,10.19.52.140,WIC,OMA01
##@NIBU@##linux850,10.19.52.141,WIC,OMA01
##@NIBU@##linux869,10.42.52.107,EIT,SAT01
##@NIBU@##linux87,172.30.94.1,EIT,OMA11
##@NIBU@##linux870,10.42.52.108,WIC,SAT01
##@NIBU@##linux871,10.42.52.109,WIC,SAT01
##@NIBU@##linux872,10.42.52.110,WIC,SAT01
##@NIBU@##linux873,10.42.52.111,WIC,SAT01
##@NIBU@##linux874,10.42.52.115,WIC,SAT01
##@NIBU@##linux875,10.42.52.116,WIC,SAT01
##@NIBU@##linux876,10.42.52.117,WIC,SAT01
##@NIBU@##linux877,10.42.52.118,WIC,SAT01
##@NIBU@##linux879,10.42.52.120,WIC,SAT01
##@NIBU@##linux880,216.57.108.66,WIC,SAT01
##@NIBU@##linux881,216.57.108.67,WIC,SAT01
##@NIBU@##linux882,216.57.108.68,WIC,SAT01
##@NIBU@##linux883,216.57.108.69,WIC,SAT01
##@NIBU@##linux886,172.30.9.173,ITC,OMA10
##@NIBU@##linux888,10.27.217.43,ITC,OMA00
##@NIBU@##linux890,10.27.217.45,ITC,OMA00
##@NIBU@##linux891,10.27.217.46,ITC,OMA00
##@NIBU@##linux892,10.27.217.47,ITC,OMA00
##@NIBU@##linux893,10.27.217.48,ITC,OMA00
##@NIBU@##linux894,10.27.217.49,ITC,OMA00
##@NIBU@##linux895,10.27.217.50,ITC,OMA00
##@NIBU@##linux896,10.27.217.51,ITC,OMA00
##@NIBU@##linux897,10.27.217.52,ITC,OMA00
##@NIBU@##linux898,10.27.217.53,ITC,OMA00
##@NIBU@##linux899,10.27.217.54,ITC,OMA00
##@NIBU@##linux900,10.27.217.55,ITC,OMA00
##@NIBU@##linux901,10.27.217.56,ITC,OMA00
##@NIBU@##linux902,10.27.217.11,ITC,OMA00
##@NIBU@##linux903,10.27.217.12,ITC,OMA00
##@NIBU@##linux904,10.27.217.13,ITC,OMA00
##@NIBU@##linux905,10.27.217.14,ITC,OMA00
##@NIBU@##linux906,10.28.200.23,ITC,ATL01
##@NIBU@##linux907,10.28.200.24,ITC,ATL01
##@NIBU@##linux908,10.27.214.145,ITC,OMA00
##@NIBU@##linux909,172.30.41.218,WIC,DEN01
##@NIBU@##linux910,172.30.8.243,WIC,OMA10
##@NIBU@##linux911,216.57.106.24,EIT,SAT01
##@NIBU@##linux912,216.57.106.25,EIT,SAT01
##@NIBU@##linux913,216.57.98.32,EIT,OMA01
##@NIBU@##linux914,216.57.98.33,EIT,OMA01
##@NIBU@##linux915,216.57.102.42,EIT,OMA01
##@NIBU@##linux916,216.57.102.43,EIT,OMA01
##@NIBU@##linux917,10.18.153.111,WIC,OMA11
##@NIBU@##linux919,10.27.193.62,WIC,OMA00
##@NIBU@##linux92,10.27.193.59,WIC,OMA00
##@NIBU@##linux920,10.19.52.142,WIC,OMA01
##@NIBU@##linux921,10.29.124.52,WIC,DEN01
##@NIBU@##linux922,172.30.8.231,WIC,OMA10
##@NIBU@##linux923,10.31.40.25,EIT,PHX01
##@NIBU@##linux924,10.31.40.48,EIT,PHX01
##@NIBU@##linux925,10.31.40.28,ITC,PHX01
##@NIBU@##linux926,10.31.40.26,ITC,PHX01
##@NIBU@##linux927,10.31.40.21,ITC,PHX01
##@NIBU@##linux928,10.31.40.22,ITC,PHX01
##@NIBU@##linux929,10.27.220.56,ITC,OMA00
##@NIBU@##linux93,linux93,CORP,OMA00
##@NIBU@##linux930,10.31.40.24,ITC,PHX01
##@NIBU@##linux931,10.31.41.11,ITC,PHX01
##@NIBU@##linux932,10.31.41.12,ITC,PHX01
##@NIBU@##linux933,10.31.41.13,ITC,PHX01
##@NIBU@##linux934,10.31.41.14,ITC,PHX01
##@NIBU@##Linux935,10.31.41.15,ITC,PHX01
##@NIBU@##linux936,10.31.41.43,ITC,PHX01
##@NIBU@##linux937,10.31.41.44,ITC,PHX01
##@NIBU@##linux938,10.31.41.45,ITC,PHX01
##@NIBU@##linux939,10.31.41.46,ITC,PHX01
##@NIBU@##linux940,10.17.52.171,WIC,OMA10
##@NIBU@##linux941,10.17.52.184,WIC,OMA10
##@NIBU@##linux942,10.17.52.172,WIC,OMA10
##@NIBU@##linux943,10.17.52.183,WIC,OMA10
##@NIBU@##linux944,10.17.52.182,WIC,OMA10
##@NIBU@##linux954,10.19.117.88,WIC,OMA01
##@NIBU@##linux966,10.27.124.46,WIC,OMA00
##@NIBU@##LINUX968,10.18.135.46,WIC,OMA11
##@NIBU@##LINUX969,10.18.135.47,WIC,OMA11
##@NIBU@##linux970,172.30.114.79,WIC,OMA00
##@NIBU@##linux971,10.29.96.209,WIC,DEN01
##@NIBU@##linux972,10.29.96.212,WIC,DEN01
##@NIBU@##linux973,10.17.52.178,WIC,OMA10
##@NIBU@##linux974,10.17.53.46,WIC,OMA10
##@NIBU@##linux975,10.19.118.60,WIC,OMA01
##@NIBU@##linux976,10.19.118.64,WIC,OMA01
##@NIBU@##linux977,10.70.0.21,WIC,DEN06
##@NIBU@##linux978,10.70.0.29,WIC,DEN06
##@NIBU@##linux979,10.29.96.206,WIC,DEN01
##@NIBU@##linux980,10.29.96.215,WIC,DEN01
##@NIBU@##linux981,10.29.96.216,WIC,DEN01
##@NIBU@##linux982,10.29.96.217,WIC,DEN01
##@NIBU@##linux983,10.17.52.176,WIC,OMA10
##@NIBU@##linux984,10.19.52.148,WIC,OMA01
##@NIBU@##linux985,10.17.52.177,WIC,OMA10
##@NIBU@##linux986,10.29.96.207,WIC,DEN01
##@NIBU@##linux987,10.27.194.146,WIC,OMA00
##@NIBU@##linux988,10.23.26.35,WBS,SPO01
##@NIBU@##linux998,216.57.102.69,WIC,OMA01
##@NIBU@##linux999,10.19.117.104,WIC,OMA01
##@NIBU@##LMT01VOR03,10.72.10.79,ITC,DEN06
##@NIBU@##mckdev01,10.0.35.14,WBS,OMA11
##@NIBU@##mckdev02,10.0.35.15,WBS,OMA11
##@NIBU@##mum03hmc1,10.112.4.43,ITC,MUM03
##@NIBU@##oma00crfax01,10.27.114.77,EIT,ATL01
##@NIBU@##oma00ds01,10.27.60.133,EIT,OMA00
##@NIBU@##oma00ds02,10.27.60.129,EIT,OMA00
##@NIBU@##OMA00FEX01,10.27.118.24,CORP,OMA00
##@NIBU@##OMA00FIN01,10.27.118.28,CORP,OMA00
##@NIBU@##OMA00FST01,10.27.118.26,CORP,OMA00
##@NIBU@##oma00hmc1,10.27.216.54,WIC,OMA00
##@NIBU@##OMA00HMC3,10.27.129.50,WIC,OMA00
##@NIBU@##OMA00RHEVM01,10.27.108.190,EIT,OMA00
##@NIBU@##OMA10HMC1,10.17.125.38,WNG,OMA10
##@NIBU@##omhadsma,10.15.1.148,WDR,OMA11
##@NIBU@##ops1a,172.30.7.204,CORP,OMA10
##@NIBU@##Q1ATL011605EVP,10.28.107.33,ITC,ATL01
##@NIBU@##Q1DEN061605EVP,10.70.1.100,ITC,DEN06
##@NIBU@##Q1OMA001605EVP,10.27.108.201,ITC,OMA00
##@NIBU@##Q1OMA001705FLW,10.27.108.202,ITC,OMA00
##@NIBU@##Q1OMA003124MGT,10.27.108.203,ITC,OMA00
##@NIBU@##restore,10.62.72.49,ITC,VAL01
##@NIBU@##restore1,172.30.8.167,EIT,OMA10
##@NIBU@##rh_5u1,rh_5u1,EIT,OMA00
##@NIBU@##sahara,10.27.194.31,WIC,OMA00
##@NIBU@##sat01zsametim01,216.57.106.39,ITC,SAT01
##@NIBU@##seafelt1,10.62.16.68,ITC,WPT02
##@NIBU@##spare48,192.168.25.201,WBS,SAT01
##@NIBU@##spare96,192.168.25.197,WBS,SAT01
##@NIBU@##sparems,10.42.118.61,WBS,SAT01
##@NIBU@##sun06,10.20.184.71,WCMG,RFD01
##@NIBU@##sun07,10.20.151.80,WCMG,NLS01
##@NIBU@##sun14,10.27.124.82,EIT,OMA00
##@NIBU@##sun15,10.42.122.87,EIT,SAT01
##@NIBU@##sun16,10.27.124.60,EIT,OMA00
##@NIBU@##sun21,10.28.30.40,WCMG,OMA01
##@NIBU@##SUN22,10.28.102.21,TFCC,ATL01
##@NIBU@##SUN23,10.28.102.27,TFCC,ATL01
##@NIBU@##SUN24,10.28.102.32,TFCC,ATL01
##@NIBU@##SUN25,10.28.102.33,TFCC,ATL01
##@NIBU@##SUN26,10.28.102.36,TFCC,ATL01
##@NIBU@##SUN27,10.28.102.37,TFCC,ATL01
##@NIBU@##SUN28,10.70.64.157,TFCC,DEN06
##@NIBU@##SUN29,10.70.64.163,TFCC,DEN06
##@NIBU@##SUN30,10.70.64.168,TFCC,DEN06
##@NIBU@##SUN31,10.70.64.169,TFCC,DEN06
##@NIBU@##SUN32,10.70.64.172,TFCC,DEN06
##@NIBU@##SUN33,10.70.64.173,TFCC,DEN06
##@NIBU@##sun34,10.27.108.58,TFCC,OMA00
##@NIBU@##Sun35,10.70.72.70,TFCC,DEN06
##@NIBU@##Sun36,75.78.162.75,TFCC,DEN06
##@NIBU@##Sun37,75.78.176.39,TFCC,DEN06
##@NIBU@##Sun40,75.78.176.40,TFCC,DEN06
##@NIBU@##Sun43,75.78.176.41,TFCC,DEN06
##@NIBU@##Sun46,75.78.176.42,TFCC,DEN06
##@NIBU@##Sun53,75.78.176.43,TFCC,DEN06
##@NIBU@##Sun54,na,TFCC,DEN06
##@NIBU@##Sun57,na,TFCC,DEN06
##@NIBU@##Sun60,na,TFCC,DEN06
##@NIBU@##Sun63,na,TFCC,DEN06
##@NIBU@##Sun66,na,TFCC,DEN06
##@NIBU@##Sun69,na,TFCC,DEN06
##@NIBU@##Sun72,na,TFCC,DEN06
##@NIBU@##Sun75,na,TFCC,DEN06
##@NIBU@##Sun78,na,TFCC,DEN06
##@NIBU@##Sun82,10.70.72.75,TFCC,DEN06
##@NIBU@##Sun85,na,TFCC,DEN06
##@NIBU@##Sun88,na,TFCC,DEN06
##@NIBU@##svru343,172.22.107.1,WBS,SPO01
##@NIBU@##svru363,172.22.117.4,WBS,SPO02
##@NIBU@##svru365,172.22.117.6,WBS,SPO02
##@NIBU@##svru381,172.22.147.2,WBS,PAS01
##@NIBU@##swn01_Oracle_APAC_Sep02,10.64.8.18,ITC,SWN01
##@NIBU@##swn01hmc1,10.64.12.22,ITC,SWN01
##@NIBU@##swn01lpar01,10.65.77.43,ITC,SWN01
##@NIBU@##swn01lpar02,10.65.77.44,ITC,SWN01
##@NIBU@##swn01zcrs01,10.64.49.27,ITC,SWN01
##@NIBU@##testaix01,10.62.33.69,ITC,WPT02
##@NIBU@##testaix02,10.62.33.78,ITC,WPT02
##@NIBU@##testaix04,10.62.72.133,ITC,VAL01
##@NIBU@##testaix05,10.62.72.134,ITC,VAL01
##@NIBU@##testaix08,10.62.72.137,ITC,VAL01
##@NIBU@##testaix10,10.62.72.139,ITC,VAL01
##@NIBU@##testexls01,192.168.10.89,ITC,SWN01
##@NIBU@##testexls02,192.168.10.91,ITC,SWN01
##@NIBU@##testls01,10.62.33.233,ITC,WPT02
##@NIBU@##testls02,10.62.33.135,ITC,WPT02
##@NIBU@##testls03,10.62.33.89,ITC,WPT02
##@NIBU@##testls04,10.62.33.121,ITC,WPT02
##@NIBU@##testls05,10.62.33.106,ITC,WPT02
##@NIBU@##testls06,10.62.33.115,ITC,WPT02
##@NIBU@##testls08,10.62.33.180,ITC,WPT02
##@NIBU@##testls09,10.62.33.90,ITC,WPT02
##@NIBU@##testls10,10.62.33.134,ITC,WPT02
##@NIBU@##testls11,10.62.33.125,ITC,WPT02
##@NIBU@##testls12,TESTLS12,ITC,WPT02
##@NIBU@##testls13,TESTLS13,ITC,WPT02
##@NIBU@##testls14,TESTLS14,ITC,WPT02
##@NIBU@##testls15,TESTLS15,ITC,WPT02
##@NIBU@##testls16,10.62.33.110,ITC,WPT02
##@NIBU@##testls17,TESTLS17,ITC,WPT02
##@NIBU@##testls18,10.62.33.146,ITC,WPT02
##@NIBU@##testls19,TESTLS19,ITC,WPT02
##@NIBU@##testls20,10.62.33.20,ITC,WPT02
##@NIBU@##testls21,10.62.33.152,ITC,WPT02
##@NIBU@##testls22,10.62.33.67,ITC,WPT02
##@NIBU@##testls23,10.62.33.153,ITC,WPT02
##@NIBU@##testls24,10.62.33.136,ITC,WPT02
##@NIBU@##testls25,10.62.33.137,ITC,WPT02
##@NIBU@##testls26,10.62.33.143,ITC,WPT02
##@NIBU@##testls27,10.62.33.144,ITC,WPT02
##@NIBU@##testls28,10.62.33.145,ITC,WPT02
##@NIBU@##testls29,10.62.33.68,ITC,WPT02
##@NIBU@##testls30,10.62.33.199,ITC,WPT02
##@NIBU@##testls31,10.62.33.31,ITC,WPT02
##@NIBU@##testls32,10.62.33.155,ITC,WPT02
##@NIBU@##testls33,10.62.33.177,ITC,WPT02
##@NIBU@##testls34,10.62.33.85,ITC,WPT02
##@NIBU@##testls35,10.62.33.45,ITC,WPT02
##@NIBU@##testls36,10.62.33.47,ITC,WPT02
##@NIBU@##testls37,TESTLS37,ITC,WPT02
##@NIBU@##testls38,10.62.33.48,ITC,WPT02
##@NIBU@##testls39,10.62.33.65,ITC,WPT02
##@NIBU@##testls40,10.62.33.17,ITC,WPT02
##@NIBU@##testls41,10.62.33.41,ITC,WPT02
##@NIBU@##testls42,TESTLS42,ITC,WPT02
##@NIBU@##testls43,TESTLS43,ITC,WPT02
##@NIBU@##testls44,TESTLS44,ITC,WPT02
##@NIBU@##testls45,10.62.33.87,ITC,WPT02
##@NIBU@##testls46,10.62.33.156,ITC,WPT02
##@NIBU@##testls47,10.62.33.142,ITC,WPT02
##@NIBU@##testls48,10.62.33.185,ITC,WPT02
##@NIBU@##testls49,10.62.33.186,ITC,WPT02
##@NIBU@##testls50,10.62.33.187,ITC,WPT02
##@NIBU@##testls51,10.62.33.51,ITC,WPT02
##@NIBU@##testls52,10.62.33.52,ITC,WPT02
##@NIBU@##testls53,10.62.33.53,ITC,WPT02
##@NIBU@##testls54,10.62.33.55,ITC,WPT02
##@NIBU@##testls55,10.62.33.21,ITC,WPT02
##@NIBU@##testls56,10.62.33.22,ITC,WPT02
##@NIBU@##testls57,10.62.33.229,ITC,WPT02
##@NIBU@##testls58,10.62.33.195,ITC,WPT02
##@NIBU@##testls59,10.62.33.196,ITC,WPT02
##@NIBU@##testls60,10.62.33.60,ITC,WPT02
##@NIBU@##testls61,10.62.33.61,ITC,WPT02
##@NIBU@##testls62,10.62.33.198,ITC,WPT02
##@NIBU@##testls63,10.62.33.4,ITC,WPT02
##@NIBU@##testls64,10.62.33.5,ITC,WPT02
##@NIBU@##testls65,10.62.33.6,ITC,WPT02
##@NIBU@##testls66,10.62.33.7,ITC,WPT02
##@NIBU@##testls67,10.62.33.8,ITC,WPT02
##@NIBU@##testls72,10.62.33.230,ITC,WPT02
##@NIBU@##testls73,10.62.33.231,ITC,WPT02
##@NIBU@##testls74,10.62.33.10,ITC,WPT02
##@NIBU@##testls75,10.62.33.234,ITC,WPT02
##@NIBU@##testls76,10.62.33.225,ITC,WPT02
##@NIBU@##testls81,10.62.33.159,ITC,WPT02
##@NIBU@##testls82,10.62.33.172,ITC,WPT02
##@NIBU@##testls83,10.62.33.173,ITC,WPT02
##@NIBU@##testls84,10.62.33.204,ITC,WPT02
##@NIBU@##testls85,10.62.33.94,ITC,WPT02
##@NIBU@##TESTLS86,10.62.33.95,ITC,WPT02
##@NIBU@##testls88,10.62.33.238,ITC,WPT02
##@NIBU@##testls89,10.62.33.239,ITC,WPT02
##@NIBU@##testls90,10.62.72.140,ITC,VAL01
##@NIBU@##testls91,10.62.33.228,ITC,WPT02
##@NIBU@##testls92,10.62.33.166,ITC,WPT02
##@NIBU@##testls93,10.62.33.167,ITC,WPT02
##@NIBU@##testls94,10.62.33.150,ITC,WPT02
##@NIBU@##testlt86,TESTLT86,ITC,WPT02
##@NIBU@##testlt87,TESTLT87,ITC,WPT02
##@NIBU@##TESTNT71,10.62.33.126,ITC,WPT02
##@NIBU@##TESTNT72,10.62.33.127,ITC,WPT02
##@NIBU@##TESTNT73,10.62.33.128,ITC,WPT02
##@NIBU@##TESTNT74,10.62.33.129,ITC,WPT02
##@NIBU@##testss01,10.62.33.63,ITC,WPT02
##@NIBU@##testss02,10.62.33.64,ITC,WPT02
##@NIBU@##testss62,TESTSS62,ITC,WPT02
##@NIBU@##testss63,TESTSS63,ITC,WPT02
##@NIBU@##testss64,TESTSS64,ITC,WPT02
##@NIBU@##USATL193,10.28.160.129,ITC,ATL01
##@NIBU@##USTEST193,10.28.160.129,ITC,ATL08
##@NIBU@##Venus,10.184.0.217,ITC,DEN06
##@NIBU@##viper,10.27.194.72,WIC,OMA00
##@NIBU@##vm-linux13,172.30.116.72,WIC,OMA00
##@NIBU@##vm-linux14,172.30.116.71,EIT,OMA00
##@NIBU@##vrmnl01,10.46.1.211,WCMG,MNL01
##@NIBU@##vrmnl02,10.46.1.212,WCMG,MNL01
##@NIBU@##vrmnl03,10.42.1.213,WCMG,MNL01
##@NIBU@##vrmnl04,10.46.1.214,WCMG,MNL01
##@NIBU@##vrmnl05,10.46.1.215,WCMG,MNL01
##@NIBU@##vrmnl06,10.46.1.216,WCMG,MNL01
##@NIBU@##vrmnl07,10.46.1.217,WCMG,MNL01
##@NIBU@##vrmnl08,10.46.1.218,WCMG,MNL01
##@NIBU@##vrmnl09,10.46.1.219,WCMG,MNL01
##@NIBU@##vrmnl10,10.46.1.225,WCMG,MNL01
##@NIBU@##vrmnl11,10.46.1.226,WCMG,MNL01
##@NIBU@##vrmnl12,10.46.1.227,WCMG,MNL01
##@NIBU@##vru131,10.42.112.152,WBS,SAT01
##@NIBU@##vrusilo2,192.168.25.52,WBS,SAT01
##@NIBU@##vvded01,10.0.35.21,WDR,OMA11
##@NIBU@##vvru100,192.168.25.46,WBS,SAT01
##@NIBU@##vvru200,192.168.25.47,WBS,SAT01
##@NIBU@##vvru300,192.168.25.50,WBS,SAT01
##@NIBU@##vvru344,172.22.107.5,WBS,SPO01
##@NIBU@##vvru435,192.168.25.214,WBS,SAT01
##@NIBU@##vvru436,192.168.253.109,WBS,SAT01
##@NIBU@##westoma-vmhost01,10.251.60.131,WCMG,OMA01
##@NIBU@##westoma-vmhost02,10.251.60.132,WCMG,OMA01
##@NIBU@##westoma-wahasvr01,216.57.102.75,WCMG,OMA01
##@NIBU@##wrkvru,192.168.19.43,WBS,SAT01
##@NIBU@##xena,10.27.194.73,WIC,OMA00
