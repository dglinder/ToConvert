#!/bin/bash

#############################################
# Purpose: Configures a RHEL server for LDAP
# Author: SDW / DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
# To export the latest version of this file:
#   svn export https://eitsvn.west.com/svn/EIT-post_scripts/trunk/setup_ldap.sh
#############################################

##The script serial number should be incremented each
##time an update is made to the script
###SCRIPTSERIAL=1013

TIME=`date +%Y%m%d%H%M%Z`

# SET FULL PATH FOR EXECUTABLES
PING=/bin/ping
TPUT=/usr/bin/tput
MKDIR=/bin/mkdir
WGET=/usr/bin/wget
CACERTDIR_REHASH=/usr/sbin/cacertdir_rehash
GETENT=/usr/bin/getent
DMIDECODE=/usr/sbin/dmidecode
EGREP=/bin/egrep
GREP=/bin/grep
SED=/bin/sed
RM=/bin/rm
CAT=/bin/cat
UNAME=/bin/uname
RPM=/bin/rpm
LDSEARCH=/usr/bin/ldapsearch
LDMODIFY=/usr/bin/ldapmodify
AWK=/bin/awk

unset PRE_CHECK
PRE_CHECK=`rpm -qa | grep sssd`
if [[ -z $PRE_CHECK ]]
then
	echo Instaling sssd
	yum -y install sssd
fi
unset PRE_CHECK

PRE_CHECK=`rpm -qa | grep pam_ldap`
if [[ -z $PRE_CHECK ]]
then
	echo Instaling pam_ldap
	yum -y install pam_ldap
fi
unset PRE_CHECK

PRE_CHECK=`rpm -qa | grep nscd`
if [[ -z $PRE_CHECK ]]
then
	echo Instaling nscd
	yum -y install nscd
	chkconfig nscd on
	service nscd start
fi
unset PRE_CHECK

PRE_CHECK=`rpm -qa | grep sssd-client`
if [[ -z $PRE_CHECK ]]
then
	echo Instaling sssd-client
	yum -y install sssd-client
fi
unset PRE_CHECK

PRE_CHECK=`rpm -qa | grep sssd-client.i686`
if [[ -z $PRE_CHECK ]]
then
	echo Instaling sssd-client.i686
	yum -y install sssd-client.i686
fi
unset PRE_CHECK

##Backups
/bin/cp -p /etc/nscd.conf /etc/nscd.conf.$TIME
/bin/cp -p /etc/nslcd.conf /etc/nslcd.conf.$TIME
/bin/cp -p /etc/pam.d/system-auth-ac /etc/pam.d/system-auth-ac.$TIME
/bin/cp -p /etc/nsswitch.conf /etc/nsswitch.conf.$TIME
/bin/cp -p /etc/passwd /etc/passwd.$TIME
/bin/cp -p /etc/shadow /etc/shadow.$TIME
/bin/cp -p /etc/group /etc/group.$TIME
/bin/cp -p /etc/pam_ldap.conf /etc/pam_ldap.conf.$TIME
if [[ -f /etc/sssd/sssd.conf ]]
then
	/bin/cp -p /etc/sssd/sssd.conf /etc/sssd/sssd.conf.$TIME
fi
/bin/cp -p /etc/security/access.conf /etc/security/access.conf.$TIME
/bin/cp -p /maint/scripts/common_functions.h /maint/scripts/common_functions.h.$TIME

##Backups
/bin/cp -p /etc/nscd.conf /etc/nscd.conf.$TIME
/bin/cp -p /etc/nslcd.conf /etc/nslcd.conf.$TIME
/bin/cp -p /etc/pam.d/system-auth-ac /etc/pam.d/system-auth-ac.$TIME
/bin/cp -p /etc/nsswitch.conf /etc/nsswitch.conf.$TIME
/bin/cp -p /etc/passwd /etc/passwd.$TIME
/bin/cp -p /etc/shadow /etc/shadow.$TIME
/bin/cp -p /etc/group /etc/group.$TIME
/bin/cp -p /etc/pam_ldap.conf /etc/pam_ldap.conf.$TIME
if [[ -f /etc/sssd/sssd.conf ]]
then
	/bin/cp -p /etc/sssd/sssd.conf /etc/sssd/sssd.conf.$TIME
fi
/bin/cp -p /etc/security/access.conf /etc/security/access.conf.$TIME
/bin/cp -p /maint/scripts/common_functions.h /maint/scripts/common_functions.h.$TIME
/bin/cp -p /maint/scripts/ldapservers.txt /maint/scripts/ldapservers.txt.$TIME

/usr/sbin/authconfig --savebackup /etc/authconfig-backup.$TIME

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


# Explicitly set term variable if not already set
if [[ -z $TERM ]]; then
   export TERM=xterm
fi

# Check for "unattended mode"
UNATTENDED=NO
if [[ -n $1 ]] && [[ "$1" == "-ua" ]]; then
   UNATTENDED=YES
fi

# Enumerate required executables
REQUIRED="$AWK $PING $TPUT $MKDIR $WGET $CACERTDIR_REHASH $GETENT $DMIDECODE $EGREP $GREP $SED $RM $CAT $UNAME $RPM $LDSEARCH $LDMODIFY"

# Check for needed pre-requisites
unset PRECHECK_FAIL
for EXE in $REQUIRED; do
   if [[ ! -x $EXE ]]; then
      echo "PRECHECK FAILED: $EXE not found"
      PRECHECK_FAIL=TRUE
   fi
done


if [[ -n $PRECHECK_FAIL ]]; then
   echo "FAILURE: One or more pre-checks failed. See above for details."
   echo "         This system HAS NOT been configured for LDAP."
   exit 1
fi

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         This system HAS NOT been configured for LDAP."
   exit 2
fi



# Check for network connectivity

echo "Checking for network connectivity..."

