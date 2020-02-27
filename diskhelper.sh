#!/bin/bash

## Options ##

	# script settings
CMD_CHECKS="true"
SAFETY_CHECKS="true"
INSTALL_DEP="false"

	# defualt command settings
DD_BS="1M"
DD_FILE_EXT=".dd" 
DD_OPTIONS="conv=sync,noerror" # conv=sync,noerror
CLONE_COMP="0" # 0-9
CLONE_BS="1M"
GZIP_FILE_EXT=".gz" # .zip .z .gz
FILE_SIZE_UNIT="iec" # si, iec, iec-i
FILE_SIZE_SUFFIX="B"

		# Shreding
SHRED_METHOD_DD_TYPE="/dev/urandom"
SHRED_METHOD_DD_PASS="1"

SHRED_METHOD_SHRED_PASS="3"
SHRED_METHOD_SHRED_ZERO="false"
SHRED_METHOD_SHRED_DEL="false"

SCRUB_METHOD_SCRUB_PATTERN="nnsa"
SCRUB_METHOD_SCRUB_FREESPACE="false"
SCRUB_METHOD_SCRUB_DEL="false"

		# smart data
SMART_TARGET=""

		# Benchmarking
DEFUALT_BENCH_PATTERN_PERCENT="50"
DEFUALT_BENCH_SIZE="4G"
DEFUALT_BENCH_BS="4k"
DEFUALT_BENCH_COUNT="1"
DEFUALT_BENCH_RUNTIME="60"
DEFUALT_BENCH_JOBDEPTH="1"

BENCH_TARGET=""
BENCH_PATTERN="read"
BENCH_PATTERN_PERCENT="$DEFUALT_BENCH_PATTERN_PERCENT"
BENCH_SIZE="$DEFUALT_BENCH_SIZE"
BENCH_BS="$DEFUALT_BENCH_BS"
BENCH_COUNT="$DEFUALT_BENCH_COUNT"
BENCH_RUNTIME="$DEFUALT_BENCH_RUNTIME"
BENCH_JOBDEPTH="$DEFUALT_BENCH_JOBDEPTH"

DEFUALT_BENCH_FILE_LOCATION="/tmp/" 
DEFUALT_BENCH_FILE_NAME="bench.tmp"

BENCH_FILE_LOCATION="$DEFUALT_BENCH_FILE_LOCATION"
BENCH_FILE_NAME="$DEFUALT_BENCH_FILE_NAME"
BENCH_PREALLOCATION='false'


BENCH_FIO_CMD="fio-cmd.ini"
BENCH_FIO_RESULTS="fio-results.txt"

## STARTUP ##
func_greetings () {
clear
echo "$(func_print_div)
	Welcome to the Disk Helper script!
	Written by Bryce Goupille
	$(date)
$(func_print_div)"
func_menu_entertocontinue
clear
}
func_cmd_checks () {
echo "Starting Command checks..."
# Checking for and switching to root user
if [[ $(whoami) != root ]]
then
	echo "You should run this as root user! Some things might not work otherwise!"
	func_menu_entertocontinue
fi

# command checks
SOFTWARE_ABSENT=''
SOFTWARE_LIST='dd
lsblk
pv
screen
scrub
shred
smartctl
numfmt
testdisk
fio'

for SOFTWARE_ITEM in $SOFTWARE_LIST
do
	if command -v $SOFTWARE_ITEM &> /dev/null
	then
		continue
	else
		SOFTWARE_ABSENT=$SOFTWARE_ABSENT' '$SOFTWARE_ITEM
	fi
done
	
if [[ -n $SOFTWARE_ABSENT ]]
then
	echo "It appears the following commands are absent, not all features may work: " $SOFTWARE_ABSENT
	func_menu_entertocontinue
fi

if [[ $INSTALL_DEP = "true" ]]
then
	apt-get update && apt-get install -y coreutils util-linux screen pv scrub shred smartmontools testdisk
fi
}

## INTERUPTS ##
func_cleanup () {
# PhotoRec Session file
rm -i photorec.ses 2> /dev/null
rm -i $BENCH_FIO_CMD 2> /dev/null
rm -i $DEFUALT_BENCH_FILE_LOCATION$BENCH_FILE_NAME 2> /dev/null
exit 0
}
#func_interupt () {
#clear
#}

## CLONE FUNCTIONS ##

	# Get size of source and target (in bytes)
func_clone_source_size () {
if $(echo "$CLONE_SOURCE" | grep '/dev/' &> /dev/null)
then
	# check size of block device
	SOURCE_SIZE=$(blockdev --getsize64 "$CLONE_SOURCE")
	SOURCE_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$SOURCE_SIZE")
	SOURCE_TYPE="d"
else
	if $(echo "$CLONE_SOURCE" | grep -E ".zip|.gz|.z" &> /dev/null)
	then
		# check size of compressed file
		SOURCE_SIZE=$(zcat "$CLONE_SOURCE" | wc -c | tr -dc '0-9\n')
		SOURCE_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$SOURCE_SIZE")
		SOURCE_TYPE="cf"
	else
		# check size of uncompressed file
		SOURCE_SIZE=$(wc -c "$CLONE_SOURCE" | tr -dc '0-9\n')
		SOURCE_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$SOURCE_SIZE")
		SOURCE_TYPE="f"
	fi
fi
}
func_clone_target_size () {
if $(echo "$CLONE_TARGET" | grep '/dev/' &> /dev/null)
then
	# check size of block device
	TARGET_SIZE=$(blockdev --getsize64 "$CLONE_TARGET")
	TARGET_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$TARGET_SIZE")
	TARGET_TYPE="d"
else
	# check space on target file system
	TARGET_SIZE=$(df -k -B 1 $(echo "$CLONE_TARGET" | sed 's/[^\/]*$//') | grep / | sed 's/ \+/ /' | cut -d ' ' -f 4)
	TARGET_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$TARGET_SIZE")
	TARGET_TYPE="f"
fi
}

	# Primary Menu Selections
