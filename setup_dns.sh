#!/bin/sh

#############################################
# Purpose: Configure DNS servers using nearest-neighbor logic
#   Primary and Secondary will be chosen from Site-Specific DNS servers
#   Tertiary will be chosen from between corporate DNS servers
# Author: SDW
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

# Locate and source common_functions.h
SCRIPTDIR1=/maint/scripts
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 5
fi


###                        ###
###  PRELIMINARY SETTINGS  ###
###                        ###

SERVERLIST=/maint/scripts/dnsservers.txt
TEST_A_REC=west.com
TMPLST=/tmp/dlst.tmp
OPTTMP=/tmp/dopt.tmp
RESOLV=/etc/resolv.conf
NSSWITCH=/etc/nsswitch.conf
SSO=/etc/sso
TS=`date +%Y%m%d%H%M%S`

export TEST_A_REC

# Determine Operating System
OS=`uname -s`


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
	   UNIQ=/usr/bin/uniq

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
	   UNIQ=/usr/bin/uniq

           # Special command switches
           NSLOOKUP_C="$NSLOOKUP -sil"
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
           BASH=/usr/bin/bash
	   UNIQ=/usr/bin/uniq

           # Special command switches
           if [ `uname -r` = 5.8 ]; then
              NSLOOKUP_C=$NSLOOKUP
           else
              NSLOOKUP_C="$NSLOOKUP -sil"
           fi
           ;;

       * ) echo "Operating System [$OS] not supported, contact Engineering and report this message and server name."
           exit 2
           ;;
esac


# Verify that the essential executables are all present and accounted for
REQ_BINS="$NSLOOKUP $GREP $RM $BC $TIME $CAT $SORT $AWK $HEAD $TAIL $EGREP $SED $CP $MV $PS $WC $CUT $WHICH $CHMOD"

# Solaris uniquely requires BASH
if [ "$OS" = "SunOS" ]; then
   REQ_BINS="$REQ_BINS $BASH"
fi

# Assume pre-check failure is false to start with - it'll be switched to TRUE for any single failure
PCF=FALSE
for REQ_BIN in $REQ_BINS; do

   if [ ! -x "$REQ_BIN" ]; then
      echo "Fatal Error: unable to locate [$REQ_BIN]."
      PCF=TRUE
   fi

done

if [ $PCF = TRUE ]; then 
   echo ""
   echo "Unable to locate one or more executables on this system."
   echo "Please either update the script with the correct path, or"
   echo "use symlinks to link this system's executables to the expected"
   echo "path, then try again"
   exit 3
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
         echo "Failure: unable to write out $SOLEX"
         exit 7
      fi
   fi
fi

# Export executable variables
export NSLOOKUP GREP RM BC TIME CAT SORT AWK HEAD TAIL EGREP SED CP MV PS WC CUT WHICH CHMOD NSLOOKUP_C

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
   echo "   If run without arguments the script will determine the best DNS servers"
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
   echo "       been made."
   echo ""


}