ISNETUP=`f_IsNetUp`

if [[ $ISNETUP == NO ]]; then
   echo "   FAILURE: network is not set up or not working."
   echo "            Please set up the network and ensure"
   echo "            it is working, then run this script again."
   exit 3
else
   # If we have network connectivity, check to see if we're in a DMZ
   DMZ=`f_InDMZ`
   if [[ $DMZ == FALSE ]]; then
      
      # If we're not in a DMZ, check to see if we've got normal connectivity
      ATWEST=`f_AtWest`
      if [[ $ATWEST == FALSE ]]; then
         echo ""
         echo "   FAILURE: There appears to be a working network,"
         echo "            however, it does not appear to be the"
         echo "            West network.  Please connect this server"
         echo "            to the West internal network and try again."
         echo ""
         echo "      NOTE: If this server is in a West DMZ, it is not"
         echo "            being detected.  You can force DMZ behavior"
         echo "            by creating an empty file at this location:"
         echo "               /maint/.forceDMZTRUE"
         exit 4
      fi
   fi
fi

# Environment Variables 
LDAP_BASE="dc=ds,dc=west,dc=com"
NISDOMAIN=ds.west.com
LDAP_MASTER_SERVER=oma00ds01.ds.west.com
LDAP_DEFAULT_SERVERS="oma00ds01.ds.west.com oma00ds02.ds.west.com"

# DNS Check
if [[ $DMZ == FALSE ]]; then
   # If not in DMZ, DNS is required
   if [[ -z `$GETENT hosts $LDAP_MASTER_SERVER` ]]; then
      echo "LDAP setup requires functional DNS, but this server"
      echo "is unable to resolve $LDAP_MASTER_SERVER."
      exit 7
   fi
else
   # If in DMZ, statically assign IPs to hostnames
   if [[ -z `grep xatl01dz01 /etc/hosts` ]]; then echo "75.78.102.32      xatl01dz01.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xden06dz01 /etc/hosts` ]]; then echo "75.78.177.68      xden06dz01.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xswn01dz01 /etc/hosts` ]]; then echo "75.78.1.92        xswn01dz01.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xlon13dz01 /etc/hosts` ]]; then echo "75.78.192.61      xlon13dz01.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xlon13dz02 /etc/hosts` ]]; then echo "75.78.192.62      xlon13dz02.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xsin10dz01 /etc/hosts` ]]; then echo "75.78.200.25      xsin10dz01.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xsin10dz02 /etc/hosts` ]]; then echo "75.78.200.26      xsin10dz02.ds.west.com" >> /etc/hosts; fi
   if [[ -z `grep xoma01dz01 /etc/hosts` ]]; then echo "216.57.102.38     xoma01dz01.ds.west.com" >> /etc/hosts; fi
fi


if [[ $DMZ == FALSE ]]; then
   # Check for an updated version of the script (will silently fail in the DMZ)
   echo "Checking $LDAP_MASTER_SERVER for an updated version of this script"


   NETVERTMP=/tmp/cld.downloaded
   $WGET --timeout=8 --tries=3 --quiet http://${LDAP_MASTER_SERVER}/0uMxWccP3EtxmU2xVJV5Hqjl4/setup_ldap-sssd.sh -O $NETVERTMP
   $WGET --timeout=8 --tries=3 --quiet http://${LDAP_MASTER_SERVER}/0uMxWccP3EtxmU2xVJV5Hqjl4/ldapservers.txt -O /maint/scripts/ldapservers.txt
   $WGET --timeout=8 --tries=3 --quiet http://${LDAP_MASTER_SERVER}/0uMxWccP3EtxmU2xVJV5Hqjl4/common_functions.h -O /maint/scripts/common_functions.h
   if [[ -s "$NETVERTMP" ]]; then
      THISSER=`grep ^###SCRIPTSERIAL $0 | awk -F'=' '{print $2}'`
      THATSER=`grep ^###SCRIPTSERIAL $NETVERTMP | awk -F'=' '{print $2}'`
      if [[ -n $THISSER ]] && [[ -n $THATSER ]] && [[ $THATSER -gt $THISSER ]]; then
   
         echo ""
         echo "Updating this script from serial $THISSER to $THATSER and restarting."
         #echo "chmod +x $NETVERTMP;/bin/mv $NETVERTMP /opt/configure_ldap-sssd.sh; /opt/configure_ldap-sssd.sh;" | /bin/bash &
         cp -p $0 $0.back.$TIME
         cat $NETVERTMP > $0
         exec $0
         exit
      else
         /bin/rm $NETVERTMP
      fi
   fi
fi


# Read release version
FULLNAME=`f_GetRelease`
PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

# Verify this OS version is supported
if [[ -z `echo $PRODUCT | $EGREP 'RHEL|RHES|RHAS'` ]] || [[ $RELEASE -le r4 ]]; then
   echo "LDAP-sssd setup has not been certified for this release:"
   echo "   "`$CAT /etc/redhat-release`
   echo "Please see engineering for a list of supported platforms"
   echo "if you believe this message is in error."
   exit 5
fi



## Get a list of checkable LDAP servers.

unset LDAP_SERVER_LIST

# First attempt, if we're in the DMZ, just use a static list
if [[ $DMZ == TRUE ]]; then
   echo "Using DMZ server list..."
   LDAP_SERVER_LIST="xatl01dz01.ds.west.com xden06dz01.ds.west.com xswn01dz01.ds.west.com xlon13dz01.ds.west.com xlon13dz02.ds.west.com xsin10dz01.ds.west.com xsin10dz02.ds.west.com"
fi