func_clone_source () {
	func_clone_source_error () {
while true
do
clear
echo "$(func_print_div)
$ERROR_MESSAGE
$(func_print_div)
	(K) Keep source and continue.
	(S) Start a screen session to fix it.
	(Q) Quit to imaging menu.
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	k|K)
		return 0 
	;;
	s|S)
		func_screen
		continue
	;;
	q|Q)
		CLONE_SOURCE=''
		clear
		# this is a hacky way to exit to the menu system without prompting twice relies on if statment following function call
		return 10
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_clone_source_safety () {
# Check if device file
if echo $CLONE_SOURCE | grep '/dev/' &> /dev/null
then
	# check if partion/disk exists
	if lsblk -p | grep "$CLONE_SOURCE" &> /dev/null 
	then
		# if mounted partion prompt change
		if echo $(df -x tmpfs)$(cat /proc/swaps) | grep $CLONE_SOURCE &> /dev/null  
		then
			ERROR_MESSAGE="It appears that disk/partion $CLONE_SOURCE is currently in use!" 
			# prompt if the user would like to attmept to unmount or swapoff the source
			func_clone_source_error 
			if [[ $? = 10 ]]
			then
				return 0
			fi
		# when not mounted return
		else
			return 0
		fi
	# if partion does not exist prompt
	else
		ERROR_MESSAGE="It appears that disk/partion $CLONE_SOURCE does not exist."
		func_clone_source_error 
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
# Assume normal file when not device file 
else
	if [[ -e $CLONE_SOURCE ]]
	then
		return 0
		
	# when source does not exist warn user
	else
		ERROR_MESSAGE="It appears that file $CLONE_SOURCE does not exist."
		func_clone_source_error
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
fi
}
# Get user input
CLONE_SOURCE=''
echo "Type the absolute path for the source. (e.g. /dev/sda /root/file.img)"
read -re -p ": " CLONE_SOURCE
case $CLONE_SOURCE in
	q|Q)
		CLONE_SOURCE=''
		clear
		return 0
	;;
	*)
		clear
	;;
esac
# source check
if [[ $SAFETY_CHECKS = "true" ]]
then
	func_clone_source_safety
fi
}
func_clone_target () {
	func_clone_target_error () {
while true
do
clear
echo "$(func_print_div)
$ERROR_MESSAGE
$(func_print_div)
	(K) Keep source and continue.
	(S) Start a screen session to fix it.
	(Q) Quit to imaging menu.
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	k|K)
		return 0 
	;;
	s|S)
		func_screen
		continue
	;;
	q|Q)
		CLONE_TARGET=''
		clear
		# this is a hacky way to exit to the menu system without prompting twice relies on if statment following function call
		return 10
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_clone_target_safety () {
		
	# Check if device file
if echo $CLONE_TARGET | grep '/dev/' &> /dev/null
then
	# check if partion/disk exists
	if lsblk -p | grep "$CLONE_SOURCE" &> /dev/null 
	then
		# if mounted partion prompt change
		if echo $(df -x tmpfs)$(cat /proc/swaps) | grep $CLONE_TARGET &> /dev/null  
		then
			ERROR_MESSAGE="It appears that disk/partion $CLONE_TARGET is currently in use!" 
			# prompt if the user would like to attmept to unmount or swapoff the target
			func_clone_target_error 
			if [[ $? = 10 ]]
			then
				return 0
			fi
		# when not mounted return
		else
			return 0
		fi
	# if partion does not exist prompt
	else
		ERROR_MESSAGE="It appears that disk/partion $CLONE_TARGET does not exist."
		func_clone_target_error 
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
# Assume normal file when not device file 
else
	if [[ -e $CLONE_TARGET ]]
	then
		ERROR_MESSAGE="It appears that file $CLONE_TARGET already exists!"
		func_clone_target_error
		if [[ $? = 10 ]]
		then
			return 0
		fi
		
		
	# when target does not exist check disk space
	else
		df -k $CLONE_TARGET
	fi
fi
}
# Get user input
CLONE_TARGET=''
echo "Type the absolute path for the target. (e.g. /dev/sda /root/file.img)"
read -re -p ": " CLONE_TARGET
case $CLONE_TARGET in
	q|Q)
		CLONE_TARGET=''
		clear
		return 0
	;;
	*)
		clear
	;;
esac
# target check
if [[ $SAFETY_CHECKS = "true" ]]
then
	func_clone_target_safety
fi
}
func_clone_comp () {
while true
do	
read -re -p "Set the gzip compression ratio [0 = none] (1 = fastest, 9 = slowest):" CLONE_COMP
case $CLONE_COMP in
	[1-9])
		return 0
	;;
	''|0)
		CLONE_COMP=0
		return 0
	;;
	*)
		echo "Compression needs to be set as a single value between 0 and 9"
		func_menu_entertocontinue
		clear
	;;
esac
done
}
func_clone_bs () {
while true
do	
echo "Set the block size, you may use the following multiplicative suffixes:
c=1, w=2, b=512, kB=1000, K=1024, MB=1000^2, M=1024^2, 
GB=1000^3, G=1024^3, and so on for T, P, E, Z, Y" 
read -re -p "The defualt block size is [1M]: " CLONE_BS
case $CLONE_BS in
	'')
		CLONE_BS="1M"
		return 0
	;;
	*)
		return 0
	;;
