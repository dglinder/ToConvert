#!/bin/sh
#############################################
# Purpose: Install and configure the Hyperic agent for the West Cloud
#    NOTE: BETA as of 2015-04-28 - DGL
# Author: DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
# To export the latest version of this file:
#   svn export https://eitsvn.west.com/svn/EIT-post_scripts/trunk/setup_hyperic.sh
#############################################

# Test flag - un-comment to enable testing.
#	NOTE: This requires ".TEST" files on the source server.
#TESTING=".TEST"

# TODO: Setup a DNS alias for den06hypap01.svc.west.com and update agent.setup.camIP setting.
HYPSRV=den06hypap01.svc.west.com

# TODO: Setup a DNS alias rather than pointing to Linux157
SOURCE_SRV=linux157.wic.west.com
# TODO: Set to "https" when a SSL cert is created for $SOURCE_SRV.
HTTP=http
#
AGENT_NAME=hyperic-agent
AGENT_INIT=/etc/init.d/${AGENT_NAME}

# The user and group to run the service as.
# Un-set ("USERID=") if you want to run as root.
USERID=eithprcp
GROUPID=eithprcp

# Hyperic needs to communicate on these ports:
# Outbound TCP connections FROM the agent to the SERVER:
CAMPORT=7080
CAMSSLPORT=7443
# Inbound TCP connections FROM the SERVER to the agent:
LOCALPORT=2144
LOCALSSLPORT=2443

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
# Alert if in TESTING mode.
if [ ! -z $TESTING ] ; then 
	echo NOTE: Running in testing mode.
fi

###########################
# Verify usefull commands and set sane values if necessary.
if [ -z "${USERID}" -o -z "${GROUPID}" ] ; then
	# Run as root if no user or group is defined.
	USERID=root
	GROUPID=root
fi

PATH=$PATH:/sbin/
CURL=$(which curl) || error_exit "Could not find curl binary."
NETCAT=$(which nc 2>/dev/null) # Not mandatory but nice.
DATESTAMP=$(date +%Y%m%d_%H%M)
CHKCONFIG=$(which chkconfig) || error_exit "Could not find chkconfig binary."
IPTABLES=$(which iptables) || error_exit "Could not find iptables binary."

TEMP_PATH=$(mktemp -d) || error_exit "Could not create a temporary directory."
cd ${TEMP_PATH} || error_exit "Unable to change to ${TEMP_PATH} - exiting."

###########################
# Confirm the user and group we're running under is available.
getent passwd ${USERID} > /dev/null || error_exit "User ${USERID} not found, exiting."
getent group ${GROUPID} > /dev/null || error_exit "Group ${GROUPID} not found, exiting."

###########################
# Verify that we have our hostname in the /etc/hosts file.
# (We'll assume it's correct...)
grep $(hostname -s) /etc/hosts > /dev/null || error_exit "Could not find $(hostname -s) in /etc/hosts - exiting."

###########################
# Check if we have NetCat, and if so check that we can communicate on the TCP ports.
if [ ! -z "${NETCAT}" ] ; then
	# We have netcat, so use it.
	# TODO: We /should/ check if we can open a local port for listening...

	# Check that the non-encrypted port is open to the server.
	if [ ! -z "${CAMPORT}" ] ; then
		# If CAMPORT is not blank, test it.
		${NETCAT} -z -w 3 ${HYPSRV} ${CAMPORT} > /dev/null || error_exit "Unable to verify that agent.setup.camPort (${CAMPORT}) is open."
	fi

	# Check that the encrypted port is open to the server.
	if [ ! -z "${CAMSSLPORT}" ] ; then
		# If CAMSSLPORT is not blank, test it.
		${NETCAT} -z -w 3 ${HYPSRV} ${CAMSSLPORT} > /dev/null || error_exit "Unable to verify that agent.setup.camSSLPort (${CAMSSLPORT}) is open."
	fi
fi

###########################
# Confirm we can communicate with the installation server.
#
INFO_FILE="${HTTP}://${SOURCE_SRV}/hw_tools/Hyperic/Hyperic.info${TESTING}"
${CURL} --silent ${INFO_FILE} > /dev/null \
	|| error_exit "Unable to retrieve install information from ${SOURCE_SRV}: ${INFO_FILE} - exiting."

###########################
# Get the info file to set some variables for us to use.
# Variables:
#  VERSION = Version of the Hyperic agent
eval $(${CURL} --silent ${INFO_FILE})

###########################
# Determine if we are a 32-bit or 64-bit system and note that to download the correct installer.
# Processort size : Hyperic expects either "x86-64" (Intel/AMD 64bit), or "x86" (for 32bit)
UNAME_M=$(uname -m)
case $UNAME_M in
	i?86 )
		PROC_SIZE=x86
		;;
	x86_64      )
		PROC_SIZE=x86-64
		;;
	*           )
		error_exit "Unable to determine processor size: $(uname -m) - exiting."
		;;
