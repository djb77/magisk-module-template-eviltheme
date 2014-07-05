#!/tmp/bash
evtVersion="2.0.5"

# Enhanced VRTheme engine
# Copyright aureljared@XDA, 2014-2016.
#
# Original VRTheme engine is copyright
# VillainROM 2011. All rights reserved.
# Edify-like methods defined below are
# copyright Chainfire 2011.
#
# Portions are copyright Spannaa@XDA 2015.

# Declare busybox, output file descriptor, timecapture, and logging mechanism
bb="/tmp/busybox"
datetime=$($bb date +"%m%d%y-%H%M%S")
OUTFD=$(ps | grep -v "grep" | grep -o -E "update_binary(.*)" | cut -d " " -f 3);
[[ $OUTFD != "" ]] || OUTFD=$(ps | grep -v "grep" | grep -o -E "updater(.*)" | cut -d " " -f 3);

# Welcome!
ui_print() {
	# Print to recovery screen
	if [ $OUTFD != "" ]; then
		echo "ui_print ${1} " 1>&$OUTFD;
		echo "ui_print " 1>&$OUTFD;
	else
		echo "${1}";
	fi;
}
evtlog() {
	# Append to our own log file
	if [ -d /data/eviltheme-backup ]; then
		logfile="/data/eviltheme-backup/evt_$datetime.log"
	else
		logfile="/data/tmp/eviltheme/evt_$datetime.log"
	fi
	if [ ! -e "$logfile" ]; then
		$bb touch $logfile
		chmod 0644 $logfile
	fi
	if [ "$1" == "loglocation" ]; then
		echo "$logfile"
		return
	fi
	echo "$@" >> "$logfile"
}
evtlog "I: This is EVilTheme version $evtVersion."

# ROM checks
getpropval() {
	acquiredValue=`cat /system/build.prop | grep "^$1=" | cut -d"=" -f2 | tr -d '\r '`
	echo "$acquiredValue"
}
platformString=`getpropval "ro.build.version.release"`
platform=`echo "$platformString" | cut -d. -f1`
evtlog "I: Device is running Android $platformString."
if [ "$platform" -ge "5" ]; then
	evtlog "I: ART runtime detected."
	lollipop="1"
	ui_print "- Adjusting engine for new app hierarchy"
	friendlyname() {
		# Example: Return "Settings" for "Settings.apk"
		tempvar="$(echo $1 | $bb sed 's/.apk//g')"
		echo "$tempvar"
	}
	checkdex() {
		tmpvar=$(friendlyname "$2")
		if [ -e ./classes.dex ]; then
			evtlog "P: Replacement bytecode for $1 $2.apk present. Deleting old Dalvik entry."
			rm -f "/data/dalvik-cache/arm/system@$1@$tmpvar@$2.apk@classes.dex"
		fi
	}
else
	evtlog "I: Dalvik runtime detected."
	checkdex() {
		if [ -e ./classes.dex ]; then
			evtlog "P: Replacement bytecode for $1 $2 present. Deleting old Dalvik entry."
			if [ -e "/data/dalvik-cache/system@$1@$2@classes.dex" ]; then
				rm -f "/data/dalvik-cache/system@$1@$2@classes.dex"
			else
				rm -f "/cache/dalvik-cache/system@$1@$2@classes.dex"
			fi
		fi
	}
fi