# Second attempt, use the replica list from the LDAP_MASTER_SERVER 
if [[ -z $LDAP_SERVER_LIST ]]; then
   LDAPCSV=/tmp/lst.csv
   $WGET --timeout=8 --tries=3 --quiet http://${LDAP_MASTER_SERVER}/0uMxWccP3EtxmU2xVJV5Hqjl4/replids.csv -O $LDAPCSV
   CSVRESULT=$?
   if [[ $CSVRESULT == 0 ]]; then
      echo "Using live server list from $LDAP_MASTER_SERVER"
      for LDS in `$AWK -F',' '{print $1}' $LDAPCSV | $AWK -F'(' '{print $1}' | $EGREP -v 'dz|lab'`; do
         LDAP_SERVER_LIST="$LDAP_SERVER_LIST $LDS"   
      done
   fi
   
   # Whatever happened, clean up the CSV list
   if [[ -f $LDAPCSV ]]; then
      $RM $LDAPCSV
   fi

fi

# Third attempt, use the "ldapservers" file.
if [[ -z $LDAP_SERVER_LIST ]]; then
   echo "Using ldapservers.txt file for serverlist"
   LDAP_SERVER_FILE=/maint/scripts/ldapservers.txt
   if [[ -f $LDAP_SERVER_FILE ]]; then
      for e in `$CAT $LDAP_SERVER_FILE | $EGREP -v 'dz|lab'`; do
         LDAP_SERVER_LIST="$LDAP_SERVER_LIST $e"
      done
   fi
fi

# Last Resort, use defaults
if [[ -z $LDAP_SERVER_LIST ]]; then
   echo "Using fallback default server list"
   LDAP_SERVER_LIST=$LDAP_DEFAULT_SERVERS
fi

echo ""

## Whittle down the server list to the USEABLE servers and elect the fastest responders

TMPLST=/tmp/lst.tmp
if [[ -f $TMPLST ]]; then $RM $TMPLST; fi
best=
besttime=
for s in $LDAP_SERVER_LIST; do
   $TPUT cuu1; $TPUT el
   echo -n "Checking server $s"
   # Make sure the server actually responds to ldap requests
   if [[ -z `/usr/bin/ldapsearch -x -o nettimeout=7 -h $s -b "$LDAP_BASE" '(ou=People)' 2>&1 | $GREP "Can't contact LDAP server"` ]]; then
      echo -n "...answers queries"
      ## Collect the average of 4 pings
      #time=`$PING -q -c4 $s | $GREP rtt | awk '{print $4}' | awk -F'/' '{print $2}'`
      #echo "...$ping time $time"

      # Check round trip time for a basic LDAP query
      time=`{ time /usr/bin/ldapsearch -x -h $s -b "$LDAP_BASE" '(ou=People)'; } 2>&1 | $GREP ^real | $AWK -F'm' '{print $2}' | $SED 's/s$//'`
      echo "...time $time"
      echo "$s,$time" >> $TMPLST
      if [[ -z $besttime ]] || ( [[ -n $time ]] && [[ $time < $besttime ]] ); then
         best=$s
         besttime=$time
      fi
   else
      echo "...does not answer"
   fi
done 
$TPUT cuu1; $TPUT el

echo 'Top 5 quickest server response times (FQDN, time in seconds):'
cat $TMPLST | sort -t, -k 2 -n | head -5 | cat -n

# If none of the CHECKABLE servers were USEABLE then fail out

if [[ ! -s $TMPLST ]]; then
   echo "FAILURE: No reachable LDAP servers found from the following:"
   echo "   $LDAP_SERVER_LIST"
   echo ""
   echo "If the server you expect to use is not on this list, please"
   echo "update /maint/scripts/ldapservers.txt with the proper list."
   echo "Please ensure that name resolution is working for these"
   echo "servers, and that firewall rules are not preventing"
   echo "communication on ports 80, 389 and 636."
   echo ""
   exit 6
fi


# Download the CA cert from the fastest responding directory server

echo -n "Downloading CA cert from $best..."

$MKDIR -p /etc/openldap/cacerts
$WGET --timeout=8 --tries=3 --quiet http://${best}/0uMxWccP3EtxmU2xVJV5Hqjl4/cacert.asc -O /etc/openldap/cacerts/cacert.asc
CACERTGET_RESULT=$?
if [[ $CACERTGET_RESULT != 0 ]]; then
   echo "unable to download."
else
   echo "downloaded."
fi
if [[ ! -s /etc/openldap/cacerts/cacert.asc ]]; then
   echo ""
   echo "Warning:"
   echo "Unable to download CA cert from:"
   echo "   http://${best}/0uMxWccP3EtxmU2xVJV5Hqjl4/cacert.asc"
   echo ""
   echo "Falling back to an embedded version of the cert."
   echo "This cert may be outdated."
   echo ""

cat << EOF >> /etc/openldap/cacerts/cacert.asc
-----BEGIN CERTIFICATE-----
MIIBrDCCARWgAwIBAgICA+gwDQYJKoZIhvcNAQEFBQAwETEPMA0GA1UEAxMGQ0Fj
ZXJ0MB4XDTEyMDgwMzIwMjgyOFoXDTIyMDgwMzIwMjgyOFowETEPMA0GA1UEAxMG
Q0FjZXJ0MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDEBAbp56VGMeAeDeJF
aPJsZoCBaMXbmCqxjMf8IKz4UgXB5vuQ83wauw6gW1URtN17U4f1XqiWAg0gP7ur
5U2AQqGiWtWH0dqfZWQKIsGaseJn7zyh7PdHXTCY3LE3g9jLenfh8cLQuXGj+Zt2
PmixOxCpXMJeMhehQkLi/qcSwQIDAQABoxMwETAPBgNVHRMBAf8EBTADAQH/MA0G
CSqGSIb3DQEBBQUAA4GBAK1FAjwcpXtZWR0dtpABgwKtHymPj2ZMYS4MSTTsPeQ+
AyVDdCAFVh4X5HlbPX30KXV6mT97NkLupAybQ66rwhskwTQvnNYqC6JnzHwLS79f
gGjEXbHYbjue61NYs9eQdP5ZskMtCJanJ4YbqmP4CpRpjNv1mwtDJO2AZ/dTvDlb
-----END CERTIFICATE-----
EOF
/bin/cp -p /etc/openldap/cacerts/cacert.asc /etc/openldap/cacerts/authconfig_downloaded.pem
fi

