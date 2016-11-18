#!/bin/sh
#############################################
# Purpose: Setup new clone with West specific info for Radisys SWMS servers.
# Author: DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#
# NOTE: Run this script immedieatly after building a Radisys SWMS server from
#       the VM template.
#
# Steps this script takes:
#  Sets the IP address and related settings i the ifcfg-eth0 file
#  Sets the hostname (both short and FQDN)

if [[ $# -eq 0 ]] ; then
	echo Missing command line parameters. Need the hostname.
	exit
fi

HN=$1
echo Hostname provided: $HN

case $HN in
	oma00vswms02)
		IPADDR=10.50.120.112
		NETMASK=255.255.255.0
		GATEWAY=10.50.120.1
		DOM=net.west.com
		SHORTHN=${HN}
		LONGHN=${HN}.${DOM}
		DNS1=10.70.1.60
		DNS2=10.70.1.61
		NTP1=10.31.40.52
		NTP2=172.30.39.15
		;;
	oma00vswms03)
		IPADDR=10.50.120.114
		NETMASK=255.255.255.0
		GATEWAY=10.50.120.1
		DOM=net.west.com
		SHORTHN=${HN}
		LONGHN=${HN}.${DOM}
		DNS1=10.70.1.60
		DNS2=10.70.1.61
		NTP1=10.31.40.52
		NTP2=172.30.39.15
		;;
	oma00vswms04)
		IPADDR=10.50.120.118
		NETMASK=255.255.255.0
		GATEWAY=10.50.120.1
		DOM=net.west.com
		SHORTHN=${HN}
		LONGHN=${HN}.${DOM}
		DNS1=10.70.1.60
		DNS2=10.70.1.61
		NTP1=10.31.40.52
		NTP2=172.30.39.15
		;;
	*)
		echo INVALID hostname provided: ${HN}
		exit 1
esac

# Setup the IP information on eth0
FILE=/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i'' -e "s/^IPADDR=.*/IPADDR=${IPADDR}/g" ${FILE}
sed -i'' -e "s/^NETMASK=.*/NETMASK=${NETMASK}/g" ${FILE}
sed -i'' -e "s/^GATEWAY=.*/GATEWAY=${GATEWAY}/g" ${FILE}

#  Resets the hostname in the "network" files if set
FILE=/etc/sysconfig/network
sed -i'' -e "s/^HOSTNAME=.*/HOSTNAME=${SHORTHN}/g" ${FILE}
hostname ${HN}

# Add this system to the local /etc/hosts file
FILE=/etc/hosts
if [[ $(grep ${SHORTHN} ${FILE} | wc -l) -eq 0 ]] ; then
	echo Updating ${FILE} with ${LONGHN} information.
	echo "${IPADDR}	${LONGHN} ${SHORTHN}" >> ${FILE}
else
	echo Found ${SHORTHN} in ${FILE}, not modifying.
fi

#  Configures ntp.conf with "West Cloud" specific NTP servers
FILE=/etc/ntp.conf
awk "/^server.*/{ \
	c++; \
	if(c==1){sub(\"server.*\",\"server $NTP1\")}; \
	if(c==2){sub(\"server.*\",\"server $NTP2\")}; \
	}1" ${FILE} > ${FILE}.tmp && mv ${FILE}.tmp ${FILE}

#  Ensures the NTP daemon is set to start on boot and time is correct
#   during bootup.

# Setup the correct timezone.
OLD_DIR=$(pwd)
cd /etc
rm -f /etc/localtime
ln -s ../usr/share/zoneinfo/US/Eastern ./localtime
cd ${OLD_DIR}

chkconfig ntpd on

FILE=/etc/rc.local
if [[ $(grep ntp.net.west.com ${FILE} | wc -l) -eq 0 ]] ; then
	echo Adding NTP configurations to ${FILE}.
	echo "/sbin/service ntpd stop
/usr/sbin/ntpdate -b ntp.net.west.com
/sbin/service ntpd start
" >> ${FILE}
else
	echo West NTP settings already applied to ${FILE}.
fi

#  Adjusts the resolv.conf to add the "net.west.com" domain and to
#   use the West Cloud specific DNS server entries
FILE=/etc/resolv.conf
if [[ $(grep net.west.com ${FILE} | wc -l) -eq 0 ]] ; then
	echo Updating ${FILE}
	echo "search west.com wic.west.com corp.westworlds.com svc.west.com icallinc.com net.west.com
nameserver ${DNS1}
nameserver ${DNS2}
" > ${FILE}
else
	echo West ${FILE} settings already applied.
fi

echo Restarting services...
service network restart

echo Configuration of eth0:
ifconfig eth0

echo
echo -n Confirming ping to default gateway:
if [[ ! $(ping -c 1 ${GATEWAY}) ]] ; then
	echo Ping failed - please check.
	exit
else
	echo Success
fi

echo Current time: $(date)
echo Short hostnmae: $(hostname -s)
echo Long hostnmae: $(hostname -f)

echo Rebooting to confirm changes.
reboot -f now

