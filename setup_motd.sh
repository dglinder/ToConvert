#!/bin/bash
#
# New MOTD generator script
#!/bin/bash

# Purpose: create MOTD message with meaningful information

##################VARIABLE DEFINITIONS#############

SCRIPTDIR1=/maint/scripts
SCRIPTDIR2=/usr/sbin

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.h" ]]; then
   source "${SCRIPTDIR1}/common_functions.h"
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

################MAIN EXECUTION START##############################

# If there is no "orig" file then move the current MOTD to it
# If this has already been done, we don't want to overwrite the original
# with one that isn't original
if [[ ! -f /etc/motd.orig ]]; then
   mv /etc/motd /etc/motd.orig
fi

# Rebuild the sso file so we have the latest data available.
f_DEBUG "Start of $0."
f_DEBUG "Regenerating the SSO file."
/maint/scripts/regensso.sh

# The the info file contains mostly the non-programmaticly generated data
INFOFILE=/etc/motd.info
SSO=/etc/sso

# First, attempt to get the details from the SSO file
if [[ -s $SSO ]]; then
   LOCATION=`grep "^SITENAME=" $SSO | awk -F'=' '{print $2}'`
   PURPOSE=`grep "^PURPOSE=" $SSO | awk -F'=' '{print $2}'`
fi

if [[ -z $PURPOSE ]] || [[ -z $LOCATION ]] || [[ $1 == -r ]]; then

   echo "Where is this machine located?"
   read -p "A site name such as \"DEN06\": " LOCATION
   if [[ -z $LOCATION ]]; then
      LOCATION=UNSET
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:setup_motd.sh - user declined to provide location" | $LOG1
      fi
   else
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:setup_motd.sh - user provided $LOCATION for LOCATION" | $LOG1
      fi
   fi

   echo  "What will this unit be used for?"
   read -p "A short description such as \"VXML Server\": " PURPOSE
   if [[ -z $PURPOSE ]]; then
      PURPOSE=UNSET
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:setup_motd.sh - user declined to provide a purpose for the server" | $LOG1
      fi
   else
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:setup_motd.sh - user provided \"$PURPOSE\" as the server's purpose" | $LOG1
      fi
   fi

   echo > $INFOFILE
   echo "Location:${LOCATION}" >> $INFOFILE
   echo "Purpose:${PURPOSE}" >> $INFOFILE
fi

###     Gather the disc info
# Logical disk count
LDISKS=`fdisk -l 2>&1 | grep ^Disk | egrep -v 'doesn|mapper|identifier|type' | wc -l`
# Physical disk count
PDISKS=`f_GetPhysicalDriveCount`

# The function to get physical disks returns 0 if unsuccessful
# In that case, just use logical disk count
if [[ $PDISKS -gt 0 ]]; then
   DISKS=$PDISKS
else
   DISKS=$LDISKS
fi

# Get total disk capacity
total=
for s in `fdisk -l 2>&1 | grep ^Disk | egrep -v 'doesn|mapper|identifier' | awk '{print $3}'`; do
   total=$total+$s
done
total=`echo $total | sed 's/^+//g'`
SIZE=`echo $total | bc`
if [[ -s $INFOFILE ]] && [[ -n `grep "^Disks:" $INFOFILE` ]]; then
   sed -i '/^Disks:/d' $INFOFILE
fi
DISK_STRING="Disks:${SIZE} GB Storage using ${DISKS} disks"


# Reformat a couple of variables
#loc=$LOCATION
#loc=`cat $INFOFILE | grep ^L | awk -F: '{ print $2 }'`
#disks=`cat $INFOFILE | grep ^D | awk -F: '{ print $2 }'`
#purpose=$PURPOSE
#purpose=`cat $INFOFILE | grep ^P | awk -F: '{ print $2 }'`


#### Software Information ####
 
name=`uname -a | awk '{print $2}'`                               # Gets the hostname
os=`uname -a | awk '{print $1" "$3}'`                            #Gets the OS and Kernel
mem=`cat /proc/meminfo | grep MemTotal | awk '{print $2" "$3}'`  #Gets the RAM info
gcc=`cat /proc/version | awk '{print $5" "$6" "$7} ' | tr -d '()'`            #Gets GCC version
ver=`cat /etc/redhat-release`                                    #Gets the RH version

#### END Software Information ####

#### Network Information ####

# Determine the public IP based on the gateway
#subnet=`grep "^GATEWAY" /etc/sysconfig/network | awk -F'=' '{print $2}' | awk -F'.' '{print $1"."$2"."$3}'`
#ip=`ifconfig | grep $subnet | awk -F'addr:' '{print $2}' | awk '{print $1}'`
ip=`f_FindPubIP`

#### END Network Information ####

#### Machine Information ####