# Set up necessary links
$CACERTDIR_REHASH /etc/openldap/cacerts

#BUILD the host string for authconfig using the three fastest servers
OSL=
for t in `$CAT $TMPLST | sort -t , -k2 -n | head -3`; do
   # RHEL 4 authconfig requires "HOST" instead of "URI"
   if [[ $RELEASE == 4 ]]; then
      SERVER=`echo $t | awk -F',' '{print $1}'`
   else
      SERVER="ldap://`echo $t | awk -F',' '{print $1}'`"
   fi
   OSL="$OSL $SERVER"
   # While we're building the server list for authconfig, also add these
   # servers to the hosts file
   ts=`echo $t | awk -F',' '{print $1}'`
   if [[ -z `grep $ts /etc/hosts` ]]; then
      /usr/bin/getent hosts $ts >> /etc/hosts
      unset ts
   fi

done

# Couple of additional formatting on the final server list
OSL=`echo $OSL | $SED 's/^ //'`
SSSDOSL=$(echo $OSL | sed -e 's/ /,/g' -e 's/ldap:/ldaps:/g')
OSL="'$OSL'"


###LDAP ENVIONMENTAL SETTINGS###
# Define some commands - LDAPAMS needs to be a master server capable of
# Performing updates
LDAPMS=$LDAP_MASTER_SERVER
KS_SERV=linux157
NG_BASE="ou=Netgroups,${LDAP_BASE}"
PG_BASE="ou=Groups,${LDAP_BASE}"
#LDAP_SEARCH="$LDSEARCH -x -h $LDAPMS -p 389"
LDAP_SEARCH="$LDSEARCH -x -h $best -p 389"
#LDAP_MODIFY="$LDMODIFY -x -h $LDAPMS -p 389 -D \"cn=machine account manager,cn=config\""
LDAP_MODIFY="$LDMODIFY -x -h $LDAPMS -p 389" 
LDIF_TMP=/tmp/cldt

# DEFINE MACHINE NETGROUP PARAMETERS

# Create the string to use for "Description"
HN=`hostname -s`
MNG="${HN}_machine"
SERIAL=`$DMIDECODE | strings | awk /"System Information"/,/"Serial Number"/ | $GREP "Serial Number" | awk -F':' '{print $NF}' | $SED 's/^ //;s/ *$//g'`
PRODUCT=`$DMIDECODE | strings | awk /"System Information"/,/"Serial Number"/ | $GREP "Product" | awk -F':' '{print $NF}' | $SED 's/^ //;s/ *$//g'`
PUBIP=`f_FindPubIP | grep -v FAILURE`
DESC=":::${SERIAL}::${HN}::${PRODUCT}::${TIME}::${PUBIP}:::::"

# Prepare to check and/or update the Directory
unset OPERATION

echo -n "Checking for duplicate netgroups..."
# First check to see if there is already a netgroup name for this server
if [[ -z `$LDAP_SEARCH -b $NG_BASE "(&(objectClass=nisnetgroup)(cn=${MNG}))" cn | $GREP ^cn:` ]]; then

   # If there's no existing netgroup for this machine, then check for duplicate serial numbers
   if [[ -n `$LDAP_SEARCH -b $NG_BASE "(Description=:::${SERIAL}::*)" | $EGREP -v '^#|^ |^$|^search:|^result:'` ]]; then
      HASSERIAL=`$LDAP_SEARCH -b $NG_BASE "(Description=:::${SERIAL}::*)" cn | $GREP ^cn: | awk '{print $NF}'`
      HASSERIAL_N=`echo $HASSERIAL | $SED 's/_machine$//'`
      echo "...duplicate found"
      echo "ERROR: this machine's serial is already in use by \"${HASSERIAL}\"."
      echo "       If the host name ${HASSERIAL_N} has been decommissioned, you will need"
      echo "       to delete the netgroup \"${HASSERIAL}\" before configuring this"
      echo "       machine to use LDAP."
      echo "       If ${HASSERIAL_N} is still a valid host name, you will need to log in"
      echo "       to that server and re-run /opt/configure_ldap.sh to update LDAP with"
      echo "       the correct serial number for that host before you'll be able to continue"
      echo "       configuring this one for LDAP."
      exit 8
   else
      # If no duplicate names or serials were found then we'll verify whether we're in unattended mode
      if [[ "$UNATTENDED" != "YES" ]]; then
         OPERATION=ADD
      else
         echo "ERROR: [`basename $0`] is being run in unattended mode and there is no"
         echo "       netgroup for this server in the directory.  Unable to configure LDAP."
         echo "       please report this error message to Server Operations."
         exit 20
         
      fi
   fi