esac

###########################
# Tell user we're ready to start.
echo "Installing Hyperic agent version: ${VERSION}"
echo "Processor size: ${PROC_SIZE}"
echo "Run as user: ${USERID}"

# Setup the agent startup file location.
AGENTBASE="/opt/hyperic/hyperic-hqee-agent-${VERSION}/bundles/agent-${PROC_SIZE}-linux-${VERSION}"

# Setup the agent startup file location.
AGENTRC="${AGENTBASE}/rcfiles/agent.rc"

# Setup the agent java binary location.
JAVABIN="${AGENTBASE}/jre/bin/java"

###########################
# If there is a previous one installed, attempt to stop it.
if [ -x ${AGENT_INIT} ] ; then
	${AGENT_INIT} stop
fi

###########################
# Download the correct installer tar.gz package based on VERSION and PROC_SIZE.
INSTALL_FILE="hyperic-hqee-agent-${PROC_SIZE}-linux-${VERSION}.tar.gz"
echo
echo "Downloading ${INSTALL_FILE} from ${SOURCE_SRV}:"
${CURL} "${HTTP}://${SOURCE_SRV}/hw_tools/Hyperic/${INSTALL_FILE}" \
	-o "${TEMP_PATH}/${INSTALL_FILE}" \
	|| error_exit "Unable to download ${INSTALL_FILE} from ${SOURCE_SRV}."

###########################
# Move any old /opt/hyperic directory out of the way
if [ -d /opt/hyperic ] ; then
	OLDDS=$(date -r /opt/hyperic +%Y%m%d_%H%M)
        echo Moving old /opt/hyperic to /opt/hyperic.pre-${OLDDS}
        mv /opt/hyperic /opt/hyperic.pre-${OLDDS}
fi
rm -rf /opt/hyperic
mkdir /opt/hyperic

###########################
# Extract to /opt/hyperic
cd /opt/hyperic
tar -xzf "${TEMP_PATH}/${INSTALL_FILE}"

###########################
# Make sure Hyperic home directory does not contain a ".hq" file:
HYPHOME=$(getent passwd ${USERID} | awk -F: '{ print $6 }')
if [ ! -d "${HYPHOME}/" ] ; then
	# Attempt to make the empty home directory so the Hyperic agent doesn't complain.
	mkdir ${HYPHOME}
	chown ${USERID}:${GROUPID} ${HYPHOME}
	HDUSER=$(stat -c %U ${HYPHOME})
	HDGROUP=$(stat -c %G ${HYPHOME})
	if [[ ! -d "${HYPHOME}/" || ${HDUSER} != ${USERID} || ${HDGROUP} != ${GROUPID} ]] ; then
		# Something went wrong creating the Hyperic user home directory.
		error_exit "User ${USERID} does not have a valid home directory (${HYPHOME}) - exiting."
	fi
fi

if [ -f "${HYPHOME}/.hq" ] ; then
	echo Moving ${HYPHOME}/.hq to ${HYPHOME}/.hq.disabled.${DATESTAMP}
	mv -f "${HYPHOME}/.hq" "${HYPHOME}/.hq.disabled.${DATESTAMP}"
fi

###########################
# Setup the agent.properties in $AgentHome/conf
mv -f "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/agent.properties" "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/agent.properties.DEFAULT" > /dev/null 2>&1
${CURL} --silent "${HTTP}://${SOURCE_SRV}/hw_tools/Hyperic/agent.properties.MASTER${TESTING}" -o "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/agent.properties"

###########################
# Setup the auto-approve.properties in $AgentHome/conf
# Based loosely on notes from "https://communities.vmware.com/message/2504480"
mv -f "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/auto-approve.properties" "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/auto-approve.properties.DEFAULT" > /dev/null 2>&1
${CURL} --silent "${HTTP}://${SOURCE_SRV}/hw_tools/Hyperic/auto-approve.properties.MASTER${TESTING}" -o "/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/auto-approve.properties"

###########################
# Build the encryption key file so the pre-encrypted Hyperic agent password is usable.
SCU_FILE="/opt/hyperic/hyperic-hqee-agent-${VERSION}/conf/agent.scu"
touch ${SCU_FILE} || error_exit "Unable to create agent.scu file - exiting."
chmod 700 $SCU_FILE
cat << EOF-agent.scu > ${SCU_FILE}
#Wed Feb 04 12:39:25 MST 2015
k=ENC(4eF+QM/IaQrBO4rEj3Igu8YNS1+aKtzLB5IE1wmTUQR4Ylo/NW1DWjndQN+AkBGfsBKlYtmlEv7hOF89ta1Khw\=\=)
EOF-agent.scu