esac
done
}
func_clone_start () {
	func_clone_start_safety () {
# check if source < target
if [[ $SOURCE_SIZE -gt $TARGET_SIZE ]]
then
	if [[ $SOURCE_TYPE = "d" ]] && [[ $TARGET_TYPE = "d" ]]
	then
		func_print_div
		echo "WARNING! The source device appears to be larger than the target device!"
		func_menu_areyousure
		if [[ $? != 0 ]]
		then
			return 1
		else
			return 0
		fi
	elif [[ $SOURCE_TYPE = "d" ]] && ([[ $TARGET_TYPE = "f" ]] || [[ $TARGET_TYPE = "cf" ]])
	then
		func_print_div
		echo "WARNING! The source device appears to be larger than the available space on the target drive!"
		echo "(This may work if you use compression)"
		func_menu_areyousure
		if [[ $? != 0 ]]
		then
			return 1
		else
			return 0
		fi
	elif ([[ $SOURCE_TYPE = "f" ]] || [[ $SOURCE_TYPE = "cf" ]]) && ([[ $TARGET_TYPE = "f" ]] || [[ $TARGET_TYPE = "cf" ]])
	then
		func_print_div
		echo "WARNING! The source file appears to be larger larger than the target device!"
		func_menu_areyousure
		if [[ $? != 0 ]]
		then
			return 1
		else
			return 0
		fi
	else
		func_print_div
		"WARNING! The source appears to be larger than the target!"
		func_menu_areyousure
		if [[ $? != 0 ]]
		then
			return 1
		else
			return 0
		fi
	fi
else
	return 0
fi
}
	func_clone_cmd () {
# set compression option
if [[ $CLONE_COMP != 0 ]] && [[ $TARGET_TYPE = "f" ]]
then 
	GZIP_COMP="-$CLONE_COMP"
	TARGET_TYPE="cf"
else
	GZIP_COMP=''
fi
# set the command format for the appropriate type of transpher
if ([[ $SOURCE_TYPE = "d" ]] || [[ $SOURCE_TYPE = "f" ]]) && ([[ $TARGET_TYPE = "d" ]] || [[ $TARGET_TYPE = "f" ]])
then
	CLONE_CMD='dd if="$CLONE_SOURCE" bs="$CLONE_BS" $DD_OPTIONS | pv -pter -s "$SOURCE_SIZE" | dd of="$CLONE_TARGET$DD_FILE_EXT" bs="$CLONE_BS" $DD_OPTIONS'
elif [[ $SOURCE_TYPE = "d" ]] && [[ $TARGET_TYPE = "cf" ]]
then
	CLONE_CMD='dd if="$CLONE_SOURCE" bs="$CLONE_BS" $DD_OPTIONS | pv -pter -s "$SOURCE_SIZE" | gzip -s $GZIP_FILE_EXT $GZIP_COMP -c > "$CLONE_TARGET$DD_FILE_EXT"'
elif [[ $SOURCE_TYPE = "cf" ]] && [[ $TARGET_TYPE = "d" ]]
then
	CLONE_CMD='gunzip -c "$CLONE_SOURCE" | pv -pter -s "$SOURCE_SIZE" | dd of="$CLONE_TARGET$DD_FILE_EXT" bs="$CLONE_BS" $DD_OPTIONS'
else
	echo "If you are attempting to decompress a file use 'gzip -xf [filename]'"
	return 1
fi
}

# Check for source and target values
if [[ -z $CLONE_SOURCE ]] || [[ -z $CLONE_TARGET ]]
then
	echo "You have not defined a source or target yet."
	func_menu_entertocontinue
	clear
	return 0
fi

clear
func_clone_source_size
func_clone_target_size
# size checks
if [[ $SAFETY_CHECKS = "true" ]]
then
	func_clone_start_safety
	if [[ $? != 0 ]]
	then
		return 1
	fi
fi
func_print_div
echo "Please confirm the following settings before proceeding:"
func_print_div
#if [[ $]]

echo "Source/Input file is: $CLONE_SOURCE
Target/Output file is: $CLONE_TARGET
Total amount of data to be copied is: $SOURCE_SIZE_HUM"
### add size info - before and after
func_print_div
func_clone_cmd
func_menu_areyousure
if [[ $? = 0 ]]
then
	func_print_div
	$CLONE_CMD 
	if [[ $? = 0 ]]
	then
		func_menu_entertocontinue
	fi
fi
}

## SHRED FUNCTIONS ##

	# Shred Target Size
func_shred_target_size () {
if $(echo "$SHRED_TARGET" | grep '/dev/' &> /dev/null)
then
	# get size of block device
	TARGET_SIZE=$(blockdev --getsize64 "$SHRED_TARGET")
	TARGET_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$TARGET_SIZE")
	TARGET_TYPE="d"
else
	# get size of file
	TARGET_SIZE==$(wc -c "$SHRED_TARGET" | tr -dc '0-9')
	TARGET_SIZE_HUM=$(numfmt --to="$FILE_SIZE_UNIT" --suffix="$FILE_SIZE_SUFFIX" "$TARGET_SIZE")
	TARGET_TYPE="f"
fi
}
	# Primary Menu Selections
func_shred_cmd () {
	func_shred_cmd_check () {
#checks if shredding commands are pressent
if command -v dd &> /dev/null
then
	CMD_DD="Standard linux disk tool."
else
	CMD_DD="NOT AVAILABLE"
fi

if command -v shred &> /dev/null
then
	CMD_SHRED="Simple data overite tool."
else
	CMD_SHRED="NOT AVAILABLE"
fi	

if command -v scrub &> /dev/null
then
	CMD_SCRUB="Advanced data overite tool."
else
	CMD_SCRUB="NOT AVAILABLE"
fi

}
clear
func_shred_cmd_check
while true
do

echo "$(func_print_div)
Main Menu > Digital Shredding > Tool 
$(func_print_div)
	(1) dd, $CMD_DD
	(2) shred, $CMD_SHRED
	(3) scrub, $CMD_SCRUB
	(Q) Quit to Main Menu
$(func_print_div)"

func_menu_option_get
case $INPUT_MENU in
	1)
		if command -v dd &> /dev/null
		then
			SHRED_CMD="dd"
			return 0
		else
			func_menu_notvalid
		fi
		;;
	2)
		SHRED_CMD="shred"
		return 0
		if command -v shred &> /dev/null
		then
			SHRED_CMD="shred"
			return 0
		else
			func_menu_notvalid
		fi
		;;
	3)
		SHRED_CMD="scrub"
		return 0
		if command -v shred &> /dev/null
		then
			SHRED_CMD="scrub"
			return 0
		else
			func_menu_notvalid
		fi
		;;
	q|Q)
		clear
		return 0
		;;
	'')
		clear
		;;
	*)
		func_menu_notvalid
		clear
		;;