else # If there IS an existing netgroup named for this server
 
   # Parse the existing netgroup to make sure it matches

   # ldapsearch will return the Description in line-wrapped base64
   EXISTDESCB64=`$LDAP_SEARCH -b $NG_BASE "(cn=${MNG})" Description | $EGREP -v '^#|^$|^search:|^result:' | awk '/Description/,/==/' | strings | $SED ':a;N;$!ba;s/\n//g; s/ //g; s/^Description:://g'`

   # Convert to ASCII
   EXISTDESC=`echo $EXISTDESCB64 | perl -MMIME::Base64 -0777 -ne 'print decode_base64($_)' 2>&1 | awk -F':::' '{print $2}'`

   # Parse the resultant string
   EXISTSERIAL=`echo $EXISTDESC | awk -F'::' '{print $1}' | sed 's/^ //g;s/ *$//g'`
   EXISTHN=`echo $EXISTDESC | awk -F'::' '{print $2}' | sed 's/^ //g;s/ *$//g'`
   EXISTPN=`echo $EXISTDESC | awk -F'::' '{print $3}' | sed 's/^ //g;s/ *$//g'`
   EXISTDATE=`echo $EXISTDESC | awk -F'::' '{print $4}'`
   EXISTIP=`echo $EXISTDESC | awk -F'::' '{print $5}' | sed 's/^ //g;s/ *$//g'`

   # If the relevant fields match then use the existing netgroup without asking
   if [[ "$EXISTSERIAL" == "$SERIAL" ]] && [[ "$EXISTHN" == "$HN" ]] && [[ "$EXISTPN" == "$PRODUCT" ]] && [[ "$EXISTIP" == "$PUBIP" ]]; then
      OPERATION=SKIP
   else
      if [[ "$UNATTENDED" != "YES" ]]; then
         OPERATION=UPDATE
      else
         echo "ERROR: [`basename $0`] is being run in unattended mode and the netgroup"
         echo "       in the directory does not match this server. Unable to configure LDAP."
         echo "       please report this error message to Server Operations."
         exit 21

      fi

   fi
fi

echo ""

# Define group authorized to add/modify machine netgroups (for future use in clone automation)
ALG=eitldjap


if [[ $OPERATION == ADD ]] || [[ $OPERATION == UPDATE ]]; then

   # Only perform this check if NOT in the DMZ
   if [[ $DMZ != TRUE ]]; then

      echo "This host's machine account needs to be added or updated.                     "
      # Get a username from the administrator running this script to "join" the machine to the domain
      VC1=FALSE
      while [[ "$VC1" == "FALSE" ]]; do
         read -p "Account with rights to add a machine to ds.west.com: " JUSER
         if [[ -n $JUSER ]]; then
            # Check to see if the user does have rights
            APG_GOOD=FALSE
   
            # Check to see if the user account exists in the directory
            if [[ -z `$LDAP_SEARCH -b "ou=People,${LDAP_BASE}" "(uid=${JUSER})" uid | grep "^uid:"` ]]; then
               echo "Error, user [$JUSER] does not exist in the directory."
               unset JUSER
               read -p "Ctrl+C to quit, anything else to try again: " JUNK
               $TPUT cuu1; $TPUT el;$TPUT cuu1; $TPUT el;$TPUT cuu1; $TPUT el
   
            else
               # Check LDAP group membership
   
               # Get the numeric ID for the POSIX group
               #PGNID=`$LDAP_SEARCH -b $PG_BASE "(&(objectClass=posixgroup)(cn=${APG}))" gidNumber | grep "^gidNumber:" | sed 's/^gidNumber:[ \t]//'`
               #JUNGN=`$LDAP_SEARCH -b "ou=People,${LDAP_BASE}" "(uid=${JUSER})" gidNumber | grep "^gidNumber:" | sed 's/^gidNumber:[ \t]//'`
   
               # Get the DN for the user
               JUSERDN=`$LDAP_SEARCH -b "ou=People,${LDAP_BASE}" "(uid=${JUSER})" dn | grep "^dn:" | sed 's/^dn:[ \t]//'`

               if [[ -n `$LDAP_SEARCH -b $PG_BASE "(&(objectClass=groupofuniquenames)(cn=${ALG}))" uniqueMember | grep "^uniqueMember:" | grep "$JUSERDN"` ]]; then
                  VC1=TRUE
               else
                  echo "Error, user [$JUSER] does not have rights to add/modify machine accounts."
                  unset JUSER
                  read -p "Ctrl+C to quit, anything else to try again: " JUNK
                  $TPUT cuu1; $TPUT el;$TPUT cuu1; $TPUT el;$TPUT cuu1; $TPUT el
               fi
   
            fi
   
         else
            $TPUT cuu1; $TPUT el
            echo "DEBUG:Missing account with rights to add machine."
            sleep 1
         fi
   
      done
   
      # Add the joining/updating user to the description field
   
      DESC=":::${SERIAL}::${HN}::${PRODUCT}::${TIME}::${PUBIP}::${JUSER}:::"
   
      # Define the BIND test
      LDAP_BT="$LDAP_SEARCH '(ou=SUDOers)' -b \"$LDAP_BASE\" -D \"$JUSERDN\" -w"
   
      # Verify JUSER password
      VP=FALSE
      TRIES=0
      MAXTRIES=5
      while [[ $VP == FALSE ]] && [[ $TRIES -le $MAXTRIES ]]; do
         read -sp "LDAP Password ($JUSERDN): " UUP
         echo "$LDAP_BT \"$UUP\"" | /bin/bash 2>&1 >/dev/null
         if [[ $? != 0 ]]; then
            unset UUP
            let TRIES=$TRIES+1
         else
            echo ""
            VP=TRUE
         fi
      done
   fi   
fi
   


