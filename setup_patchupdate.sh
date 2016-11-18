#!/bin/bash 
# This script performs a full yum-update of the system.
# This script can be modified to perform other one-off tasks
# that are to be performed when a system has been freshly
# provisioned.

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

LOG=/root/yum-y.upgrade.out
date | tee -a $LOG
yum -y upgrade 2>&1 | tee -a $LOG
date | tee -a $LOG