esac
done
}
func_shred_target () {
	func_shred_target_error () {
while true
do
echo "$(func_print_div)
$ERROR_MESSAGE
$(func_print_div)
	(K) Keep source and continue.
	(S) Start a screen session to fix it.
	(Q) Quit to imaging menu.
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	k|K)
		return 0 
	;;
	s|S)
		func_screen
		continue
	;;
	q|Q)
		SHRED_TARGET=''
		clear
		# this is a hacky way to exit to the menu system without prompting twice relies on if statment following function call
		return 10
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_shred_target_safety () {
# Check if device file
if echo $SHRED_TARGET | grep '/dev/' &> /dev/null
then
	# check if partion/disk exists
	if lsblk -p | grep "$CLONE_SOURCE" &> /dev/null 
	then
		# if mounted partion prompt change
		if echo $(df -x tmpfs)$(cat /proc/swaps) | grep $SHRED_TARGET &> /dev/null  
		then
			ERROR_MESSAGE="It appears that disk/partion $SHRED_TARGET is currently in use!" 
			# prompt if the user would like to attmept to unmount or swapoff the target
			func_shred_target_error 
			if [[ $? = 10 ]]
			then
				return 0
			fi
		# when not mounted return
		else
			return 0
		fi
	# if partion does not exist prompt
	else
		ERROR_MESSAGE="It appears that disk/partion $SHRED_TARGET does not exist."
		func_shred_target_error 
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
# Assume normal file when not device file 
else
	if [[ -e $SHRED_SOURCE ]]
	then
		return 0
		
	# when source does not exist warn user
	else
		ERROR_MESSAGE="It appears that file $SHRED_SOURCE does not exist."
		func_shred_source_error
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
fi
}
# Get user input
SHRED_TARGET=''
echo "Type the absolute path for the target. (e.g. /dev/sda /root/file.img)"
read -re -p ": " SHRED_TARGET
case $SHRED_TARGET in
	q|Q)
		SHRED_TARGET=''
		clear
		return 0
	;;
	*)
		clear
	;;
esac
# target check
if [[ $SAFETY_CHECKS = "true" ]]
then
	func_shred_target_safety
fi
}
func_shred_method () {
	func_shred_method_dd () {
		func_shred_method_dd_pass () {
while true
do	
SHRED_METHOD_DD_PASS=''
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (dd) > Number of Passes
$(func_print_div)"
read -re -p "Set the number of passes to make (integer > 0) [1]: " SHRED_METHOD_DD_PASS
case $SHRED_METHOD_DD_PASS in
	[1-9]*)
		return 0
	;;
	'')
		SHRED_METHOD_DD_PASS=1
		return 0
	;;
	*)
		echo "Number of passes needs to be 1 or greater."
		func_menu_entertocontinue
		clear
	;;
esac
done
}
		func_shred_method_dd_type () {
while true
do
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (dd) > Overwrite Type
$(func_print_div)
	(1) /dev/zero
	(2) /dev/urandom
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		SHRED_METHOD_DD_TYPE="/dev/zero"
		return 0
	;;
	2)
		SHRED_METHOD_DD_TYPE="/dev/urandom"
		return 0
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
clear
while true
do
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (dd)
$(func_print_div)
	(1) Set Number of passes: $SHRED_METHOD_DD_PASS
	(2) Set overwrite type: $SHRED_METHOD_DD_TYPE
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_shred_method_dd_pass
		clear
	;;
	2)
		func_shred_method_dd_type
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_shred_method_shred () {
		func_shred_method_shred_pass () {
while true
do	
SHRED_METHOD_SHRED_PASS=''
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (shred) > Number of Passes
$(func_print_div)"
read -re -p "Set the number of passes to make (integer > 0) [3]: " SHRED_METHOD_SHRED_PASS
case $SHRED_METHOD_SHRED_PASS in
	[1-9]*)
		return 0
	;;
	'')
		SHRED_METHOD_SHRED_PASS=3
		return 0
	;;
	*)
		echo "Number of passes needs to be 1 or greater."
		func_menu_entertocontinue
		clear
	;;