if [[ $OPERATION == ADD ]]; then

   if [[ $DMZ != TRUE ]]; then

      echo "dn: cn=$MNG,ou=Machines,$NG_BASE" > $LDIF_TMP
      echo "cn: $MNG" >> $LDIF_TMP
      echo "objectClass: top" >> $LDIF_TMP
      echo "objectClass: nisnetgroup" >> $LDIF_TMP
      echo "nisNetgroupTriple: ($HN,-,)" >> $LDIF_TMP
      echo "memberNisNetgroup: UnixAdmin_users" >> $LDIF_TMP
      echo "memberNisNetgroup: StorageAdmin_users" >> $LDIF_TMP
      echo "memberNisNetgroup: EITNightOps_users" >> $LDIF_TMP
      echo "memberNisNetgroup: eitscanp_sa" >> $LDIF_TMP
      echo "memberNisNetgroup: eitcmdbp_sa" >> $LDIF_TMP
      echo "Description: $DESC" >> $LDIF_TMP
      echo "" >> $LDIF_TMP
   
   
      # Add the machine netgroup
   
      
      echo "$LDAP_MODIFY -D \"$JUSERDN\" -w \"$UUP\" -a -f $LDIF_TMP " | /bin/bash
      if [[ $? != 0 ]]; then
         echo "...failure"
         echo "There was an error adding the object(s)"
         echo "The command that failed was:"
         echo "   $LDAP_MODIFY -D \"$JUSERDN\" -W -a -f $LDIF_TMP"
         echo ""
         exit 9
      fi
      echo "...success"
      unset UUP
      $RM $LDIF_TMP

   else

      echo "DMZ NOTICE: You will need you will need to manually create a new machine netgroup"
      echo "            for this server with the following attributes:"
      echo ""
      echo "              Hostname: ${HN}"
      echo "                Serial: ${SERIAL}"
      echo "               Product: ${PRODUCT}"
      echo "          IPv4 Address: ${PUBIP}"
      echo ""

   fi

elif [[ $OPERATION == UPDATE ]] && [[ "$PPID" != "1" ]]; then
 
   echo "The netgroup ${MNG} already exists with the following attributes:"
   echo ""
   echo "  Netgroup Name: ${MNG}"
   echo "       Hostname: ${EXISTHN}"
   echo "         Serial: ${EXISTSERIAL}"
   echo "   Product Name: ${EXISTPN}"
   echo "  IP When Added: ${EXISTIP}"
   echo "  Added/Updated: ${EXISTDATE}"
   echo ""
   echo "The CURRENT system has the following attributes:"
   echo ""
   echo "       Hostname: ${HN}"
   echo "         Serial: ${SERIAL}"
   echo "   Product Name: ${PRODUCT}"
   echo "     Current IP: ${PUBIP}"
   echo "  Added/Updated: ${TIME}"
   echo ""
   # Only prompt and set the variable IF NOT running unattended
   if [[ $DMZ != TRUE ]]; then
      if [[ $UNATTENDED == NO ]]; then
         echo "Would you like to update it with current values or use it as-is?"
         read -p "(Enter \"y\" to update, anything else to use as-is): " UMNG
      fi
   
      if [[ -n `echo $UMNG | $EGREP -i '^y'` ]]; then
         echo ""
         echo "Updating \"${MNG}\" with current values."
   
         echo "dn: cn=$MNG,ou=Machines,$NG_BASE" > $LDIF_TMP
         echo "changetype: modify" >> $LDIF_TMP
         echo "replace: Description" >> $LDIF_TMP
         echo "Description: $DESC" >> $LDIF_TMP
   
   
         #echo "$LDAP_MODIFY -a -w `echo $RI | tr "[$ECHOA]" "[$ECHOB]"` -f $LDIF_TMP " | /bin/bash 
         echo "$LDAP_MODIFY -D \"$JUSERDN\" -w \"$UUP\" -a -f $LDIF_TMP " | /bin/bash
            if [[ $? != 0 ]]; then
               echo "There was an error adding the object(s)"
               echo "The command that failed was:"
               echo "   $LDAP_MODIFY -D \"$JUSERDN\" -W -a -f $LDIF_TMP"
               echo ""
               exit 10
            fi
            unset UUP
            $RM $LDIF_TMP
      else
         echo "FAILURE: A Machine Netgroup exists that matches this server's name, but the"
         echo "         description data does not match. Manual intervention is required."
         echo "         Either run the script again in interactive mode, or update the"
         echo "         Netgroup directly in LDAP."
         exit 12
      fi

   else
      echo "FAILURE: A Machine netgroup for this server already exists, but the"
      echo "         description data does not match.  You'll need to correct the"
      echo "         Netgroup manually in LDAP before configuration can continue."
      exit 13

   fi
fi

# Configure access.conf
echo -n "Configuring /etc/security/access.conf"

ACF=/etc/security/access.conf
# Removed chattr per request in SDR6310213
chattr -i $ACF

# Generate a new access.conf
cat << EOF > $ACF.tmp

## !!NOTICE!! !!NOTICE!! !!NOTICE!! !!NOTICE!!
##
## It is a violation of West Security Policy to modify this file.
## Any unauthorized modifications will be reported and removed
## without prior notice.
##
## Access may only be provided via LDAP, which does not require
## modification of this file, and may be subject to
## InfoSec approval.
##
## !!NOTICE!! !!NOTICE!! !!NOTICE!! !!NOTICE!!

EOF

# Prevent hosts file overwriting
if [[ -z `$GREP "\-:root:172.30.7.204" $ACF.tmp` ]]; then
   echo "-:root:172.30.7.204" >> $ACF.tmp
fi

# Remove the deny all from the file
$SED -i 's/^-:ALL:ALL//' $ACF.tmp

# Remove any existing _machine netgroups - most useful for cloned systems
$SED -i ':a;N;$!ba;s/\n+:@.*_machine:ALL//g' $ACF.tmp

# allow root, zadmin, and login via group membership for linux SA's
if [[ -z `$GREP "+:root zadmin unixhw bbuser:ALL" $ACF.tmp` ]]; then
   echo "+:root zadmin unixhw bbuser:ALL" >> $ACF.tmp
fi

# allow service accounts to run cron (service accounts are not permitted to log in directly)
if [[ -z `$GREP "+:ALL:cron crond" $ACF.tmp` ]]; then
   echo "+:ALL:cron crond" >> $ACF.tmp
fi

# Add the current machine netgroup
echo "+:@$MNG:ALL" >> $ACF.tmp

# Clean up any blank lines
$SED -i '/^$/d' $ACF.tmp

# Add the deny all back to the file
echo "-:ALL:ALL" >> $ACF.tmp
echo "" >> $ACF

