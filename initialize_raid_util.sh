#!/bin/bash

##################################################
# Purpose: Install RAID utility where appropriate
# Author: SDW
# Incept: 20120821
#
# Note: these utilities are very specific to vendors
#       and chipsets.  New hardware may require updates
#       to both the identification logic and binaries
# 
# Currently recognized hardware:
#   LSI MegaRaid, ServRaid controllers
#   Adaptec SCSI RAID controllers
#   HP SmartArray controllers

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi


VENDOR=`f_GetVendor`
WORKING_DIR=`f_PathOfScript`

# Figure out architecure
if [[ -n `uname -m | grep x86_64` ]]; then
   ARCH=64
else
   ARCH=32
fi

# Break down the process by vendor
if [[ $VENDOR == HP ]]; then
   # Currently the hpacucli seems to handle any and all things HP
   if [[ $ARCH == 64 ]]; then
      rpm -ivH ${WORKING_DIR}/rpms/hp-raid/hpacucli-9.10-22.0.x86_64.rpm
   else
      rpm -ivH ${WORKING_DIR}/rpms/hp-raid/hpacucli-9.10-22.0.i386.rpm
   fi
elif [[ $VENDOR == IBM ]]; then
   # Check for adaptec RAID
   if [[ -n `/sbin/lspci | grep -i raid | grep -i adaptec` ]]; then
      # Copy the appropriate arcconf file to /sbin
      tar -C /sbin -xzf ${WORKING_DIR}/tars/arcconf.tar.gz arcconf-${ARCH}
      ln -s /sbin/arcconf-${ARCH} /sbin/arcconf
   # Check for LSI RAID
   elif [[ -n `/sbin/lspci | grep -i raid | grep -i LSI` ]]; then
      rpm -ivH ${WORKING_DIR}/rpms/lsi-raid/Lib_Utils*.noarch.rpm
      rpm -ivH ${WORKING_DIR}/rpms/lsi-raid/MegaCli*.noarch.rpm
   fi
fi
