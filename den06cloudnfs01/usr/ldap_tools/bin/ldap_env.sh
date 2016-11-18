# Attributes not defined here will attempt to read from
# system settings to determine LDAP environment

LDAP_SERVER="oma00ds02.ds.west.com"
LDAP_SEARCH="/usr/bin/ldapsearch -x -ZZ -h ${LDAP_SERVER}"

#UPDATE_USER=`ldapsearch -x -ZZ "(uid=$USER)" dn | grep ^dn: | sed 's/^dn:[ \t]//'`
UPDATE_USER="cn=machine management agent,cn=config"
UPDATE_PASS="CRSMZP1MjimUzdHGCENDTJy2LxvIihyyFgQ"
LDAP_MODIFY="/usr/bin/ldapmodify -x -ZZ -h ${LDAP_SERVER} -w \"$UPDATE_PASS\" -D \"$UPDATE_USER\""
LDAP_BT="$LDAP_SEARCH '(ou=SUDOers)' -D \"$UPDATE_USER\" -w \"$UPDATE_PASS\""
MAXTRIES=5
LOG_DIR=/usr/ldap_tools/log
BACKUP_DIR=/usr/ldap_tools/local_backup
TS=`date +%Y%m%d%H%M%S`
LDAP_BASE="dc=ds,dc=west,dc=com"
NG_BASE="ou=Netgroups,${LDAP_BASE}"
SUDO_BASE="ou=SUDOers,${LDAP_BASE}"

