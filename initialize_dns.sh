#!/bin/bash

# This creates the initial DNS configuration during kickstart
# Do not use this on an up-and-running system

RESOLV=/etc/resolv.conf

echo "search svc.west.com wic.west.com icallinc.com" > $RESOLV
echo "nameserver 10.19.119.82" >> $RESOLV
echo "nameserver 10.19.119.83" >> $RESOLV
echo "nameserver 10.17.126.43" >> $RESOLV