###########################
# Setup the startup scripts
${CURL} --silent "${HTTP}://${SOURCE_SRV}/hw_tools/Hyperic/hyperic-agent.initd.script${TESTING}" -o "/opt/hyperic/hyperic-hqee-agent-${VERSION}/hyperic-agent.initd.script" || error_exit "Could not find retrieve the hyperic-agent startup script."

if [ -f /etc/init.d/hyperic-hqee-agent ] ; then
	echo Renaming /etc/init.d/hyperic-hqee-agent to hyperic-hqee-agent.disabled.${DATESTAMP}
	mv /etc/init.d/hyperic-hqee-agent /etc/init.d/hyperic-hqee-agent.disabled.${DATESTAMP}
fi

###########################
# Setup the startup scripts.
cp "/opt/hyperic/hyperic-hqee-agent-${VERSION}/hyperic-agent.initd.script" ${AGENT_INIT}
chmod +x ${AGENT_INIT}
# Set the init.d script to use the provided Java binary, commenting
# out other HQ_JAVA_HOME settings.
sed -i "s/\(^.*HQ_JAVA_HOME=.*$\)/## \1/g; /HQ_JAVA_HOME=/a export HQ_JAVA_HOME=${JAVABIN}" ${AGENT_INIT}
# Ensure we're using the proper service account.
if [ ! -z "$(grep ^USER=root ${AGENT_INIT})" ] ; then 
	# Set the init.d script to use the ${USERID} user account.
	sed -i "s/^USER=root/USER=${USERID}/g" ${AGENT_INIT}
fi
if [ -f ${AGENTRC} ] ; then
	sed -i'.orig' "s#^USER=.*#USER=${USERID}#g; s#^AGENT_DIR=.*#AGENT_DIR=/opt/hyperic/hyperic-hqee-agent-${VERSION}#g" $AGENTRC
fi
${CHKCONFIG} --add ${AGENT_NAME}
${CHKCONFIG} ${AGENT_NAME} on

###########################
# Cleanup the agent /data/ and /log/ directories
# (May not exist on fresh install, but this will also address re-installs, too.)
rm -f "/opt/hyperic/hyperic-hqee-agent-${VERSION}/data/*"
rm -f "/opt/hyperic/hyperic-hqee-agent-${VERSION}/log/*"

chown -R ${USERID}:${GROUPID} /opt/hyperic

###########################
# Open the required ports in the firewall.
# External post install test: nc -v $HOSTNAME 26542
FULLNAME=`f_GetRelease`
PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`
case ${RELEASE} in
	5 )
		# RHEL 5.x
		# The LokKit command does not permit enough flexibility
		# to mirror and work with the West IPtables required
		# features (QoS, etc).
		### /usr/sbin/lokkit --port=${LOCALPORT}:tcp -q
		### /usr/sbin/lokkit --port=${LOCALSSLPORT}:tcp -q
		echo "NOTE: Must ensure that the ports (${LOCALPORT}:tcp and ${LOCALSSLPORT}:tcp) are open on this box:"
		iptables -L -n | egrep '${LOCALPORT}|${LOCALSSLPORT}'
		echo Pausing 5 seconds for manual verify.
		sleep 5
		;;
	6 )
		# RHEL 6.x
		# The LokKit command does not permit enough flexibility
		# to mirror and work with the West IPtables required
		# features (QoS, etc).
		### /usr/sbin/lokkit --port=${LOCALPORT}:tcp --update
		### /usr/sbin/lokkit --port=${LOCALSSLPORT}:tcp --update
		echo "NOTE: Must ensure that the ports (${LOCALPORT}:tcp and ${LOCALSSLPORT}:tcp) are open on this box:"
		iptables -L -n | egrep '${LOCALPORT}|${LOCALSSLPORT}'
		echo Pausing 5 seconds for manual verify.
		sleep 5
		;;
#	7 )
#		# RHEL 7.x
#		TODO / Untested:
#		firewall-cmd --permanent --add-service=tftp
#		firewall-cmd --permanent --add-port=8140/tcp
#		;;
	* )
		# Unknown
		echo "ERROR: Unknown release: ${PRODUCT} ${RELEASE}.${UPDATE}"
		exit 1
	;;
esac

for PORTNUM in ${LOCALPORT} ${LOCALSSLPORT} ; do
	# Confirm the ports are open on the local firewall.
	if [ $(${IPTABLES} -L -n | grep ${PORTNUM} | wc -l) -eq 0 ] ; then
		echo "ERROR: Unable to confirm TCP port ${PORTNUM} was opened."
		exit 1
	fi
done

###########################
# Now start up the agent
service hyperic-agent stop ; echo
service hyperic-agent start ; echo

###########################
# Cleanup
cd /tmp/ && rm -rf ${TEMP_PATH}

echo "Complete."