product=`/usr/sbin/dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Product" | awk -F':' '{print $NF}'`
# Set up some conditional logic to output differently for IBM and non-IBM
if [[ `f_GetVendor` == IBM ]]; then
   machine=`echo $product | tr -d '[]' | awk -F'-' '{print $1}' | sed 's/IBM//' | sed 's/System//'`
   model=`echo $product | tr -d '[]' | awk -F'-' '{print $2}'`
   model1=`echo $model | cut -c 1-4`
   model2=`echo $model | cut -c 5-8`
   product_string="Model: $model1-$model2    Machine: IBM$machine"
   echo $name","$ip",IBM,"$model1-$model2","$machine","$serial"," > invfile.csv
else
   product_string="Machine Type: $product"
fi

serial=`/usr/sbin/dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Serial Number" | awk -F':' '{print $NF}'`
firmware=`/usr/sbin/dmidecode | awk /"BIOS Information"/,/"Capabilities"/ | grep "Version: " | head -1 | awk '{print $2}' | sed 's/^-\[//' | sed 's/\]-$//g'`

#### END Machine Information ####

#### Memory Information ####

memchips=`/usr/sbin/dmidecode -t 17 | grep Size | egrep -v 'No Module Installed' | sort | uniq -c | awk '{print $1"x"$3 $4}' | tr '\n' ','` 

#### END Memory Information ####

#### CPU information ####

# Get a socket count by looking at how many unique physical ids there are
socket_count=`cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l`
if [[ -z $socket_count ]] || [[ $socket_count == 0 ]]; then
   socket_count=1
fi

# Get a physical core count by looking at how many unique core ids we have per physical id
phys_core_count=
for i in `cat /proc/cpuinfo | grep "physical id" | sort -u | awk '{print $NF}'`; do
   this_core_count=`cat /proc/cpuinfo | sed 's/\t/ /g' | sed 's/ //g' | awk /"physicalid:$i"/,/"coreid"/ | grep "coreid"| sort -u | wc -l`
   let phys_core_count=$phys_core_count+$this_core_count
done

if [[ -z $phys_core_count ]]; then
   phys_core_count=1
fi

# Get a thread count based on the raw number of "processors" showing up
thread_count=`cat /proc/cpuinfo | grep "^processor" | wc -l`

# If the core and thread counts don't agree, it can only be because hyperthreading is on
if [[ $phys_core_count != $thread_count ]]; then
   cpunmbr="($phys_core_count cores, $thread_count threads)"
else
   cpunmbr="($phys_core_count cores)"
fi

# Grab the CPU speed
cpuspeed=`/usr/sbin/dmidecode | grep "Current Speed" | egrep -v "Unknown" | sort | uniq | cut -c17-25`
cpuspeed=`echo $cpuspeed | sed 's/^ //' | sed 's/ $//'`

# Grab the CPU type
cputype=`/usr/sbin/dmidecode | awk /"Processor Information"/,/"Core Enabled"/ | grep "Version:" | head -1 | sed 's/Version://' | awk -F'@' '{print $1}' | sed 's/\t/ /g' | sed 's/ \+ / /g'`
cputype=`echo $cputype | sed 's/^ //' | sed 's/ $//'`

#### END CPU Information ####

#### Output Results ####

outfile=/etc/.motd.tmp
echo "-------------------------------------------------------------------------" > ${outfile}
echo " Name: $name                             $LOCATION " >> ${outfile}
echo " West Corporation                          $PURPOSE " >> ${outfile}
echo " " >> ${outfile}
echo " $product_string" >> ${outfile}
echo " Serial#: $serial " >> ${outfile}
echo " BIOS: $firmware " >> ${outfile}
echo " GCC: $gcc " >> ${outfile}
echo " Version at Build: $ver " >> ${outfile}
echo " Kernel: $os " >> ${outfile}
echo " CPU: ${socket_count}x ${cputype} ${cpuspeed} Processor(s), $cpunmbr " >> ${outfile}
echo " RAM: $memchips Total Usable: $mem " >> ${outfile}
echo " $gb " >> ${outfile}
echo " $DISK_STRING " >> ${outfile}
echo " " >> ${outfile}
echo " $ip " >> ${outfile}
echo " Firewall Enabled at Install" >> ${outfile}
echo " " >> ${outfile} 
echo "-------------------------------------------------------------------------" >> ${outfile}
echo "I acknowledge and agree that: (A) I have been authorized by West to gain access and use the Internet and/or West's systems; (B) my access and usage is monitored and logged and any such monitoring information may be shared by West with any third party; (C) I will take no action to harm West, its clients or suppliers, or others, or gain unauthorized access to any information of West, its clients or suppliers or others; (D) West reserves the right to deny use or access in its sole discretion and without notice. By continuing, I represent that I am an authorized user, and expressly consent and agree to the foregoing." >> ${outfile}


#Now let's take what we have and put it in the motd
/bin/mv $outfile /etc/motd

#DONE!
