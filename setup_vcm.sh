#!/bin/sh
#############################################
# Purpose: Install and configure the VMware Configuration
#          Manager agent for the West Cloud
# Author: DGL
# Revision: $Rev$ 
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

VCMSRV=den06vcm01

# TODO: Setup a DNS alias rather than pointing to Linux157
SOURCE_SRV=linux157.wic.west.com
# TODO: Set to "https" when a SSL cert is created for $SOURCE_SRV.
HTTP=http
#
AGENT_NAME=csi-agent
AGENT_INIT=/etc/init.d/${AGENT_NAME}

# The user and group to run the service as.
# Un-set ("USERID=") if you want to run as root.
# TODO: Should be "eitvrcmp" and "cfgsoft" when in production.
USERID=eitvrcmp
GROUPID=cfgsoft

# Hyperic needs to communicate on these ports:
# Outbound TCP connections FROM the agent to the SERVER:
CAMPORT=7080
# Inbound TCP connections FROM the SERVER to the agent:
# The default <port_number> is 26542 for VCM installations.
LOCALPORT=26542

function error_exit {
# Report error message and exit.
        echo "$1" 1>&2
        exit 1
}

###########################
# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
	source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
	source common_functions.h
else
	echo "ERROR:Critical dependency failure: unable to locate common_functions.h"
	exit 1
fi

###########################
# Verify usefull commands and set sane values if necessary.
if [ -z "${USERID}" -o -z "${GROUPID}" ] ; then
	# Run as root if no user or group is defined.
	USERID=root
	GROUPID=root
fi

CURL=$(which curl) || error_exit "Could not find curl binary."
GREP=$(which grep) || error_exit "Could not find grep binary."
NETCAT=$(which nc 2>/dev/null) # Not mandatory but nice.
DATESTAMP=$(date +%Y%m%d_%H%M)

TEMP_PATH=$(mktemp -d) || error_exit "Could not create a temporary directory."
cd ${TEMP_PATH} || error_exit "Unable to change to ${TEMP_PATH} - exiting."

###########################
# Confirm the user and group we're running under is available.
getent passwd ${USERID} > /dev/null || error_exit "User ${USERID} not found, exiting."
getent group ${GROUPID} > /dev/null || error_exit "Group ${GROUPID} not found, exiting."

###########################
# Verify that we have our hostname in the /etc/hosts file.
# (We'll assume it's correct...)
${GREP} $(hostname -s) /etc/hosts > /dev/null || error_exit "Could not find $(hostname -s) in /etc/hosts - exiting."

###########################
# Check if we have NetCat, and if so check that we can communicate on the TCP ports.
#if [ ! -z "${NETCAT}" ] ; then
#	# We have netcat, so use it.
#
#	# Check that the non-encrypted port is open to the server.
#	if [ ! -z "${CAMPORT}" ] ; then
#		# If CAMPORT is not blank, test it.
#		${NETCAT} -z -w 3 ${VCMSRV} ${CAMPORT} > /dev/null || error_exit "Unable to verify that agent.setup.camPort (${CAMPORT}) is open."
#	fi
#
#	# Check that the encrypted port is open to the server.
#	if [ ! -z "${CAMSSLPORT}" ] ; then
#		# If CAMSSLPORT is not blank, test it.
#		${NETCAT} -z -w 3 ${VCMSRV} ${CAMSSLPORT} > /dev/null || error_exit "Unable to verify that agent.setup.camSSLPort (${CAMSSLPORT}) is open."
#	fi
#fi

###########################
# Confirm we can communicate with the installation server.
#
${CURL} --fail --silent ${HTTP}://${SOURCE_SRV}/hw_tools/vConfigMgr/vConfigMgr.info > /dev/null \
	|| error_exit "Unable to retrieve install information from ${SOURCE_SRV} - exiting."

###########################
# Get the info file to set some variables for us to use.
# Variables:
#  VERSION = Version of the Hyperic agent
${CURL} -o vConfigMgr.info --fail --silent ${HTTP}://${SOURCE_SRV}/hw_tools/vConfigMgr/vConfigMgr.info
if [ -e vConfigMgr.info ] ; then
	. ./vConfigMgr.info
	echo VERSION: ${VERSION}
else
	echo "Failed to download vConfigMgr.info from ${SOURCE_SRV}."
	exit 1
fi

if [ -z ${VERSION} ] ; then
	echo "Unable to get version from the vConfigMgr.info file on ${SOURCE_SRV}."
	exit 1
fi

###########################
# Determine if we are a 32-bit or 64-bit system and note that to download the correct installer.
# Processort size : Hyperic expects either "x86-64" (Intel/AMD 64bit), or "x86" (for 32bit)
UNAME_M=$(uname -m)
case $UNAME_M in
	i?86 )
		PROC_SIZE=x86-32
		;;
	x86_64      )
		PROC_SIZE=x86-64
		;;
	*           )
		error_exit "Unable to determine processor size: $(uname -m) - exiting."
		;;
esac

OSTYPE=$(uname -s)