esac
done
}
		func_shred_method_shred_zero () {
if [[ $SHRED_METHOD_SHRED_ZERO = true ]]
then
	SHRED_METHOD_SHRED_ZERO="false"
else
	SHRED_METHOD_SHRED_ZERO="true"
fi
}
		func_shred_method_shred_del () {
if [[ $SHRED_METHOD_SHRED_DEL = true ]]
then
	SHRED_METHOD_SHRED_DEL="false"
else
	SHRED_METHOD_SHRED_DEL="true"
fi
}
clear
while true
do
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (shred)
$(func_print_div)
	(1) Set Number of passes: $SHRED_METHOD_SHRED_PASS
	(2) Hide Shredding with an overpass of zeros (true\false): $SHRED_METHOD_SHRED_ZERO
	(3) Delete files after overwriting (true\false): $SHRED_METHOD_SHRED_DEL
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_shred_method_shred_pass
		clear
	;;
	2)
		func_shred_method_shred_zero
		clear
	;;
	3)
		func_shred_method_shred_del
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_shred_method_scrub () {
		func_scrub_method_scrub_pattern () {
while true
do
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (scrub) > Pattern
$(func_print_div)
	(1)  nnsa | 4-pass; random(x2) 0x00 verify
	(2)  dod | 4pass; random 0x00 0xff verify
	(3)  bsi | 9-pass; 0xff 0xfe 0xfd 0xfb 0xf7 0xef 0xdf 0xbf 0x7f
	(4)  gutmann | 35-pass; (https://en.wikipedia.org/wiki/Gutmann_method)
	(5)  schneier | 7-pass; 0x00 0xff random(x5)
	(6)  pfitzner7 | 7-pass; random(x7)
	(7)  pfitzner33 | 33-pass; random(x33)
	(8)  usarmy | 3-pass; 0x00 0xff random
	(9)  fillzero | 1-pass; 0x00
	(10) fillff | 1-pass; 0xff
	(11) old | 6-pass; 0x00 0xff 0xaa 0x00 0x55 verify
	(12) fastold | 5-pass; 0x00 0xff 0xaa 0x55 verify
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		SCRUB_METHOD_SCRUB_PATTERN="nnsa"
		return 0
	;;
	2)
		SCRUB_METHOD_SCRUB_PATTERN="dod"
		return 0
	;;
	3)
		SCRUB_METHOD_SCRUB_PATTERN="bsi"
		return 0
	;;
	4)
		SCRUB_METHOD_SCRUB_PATTERN="gutmann"
		return 0
	;;
	5)
		SCRUB_METHOD_SCRUB_PATTERN="schneier"
		return 0
	;;
	6)
		SCRUB_METHOD_SCRUB_PATTERN="pfitzner7"
		return 0
	;;
	7)
		SCRUB_METHOD_SCRUB_PATTERN="pfitzner33"
		return 0
	;;
	8)
		SCRUB_METHOD_SCRUB_PATTERN="usarmy"
		return 0
	;;
	9)
		SCRUB_METHOD_SCRUB_PATTERN="fillzero"
		return 0
	;;
	10)
		SCRUB_METHOD_SCRUB_PATTERN="fillff"
		return 0
	;;
	11)
		SCRUB_METHOD_SCRUB_PATTERN="old"
		return 0
	;;
	12)
		SCRUB_METHOD_SCRUB_PATTERN="fastold"
		return 0
	;;
	q|Q)
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
		func_scrub_method_scrub_freespace () {
if [[ $SCRUB_METHOD_SCRUB_FREESPACE = false ]]
then
	SCRUB_METHOD_SCRUB_FREESPACE="true"
else
	SCRUB_METHOD_SCRUB_FREESPACE="false"
fi
}
		func_scrub_method_scrub_del () {
if [[ $SCRUB_METHOD_SCRUB_DEL = false ]]
then
	SCRUB_METHOD_SCRUB_DEL="true"
else
	SCRUB_METHOD_SCRUB_DEL="false"
fi
}
clear
while true
do
echo "$(func_print_div)
Main Menu > Digital Shredding > Method (scrub)
$(func_print_div)
	(1) Choose a pattern: $SCRUB_METHOD_SCRUB_PATTERN
	(2) Wipe freespace mode: $SCRUB_METHOD_SCRUB_FREESPACE
	(3) Delete files after overwriting (true\false): $SCRUB_METHOD_SCRUB_DEL
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_scrub_method_scrub_pattern
		clear
	;;
	2)
		func_scrub_method_scrub_freespace
		clear
	;;
	3)
		func_scrub_method_scrub_del
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
# Method options displayed are dependant on what tool the user has selected
case $SHRED_CMD in
	"dd")
		func_shred_method_dd
	;;
	"shred")
		func_shred_method_shred
	;;
	"scrub")
		func_shred_method_scrub
	;;
	*)
		echo "You need to choose a shredding tool first!"
		func_menu_entertocontinue
		return 0
	;;
esac
}
func_shred_start () {
	func_shred_start_confirm () {
func_shred_target_size
clear
func_print_div
if [[ $TARGET_TYPE = f ]]
then
	echo "	WARNING! This target apears to be a file." 
	echo "	Copies of a file in swap/virtual memory will not be overwritten!"
	func_print_div
fi
echo "Are you certain you want to overwrite this?"
echo "Target to be overwriten: $SHRED_TARGET"
echo "Amount of data to be overwriten: $TARGET_SIZE_HUM"
func_print_div
}
	func_shred_start_dd () {
func_shred_start_confirm
func_menu_areyousure
if [[ $? != 0 ]]
then
	return 1
else
	for PASS_NUM in {1..$SHRED_METHOD_DD_PASS}
	do
		echo "Begining pass $PASS_NUM of $SHRED_METHOD_DD_PASS"
		dd if=$SHRED_METHOD_DD_TYPE bs="$DD_BS" $DD_OPTIONS | pv -pter -s $TARGET_SIZE | dd of="$SHRED_TARGET" bs="$DD_BS" $DD_OPTIONS
	done
	echo "Fishised $SHRED_METHOD_DD_PASS Passes."
	exit 0
fi
}
	func_shred_start_shred () {
func_shred_start_confirm
func_menu_areyousure
if [[ $? != 0 ]]
then
	return 1
else
	SHRED_METHOD_SHRED_OPTIONS="-vf" 
	if [[ $SHRED_METHOD_SHRED_DEL = "true" ]]
	then 
		SHRED_METHOD_SHRED_OPTIONS=$SHRED_METHOD_SHRED_OPTIONS'u'
	fi
	if [[ $SHRED_METHOD_SHRED_ZERO = "true" ]]
	then
		SHRED_METHOD_SHRED_OPTIONS=$SHRED_METHOD_SHRED_OPTIONS'z'
	fi
	shred $SHRED_METHOD_SHRED_OPTIONS -n $SHRED_METHOD_SHRED_PASS "$SHRED_TARGET"
	exit 0
fi
}
	func_shred_start_scrub () {
func_shred_start_confirm
func_menu_areyousure
if [[ $? != 0 ]]
then
	return 1
else
	if [[ $SCRUB_METHOD_SCRUB_FREESPACE = "true" ]]
	then
		scrub -X -r "$SHRED_TARGET"
	else
		SCRUB_METHOD_SCRUB_OPTIONS="-fS"
		if [[ $SCRUB_METHOD_SCRUB_DEL = "true" ]]
		then
			SCRUB_METHOD_SCRUB_OPTIONS=$SCRUB_METHOD_SCRUB_OPTIONS'r'
		fi
		scrub $SCRUB_METHOD_SCRUB_OPTIONS -p $SCRUB_METHOD_SCRUB_PATTERN "$SHRED_TARGET"
		exit 0
	fi
fi
}
case $SHRED_CMD in
	"dd")
		func_shred_start_dd
	;;
	"shred")
		func_shred_start_shred
	;;
	"scrub")
		func_shred_start_scrub
	;;
	*)
		echo "You need to choose a shredding tool first!"
		func_menu_entertocontinue
		return 0
	;;
esac
}
	# passes options up from method sub menu
