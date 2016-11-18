#!/bin/bash

###########################################
# Purpose: Delete A New Netgroup
# Author: SDW
# Incept 08/08/2012

# Notes: - basic LDAP authentication must already be configured and working
#          on the server where this script is run from

f_Usage () {
   echo "$0 USAGE"
   echo ""
   echo "$0 <netgroup name>"
   echo ""
   echo "   Deletes a netgroup from the directory and removes it"
   echo "   from any other netgroups."
   echo ""
}


# Set path to the location of the script no matter how it was invoked
if [[ `echo $0 | sed 's/^.\///g'` == `basename $0` ]]; then
   WORKDIR=`pwd`
else
   BASENAME=`basename $0`
   WORKDIR=`echo $0 | sed 's/'"$BASENAME"'$//g'`
fi

cd $WORKDIR

# Set some basic options for ldap searching, durrently the directory server doesn't require a binddn or a rootbinddn
# so simple authentication should work fine
LDAP_SEARCH="/usr/bin/ldapsearch -x -ZZ"
UPDATE_USER=`ldapsearch -x -ZZ "(uid=$USER)" dn | grep ^dn: | sed 's/^dn:[ \t]//'`
LDAP_MODIFY="/usr/bin/ldapmodify -x -ZZ -D \"$UPDATE_USER\""
LDAP_BT="$LDAP_SEARCH '(ou=SUDOers)' -D \"$UPDATE_USER\" -w"
MAXTRIES=5

# Define variables
LDIF_TMP=/eit/admin/scripts/ldap_tools/tmp/.`basename $0`.$$.ldt
TS=`date +%Y%m%d%H%M%S`
BACKUP_DIR=/eit/admin/scripts/ldap_tools/local_backup


# find the ldap base
if [[ -s /etc/ldap.conf ]]; then
   LDC=/etc/ldap.conf
elif [[ -s /etc/openldap/ldap.conf ]]; then
   LDC=/etc/openldap/ldap.conf
fi
LDAP_BASE=`egrep -i "^base[ \t]" $LDC | sed 's/^base[ \t]//i'`

if [[ -z $LDAP_BASE ]]; then 
   echo "Unable to find the base dn for LDAP - please make sure ldap is properly"
   echo "configured on this machine.  If it IS properly configured and you're"
   echo "still getting this error, you probably need to update the LDAP_SEARCH"
   echo "variable in this script to something that works with the current config."
   exit
fi

# Look for a "Netgroups" OU at the base level
NG_BASE=`$LDAP_SEARCH '(ou=Netgroups)' | grep "dn: ou" | awk '{print $2}'`

# Set a path for LSNETGROUP

LSNETGROUP=./lsnetgroup

# Assume nothing is needed until a check fails
NEEDOU=FALSE

# If there is no Netgroups OU then we need to create the OU
if [[ -z $NG_BASE ]]; then 
  echo "No Netgroup OU was found at $LDAP_BASE..."
  echo "Please run the appropriate script from directory-setup"
  echo "and try again."
  exit
fi

if [[ -z $UPDATE_USER ]]; then
   echo "Unable to locate the correct DN for your user account [$USER]."
   echo "You must be a member of the domain in order to use this script."
   exit
fi

# Get information from the user

NGTBD=$1

# If we got a name from the command line
if [[ -n $NGTBD ]]; then
   if [[ "$NGTBD" == "--help" ]]; then
      f_Usage
      exit
   elif [[ "$NGTBD" == "oma10devds01_machine" ]] || [[ "$NGTBD" == "ISDevelopment_users" ]]; then
      echo "Error: $NGTBD cannot be deleted."
      exit
   fi

   # Verify the netgroup exists
   if [[ -z `$LDAP_SEARCH -b $NG_BASE "(cn=${NGTBD})" 2>&1 | egrep -v '^#|^$|^search|^result'` ]]; then
      echo "ERROR: netgroup \"$NGTBD\" not found in the directory."
      exit
   else
      NGTBDDN=`$LDAP_SEARCH -b $NG_BASE "(cn=${NGTBD})" dn | sed ':a;N;$!ba;s/\n //g' | grep $NGTBD | grep ^dn: | sed 's/^dn: //g'`
   fi

