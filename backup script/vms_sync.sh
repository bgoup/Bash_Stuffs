#!/bin/bash
func_dateformat() {
date +%y.%m.%d_%I:%M:%S
}

echo 'Start VMs Sync'

SYNC_WORK="/mnt"
SYNC_SOURCE="sync_sources.txt" # file with list of sources (ssh remotes directories)
SYNC_DEST="/data/.vmsync" # do not use a trailing /
SYNC_DIR_LOG="$SYNC_WORK/logs/sync" # log directory
SYNC_LOG_FILE="$SYNC_DIR_LOG/sync_$(func_dateformat).log" # log name scheme
SYNC_BLACKLIST="$SYNC_WORK/blacklist.txt" 

while IFS= read -r LINE
do
	echo 'Start Sync for: ' "$LINE"
	echo 'Start Sync for: ' "$LINE" >> "$SYNC_LOG_FILE"
	TARGET_HOSTNAME=$(sed s/^.*@//g <<< $(sed s/:.*$//g <<< "$LINE"))
	TARGET_PATH=$(sed s/^.*://g <<< "$LINE")
	mkdir -p "$SYNC_DEST/$TARGET_HOSTNAME$TARGET_PATH"
	rsync -rthzuv --delete --ignore-existing --exclude-from="$SYNC_BLACKLIST" --copy-links --modify-window=1 -s  "$LINE" "$SYNC_DEST/$TARGET_HOSTNAME$TARGET_PATH" >> "$SYNC_LOG_FILE" &
done < "$SYNC_SOURCE"
exit 0
#eof
