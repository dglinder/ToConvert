#!/bin/sh
#############################################
# Purpose: Prep Radisys VM image for template usage.
# Author: DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#
# NOTE: Run this script just before powering off and converting to a template.
#       Changes this script makes are detrimental to the connectivity of this
#       specific system, but are necessary to anonymize it in preparation for
#       being used as a template.
#
#       When a clone is produced from this template, run the setup_radisys.sh
#       script to setup the files and settings for that specific Radisys system.
#
# Steps this script takes:
#  Clears out the udev persistent net rules
#   - Resets the knowledge about what MAC address is assigned to eth0
#  Clear out the IP address and related settings in the ifcfg-eth0 file
#  Resets the hostname in the "network"
#  Configures ntp.conf with "West Cloud" specific NTP servers
#   - May need to modify this in future deployments
#  Ensures the NTP daemon is set to start on boot and time is correct
#   during bootup.
#  Adjusts the resolv.conf to add the "net.west.com" domain and to
#   use the West Cloud specific DNS server entries

# Clear out persistent net rules
echo > /etc/udev/rules.d/70-persistent-net.rules

# Clear out IP settings
FILE=/etc/sysconfig/network-scripts/ifcfg-eth0
sed -i'' -e 's/^IPADDR=.*/IPADDR=#IPADDR#/g' ${FILE}
sed -i'' -e 's/^NETMASK=.*/NETMASK=#NETMASK#/g' ${FILE}
sed -i'' -e 's/^GATEWAY=.*/GATEWAY=#GATEWAY#/g' ${FILE}

#  Resets the hostname in the "network" files if set
FILE=/etc/sysconfig/network
sed -i'' -e 's/^HOSTNAME=.*/HOSTNAME=#HOSTNAME#/g' ${FILE}

#  Configures ntp.conf with "West Cloud" specific NTP servers
FILE=/etc/ntp.conf
sed -i'' -e 's/^server .*/server #NTPSERVER#/g' ${FILE}

#  Ensures the NTP daemon is set to start on boot and time is correct
#   during bootup.

chkconfig ntpd on

#  Adjusts the resolv.conf to add the "net.west.com" domain and to
#   use the West Cloud specific DNS server entries
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
nameserver 10.70.1.60
nameserver 10.70.1.61
" > ${FILE}
else
	echo West ${FILE} settings already applied.
fi

echo Updates completed - powering down.
poweroff -f now
sleep 999
# We'll never get here...