###########################
# Check that the firewall port is open
# External post install test: nc -v $HOSTNAME 26542
FULLNAME=`f_GetRelease`
PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`
case ${RELEASE} in
	5 )
		# RHEL 5.x
		/usr/sbin/lokkit --port=${LOCALPORT}:tcp -q
		;;
	6 )
		# RHEL 6.x
		/usr/sbin/lokkit --port=${LOCALPORT}:tcp --update
		;;
	* )
		# Unknown
		echo "ERROR: Unknown release: ${PRODUCT} ${RELEASE}.${UPDATE}"
		exit 1
		;;
esac

if [ $(iptables -L -n | grep ${LOCALPORT} | wc -l) -eq 0 ] ; then
	echo "ERROR: Unable to confirm TCP port ${LOCALPORT} was opened."
	exit 1
fi

###########################
# Tell user we're ready to start.
echo "Installing Hyperic agent version: ${VERSION}"
echo "Processor size: ${PROC_SIZE}"
echo "OS type: ${OSTYPE}"
echo "Run as user: ${USERID}"
echo "Run as group: ${GROUPID}"
echo "Downloading to: ${TEMP_PATH}/"

###########################
# If there is a previous one installed, attempt to stop it.
if [ -x ${AGENT_INIT} ] ; then
	${AGENT_INIT} stop
fi

###########################
# Download the correct installer files based on VERSION and PROC_SIZE.
INSTALL_FILE="CMAgent.${VERSION}.${OSTYPE}"
echo
echo "Downloading ${INSTALL_FILE} from ${SOURCE_SRV}:"
${CURL} --fail "${HTTP}://${SOURCE_SRV}/hw_tools/vConfigMgr/${VERSION}/${INSTALL_FILE}" \
	-o "${TEMP_PATH}/${INSTALL_FILE}" \
	|| error_exit "Unable to download ${INSTALL_FILE} from ${SOURCE_SRV}."
echo
chmod u+x "${TEMP_PATH}/${INSTALL_FILE}"

echo "Downloading csi.config.west from ${SOURCE_SRV}:"
${CURL} --fail "${HTTP}://${SOURCE_SRV}/hw_tools/vConfigMgr/${VERSION}/csi.config.west" \
	-o "${TEMP_PATH}/csi.config.west" \
	|| error_exit "Unable to download csi.config.west from ${SOURCE_SRV}."
echo

###########################
# Extract the files, use the "-o" (overwrite) just in case.
cd "${TEMP_PATH}/"
./"${INSTALL_FILE}" -o

###########################
# Use the West csi.config file instead of the pre-packaged one.
AGENT_CONF=CSIInstall/csi.config
cp ${AGENT_CONF} ${AGENT_CONF}.orig
cp -p ${TEMP_PATH}/csi.config.west ${AGENT_CONF}

# TODO : Remove when vCM agent installer is LDAP aware.
#        A support ticket (15679347006) and feature request (???)
#        were opened June 2015 to address this. - DanL (SDR 1459424)
###########################
# Add the $USERID to the /etc/passwd
# NOTE: HACK! Need to get real fix from VMWare to check LDAP via getent, 
# and/or add to WC /etc/passwd file.
if [ $( ${GREP} "^${USERID}:" /etc/passwd 2>&1 | wc -l ) -eq 0 ] ; then
	echo "NOTE: Adding ${USERID} to /etc/passwd."
	IMMUTABLE=0
	if [ "$(lsattr /etc/passwd | cut -c 5)" == "i" ] ; then
		IMMUTABLE=1
		chattr -i /etc/passwd
	fi
	cp -p /etc/passwd /etc/passwd.pre-vCM-agent
	getent -s ldap passwd ${USERID} | sed 's/\ *$//g' >> /etc/passwd
	if [ ${IMMUTABLE} -eq 1 ] ; then
		chattr +i /etc/passwd
	fi
fi

# TODO : Remove when vCM agent supports customer groups and is LDAP aware.
#        A support ticket (15679304506) and a feature request (but 1459424)
#        were opened June 2015 to address this. - DanL (SDR 1459424)
###########################
# Add the $GROUPID to the /etc/group
# NOTE: HACK! Need to get VMware to support LDAP and customer supplied group name.
if [ $( ${GREP} "^${GROUPID}:" /etc/group 2>&1 | wc -l ) -eq 0 ] ; then
	echo "NOTE: Adding ${GROUPID} to /etc/group."
	IMMUTABLE=0
	if [ "$(lsattr /etc/group | cut -c 5)" == "i" ] ; then
		IMMUTABLE=1
		chattr -i /etc/group
	fi
	cp -p /etc/group /etc/group.pre-vCM-agent
	getent -s ldap group ${GROUPID} >> /etc/group
	if [ ${IMMUTABLE} -eq 1 ] ; then
		chattr +i /etc/group
	fi
fi

# ##################################################
# ## HACK HACK HACK HACK HACK HACK HACK HACK HACK ##
# ## Remove when the "cfgsoft" group is actually created in production.
# ##################################################
# echo "##################################################"
# echo "## HACK HACK HACK HACK HACK HACK HACK HACK HACK ##"
# echo "##################################################"
# echo ": REMOVE BEFORE PRODUCTION!"
# if [ $( ${GREP} "^cfgsoft:" /etc/group 2>&1 | wc -l ) -eq 0 ] ; then
# 	echo " -> Adding cfgsoft as alias of eithprcp group."
# 	echo "cfgsoft:*:999:" >> /etc/group
# fi
# ##################################################
# ## HACK HACK HACK HACK HACK HACK HACK HACK HACK ##
# ##################################################
# 
# echo "DEBUG: Updated passwd and group, check"
# read

###########################
# Move any old /opt/CMAgent directory out of the way
if [ -d /opt/CMAgent ] ; then
	OLDDS=$(date -r /opt/CMAgent +%Y%m%d_%H%M)
        echo Moving old /opt/CMAgent to /opt/CMAgent.pre-${OLDDS}
        mv /opt/CMAgent /opt/CMAgent.pre-${OLDDS}
fi
rm -rf /opt/CMAgent

###########################
# Run the installer (it will use csi.config to answer questions).
cd CSIInstall/
./InstallCMAgent -s
EC=$?
echo "Installer exit code: ${EC}"
if [ $EC -gt 0 ] ; then
	error_exit "Installation failed, exiting."
fi

###########################
# Cleanup the install files if we appear to install successful.
cd /
rm -rf ${TEMP_PATH}

echo "Complete."