# Function to get average response time from a DNS server
# Usage: f_DNSAverageResponse <IP>
# Output: <average response time in seconds>
#            OR
#         -1 (DNS Service not found)
f_DNSAverageResponse () {

   DITC=$1

   # Verify that we're even getting responses on port 53
   RESPONDS=NO
   if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
      if [[ -z `echo -e "set timeout=3\nset retries=2\nserver $s\nwest.com\nexit\n" | $NSLOOKUP 2>&1 | grep -i "no response"` ]]; then
         RESPONDS=YES
      fi
   else
      if [[ -z `$NSLOOKUP -sil west.com $s 2>&1 | $GREP "connection timed out"` ]]; then
         RESPONDS=YES
      fi
   fi

   if [[ $RESPONDS == YES ]]; then

      # make sure we're always dealing with fresh variables
      unset thistime totaltime

      #Set the number of subsequent times to check
      CHECKCOUNT=20
      CHECK=0
      while [[ $CHECK -lt $CHECKCOUNT ]]; do
      #for i in {1..8}; do

         # measure time with nmap
         #thistime=`/usr/bin/nmap -sU -p 53 $DITC 2>&1 | grep seconds | awk '{print $(NF-1)}'`

         # measure with time and nslookup
         # perform one lookup to get the entry in cache, so we're averaging raw response time
         if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
            echo -e "set timeout=3\nset retries=2\nserver $s\nwest.com\nexit\n" | $NSLOOKUP 2>&1 > /dev/null
            thistime=`{ time echo -e "set timeout=3\nset retries=2\nserver $s\nwest.com\nexit\n" | $NSLOOKUP; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
         else
            $NSLOOKUP_C  west.com $s 2>&1 > /dev/null
            thistime=`{ time $NSLOOKUP_C west.com $s; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
         fi

         # first time through, just assign thstime to totaltime
         if [[ -z $totaltime ]]; then
            totaltime=$thistime
         else
            totaltime=`echo "$totaltime + $thistime" | $BC -l`
         fi

         let CHECK=$CHECK+1

      done

      average=`echo "$totaltime / 8" | $BC -l | $CUT -b1-5`

      echo $average

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



###                        ###
###     READ ARGUMENTS     ###
###                        ###

ACTION=UPDATE

if [[ -n "$1" ]]; then
   if [[ "$1" == "-F" ]]; then
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
# If it's not, we should leave it alone unless -F is specified
if [[ ! -s $RESOLV ]] || [[ -z `$EGREP -v "^.*#" $RESOLV | $EGREP "nameserver"` ]]; then
   echo "Server is not configured for DNS resolution."
   if [[ $ACTION == FORCE ]]; then
      echo "FORCE option used: the server will be configured anyway."
   else
      echo "No changes will be made automatically.  If you want"
      echo "to force updating of this server, use -F"
      echo ""
      exit 1
   fi
fi

###                           ###
###  END CHECK CURRENT STATE  ###
###                           ###

###                       ###
###  INTERDICTION 1: DMZ  ###
###                       ###
if [[ `f_InDMZ` == TRUE ]]; then
   echo "Detected DMZ: Disabling DNS"

   # Comment out the current resolv.conf
   if [[ -n `$GREP -v ^# $RESOLV` ]]; then
      $SED -i${TS} 's/^/#/g' $RESOLV
   fi

   # Remove dns from the hosts map in nsswitch
   if [[ -n `$GREP -v "^#" $NSSWITCH | $GREP hosts | $GREP dns` ]]; then
       $SED -i${TS} '/hosts/s/[ \t]dns//' $NSSWITCH
   fi
   exit 0
else

   # Ensure DNS exists in nsswitch
   if [[ -z `grep "^hosts:" $NSSWITCH | grep dns` ]]; then
      sed -i${TS} '/^hosts:/s/$/ dns/' $NSSWITCH
   fi
fi


###                           ###
###  END INTERDICTION 1: DMZ  ###
###                           ###

###                             ###
###  INTERDICTION 2: INTERCALL  ###
###                             ###

## NO MAS - Alex - 2015 10 07 ##
#if [[ -s $SSO ]] && [[ "`$GREP ^ITC= $SSO | $AWK -F'=' '{print $2}'`" == "YES" ]]; then
#   echo "Using Legacy DNS settings for Intercall"
#   mv /etc/resolv.conf /etc/resolv.conf.${TS}
#   echo "search icallinc.com wic.west.com svc.west.com" > /etc/resolv.conf
#   echo "nameserver 10.62.21.10" >> /etc/resolv.conf
#   echo "nameserver 10.62.21.20" >> /etc/resolv.conf
#   echo "nameserver 10.0.0.210" >> /etc/resolv.conf
#   exit 0
#fi


###                                 ###
###  END INTERDICTION 2: INTERCALL  ###
###                                 ###


###                      ###
###  READ/SET VARIABLES  ###
###                      ###


# This is a list of servers that need to be removed from
# resolv.conf
#LEGACY_IPLIST="172.30.9.151 172.30.94.108 172.30.41.227 10.28.101.26 216.57.98.32 216.57.106.45 216.57.106.46 216.57.98.33 216.57.102.97 216.57.102.98 216.57.106.48 216.57.106.49 216.57.102.95 216.57.102.96 216.57.110.24 216.57.110.25 216.57.102.42 10.28.101.40 10.28.101.41 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 172.30.41.224 172.30.41.225 172.30.8.24 172.30.8.25 172.30.8.204 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15 192.168.12.14 192.168.12.15"

LEGACY_IPLIST="10.0.0.210 10.0.14.100 10.0.35.210 10.19.124.23 10.28.101.26 10.28.101.40 10.28.101.41 10.51.254.102 10.62.21.10 10.62.21.20 10.62.220.2 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 10.70.192.22 10.70.71.68 172.30.41.224 172.30.41.225 172.30.41.227 172.30.8.204 172.30.8.24 172.30.8.25 172.30.9.151 172.30.9.228 172.30.94.108 172.30.94.116 192.168.12.14 192.168.12.15 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15 10.28.101.51 10.28.101.52 10.17.126.43 10.17.126.44 10.19.119.82 10.19.119.83"

#LEGACY_TER="10.62.21.10 10.62.21.20 172.30.9.151 172.30.94.108"
LEGACY_TER="10.0.0.210 10.0.14.100 10.0.35.210 10.19.124.23 10.28.101.26 10.28.101.40 10.28.101.41 10.51.254.102 10.62.21.10 10.62.21.20 10.62.220.2 10.64.10.74 10.64.10.75 10.70.1.25 10.70.1.26 10.70.192.22 10.70.71.68 172.30.41.224 172.30.41.225 172.30.41.227 172.30.8.204 172.30.8.24 172.30.8.25 172.30.9.151 172.30.9.228 172.30.94.108 172.30.94.116 192.168.12.14 192.168.12.15 192.168.18.15 192.168.18.16 192.168.45.14 192.168.45.15 10.28.101.51 10.28.101.52 10.17.126.43 10.17.126.44 10.19.119.82 10.19.119.83"

# Default values - this is a fallback in case everything else fails
#old#D_PRIMARY="10.19.119.82"
#old#D_SECONDARY="10.19.119.83"
#old#D_TERTIARY="10.17.126.43"
#den06 
D_PRIMARY="10.70.1.60"
#swn01 
D_SECONDARY="10.64.10.152"
#lon13
D_TERTIARY="10.166.128.52"
D_SEARCH="wic.west.com icallinc.com one.west.com svc.west.com"


# Try to see if we have a serverlist - that will be the preferred method
echo -n "Looking for $SERVERLIST"
if [[ -s $SERVERLIST ]]; then
   PRIMARY_IPLIST=`grep ^p $SERVERLIST | awk '{print $3}'`
   SS_IPLIST=`grep ^s $SERVERLIST | awk '{print $3}'`
   echo ", found file, using primary/secondary values."
else
   echo ", not found, using defaults."
fi

# If we don't have these populated, then fall back on static values
if [[ -z $PRIMARY_IPLIST ]]; then
   PRIMARY_IPLIST="10.70.1.60 10.64.10.152 10.166.128.52"
fi

if [[ -z $SS_IPLIST ]]; then
   SS_IPLIST="10.70.1.61 10.64.10.153 10.166.128.53"
fi

##  Alex - 20151007 - no more "primary/secondary/master/slave" 
#
FULL_IPLIST=`echo $PRIMARY_IPLIST $SS_IPLIST | tr ' ' '\n' | $SORT | $UNIQ | tr '\n' ' '`
##


###                          ###
###  END READ/SET VARIABLES  ###
###                          ###


###                                ###
###  CALCULATE RECOMMENDED CONFIG  ###
###                                ###

# Determine primary and secondary servers 
## Alex - 20151007 - simplifying this to one block of IPs to sort.
##20151007#echo "Negotiating best Site-Specific DNS servers."
echo "Querying potential servers, please be patient"
# if [[ -n `/usr/bin/nslookup $TEST_A_RED $s 2>&1 | grep -v $s | grep "^Address"` ]]; then

# Remove any previous version of TMPLST
if [[ -f $TMPLST ]]; then $RM $TMPLST; fi

##20151007#for s in $SS_IPLIST; do
echo ""
for s in $FULL_IPLIST; do
   #echo "Checking server $s"
   echo -n "."
   # Make sure the server actually responds to dns requests
   RESPONDS=NO
   if [[ `uname -s` == SunOS ]] && [[ `uname -r` == 5.8 ]]; then
      if [[ -z `echo -e "set timeout=3\nset retries=2\nserver $s\n$TEST_A_REC\nexit\n" | $NSLOOKUP 2>&1 | grep -i "no response"` ]]; then
         RESPONDS=YES
      fi
   else
      if [[ -z `$NSLOOKUP -sil $TEST_A_REC $s 2>&1 | $GREP "connection timed out"` ]]; then
         RESPONDS=YES
      fi
   fi

   if [[ $RESPONDS == YES ]]; then
      #echo "   answers queries"
      echo -n "."
      # Collect the average of 4 lookups
      time=`f_DNSAverageResponse $s`
      if [[ $time != -1 ]]; then

         # If we got a valid response time for the server, then add it to the TMPLST
         #echo "   average response time $time seconds"
         #echo ""
         echo "$s,$time" >> $TMPLST
      else
         echo "   does not answer"
      fi
   else
      echo "   does not answer"
   fi

done
echo ""
echo ""

if [[ ! -s $TMPLST ]]; then
   echo "FAILURE: No reachable DNS servers found from the following:"
##20151007#   echo "   $SS_IPLIST"
   echo "    $FULL_IPLIST"
   echo ""
   echo "If the server you expect to use is not on this list, please"
   echo "update /maint/scripts/dnsservers.txt with the proper list."
   echo "Please ensure that name resolution is working for these"
   echo "servers, and that firewall rules are not preventing"
   echo "communication on UDP port 53."
   echo ""
   exit 6
fi

##20151007##Use sort to grab the two fastest servers from the list
##20151007#PRIMARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -1 | $AWK -F',' '{print $1}'`
##20151007#SECONDARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 | head -2 | $TAIL -1 | $AWK -F',' '{print $1}'`
## Use sort to grab the top 3 responders from the list
PRIMARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 |  $HEAD -1 | $AWK -F',' '{print $1}'`
SECONDARY_SS=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -2 | $TAIL -1 | $AWK -F',' '{print $1}'`
TERTIARY=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -3 | $TAIL -1 | $AWK -F',' '{print $1}'`

$RM $TMPLST

##20151007## Now pick a tertiary from the list of primary DNS servers
##20151007#echo -e "\nNegotiating best Tertiary DNS server."
##20151007#echo "  Please be patient"

##20151007#if [[ -f $TMPLST ]]; then $RM $TMPLST; fi

##20151007#for p in $PRIMARY_IPLIST; do
##20151007#   #echo "Checking server $p"
##20151007#   echo -n "."
##20151007#   # Make sure the server actually responds to requests
##20151007#   if [[ -z `$NSLOOKUP_C $TEST_A_REC $p 2>&1 | $GREP "connection timed out"` ]]; then
##20151007#      #echo "   answers queries"
##20151007#      echo -n "."
##20151007#      # Collect the average of 4 pings
##20151007#      time=`f_DNSAverageResponse $p`
##20151007#      #echo "   average response time $time seconds"
##20151007#      #echo ""
##20151007#      echo -n "."
##20151007#      echo "$p,$time" >> $TMPLST
##20151007#   else
##20151007#      #echo "   does not answer"
##20151007#      echo -n "."
##20151007#   fi

##20151007#done
##20151007#echo ""
##20151007#
##20151007#if [[ ! -s $TMPLST ]]; then
##20151007#   echo "FAILURE: No reachable DNS servers found from the following:"
##20151007#   echo "   $PRIMARY_IPLIST"
##20151007#   echo ""
##20151007#   echo "If the server you expect to use is not on this list, please"
##20151007#   echo "update /maint/scripts/dnsservers.txt with the proper list."
##20151007#   echo "Please ensure that name resolution is working for these"
##20151007#   echo "servers, and that firewall rules are not preventing"
##20151007#   echo "communication on UDP port 53."
##20151007#   echo ""
##20151007#   exit 6
##20151007#fi

##20151007#TERTIARY=`$CAT $TMPLST | $SORT -n -t , -k2 | $HEAD -1 | $AWK -F',' '{print $1}'`
##20151007#/bin/rm $TMPLST

#echo ""
#echo "Determined the following DNS server list based on response time:"
#echo "Primary: $PRIMARY_SS"
#echo "Secondary: $SECONDARY_SS"
#echo "Tertiary: $TERTIARY"

###                                    ###
###  END CALCULATE RECOMMENDED CONFIG  ###
###                                    ###


###                                    ###
###  APPLY ACTION/GENERATE NEW CONFIG  ###
###                                    ###


## Generate the new configuration based on ACTION

if [[ $ACTION == UPDATE ]] || [[ $ACTION == PRETEND ]]; then
   # Read the current configuration
   C_SEARCH=`$EGREP -v "^#" $RESOLV | $EGREP "^.*search" | $SED "s/^.*search[ \t]//"`
   C_DOMAIN=`$EGREP -v "^#" $RESOLV | $EGREP "^.*domain" | $SED "s/^.*domain[ \t]//"`
   C_PRIMARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -1`
   C_SECONDARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -2 | tail -1`
   C_TERTIARY=`$EGREP -v "^#" $RESOLV | $EGREP "^.*nameserver" | $SED "s/^.*nameserver[ \t]//" | $AWK '{print $1}' | $HEAD -3 | tail -1`
   
   # Preserve any options that may have been set
   if [[ -n `$EGREP -v "^#" $RESOLV | $EGREP "^.*options"` ]]; then
      $EGREP -v "^#" $RESOLV | $EGREP "^.*options" > $OPTTMP
   fi

   # We're going to be careful about what we replace.
   # As long as we know that the configured DNS server is in the list we want to replace or the list
   # we're replacing from it is okay to replace it
   META_IPLIST="$LEGACY_IPLIST $SS_IPLIST $PRIMARY_IPLIST"
   
   # If the fastest site server is a valid IPv4 address, and either there is no current primary, 
   # or the current primary exists in the list of known servers, go ahead and replace it.
#echo PRIMARY_SS is $PRIMARY_SS
#echo C_PRIMARY is $C_PRIMARY
#echo METALIST is $META_IPLIST 
   if [[ `f_ValidIPv4 $PRIMARY_SS` != FALSE ]] && ( [[ -z $C_PRIMARY ]] || [[ -n `echo $META_IPLIST | grep $C_PRIMARY` ]] ); then
      echo "Primary server will be set to $PRIMARY_SS"
      N_PRIMARY=$PRIMARY_SS
   else
      echo "Unable to identify $C_PRIMARY, leaving it primary."
      N_PRIMARY=$C_PRIMARY
   fi

   # Negotiate Secondary
   if [[ `f_ValidIPv4 $SECONDARY_SS` != FALSE ]] && ( [[ -z $C_SECONDARY ]] || [[ -n `echo $META_IPLIST | grep $C_SECONDARY` ]] ); then
      echo "Secondary server will be set to $SECONDARY_SS"
      N_SECONDARY=$SECONDARY_SS
   else
      echo "Unable to identify $C_SECONDARY, leaving it secondary."
      N_SECONDARY=$C_SECONDARY
   fi

   # Negotiate Tertiary - if the intercall server(s) "LEGACY_TER" is tertiary, it will be replaced
   if [[ `f_ValidIPv4 $TERTIARY` != FALSE ]] && ( [[ -z $C_TERTIARY ]] || [[ -n `echo $META_IPLIST | grep $C_TERTIARY` ]] || [[ -n `echo $LEGACY_TER | grep  "$C_TERTIARY"` ]] ); then
      echo "Tertiary server will be set to $TERTIARY"
      N_TERTIARY=$TERTIARY
   else
      echo "Unable to identify $C_TERTIARY, leaving it tertiary."
      N_TERTIARY=$C_TERTIARY
   fi

   # -- #Currently there is no reason to change the search or domain info (domain is probably blank)
	## Adding svc.west.com to existing search strings.
	## Adding one.west.com to existing search strings.

unset _ADDSVC
unset _ADDONE

for csearch in `echo $C_SEARCH`
  do 
	if [[ "$csearch" == "svc.west.com" ]]
	then
		_ADDSVC=no
	fi
	if [[ "$csearch" == "one.west.com" ]]
	then
		_ADDONE=no
	fi
  done
if [[ -z $_ADDSVC ]]
then
   SVC_SEARCH="svc.west.com"
#else
#   SVC_SEARCH=$C_SEARCH
fi
if [[ -z $_ADDONE ]]
then
   ONE_SEARCH="one.west.com"
#else
#   ONE_SEARCH=$C_SEARCH
fi
   N_SEARCH="$C_SEARCH $SVC_SEARCH $ONE_SEARCH"
   N_DOMAIN=$C_DOMAIN

elif [[ $ACTION == FORCE ]]; then

   # Set the new values to the recommended values - if something went wrong with the recommended
   # values, use the build defaults
   if [[ `f_ValidIPv4 $PRIMARY_SS` != FALSE ]]; then
      N_PRIMARY=$PRIMARY_SS
   else
      N_PRIMARY=$D_PRIMARY
   fi

   if [[ `f_ValidIPv4 $SECONDARY_SS` != FALSE ]]; then
      N_SECONDARY=$SECONDARY_SS
   else
      N_SECONDARY=$D_SECONDARY
   fi

   if [[ `f_ValidIPv4 $TERTIARY` != FALSE ]]; then
      N_TERTIARY=$TERTIARY
   else
      N_TERTIARY=$D_TERTIARY
   fi

   N_SEARCH=$D_SEARCH

fi

# Build the new resolv.conf

# Clear out any previous "new" files that didn't get cleaned up
if [[ -f ${RESOLV}.new ]]; then $RM ${RESOLV}.new; fi

# Add a domain line if the server originally had one
if [[ -n $N_DOMAIN ]]; then
   echo "domain $N_DOMAIN" > ${RESOLV}.new
fi

# Add the body of name resolution
NEW_SEARCH="$(echo -e "${N_SEARCH}" | sed -e 's/[[:space:]]*$//')"
echo "search $NEW_SEARCH" >> ${RESOLV}.new
echo "nameserver $N_PRIMARY" >> ${RESOLV}.new

# Don't create duplicate entries
if [[ "$N_SECONDARY" != "$N_PRIMARY" ]]; then
   echo "nameserver $N_SECONDARY" >> ${RESOLV}.new
fi

# Don't create duplicate entries
if [[ "$N_TERTIARY" != "$N_PRIMARY" ]] && [[ "$N_TERTIARY" != "$N_SECONDARY" ]]; then
   echo "nameserver $N_TERTIARY" >> ${RESOLV}.new
fi

# Add the options back in if the server originally had any
if [[ -s $OPTTMP ]]; then
   $CAT $OPTTMP >> ${RESOLV}.new
fi


###                                        ###
###  END APPLY ACTION/GENERATE NEW CONFIG  ###
###                                        ###

###                                 ###
###  BACKUP OLD/INSTALL NEW CONFIG  ###
###                                 ###


if [[ $ACTION == UPDATE ]] || [[ $ACTION == FORCE ]]; then
   
   # Back up the previous resolv.conf
   echo "Backing up the current resolv.conf to ${RESOLV}.${TS}"
   $CP ${RESOLV} ${RESOLV}.${TS}

   if [[ ! -s ${RESOLV}.${TS} ]]; then
      echo "Error: Unable to create backup of new configuration as ${RESOLV}.${TS}"
      echo "       This script will not make modifications until a backup can be"
      echo "       written and confirmed."
      exit 8
   fi

   # Replace the old config with the new one
   echo ""
   echo "OLD settings:"
   echo "`cat ${RESOLV}`"
   echo ""
   echo "NEW settings:"
   echo "`cat ${RESOLV}.new`"
   echo ""

   $MV ${RESOLV}.new ${RESOLV}

   echo ""
   echo "$RESOLV has been updated."
   echo ""

   # If performing an update, make sure we restart/reload any DNS caching daemons
   # to ensure that the changes are picked up.

   if [[ "$OS" == "Linux" ]]; then
      if [[ -n `$PS --no-header -C nscd -o pid` ]]; then
 	 echo ""
         echo "Detected NSCD is running - it will be reloaded to detect changes."
         /etc/init.d/nscd reload
	 echo ""
      fi
   fi
   
   if [[ "$OS" == "AIX" ]]; then
      if [[ -n `/usr/bin/lssrc -s netcd | grep "active"` ]]; then
         echo "Detected NetCD is running - it will be restarted to detect changes."
         /usr/bin/stopsrc -s netcd
         sleep 3
         /usr/bin/startsrc -s netcd
      fi
   fi

   if [[ "$OS" == "SunOS" ]]; then
      if [[ -n `$PS -ef -o comm | grep "/nscd$"` ]]; then
         echo "Detected NSCD is running - it will be stopped and started to detect changes."
         /etc/init.d/nscd stop
         /etc/init.d/nscd start
      fi
   fi

elif [[ $ACTION == PRETEND ]]; then

   echo "I would have installed the following resolv.conf:"
   echo ""
   $CAT ${RESOLV}.new
   echo ""
   $RM ${RESOLV}.new
fi


   