# Define some more methods
dir() {
	# Make folder $1 if it doesn't exist yet
	if [ ! -d "$1" ]; then
		$bb mkdir -p "$1"
	fi
}
zpln() {
	# Zipalign $1 into aligned/$1
	if [ "$lollipop" -eq "1" ]; then
		appDir=$(echo $1 | sed "s/\/$1\.apk")
		$bb mkdir -p ./aligned/$appDir
	fi
	/tmp/zipalign -f 4 "$1" ./aligned/$1
}
theme(){
	path="$1/$2" # system/framework
	evtlog "P: Processing apps in /$path."

	cd "$vrroot/$path/"
	dir "$vrbackup/$path"
	dir "$vrroot/apply/$path"
	dir "$vrroot/apply/$path/aligned"

	for f in *.apk; do
		cd "$f"
		ui_print "  /$path/$f"
		evtlog "P:   $f"

		# Backup APK
		if [ "$lollipop" -eq "1" ]; then
			appPath="$(friendlyname $f)/$f"
			dir "$vrbackup/$path/$(friendlyname $f)"
			dir "$vrroot/apply/$path/$(friendlyname $f)"
			cp "/$path/$appPath" "$vrbackup/$path/$(friendlyname $f)/"
			cp "/$path/$appPath" "$vrroot/apply/$path/$(friendlyname $f)/"
		else
			cp "/$path/$f" "$vrbackup/$path/"
			cp "/$path/$f" "$vrroot/apply/$path/"
			appPath="$f"
		fi

		# Delete files in APK, if any
		if [ -e "./delete.list" ]; then
			readarray -t array < ./delete.list
			for j in ${array[@]}; do
				/tmp/zip -d "$vrroot/apply/$path/$appPath.zip" "$j" >> $(evtlog loglocation)
			done
			rm -f ./delete.list
		fi

		# Theme APK
		mv "$vrroot/apply/$path/$appPath" "$vrroot/apply/$path/$appPath.zip"
		/tmp/zip -r "$vrroot/apply/$path/$appPath.zip" ./* >> $(evtlog loglocation)

		mv "$vrroot/apply/$path/$appPath.zip" "$vrroot/apply/$path/$appPath"

		# Refresh bytecode if necessary
		checkdex "$2" "$f"

		# Zipalign APK
		cd "$vrroot/apply/$path"
		zpln "$appPath"

		# Finish up
		$bb cp -f "aligned/$appPath" "/$path/$appPath"
		chmod 644 "/$path/$appPath"
		cd "$vrroot/$path/"
	done
}

# Work directories
vrroot="/data/tmp/eviltheme"
vrbackup="/data/tmp/evt-backup"
dir "$vrbackup"
dir "$vrroot/apply"

# Start theming
ui_print "- Theming apps"
[ -d "$vrroot/system/app" ] && sysapps=1 || sysapps=0
[ -d "$vrroot/system/priv-app" ] && privapps=1 || privapps=0
[ -d "$vrroot/system/framework" ] && framework=1 || framework=0
[ -d "$vrroot/preload/symlink/system/app" ] && preload=1 || preload=0
evtlog "I: Preliminary operations complete. Starting theme process."

# /system/app
if [ "$sysapps" -eq "1" ]; then
	theme "system" "app"
fi

# /preload/symlink/system/app
if [ "$preload" -eq "1" ]; then
	theme "preload/symlink/system" "app"
fi

# /system/priv-app
if [ "$privapps" -eq "1" ]; then
	theme "system" "priv-app"
fi

# /system/framework
if [ "$framework" -eq "1" ]; then
	theme "system" "framework"
fi

# Create flashable restore zip
ui_print "- Creating restore zip in /data/eviltheme-backup"
evtlog "I: Theme process complete. Creating restore zip [$datetime]."
cd "$vrbackup"
dir "/data/eviltheme-backup"
mv /data/tmp/eviltheme/vrtheme_restore.zip "/data/eviltheme-backup/restore-$datetime.zip"
mv $(evtlog loglocation) /data/eviltheme-backup/
/tmp/zip -r "/data/eviltheme-backup/restore-$datetime.zip" ./* >> $(evtlog loglocation)

# Cleanup
ui_print "- Cleaning up"
$bb rm -fR /data/tmp/eviltheme
$bb rm -fR /data/tmp/evt-backup
$bb rm -f /tmp/installtheme.sh
$bb rm -f /tmp/bash
$bb rm -f /tmp/zipalign
$bb rm -f /tmp/zip
$bb rm -f /tmp/busybox
ui_print "Done. If your device does not perform properly after this,"
ui_print "just flash /data/eviltheme-backup/restore-$datetime.zip."
evtlog "I: Cleanup process complete. Exiting."

exit 0
