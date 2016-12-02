---
# Purpose: Add directories and links, copy prepared files, and modify some existing ones

## ## chmod 755 /maint
## ## chmod 755 /maint/scripts
  - name: Setup the /maint and /maint/scripts directories
    file:
      path: {{ item }}
      state: directory 
      mode: 0755
    with_items:
      - /maint
      - /maint/scripts
      
## ## cd /maint/scripts
## ## chown -R root *
## ## chmod 744 *.sh
# TODO: Replace the wildcard with a with_items loop pulling these
#       files from a source code repository.
  - name: Fix owner on /maint/scripts files - NOT IDEMPOTENT
    shell: chown -R root *
    args:
      chdir: /maint/scripts
      
  - name: Fix permissions on /maint/scripts files - NOT IDEMPOTENT
    shell: chmod 744 *.sh
    args:
      chdir: /maint/scripts

## ## # Checking links
## ## echo "`$VTS` : Checking links..." | $LOG2
## ## 
## ## if [[ -d /opt/local ]]; then
## ##    if [[ ! -L /opt/local ]]; then
## ##       echo "`$VTS` : FAILURE: /opt/local should be a symbolic link to /usr/local, but appears to be a directory, aborting" | $LOG1
## ##       exit 2
## ##    else
## ##       if [[ -z `file /opt/local 2>&1 | grep /usr/local` ]]; then
## ##          echo "`$VTS` : FAILURE: /opt/local should be a symbolic link to /usr/local but has the wrong target, aborting" | $LOG1
## ##          exit 3
## ##       fi
## ##    fi
## ## else
## ##    ln -s /usr/local /opt/local
## ## fi
# TODO: This should be pulled out of the default build
# and addressed by the West teams that actually require these settings
# in future RHEL deployments.
  - name: Check West custom links - /opt/local
    file:
      src: /usr/local
      dest: /opt/local
      state: link
      
## ## if [[ -d /opt/log ]]; then
## ##    if [[ ! -L /opt/log ]]; then
## ##       echo "`$VTS` : FAILURE: /opt/log should be a symbolic link to /var/log, but appears to be a directory, aborting" | $LOG1
## ##       exit
## ##    else
## ##       if [[ -z `file /opt/log 2>&1 | grep /var/log` ]]; then
## ##          echo "`$VTS` :FAILURE: /opt/log should be a symbolic link to /var/log but has the wrong target, aborting" | $LOG1
## ##          exit
## ##       fi
## ##    fi
## ## else
## ##    ln -s /var/log /opt/log
## ## fi
# TODO: This should be pulled out of the default build
# and addressed by the West teams that actually require these settings
# in future RHEL deployments.
  - name: Check West custom links - /opt/log
    file:
      src: /var/log
      dest: /opt/log
      state: link
      
## ## if [[ -d /usr/log ]]; then
## ##    if [[ ! -L /usr/log ]]; then
## ##       echo "`$VTS` : FAILURE: /usr/log should be a symbolic link to /var/log, but appears to be a directory, aborting" | $LOG1
## ##       exit
## ##    else
## ##       if [[ -z `file /opt/log 2>&1 | grep /var/log` ]]; then
## ##          echo "`$VTS` :FAILURE: /usr/log should be a symbolic link to /var/log but has the wrong target, aborting" | $LOG1
## ##          exit
## ##       fi
## ##    fi
## ## else
## ##    ln -s /var/log /usr/log
## ## fi
# TODO: This should be pulled out of the default build
# and addressed by the West teams that actually require these settings
# in future RHEL deployments.
  - name: Check West custom links - /usr/log
    file:
      src: /var/log
      dest: /usr/log
      state: link
      
## ## # Only install the WIC stuff if this is a WIC server or if forced with -W
## ## #INSTALL_WIC_LEGACY=FALSE
## ## #if [[ -s /etc/sso ]] && [[ "`grep "^BU=" /etc/sso | awk -F'=' '{print $2}'`" == "wic" ]]; then
## ## #   INSTALL_WIC_LEGACY=TRUE
## ## #elif [[ -n $1 ]] && [[ -n `echo $1 | grep -i "\-W"` ]]; then
## ## #   INSTALL_WIC_LEGACY=TRUE
## ## #fi
## ## #
## ## #
## ## #if [[ $INSTALL_WIC_LEGACY != FALSE ]]; then
## ## #   /maint/scripts/setup_legacy_wic.sh
## ## #fi

