#!/bin/bash

# Initial configuration of SSHD - this is intended to be used by kickstart.
# Running this on an already up system will reset all of root's authorized keys.

TS=`date +%Y%m%d%H%M%S`

##########################Configue Protocol Version ##########################
#Making ssh version 2 only

#If protocol is not set, then uncomment "Protocol" and set it explicitly to 2
if [[ -z `grep "^Protocol" /etc/ssh/sshd_config` ]]; then
   sed -i.{$TS} s/"#Protocol.*$"/"Protocol 2"/  /etc/ssh/sshd_config
else
   #... otherwise change Protocol to 2 no matter what it is currently set to
   sed -i.{$TS} s/"Protocol.*$"/"Protocol 2"/  /etc/ssh/sshd_config
fi

##########################Configue Protocol Version ##########################

##########################CREATE ROOT SSH DIRECTORY ##########################

mkdir -p -m 700 /root/.ssh
if [[ `stat -c %a /root/.ssh` != 700 ]]; then
   echo "Error establishing SSH directory for root."
   exit 1
fi

##########################CREATE ROOT SSH DIRECTORY ##########################


##########################ADD AUTHORIZED KEY FOR ROOT #########################

#Note: this will remove all existing authorized keys for root, which should be okay
#      considering this is the only key that is actually authorized for root

AKF=/root/.ssh/authorized_keys

# Make a backup of any existing key(s)
if [[ -f $AKF ]]; then
   /bin/mv $AKF /root/.ssh/backup.authorized_keys.${TS}
fi

# Write the new key
cat << EOF > /root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAABAEAkGCfkeMxye8V9lyYgvWHFKzEEjPxcjeMHMsy6R/qrCY9MfW/8GTR0JXxpH7dyOKOsuanOcclyEieSCrlmY7T+y/9A7zBFP2flWmY/zdwLZpzqf87lK1pOPOePGB+vIqYbyzTi3gODGSGIu8gYZsqWF5hGOQHnqzWJd2dOqiboCxaLLvMnKjJ/HyKWAcDRQl/thHh/m62M7TMDvDOYSM/RlW4pNwJ8wmAoXTdJd65cM9p1fEFtZWVUeeIn8MJYkv075hrVgeNnIJ6at0E39tymZKVvipYzhf6Yz6/KGXYN6qs8Zs8IjrK7L1jkIKUnr2GKTyy9buRmqy8ZnTsVwS+8LJEAaeiZL70LFwqrhz+NzPSmwraV76lqXdGqVn21SMH7catPI1WEuYi7/aWmuDNGECz6eLmzUjnNX226K9SgmhRrsfAaR3WABI2qJX98Ieom75AO+9wYQf9ATF7jVQ19QQluAryn3pdEU/ZZq46fDzu7X/zLuA05+RcB+Uop1RZ1f62cDLju3F7qUVv0rTDgMIdTIRtD0TInQz+tIFJW+rrsE8eKsD6LG2wGeU8ItQGMl/uWG1j8T6otxa4jLK31TQxYpIKocDo7BuiVx6fyT6F1fHiN0JutgDdrwf0FzIWbwvoKwU7FcFEmF4VHzL02ZUVDrO230asj0fT6xWptcxDFqsdtCtRwtkICZgYJzOaZUhmRhoygkbtdAk6AgCoklpoN+fXARPelR0aueeqjpnF28NIar/eKBfkVObn4MIEuXdKXYNp24NY/JxYX+xVKuiAPEShxSaVt56pf0H+m2sXoB9/PCuArWC/FS0ZKprkjaUl4M9N//wV3N2rZViJ17Km5zDieNGlTuGsONzjhDfRU0ZJP5CiuCfXS1AlRuy0AySmuj2n72o/V4ruMpJMkwBAIWAjvnXpei8K4nmzfgInHZrS0MxNablikN3P/HkPaSlm8sQVrRcC2d1IeHllGr1LzRRlCrz/RkmuptXBTvAIfD/Laiptpus5B0IO3iB0ZiIjSwPZAlarNfgUQ9YAdC23zg7eCv3J5ll07U8n//W4bOvwPeqlkO/iAv7ZsyyCevy9n8eW7S3NZfB28S5vmTMpwKrmRiXSZTalBE28GaHVNo8YVKmDZPBPjULv64FLvRK9mDkb1ji2dv7BS88L3ju58dMIqphR9Q5EEQDxTHd3n04BmwaW7cBaGmJSW+R5KBQlNwgyNVxqG3ZxyMCTN6fRz5RtvmqdKBU6izdOqJzJzPDP1hr/xB68vcIkmVVFxu6nF7KEe7/dpQCEDG2nP1mmOnPO/m/i9M+TLuUbAXq03USzeO1XiGHOFsaLJ2Y3BRt88p5uo8niW1MzCbhYXw== linux1410 Server Operations Admin
EOF

if [[ -z `grep '5uo8niW1MzCbhYXw== linux1410 Server Operations Admin' /root/.ssh/authorized_keys` ]]; then
   echo "Error adding authorized key for linux1410"
   exit 2
fi

chmod 644 /root/.ssh/authorized_keys
if [[ `stat -c %a /root/.ssh/authorized_keys` != 644 ]]; then
   echo "Error setting correct mode for /root/.ssh/authorized_keys"
   exit 3
fi

exit 0