# Replace the real file with the temp file
if [[ -s $ACF.tmp ]] && [[ -n `/bin/grep "^+:root" $ACF.tmp` ]]; then
   /bin/mv -f $ACF.tmp $ACF
else
   echo "...FAILURE: there was a problem generating a new access.conf"
   exit 14
fi
# Removed chattr per request in SDR6310213
#chattr +i $ACF

echo "...complete"

# Add NISDOMAIN to /etc/sysconfig/network to facilitate netgroup lookups
echo -n "Configuring /etc/sysconfig/network"

if [[ -z `$GREP '^NISDOMAIN=' /etc/sysconfig/network` ]]; then
   echo "NISDOMAIN=${NISDOMAIN}" >> /etc/sysconfig/network
   echo "...complete"
else
   echo "...not needed"
fi

#Function to update sssd config file (authconfig does not do this automatically)
f_sssd-config() {
ldapuri="ldap_uri = $1"
LDMS=$2
loginfilter="; ldap_access_filter = "
    /usr/bin/wget --timeout=8 --tries=3 --quiet http://${LDMS}/0uMxWccP3EtxmU2xVJV5Hqjl4/sssd.conf-template -O /maint/scripts/sssd.conf-template

/bin/sed -e "s#\; XX-SSSDTEMPLATE_filter#$loginfilter#g" -e "s#\; XX-SSSDTEMPLATE_ldapuri#$ldapuri#g" /maint/scripts/sssd.conf-template > /etc/sssd/sssd.conf
/bin/chmod 600 /etc/sssd/sssd.conf
/bin/chown root:root /etc/sssd/sssd.conf
}

# Run authconfig according to the version of RHEL
# Removed chattr per request in SDR6310213
chattr -i /etc/passwd
chattr -i /etc/group
chattr -i /etc/shadow
echo "Applying authconfig settings.. "

if [[ $RELEASE == 7 ]]; then
   echo "RHEL 7"
   FOSL=`echo "$OSL" | sed 's/ /,/g'`
   echo "/usr/sbin/authconfig --disablekrb5realmdns --enableshadow --passalgo=sha512 --enablemd5 --disablenis --enablesssd --enablesssdauth --enableldap --enableldapauth --ldapserver=$FOSL --ldapbasedn='"$LDAP_BASE"' --enableldaptls --enablerfc2307bis --ldaploadcacert='"http://${best}/0uMxWccP3EtxmU2xVJV5Hqjl4/cacert.asc"' --enablecache --enablecachecreds --enablelocauthorize --enablepamaccess --enablemkhomedir --updateall" | /bin/bash
	systemctl stop nslcd
	systemctl disable nslcd
	systemctl stop nscd
	sed -i -e '/enable-cache.*yes/ s/yes/no/g'  -e '/enable-cache.*host/ s/no/yes/g' /etc/nscd.conf
	systemctl start nscd
	systemctl enable sssd
	systemctl stop sssd
	f_sssd-config "$SSSDOSL" "$LDAP_MASTER_SERVER"
	systemctl start sssd
	

elif [[ $RELEASE == 6 ]]; then
   echo "RHEL 6"
   FOSL=`echo $OSL | sed 's/ /,/g'`
   echo "/usr/sbin/authconfig --disablekrb5realmdns --enableshadow --passalgo=sha512 --enablemd5 --disablenis --enablesssd --enablesssdauth --enableldap --enableldapauth --ldapserver=$FOSL --ldapbasedn='"$LDAP_BASE"' --enableldaptls --enablerfc2307bis --ldaploadcacert='"http://${best}/0uMxWccP3EtxmU2xVJV5Hqjl4/cacert.asc"' --enablecache --enablecachecreds --enablelocauthorize --enablepamaccess --enablemkhomedir --updateall" | /bin/bash
	service nslcd stop
	chkconfig nslcd off
	service nscd stop
	sed -i -e '/enable-cache.*yes/ s/yes/no/g'  -e '/enable-cache.*host/ s/no/yes/g' /etc/nscd.conf
	service nscd start
	chkconfig sssd on
	service sssd stop
	f_sssd-config "$SSSDOSL" "$LDAP_MASTER_SERVER"
	service sssd start

elif [[ $RELEASE == 5 ]]; then
   echo "RHEL 5"
   echo "/usr/sbin/authconfig --disablekrb5realmdns --enableshadow --passalgo=sha512 --enablemd5 --disablenis --enablesssd --enablesssdauth --enableldap --enableldapauth --ldapserver=$OSL --ldapbasedn='"$LDAP_BASE"' --enableldaptls --enablerfc2307bis --ldaploadcacert='"http://${best}/0uMxWccP3EtxmU2xVJV5Hqjl4/cacert.asc"' --enablecache --enablecachecreds --enablelocauthorize --enablepamaccess --enablemkhomedir --updateall" | /bin/bash
        service nslcd stop
        chkconfig nslcd off
        service nscd stop
        sed -i -e '/enable-cache.*yes/ s/yes/no/g'  -e '/enable-cache.*host/ s/no/yes/g' /etc/nscd.conf
        service nscd start
        chkconfig sssd on
        service sssd stop
	f_sssd-config "$SSSDOSL" "$LDAP_MASTER_SERVER"
        service sssd start

##elif [[ $RELEASE == 4 ]]; then
##   echo "RHEL 4"
##   echo "/usr/sbin/authconfig --enableshadow --enablemd5 --disablenis --enableldap --enableldapauth --ldapserver=$OSL --ldapbasedn='"$LDAP_BASE"' --enableldaptls --enablecache --enablelocauthorize --kickstart" | /bin/bash
##   echo "session    required   pam_mkhomedir.so skel=/etc/skel/ umask=0022" >> /etc/pam.d/system-auth

##   # Set client-side idle-timeout to 300 seconds
##   $SED -i '/^[ ]*idle_timelimit/d' /etc/ldap.conf
##   echo "idle_timelimit 300" >> /etc/ldap.conf


