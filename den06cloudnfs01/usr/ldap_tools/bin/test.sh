#!/bin/bash

echo "$0 -h <hostname> -s <serial> -pn <product name> -ip <ip adress> -ru <requesting user> -bg <business group>"


echo "[$@]"


HN=`echo $@ | awk -F'-h' '{print $2}' | awk -F' -' '{print $1}'`
SERIAL=`echo $@ | awk -F'-s' '{print $2}' | awk -F' -' '{print $1}'`
PN=`echo $@ | awk -F'-pn' '{print $2}' | awk -F' -' '{print $1}'`


echo "HN: $HN"
echo "S: $SERIAL"
echo "PN: $PN"
echo "IP: $IP"
echo "RU: $RU"
