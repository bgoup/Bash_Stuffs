#!/bin/bash
cd /mnt
echo 'Start detect.sh'
while true
do
	if [ -e /dev/disk/by-label/disk ]
	then
		echo 'Start backup.sh'
		./backup.sh
		echo 'End backup.sh'
		sleep 60
		continue
	else
		#echo 'No disk detected waiting.'
		sleep 10
		continue
	fi
done
echo 'End detect.sh'
exit 0
