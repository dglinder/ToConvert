#!/bin/bash

# Include common_functions.h
SCRIPTDIR1=/maint/scripts

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 255
fi

if [[ -z $LOGFILE ]]; then
   export LOGFILE=/var/log/install/`basename $0`.log
   f_SetLogLevel 0
fi

SSDNSNAME="oma00rhs01.svc.west.com"
SSIPADDR="10.27.35.60"
ADDLOCAL=`f_InDMZ`

f_DEBUG "Beginning $0"
f_DEBUG "SSDNSNAME:${SSDNSNAME}"
f_DEBUG "SSIPADDR:${SSIPADDR}"

if [[ $ADDLOCAL != TRUE ]]
then
	f_DEBUG "Verifying DNS resolution of $SSDNSNAME....."
	SSRESCHECK=`host ${SSDNSNAME} 2>&1`
	if [[ $? -ne 0 ]]
	then
		ADDLOCAL=TRUE
	fi
fi

if [[ $ADDLOCAL == TRUE ]]
then
	HOSTSCHECK=`grep $SSDNSNAME /etc/hosts`
	if [[ -z $HOSTCHECK ]]
	then
		f_DEBUG "DNS resolution failed, appending \"$SSIPADDR $SSDNSNAME\" to /etc/hosts before proceeding."
        	echo "$SSIPADDR $SSDNSNAME" >> /etc/hosts
	fi
else
        f_DEBUG "DNS resolution is good: $SSRESCHECK"
fi

f_DEBUG "Gathering BU from /etc/sso"
GBU=$1
if [[ -z $GBU ]]
then
	if [[ -f /etc/sso ]]
	then
		SSOBU=`grep "^BU=" /etc/sso | cut -d'=' -f2`
		case $SSOBU in
			eitcorp) GBU=EIT
				;;
			intercall) GBU=ITC
				;;
			wic) GBU=WIC
				;;
			wbs) GBU=WIC
				;;
			wan) GBU=WIC
				;;
			*) GBU=$SSOBU
				;;
		esac
	fi
fi
f_DEBUG "RHSS group BU: ${BGU}"

# Set tracking key value

case $GBU in

     EIT ) TRACKINGKEY=1-eit_group_key
           ;;
     WIC ) TRACKINGKEY=1-wic_group_key
           ;;
      IS ) TRACKINGKEY=1-wic_group_key
           ;;
     ITC ) TRACKINGKEY=1-itc_group_key
           ;;
     WBS ) TRACKINGKEY=1-wbs_group_key
           ;;
   CLOUD ) TRACKINGKEY=1-cloud_key
           ;;
    CORP ) TRACKINGKEY=1-corp_group_key
	   ;;
       * ) echo "Failure: unknown BU [$GBU]"
           exit 2
           ;;
esac

# Set primary key value

# Get distro and release
DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`

# Figure out architecure
if [[ -n `uname -m | grep x86_64` ]]; then
   ARCH=64
else
   ARCH=32
fi

f_DEBUG "DISTRO:${DISTRO}"
f_DEBUG "RELEASE:${RELEASE}"
f_DEBUG "ARCH:${ARCH}"

if [[ "$DISTRO" != "RHEL" ]]; then
   echo "Error: Only Red Hat Enterprise Server is supported."
   exit 3
fi

if [[ $RELEASE -lt 5 ]] || [[ $RELEASE -gt 7 ]]; then
   echo "Error: $DISTRO $RELEASE is not a supported release."
   exit 4
fi

case $ARCH in

   32 ) if [[ $RELEASE == 5 ]]; then
           PRIMARYKEY=1-rhel-5-32bit_standard
        else
           echo "Error: 32-bit versions of $DISTRO $RELEASE are not supported."
           exit 5
        fi
        ;;
   64 ) case $RELEASE in
           
           5 ) PRIMARYKEY=1-rhel-5-standard
               ;;
           6 ) PRIMARYKEY=1-rhel-6-standard
               ;;
           * ) echo "Error: $DISTRO $RELEASE is not a supported release."
               exit 6
               ;;
        esac
        ;;
    * ) echo "Error: invalid architecture [$ARCH] set."
        exit 7
        ;;
esac

# Determine profile name - basically the simple hostname

PROFILENAME=`hostname | awk -F'.' '{print $1}' | tr '[:upper:]' '[:lower:]'`


# Install the SSL certificate from the satellite server
/usr/bin/wget -q --no-check-certificate https://${SSDNSNAME}/pub/RHN-ORG-TRUSTED-SSL-CERT -O /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT

# Install the RPM signing key from the satellite server
/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

# Use the SSL cert for the rhn agent
/bin/sed 's/RHNS-CA-CERT/RHN-ORG-TRUSTED-SSL-CERT/g' -i /etc/sysconfig/rhn/up2date

# Set the address of the satellite server for the rhn agent
/bin/sed "s/xmlrpc.rhn.redhat.com/${SSDNSNAME}/g" -i /etc/sysconfig/rhn/up2date

# Change the frequency of rhn agent check-in to the minimum of 60 minutes
sed -i "s/INTERVAL=.*/INTERVAL=60/" /etc/sysconfig/rhn/rhnsd

# Restart the rhn agent after reconfiguration
/etc/init.d/rhnsd restart

# Allow the satellite server to perform all actions via the agent
mkdir -p /etc/sysconfig/rhn/allowed-actions/script
touch /etc/sysconfig/rhn/allowed-actions/script/run
mkdir -p /etc/sysconfig/rhn/allowed-actions/configfiles
touch /etc/sysconfig/rhn/allowed-actions/configfiles/all

# First registration Example
f_DEBUG "Beginning registration process, this may take several seconds."
/usr/sbin/rhnreg_ks --force --profilename=${PROFILENAME} --serverUrl=https://${SSDNSNAME}/XMLRPC --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --activationkey=${PRIMARYKEY},${TRACKINGKEY} 2>&1 | cat -n | tee -a $LOGFILE
RESULT=$?

if [[ $RESULT == 0 ]]; then
   echo "Registration succeeded."
   if [[ -x /usr/bin/rhn-actions-control ]]; then
      /usr/bin/rhn-actions-control --enable-all
   fi
   f_DEBUG "Starting yum update"
   /usr/bin/yum update -y 2>&1 | tee -a $LOGFILE
   EC=$?
   f_DEBUG "Finished yum update, exit code: $EC"
else
   echo "Registration unsuccessful, exit code: $EC"
fi

f_DEBUG "Ending $0"