# There are too many customizations in the "setup_legacy_wic" script
# to reasonably add to this Ansible playbook.  This must be handled
# and addressed by the West teams that actually require these settings
# in future RHEL deployments.

## ## # Copy config files to /etc
## ## cd /etc
## ## if [[ $DISTRO == RHEL ]] && [[ $RELEASE == 6 ]]; then
## ##    /bin/rm /etc/sudoers
## ## else
## ##    cp /etc/sudoers /etc/sudoers.old
## ## fi

  - name: Remove /etc/sudoers file for some reason
    file:
      path: /etc/sudoers
      state: absent

## ## # Populate /var/log with clean machine settings
## ## tar -C /var -xzf /maint/scripts/tars/log.tar.gz
## ## chown root:root /var/log/clean_machine/clean_machine.cfg

# Instead of "tar" use a source code repository for the files
# In Ansible we should actually list each file in a "with_items" list
# to ensure they are placed properly.

  - name: Fix the clean_machine.cfg permissions
    file:
      path: /var/log/clean_machine/clean_machine.cfg
      force: yes
      owner: root
      group: root
      state: touch

## ## # Copy "configure" and "cos" scripts to /opt
## ## cd /opt
## ## cp -rp /maint/scripts/configure_syslog.sh .
## ## cd /maint/
## ## #mv /maint/scripts/cos* .
## ## #mv /maint/scripts/unix_crypt.cfg .
## ## 
## ## # Fix perl pathing
## ## ln -s /usr/bin/perl /usr/local/bin/perl
## ## 
## ## C1=tikkgtmi+khgh     <-- /root/.rhosts
#########/root/.rhosts
## ## C2=tvgxt+khghmvjfr2  <-- /etc/hosts.equiv
#########/etc/hosts.equiv
## ## S1=tlklv
## ## S1B=lklv
## ## S2=t+huh_hvx
## ## S2B=+huh_hvx
## ## L2=twv2.gh
## ## L2B=wv2.gh
## ## 
## ## for CIP in $C1 $C2; do
## ## 
## ##    echo -n > `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
## ##    chmod 0000 `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
## ##    chown 4294967294:4294967294 `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
## ##    # Leaving in chattr for two key files until they can be monitored externally.
## ##    chattr +ui `echo $CIP | tr "[$ECHOB]" "[$ECHOA]"`
## ## 
## ## done

  - name: Protect /root/.rhosts per InfoSec requirement
    file:
      path: /root/.rhosts
      state: file
      mode: 0000
      owner: 4294967294
      group: 4294967294
      # Can't add the "immutable" flag using the file module

## ## # Make files which should not be changed immutable
## ## # Removed chattr per request in SDR6310213
## ## #SFLIST="/etc/passwd /etc/shadow /etc/group /etc/security/access.conf"
## ## #for SF in $SFLIST; do
## ## #   chattr +ui $SF
## ## #done
## ## 
## ## 
## ## # Add newline to the end of /etc/issue and issue.net
## ## echo >> /etc/issue
## ## echo >> /etc/issue.net
## ## 
## ## #  RHEL 6 is moving to a modular take on limits and this will override the standard limits.conf.  Removing to clear up the issue
## ## if [[ $DISTRO == RHEL ]] && [[ $RELEASE == 6 ]]; then
## ##    rm -f /etc/security/limits.d/90-nproc.conf
## ## fi

#  RHEL 6 is moving to a modular take on limits and this will
#  override the standard limits.conf.  Removing to clear up the issue
  - name: Remove /etc/security/limits.d/90-nproc.conf
    file:
      path: /etc/security/limits.d/90-nproc.conf
      state: absent

## ## #if [[ $DISTRO == RHEL ]] && [[ $RELEASE -lt 5 ]]; then
## ## #   # Populate .rhosts for root
## ## #   echo -en "ops1a root\nibmn root\n" >> /root/.rhosts
## ## #
## ## #   # Add COS master to /etc/hosts
## ## #   echo "172.30.8.125      linux245 linux245.wic.west.com" >> /etc/hosts
## ## ##else
## ## ##   echo "Omitting legacy configurations"
## ## #fi

# Not translated to Ansible as it is currently only for RHEL 4 and earlier.

## ## # Legacy rc.local steps
## ## #cp /maint/scripts/rc.local.1 /etc/rc.d/rc.local
