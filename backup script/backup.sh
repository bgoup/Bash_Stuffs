#!/bin/bash

func_dateformat() {
date +%y.%m.%d_%I:%M:%S
}

BACKUP_DIR_WORK="/mnt"
BACKUP_DIR_SOURCE="/data/" # list of dirs use a trailing /
BACKUP_DIR_DEST="/mnt/disk" # do not use a trailing /
BACKUP_DIR_LOG="$BACKUP_DIR_WORK/logs/backup" # log directory
BACKUP_DISK_LABEL="disk" # partition label. no spaces in label!
BACKUP_LOG_FILE="$BACKUP_DIR_LOG/backup_$(func_dateformat).log" # log name scheme
BACKUP_RSYNC_BLACKLIST="$BACKUP_DIR_WORK/blacklist.txt" 
BACKUP_RSYNC_BLACKLIST_DEFUALT='
pagefile.sys
System\ Volume\ Information
\$RECYCLE.BIN
Index
desktop.ini
.tmp.drivedownload
'

echo 'Start Backup'
echo 'Start Backup' >> "$BACKUP_LOG_FILE"

# make log file
echo "Log: Start"
echo "Log: Start" >> "$BACKUP_LOG_FILE"
if [ -d "$BACKUP_DIR_LOG" ]
then 
	echo "Log: Directory Exists"
	echo "Log: Directory Exists" >> "$BACKUP_LOG_FILE"
else
	echo "Log: Creating Log Directory"
	echo "Log: Creating Log Directory" >> "$BACKUP_LOG_FILE"
	mkdir "$BACKUP_DIR_LOG"
fi

# make blacklist file
echo "Blacklist: Start"
echo "Blacklist: Start"
if [ -e "$BACKUP_RSYNC_BLACKLIST" ]
then 
	echo "Blacklist: Exists"
	echo "Blacklist: Exists" >> "$BACKUP_LOG_FILE"
else
	echo "Blacklist: Creating Blacklist File"
	echo "Blacklist: Creating Blacklist File" >> "$BACKUP_LOG_FILE"
	echo "$BACKUP_RSYNC_BLACKLIST_DEFUALT" >> "$BACKUP_RSYNC_BLACKLIST"
fi

# mount disk
echo "Mount: Start"
echo "Mount: Start" >> "$BACKUP_LOG_FILE"
mount -o sync,noexec,nodev,noatime,nodiratime "/dev/disk/by-label/$BACKUP_DISK_LABEL" "$BACKUP_DIR_DEST"
echo "Mount: End"
echo "Mount: End" >> "$BACKUP_LOG_FILE"

# check that disk is mounted
echo "Mount: Dest. Check"
echo "Mount: Dest. Check" >> "$BACKUP_LOG_FILE"
mountpoint -q "$BACKUP_DIR_DEST"
if [ $? -eq 0 ]
then
	echo "Mount: Check: Good"
	echo "Mount: Check: Good" >> "$BACKUP_LOG_FILE"
	echo '+++ ' $(func_dateformat) ' Backup disk mounted.'
	echo '+++ ' $(func_dateformat) ' Backup disk mounted.' >> "$BACKUP_LOG_FILE"
else
	echo "Mount: Check: Bad"
	echo "Mount: Check: Bad" >> "$BACKUP_LOG_FILE"
	echo '--- ' $(func_dateformat) ' Error. Backup disk not mounted.'
	echo '--- ' $(func_dateformat) ' Error. Backup disk not mounted.' >> "$BACKUP_LOG_FILE"
	exit 1
fi

# run backup
echo "Rsync: Start"
echo "Rsync: Start" >> "$BACKUP_LOG_FILE"
# -r = recursive, -t = preserve modification times, -v = verbose, -h = human-readable numbers, u = updates files that are newer on the source, progress = shows progress, delete = deletes files not found in the source, ignore-existing = ignores any files that already exist
rsync -rtvhu --stats --progress --delete --ignore-existing --exclude-from="$BACKUP_RSYNC_BLACKLIST" --modify-window=1 -s  "$BACKUP_DIR_SOURCE" "$BACKUP_DIR_DEST" 
BACKUP_RSYNC_EXIT="$?"
echo "Rsync: End"
echo "Rsync: End" >> "$BACKUP_LOG_FILE"
case "$BACKUP_RSYNC_EXIT" in
	0) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Success)';;
	1) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Syntax or usage error)';;
	2) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Protocol incompatibility)';;
	3) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Errors selecting input/output files, dirs)';;
	4) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Requested  action not supported: an attempt was made to manipulate 64-bit files on a platform that cannot support them; or an option was specified that is supported by the client and not by the server.)';;
	5) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error starting client-server protocol)';;
	6) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Daemon unable to append to log-file)';;
	10) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error in socket I/O)';;
	11) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error in file I/O)';;
	12) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error in rsync protocol data stream)';;
	13) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Errors with program diagnostics)';;
	14) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error in IPC code)';;
	20) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Received SIGUSR1 or SIGINT)';;
	21) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Some error returned by waitpid())';;
	22) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Error allocating core memory buffers)';;
	23) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Partial transfer due to error)';;
	24) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Partial transfer due to vanished source files)';;
	25) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (The --max-delete limit stopped deletions)';;
	30) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Timeout in data send/receive)';;
	35) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Timeout waiting for daemon connection)';;
	127) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Rsync binary may not be installed)';;
	*) BACKUP_RSYNC_RETURN="$BACKUP_RSYNC_EXIT"' (Sub command error code)';;
esac

# post log message
echo '+++ ' $(func_dateformat) " Rsync exit code: $BACKUP_RSYNC_RETURN"
echo '+++ ' $(func_dateformat) " Rsync exit code: $BACKUP_RSYNC_RETURN" >> "$BACKUP_LOG_FILE"

# df readout
echo 'Disk space usage:' 
df -h /dev/$(sed 's|/dev/||' <<< "$(readlink -f "/dev/disk/by-label/$BACKUP_DISK_LABEL")")
echo 'Disk space usage:' >> "$BACKUP_LOG_FILE"
df -h /dev/$(sed 's|/dev/||' <<< "$(readlink -f "/dev/disk/by-label/$BACKUP_DISK_LABEL")") >> "$BACKUP_LOG_FILE"

# unmount backup disk
umount "$BACKUP_DIR_DEST"
if [ $? = 0 ]
then
	echo 'Successfuly unmounted'
	echo 'Successfuly unmounted'  >> "$BACKUP_LOG_FILE"
else
	echo 'Failed to unmount'
	echo 'Failed to unmount' >> "$BACKUP_LOG_FILE"
fi
# eject disk
echo 1 > "/sys/block/$(sed 's|[1-9]||' <<< $(sed 's|/dev/||' <<< "$(readlink -f "/dev/disk/by-label/$BACKUP_DISK_LABEL")"))/device/delete"
if [ $? = 0 ]
then
	echo 'Successfuly ejected'
	echo 'Successfuly ejected'  >> "$BACKUP_LOG_FILE"
else
	echo 'Failed to eject'
	echo 'Failed to eject' >> "$BACKUP_LOG_FILE"
fi

echo 'End Backup'
exit 0
#eof