func_shred_method_display () {
case $SHRED_CMD in
	"dd")
		SHRED_METHOD="Passes: "$SHRED_METHOD_DD_PASS" | Type: "$SHRED_METHOD_DD_TYPE
		return 0
	;;
	"shred")
		SHRED_METHOD="Passes: "$SHRED_METHOD_SHRED_PASS" | Hide: "$SHRED_METHOD_SHRED_ZERO" | Delete: "$SHRED_METHOD_SHRED_DEL
		return 0
	;;
	"scrub")
		SHRED_METHOD="Pattern: "$SCRUB_METHOD_SCRUB_PATTERN" | Freespace: "$SCRUB_METHOD_SCRUB_FREESPACE" | Delete: "$SCRUB_METHOD_SCRUB_DEL
		return 0
	;;
	'')
		SHRED_METHOD='(Choose a tool first)'
		return 0
	;;
esac
}

## BENCH FUNCTIONS ##

	# Bench Type
func_menu_bench_method () {
clear
while true
do
echo "$(func_print_div)
Main Menu > Benchmarking > Method Selection
$(func_print_div)
	(1) Flexible I/O Tester (Mixed)
	(2) DD: Basic sequential write or write test. (dd)
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		BENCH_METHOD="fio"
		clear
		return 0
	;;
	2)
		BENCH_METHOD="dd"
		clear
		return 0
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
func_menu_bench_mkfile () {
clear
while true
do	
echo "$(func_print_div)
Main Menu > Benchmarking > Test File Creation
$(func_print_div)
	(1) Full Pre-Allocation: $BENCH_PREALLOCATION
	(2) File Size [$DEFUALT_BENCH_SIZE]: $BENCH_SIZE
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		if [[ $BENCH_PREALLOCATION == 'true' ]]
		then
			BENCH_PREALLOCATION='false'
		else
			BENCH_PREALLOCATION='true'
		fi
		clear
	;;
	2)
		func_bench_size
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
func_bench_method () {
	func_bench_method_fio () {
		func_bench_method_fio_pattern () {
			func_bench_method_fio_pattern_percentage () {
while true 
do
read -re -p 'Percentage of I/O that should be reads (1-99) [50]: ' BENCH_PATTERN_PERCENT
case $BENCH_PATTERN_PERCENT in
	[0-9]?[0-9])
		return 0
	;;
	'')
		BENCH_PATTERN_PERCENT=50
		return 0
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
clear
while true
do
echo "$(func_print_div)
Main Menu > Benchmarking > Method (Flexible I/O Tester) > I/O Pattern
$(func_print_div)
	(1)  read | Sequential reads
	(2)  write | Sequential writes
	(3)  randread | Random reads
	(4)  randwrite | Random writes
	(5)  readwrite | Mixed sequential reads and writes
	(6)  randrw | Mixed random reads and writes 
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		BENCH_PATTERN="read"
		return 0
	;;
	2)
		BENCH_PATTERN="write"
		return 0
	;;
	3)
		BENCH_PATTERN="randwrite"
		return 0
	;;
	4)
		BENCH_PATTERN="randwrite"
		return 0
	;;
	5)
		func_bench_method_fio_pattern_percentage
		BENCH_PATTERN="readwrite rwmixread=$BENCH_PATTERN_PERCENT"
		return 0
	;;
	6)
		func_bench_method_fio_pattern_percentage
		BENCH_PATTERN="randrw rwmixread=$BENCH_PATTERN_PERCENT"
		return 0
	;;
	q|Q)
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
clear
while true
do
echo "$(func_print_div)
Main Menu > Benchmarking > Method (Flexible I/O Tester)
$(func_print_div)
	(1) Block Size: $BENCH_BS
	(2) I/O Pattern Type: $BENCH_PATTERN
	(3) Runtime: $BENCH_RUNTIME
	(4) Parrallel Jobs: $BENCH_JOBDEPTH
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_bench_bs
		clear
	;;
	2)
		func_bench_method_fio_pattern
		clear
	;;
	3)
		func_bench_method_fio_runtime
		clear
	;;
	4)
		func_bench_method_fio_jobdepth
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_bench_method_dd () {
clear
while true
do
echo "$(func_print_div)
Main Menu > Benchmarking > Method (DD)
$(func_print_div)
	(1) Type: $BENCH_PATTERN
	(2) Block Size: $BENCH_BS
	(3) Number of Blocks: $BENCH_COUNT
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_bench_pattern
		clear
	;;
	2)
		func_bench_bs
		clear
	;;
	3)
		func_bench_count
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
# Method options displayed are dependant on what method the user has selected
case $BENCH_METHOD in
	"fio")
		func_bench_method_fio
	;;
	"dd")
		func_bench_method_dd
	;;
	*)
		echo "You need to choose a benchmarking method first!"
		func_menu_entertocontinue
		return 0
	;;
esac
}
func_bench_target () {
	func_bench_target_error () {
while true
do
echo "$(func_print_div)
$ERROR_MESSAGE
$(func_print_div)
	(K) Keep source and continue.
	(S) Start a screen session to fix it.
	(Q) Quit to imaging menu.
$(func_print_div)
$(lsblk -o NAME,LABEL,FSTYPE,SIZE,TYPE,MOUNTPOINT,RO,RM)
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	k|K)
		return 0 
	;;
	s|S)
		func_screen
		clear
		continue
	;;
	q|Q)
		BENCH_TARGET=''
		clear
		# this is a hacky way to exit to the menu system without prompting twice relies on if statment following function call
		return 10
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	func_bench_target_safety () {
# Check if device file
if echo "$BENCH_TARGET" | grep '/dev/' &> /dev/null
then
	# check if partion/disk exists
	if lsblk -p | grep "$BENCH_TARGET" &> /dev/null 
	then
		return 0
	# if partion does not exist prompt
	else
		ERROR_MESSAGE="It appears that disk/partion $BENCH_TARGET does not exist."
		func_bench_target_error 
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
# Assume normal file when not device file 
else
	if [[ -e "$BENCH_TARGET" ]]
	then
		return 0
	# when source does not exist warn user
	else
		ERROR_MESSAGE="It appears that file $BENCH_TARGET does not exist."
		func_bench_source_error
		if [[ $? = 10 ]]
		then
			return 0
		fi
	fi
fi
}
# Get user input
BENCH_TARGET=''
echo "Type the absolute path for the target. (e.g. /dev/sda /root/file.img)"
read -re -p ": " BENCH_TARGET
case "$BENCH_TARGET" in
	q|Q)
		BENCH_TARGET=''
		clear
		return 0
	;;
	*)
		clear
	;;