fi
# Removed chattr per request in SDR6310213
#chattr +i /etc/passwd
#chattr +i /etc/group
#chattr +i /etc/shadow



# Configure SUDOers to use LDAP
## -- Not needed with SSSD --

#echo -n "Configuring SUDOers to use LDAP"
echo -n "Adding sssd to /etc/nsswitch.conf"
#SUDO_BASE=`$LDAP_SEARCH -b $LDAP_BASE "(ou=sudoers)" dn | $GREP ^dn: | $SED 's/dn:[ \t]//g'`
NSSWITCH=/etc/nsswitch.conf

#if [[ -z $SUDO_BASE ]]; then
#   echo "...unable to find SUDOers ou in LDAP, aborting."
#   exit 16
#else
   # RHEL 6.1 and 6.2 are not supported because of a bug with nslcd  
   # We do not support those versions

 ##  if [[ $RELEASE == 6 ]] && [[ $UPDATE -gt 2 ]] || [[ $RELEASE == 7 ]]; then
      #Configure NSSWITCH
      if [[ -n `$GREP -v ^# $NSSWITCH | $GREP -i sudoers:` ]]; then
         $SED -i 's/sudoers:.*/sudoers:   sss/g' $NSSWITCH
      else
         echo "sudoers:   sss" >> $NSSWITCH
      fi

      # Remove configurations but leave comments
 ##     $SED -i '/^#\|^$/!d' /etc/sudo-ldap.conf
      
      # Read the general config stuff from nslcd.conf
 ##     $CAT /etc/nslcd.conf | $EGREP -v '^#|^$' >> /etc/sudo-ldap.conf

      # Add sudo-specific options
 ##     echo "sudoers_base $SUDO_BASE" >> /etc/sudo-ldap.conf
 ##     echo "" >> /etc/sudo-ldap.conf

      echo "...complete"


  ## elif [[ $RELEASE == 4 ]] || [[ $RELEASE == 5 ]]; then

      # If RHEL4, sudo needs to be updated to work with LDAP
##      if [[ $RELEASE == 4 ]]; then
##         if [[ "`rpm -q sudo --queryformat %{VERSION}`" != "1.8.5" ]]; then
##            echo "...sudo update needed."
##            if [[ -n `$UNAME -m | $GREP x86_64` ]]; then
##               ARCH=x86_64
##            else
##               ARCH=i386
##            fi
 ##           URPM="sudo-1.8.5-4.el4.${ARCH}.rpm"
##            if [[ ! -f /maint/scripts/rhel4/${URPM} ]]; then
##               $MKDIR -p /maint/scripts/rhel4
##               $WGET -q http://${KS_SERV}/post_scripts/rhel4/${URPM} -O /maint/scripts/rhel4/${URPM}
##               if [[ ! -f /maint/scripts/rhel4/${URPM} ]]; then
##                  echo ""
##                  echo "Error:  This server's version of sudo is too old to work"
##                  echo "        with LDAP. An upgrade exists but this script cannot"
##                  echo "        seem to locate it.  Please locate and install"
##                  echo "        ${URPM} then re-run this script to enable sudo."
##                  exit 11
##                fi
##            fi   
##            echo "Upgrading sudo."
##            $RPM -Uvh /maint/scripts/rhel4/${URPM}
##            if [[ $# != 0 ]]; then
##               echo ""
##               echo "Error:  This server's version of sudo is too old to work"
##               echo "        with LDAP. An attempt to upgrade was made but may"
 ##              echo "        have failed.  If the above rpm error was not fatal,"
##               echo "        you can simply re-run this script to complete setup."
##               exit 12
##            fi
##           
##         fi  
##
##      fi
##
##      # Configure NSSWITCH
##      if [[ -n `$GREP -v ^# $NSSWITCH | $GREP -i sudoers:` ]]; then
##         $SED -i 's/sudoers:.*/sudoers:   ldap/g' $NSSWITCH
##      else
##         echo "sudoers:   ldap" >> $NSSWITCH
##      fi
##
##      # Configure /etc/ldap.conf
##      if [[ -n `$GREP -v ^# /etc/ldap.conf | $GREP -i "^sudoers_base"` ]]; then
##         $SED -i 's/sudoers_base.*/sudoers_base '"$SUDO_BASE"'/g' /etc/ldap.conf
##      else
##         echo "sudoers_base $SUDO_BASE" >> /etc/ldap.conf
##      fi
##      
##      echo "...complete"
##      
##   else
##      echo "...not supported on this OS."
##      exit 13
##   fi


##fi

# Replace the "passwd" file with a script

if [[ ! -f /usr/bin/passwd.real ]]; then
   /bin/mv /usr/bin/passwd /usr/bin/passwd.real

echo "#!/bin/bash

CPS=linux2441
ETU=https://idm.west.com
# We'll need LDAP search to determine whether a user is local or remote
LDAPSEARCH=\"/usr/bin/ldapsearch -x -ZZ\"

# populate the \"user\" variable the same way \"passwd\" would
if [[ -n \"\$1\" ]]; then
   user=\$1
else
   user=\$USER
fi


# If this script was run by root and the target is a local user
if [[ \$UID == 0 ]] && [[ -n \`$GREP \"^\${user}:\" /etc/passwd\` ]]; then
   /usr/bin/passwd.real \${user}
# If the user is not in LDAP
elif [[ -z \`\$LDAPSEARCH \"(uid=\${user})\" uid | $EGREP -v '^#|^$|^search:|^result:'\` ]]; then
   /usr/bin/passwd.real \${user}
else
   echo \"To update the password for \${user}, use the self service portal: \${ETU}\"
   echo \"\"
   echo \"Password has not been updated.\"
fi
" >> /usr/bin/passwd

   chmod +x /usr/bin/passwd

fi


echo "LDAP configuration has been completed."
exit 0
