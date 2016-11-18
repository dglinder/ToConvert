#!/bin/bash

if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
elif [[ -s /images/post_scripts/common_functions.h ]]; then
   source /images/post_scripts/common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

#f_DetectVM
f_FindPubIP
#f_FindDefaultGW
#f_CheckIF eth0
#f_IPforIF eth0
f_GetRelease
#f_ValidIPv4
#f_MakeSiteMenu
#f_IsNetUp
#f_AtWest
#f_FindPubIF
#f_SpinningCountdown 10
#f_PathOfScript
#f_GetVendor
#f_GetPhysicalDriveCount

#PUBIF=`f_AskPubIF`
#echo $PUBIF
#f_IsHostValid oma00ds01.ds.west.com 389

#f_IsIPInCIDR 172.16/12 172.30.113.120
#f_IsIPInCIDR 10/8 172.30.113.120
f_InDMZ
f_GetImageServerIP