esac
# target check
if [[ $SAFETY_CHECKS = "true" ]]
then
	func_bench_target_safety
fi
}
func_bench_pattern () {
if [[ $BENCH_PATTERN = read ]]
then
	BENCH_PATTERN="write"
else
	BENCH_PATTERN="read"
fi
}
func_bench_size () {
while true
do	
echo "Set the test size, you may use the following multiplicative suffixes:
k=1024, KiB=1000, M=1024^2, MiB=1000^2, G=1024^3, GiB=1000^3, T=1024^4, TiB=1000^4" 
read -re -p "The defualt test size is [$DEFUALT_BENCH_SIZE]: " BENCH_SIZE
case $BENCH_SIZE in
	'')
		BENCH_SIZE=$DEFUALT_BENCH_SIZE
		return 0
	;;
	*)
		return 0
	;;
esac
done
}
func_bench_bs () {
while true
do	
echo "Set the block size, you may use the following multiplicative suffixes:
k=1024, KiB=1000, M=1024^2, MiB=1000^2, G=1024^3, GiB=1000^3, T=1024^4, TiB=1000^4" 
read -re -p "The defualt block size is [$DEFUALT_BENCH_BS]: " BENCH_BS
case $BENCH_BS in
	'')
		BENCH_BS=$DEFUALT_BENCH_BS
		return 0
	;;
	*)
		return 0
	;;
esac
done
}
func_bench_count () {
while true
do	
read -re -p "Set the number of blocks [1]:" BENCH_COUNT
case $BENCH_COUNT in
	''|0)
		BENCH_COUNT="$DEFUALT_BENCH_COUNT"
		return 0
	;;
	[0-9]*)
		return 0
	;;
	*)
		echo "Block count needs to be a valid integer."
		func_menu_entertocontinue
		clear
	;;
esac
done
}
func_bench_runtime () {
while true
do	
read -re -p "Set the maximum runtime (s/m/h/d)[60s]:" BENCH_RUNTIME
case $BENCH_RUNTIME in
	''|0[s|m|h|d])
		BENCH_RUNTIME="$DEFUALT_BENCH_RUNTIME"
		return 0
	;;
	[0-9]*[s|m|h|d])
		return 0
	;;
	*)
		echo "Runtime needs to be a valid integer."
		func_menu_entertocontinue
		clear
	;;
esac
done
}
func_bench_jobdepth () {
while true
do	
read -re -p "Set the maximum queue depth [1]:" BENCH_JOBDEPTH
case $BENCH_JOBDEPTH in
	''|0)
		BENCH_JOBDEPTH="$DEFUALT_BENCH_JOBDEPTH"
		return 0
	;;
	[0-9]*)
		return 0
	;;
	*)
		echo "Queue depth needs to be a valid integer."
		func_menu_entertocontinue
		clear
	;;
esac
done
}

func_bench_start () {
	func_bench_start_fio () {
clear
echo "[autogen]
name=autogen
filename=$BENCH_TARGET
rw=$BENCH_PATTERN
direct=1
refill_buffers
norandommap
ioengine=libaio
bs=$BENCH_BS
iodepth=$BENCH_JOBDEPTH
numjobs=$BENCH_JOBDEPTH
runtime=$BENCH_RUNTIME
group_reporting" > "$BENCH_FIO_CMD"
echo "Begining Flexible I/O Tester run..."
fio --output="$BENCH_FIO_RESULTS" "$BENCH_FIO_CMD"
echo "Finished Flexible I/O Tester run..."
rm -i "$BENCH_FIO_CMD"
func_menu_entertocontinue
}
	func_bench_start_dd () {
BENCH_SIZE=$(numfmt --to=none $(echo "${BENCH_BS//B}"))*"BENCH_COUNT"
	
if [[ $BENCH_PREALLOCATION == 'true' ]]
then
	if [[ -e $BENCH_TARGET ]]
	then
		echo "$BENCH_TARGET already exists!"
		func_menu_areyousure
		if [[ $? == 1 ]]
		then
			return 0
		fi
		echo "Creating test file:"
		dd if=/dev/null | pv -s "$BENCH_SIZE" | dd of="$BENCH_TARGET" bs="$BENCH_BS" count="$BENCH_COUNT"
	fi
fi

if [[ $BENCH_PATTERN == "write" ]]
then
	echo "Starting DD write test on $BENCH_TARGET:"
	dd if=/dev/null | pv -s "$BENCH_SIZE"| of="$BENCH_TARGET" bs="$BENCH_BS" count="$BENCH_COUNT"
else
	echo "Starting DD read test on $BENCH_TARGET:"
	dd if="$BENCH_TARGET" | pv -s "$BENCH_SIZE" | of=/dev/null bs="$BENCH_BS" count="$BENCH_COUNT"
fi
func_menu_entertocontinue
}
case $BENCH_METHOD in
	"fio")
		func_bench_start_fio
	;;
	"dd")
		func_bench_start_dd
	;;
	*)
		echo "You need to choose a benchmarking method first!"
		func_menu_entertocontinue
		return 0
	;;
esac
}

## SMART FUNCTIONS ##

	# SMART summary readout
func_smart_summary () {

echo "$(lsblk -o NAME,LABEL,FSTYPE,SIZE,TYPE,MOUNTPOINT,RO,RM)" | while read LINE
do
case $LINE in
	*TYPE*)
		echo "$LINE SMARTSTATUS POWERONHOURS"
	;;
	*disk*)
		echo "$LINE $(smartctl -H /dev/$(echo $LINE | awk '{print $1}') | grep overall | awk '{print $6}' | sed s/'PASSED'/'PASSED     '/ | sed s/'FAILED!'/'FAILED!    '/ ) $(smartctl -a /dev/$(echo $LINE | awk '{print $1}') | grep Power_On_Hours | awk '{print $10}')"	
	;;
	*)
		echo "$LINE"
	;;
esac
done
}

	# SMART target selction
