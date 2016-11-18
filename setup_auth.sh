#!/bin/sh

#  Setting up a top level script to manage the decision tree for authentication
#  Users now have the option to select either the legacy NSS_LDAP or the new SSSD
## Alex - 20151007
# Determine authentication type
# SSSD is currently beta - too little info for full production
# NSS_LDAP caching is broken in many RHEL6 releases (up to glibc 166-6_7.3)
# The option to build systems on SSSD is being added as an option.
# SSSD will be the standard for RHEL7

# Include common_functions.h
if [[ -s /maint/scripts/common_functions.h ]]; then
   source /maint/scripts/common_functions.h
elif [[ -s common_functions.h ]]; then
   source common_functions.h
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         Setup has not been completed on this system."
   exit 2
fi

if [[ -z $VTS ]]; then
   export VTS="date +%Y%m%d%H%M%S"
fi

if [[ -z $LOGFILE ]]; then
   export LOGFILE=/var/log/install/`basename $0`.log
   f_SetLogLevel 0
fi

# Server Statement of Origin
SSO=/etc/sso

# We will always default to legacy NSS auth, just in case....
AUTHTYPE=NSS

if [[ -f $SSO ]]
then
	AUTHCHECK=`grep "^AUTHTYPE=" $SSO | cut -d'=' -f2`
	if [[ $AUTHCHECK == SSSD ]] || [[ $AUTHCHECK == NSS ]]
	then
		AUTHTYPE="$AUTHCHECK"
		echo AUTHTYPE: ${AUTHTYPE}
		if [[ $AUTHTYPE == SSSD ]]
		then
			/maint/scripts/setup_ldap-sssd.sh
			exit $?
		elif [[ $AUTHTYPE == NSS ]]
		then
			/maint/scripts/setup_ldap.sh
			exit $?
		fi
	else
		echo ""
		echo "!!!!!!!!!!!!!!"
		echo "!!!!ERROR!!!!!"
		echo "!!!!!!!!!!!!!!"
		echo "$SSO either does not contain an entry for AUTHTYPE or the entry is not understood."
		echo "Please note - this script is not meant to be run interactively, it is part of setup_linux.sh."
		echo "If you are imaging a server, something failed with the setup_statement_of_origin script."
		echo "If you are running this directly, please refer to the documented procedures for retrofitting servers."
		echo "This script is not intended to be used to change previously configured systems."
		echo ""
		exit 99
	fi
else
	echo ""
	echo "!!!!!!!!!!!!!!"
	echo "!!!!ERROR!!!!!"
	echo "!!!!!!!!!!!!!!"
	echo "$SSO could not be read, or does not exist."
	echo "Please note - this script is not meant to be run interactively, it is part of setup_linux.sh."
	echo "If you are imaging a server, something failed and the setup_statement_of_origin script did not generate $SSO."
	echo "If you are running this directly, please refer to the documented procedures for retrofitting servers."
	echo "This script is not intended to be used to change previously configured systems."
	echo ""
	exit 99
fi

exit
##NOTES
#
#   AUTHTYPE=NSS
#   echo ""
#   echo "----------------------------------------------------"
#   echo " What authentication service would you like to use? "
#   echo "----------------------------------------------------"
#   read -p "Enter SSSD if your end user has agreed to beta test SSSD authentication \(non-prod only please\)"
#   read -p "A blank answer, or any other entry will be read in as the legacy option of NSS " AUTHTYPE
#   if [[ $AUTHTYPE == SSSD ]] || [[ $AUTHTYPE == sssd ]]; then
#      AUTHTYPE=SSSD
#      echo "`$VTS`:setup_motd.sh - user selected SSSD as the authentication client." | $LOG1
#      echo "AUTHTYPE=SSSD" #>> $SSO
#   else
#      AUTHTYPE=NSS
#      echo "`$VTS`:setup_motd.sh - user selected NSS_LDAP as the authentication client." | $LOG1
#      echo "AUTHTYPE=NSS" #>> $SSO
#   fi
#fi
#
