#!/bin/bash
#############################################
# Purpose: Adds local users
# Author: ??? / SDW / DGL
# Revision: $Rev$
# Updated by: $Author$
# Last change date: $LastChangedDate$
# SVN URL: $HeadURL$
#############################################

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

# SDR6310213 - Removing immutable non-customization that causes problems
# with some patching efforts with limited security enhancements.
for sf in "/etc/passwd /etc/shadow /etc/group"; do
   chattr -i $sf
done

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

# Everything gets zadmin
if [[ -z `grep "^zadmin:" /etc/group` ]]; then groupadd -g 1024 zadmin; fi
if [[ -z `grep "^zadmin:" /etc/passwd` ]]; then useradd -u 1024 -g 1024 -s /bin/ksh -c "ZADMIN User" -p '$6$QmK3moo0$04ipDbKj7AmNUntOHfhrGANS/DSO0AAZ0N5CRG6UdjE.5Byo/8FXxfE7lt.TymsyL2UL5.8D3q1MiYhoKgY2b0' -d /home/zadmin zadmin; fi

if [[ -z `grep "^unixapp:" /etc/group` ]]; then groupadd -g 120 unixapp; fi

# SDR6310213 - Removed deletion of "unnecessary" accounts customization.
# # Remove unnecessary accounts
# UNNEEDED_ACCOUNTS="
# apache
# games
# "
# for UA in $UNNEEDED_ACCOUNTS; do
#    if [[ -n `grep ^${UA}: /etc/passwd` ]]; then 
#       echo "# ${UA} Removed `date` by $0" >> /etc/.passwd.removed
#       grep "^${UA}" /etc/passwd >> /etc/.ps.removed
#       echo "# ${UA} Removed `date` by $0" >> /etc/.shd.removed
#       grep "^${UA}" /etc/shadow >> /etc/.shd.removed
#       /usr/sbin/userdel -f ${UA}; 
#       
#    fi
# done
# UNNEEDED_GROUPS="
# apache
# games
# "

# for UG in $UNNEEDED_GROUPS; do
#    if [[ -n `grep ^${UG}: /etc/group` ]]; then
#       echo "# ${UG} Removed `date` by $0" >> /etc/.group.removed
#       grep "^${UG}" /etc/group >> /etc/.gp.removed
#       /usr/sbin/groupdel ${UG};
#    fi
# done

# SDR6310213 - Removing immutable non-customization that causes problems
# with some patching efforts with limited security enhancements.
# for sf in "/etc/passwd /etc/shadow /etc/group"; do
#    chattr +ui $sf
# done