func_tools_smart_target () {
# Get user input
SMART_TARGET=''
echo "Type the absolute path for the target. (e.g. /dev/sda)"
read -re -p ": " SMART_TARGET
case $SMART_TARGET in
	q|Q)
		SMART_TARGET=''
		clear
		return 0
	;;
	*)
		clear
	;;
esac
}

## GENERAL ##

	# User interaction
func_menu_option_get () {
read -re -p 'Choose an (option): ' INPUT_MENU
}
func_menu_entertocontinue () {
read -rs -p "Press [Enter] to continue. "
}
func_menu_notvalid () {
read -rs -p "Your input is not a valid option. Press [Enter] to continue: "
}
func_menu_areyousure () {
read -re -p "Would like to continue anyway? [N]/y: " INPUT_MENU
case $INPUT_MENU in
	y|Y|yes|Yes|YES)
		return 0
	;;
	*)
		return 1
	;;
esac
}
func_print_div () {
# taken from: http://wiki.bash-hackers.org/snipplets/print_horizontal_line
printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}
func_screen () {
echo "	A screen Session will start when you hit [enter]. Type 'exit' when you are done."
read
screen
clear
}
func_lsblk () {
clear
func_print_div
lsblk
}
func_notyetmade () {
echo "Not yet implemented :)
Yeah I know thats lame. I'm working on it."
func_menu_entertocontinue
clear
}

## MENUS ##

	# Main
func_menu_main () {
clear
while true
do
echo "$(func_print_div)
Main Menu
$(func_print_div)
	(1) Imaging and Cloning
	(2) Digital Shredding
	(3) TestDisk: Interactive partition and [selective] file recovery
	(4) PhotoRec: Interactive [agnostic] file recovery 
	(5) Smartctl: Look at various SMART data
	(6) Benchmarking: Measure Performance of a selected drive
	(Q) Quit Disk Helper
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_menu_clone
		clear
	;;
	2)
		func_menu_shred
		clear
	;;
	3)
		testdisk 2> /dev/null
		if [[ $? = 127 ]]
		then
			echo "It doesn't look like the testdisk package is installed."
		fi
		clear
	;;
	4)
		photorec 2> /dev/null
		if [[ $? = 127 ]]
		then
			echo "It doesn't look like the testdisk package is installed."
		fi
		clear
	;;
	5)
		func_menu_smart
		clear
	;;
	6)
		func_menu_bench
		clear
	;;
	q|Q)
		echo "Goodbye!"
		exit 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	# Disk Cloning
func_menu_clone () {
clear
while true
do
echo "$(func_print_div)
Main Menu > Disk Cloning
$(func_print_div)
	(1) Set Source File/Disk (from): $CLONE_SOURCE
	(2) Set Target File/Disk (to): $CLONE_TARGET 
	(3) Compression Level (0-9) [0]: $CLONE_COMP 
	(4) Block Size [1M]: $CLONE_BS
	(START) Begin the cloning operation
	(S) Start a Shell
	(L) Print a list of disks and partions recognised on this system
	(Q) Quit to Main Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_clone_source
		clear
	;;
	2)
		func_clone_target
		clear
	;;
	3)
		func_clone_comp
		clear
	;;
	4)
		func_clone_bs
		clear
	;;
	"start"|"Start"|"START")
		func_clone_start
	;;
	s|S)
		func_screen
		clear
	;;
	l|L)
		func_lsblk
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	# Data Deletion
func_menu_shred () {
clear
while true
do
func_shred_method_display
echo "$(func_print_div)
Main Menu > Digital Shredding
$(func_print_div)
	(1) Tool: $SHRED_CMD
	(2) Set Target File/Disk (to): $SHRED_TARGET 
	(3) Shredding Method: $SHRED_METHOD 
	(START) Begin the shredding operation
	(S) Start a Shell
	(L) Print a list of disks and partions recognised on this system
	(Q) Quit to Main Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_shred_cmd
		clear
	;;
	2)
		func_shred_target
		clear
	;;
	3)
		func_shred_method
		clear
	;;
	"start"|"Start"|"START")
		func_shred_start
	;;
	s|S)
		func_screen
		clear
	;;
	l|L)
		func_lsblk
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	# Smartctl
func_menu_smart () {
clear
while true
do
echo "$(func_print_div)
$(func_smart_summary)
$(func_print_div)
Main Menu > Smartctl
$(func_print_div)
	(1) Target Drive: $SMART_TARGET
	(2) Print Disk Info 
	(3) Print Errors
	(4) Print All 
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_tools_smart_target
		clear
	;;
	2)
		clear
		if [[ $SMART_TARGET != "" ]]
		then
			smartctl $SMART_TARGET -i | less
			clear
		else
			echo "Choose a SMART target first!"
		fi
	;;
	3)
		clear
		if [[ $SMART_TARGET != "" ]]
		then
			smartctl $SMART_TARGET -H | less
			clear
		else
			echo "Choose a SMART target first!"
		fi
	;;
	4)
		clear
		if [[ $SMART_TARGET != "" ]]
		then
			smartctl $SMART_TARGET -a | less
			clear
		else
			echo "Choose a SMART target first!"
		fi
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}
	# Drive Benchmarking
func_menu_bench () {
clear
while true
do
echo "$(func_print_div)
Main Menu > Benchmarking
$(func_print_div)
	(1) Type: $BENCH_METHOD
	(2) Method Settings
	(3) Target: $BENCH_TARGET
	(4) Create a test file
	(START) Start test
	(Q) Quit to Last Menu
$(func_print_div)"
func_menu_option_get
case $INPUT_MENU in
	1)
		func_menu_bench_method
		clear
	;;
	2)
		func_bench_method
		clear
	;;
	3)
		func_bench_target
		clear
	;;
	4)
		func_menu_bench_mkfile
		clear
	;;
	"start"|"Start"|"START")
		func_bench_start
		clear
	;;
	q|Q)
		clear
		return 0
	;;
	'')
		clear
	;;
	*)
		func_menu_notvalid
		clear
	;;
esac
done
}

## SCRIPT EXECUTION ##
trap func_cleanup EXIT
#trap func_interupt INT
func_greetings
if [[ $CMD_CHECKS = "true" ]]
then
	func_cmd_checks
fi
func_menu_main