# If we did NOT get a name from the command line 
else 

   # Prompt the user for a name
   VC2=FALSE
   while [[ $VC2 == FALSE ]]; do
      unset GNGTBD
      read -p "What is the name of the netgroup to be deleted?: " GNGTBD

      # Check for non-existence - retry on error
      if [[ -z `$LDAP_SEARCH -b $NG_BASE "(cn=${GNGTBD})" 2>&1 | egrep -v '^#|^$|^search|^result'` ]]; then
         echo "ERROR: netgroup \"$NGTBD\" not found in the directory."
         read -p "Press Enter to try a different name, Ctrl+C to cancel." JUNK
         tput cuu1; tput el; tput cuu1; tput el; tput uuu1; tput el
      else
         VC2=TRUE
         NGTBD=$GNGTBD
         NGTBDDN=`$LDAP_SEARCH -b $NG_BASE "(cn=${NGTBD})" dn | sed ':a;N;$!ba;s/\n //g' | grep $NGTBD | grep ^dn: | sed 's/^dn: //g'`
      fi
   done
fi

# Protect certain nggroups
PROTECTED_NGS="
UnixAdmin_users
oma00ds01_machine
oma00ds01_machine
"

for PROTECTED_NG in $PROTECTED_NGS; do
   if [[ -n `echo $PROTECTED_NG | grep -i "^${NGTBD}$"` ]]; then
      echo "Error: Cannot delete [$NGTBD] as doing so would damage the directory."
      exit 199
   fi
done



# Get all netgroups which have this one as a member

PNGS=`$LSNETGROUP -M $NGTBD`

# Create a backup file for the netgroup
if [[ ! -d $BACKUP_DIR ]]; then
   mkdir -p $BACKUP_DIR
fi
LDIF_BAK=${BACKUP_DIR}/ng_deleted_${NGTBD}_${TS}.ldif

echo "## Script Name: $0" > $LDIF_BAK
echo "## Executed By/From: `/usr/bin/who -m`" >> $LDIF_BAK
echo "##" >> $LDIF_BAK

$LDAP_SEARCH -b $NG_BASE "(cn=${NGTBD})" 2>&1 | egrep -v '^#|^$|^search|^result' >> $LDIF_BAK

if [[ ! -s $LDIF_BAK ]]; then
   echo "Error: there was a problem creating the backup file for $NGTBD"
   exit
#else
#   echo "Backup created: $LDIF_BAK"
fi

# Create ldif to delete the netgroup
cat << EOF > $LDIF_TMP
dn: $NGTBDDN
changetype: delete
EOF

# Get all netgroups which have this one as a member

PNGS=`$LSNETGROUP -M $NGTBD`
if [[ -n $PNGS ]]; then echo "\"$NGTBD\" will also be removed from parent netgroups: $PNGS"; fi
for PNG in $PNGS; do
   PNGDN=`$LDAP_SEARCH -b $NG_BASE "(cn=${PNG})" dn | grep ^dn: | sed 's/^dn: //g'`
cat << EOF >> $LDIF_BAK
dn: $PNGDN
changetype: modify
add: memberNisNetgroup
memberNisNetgroup: $NGTBD

EOF

cat << EOF >> $LDIF_TMP

dn: $PNGDN
changetype: modify
delete: memberNisNetgroup
memberNisNetgroup: $NGTBD
EOF
done

# Ask for confirmation
echo ""
echo "You have requested to delete:"
echo "   $NGTBDDN"
echo ""
read -p "Is this correct? (Enter Y to delete, anything else to quit): " CONFIRM
if [[ -z `echo $CONFIRM | grep -i "^Y$"` ]]; then
   echo "Action Cancelled."
   echo "## Update cancelled" >> $LDIF_BAK
else   


   # Verify LDAP password
   VP=FALSE
   TRIES=0
   while [[ $VP == FALSE ]] && [[ $TRIES -le $MAXTRIES ]]; do
      read -sp "LDAP Password ($UPDATE_USER): " UUP
      echo "$LDAP_BT \"$UUP\"" | /bin/bash 2>&1 >/dev/null
      if [[ $? != 0 ]]; then
         unset UUP
         let TRIES=$TRIES+1
      else
         echo ""
         VP=TRUE
      fi
   done
   
   
   echo "$LDAP_MODIFY -w \"$UUP\" -a -f $LDIF_TMP " | /bin/bash
   if [[ $? != 0 ]]; then
      echo "There was an error adding the object(s)"
      echo "The command that failed was:"
      echo "   $LDAP_MODIFY -W -a -f $LDIF_TMP"
      echo ""
      echo "## Update failed" >> $LDIF_BAK
      exit
   fi
fi

echo "## Update succeeded" >> $LDIF_BAK
/bin/rm $LDIF_TMP
   
   
if [[ -z `$LDAP_SEARCH -b $NG_BASE "(cn=${NGTBD})" 2>&1 | egrep -v '^#|^$|^search|^result'` ]]; then
   echo "Netgroup \"$NGTBD\" was successfully removed from the directory."
else
   echo "Netgroup \"$NGTBD\" was NOT removed from the directory."
fi

