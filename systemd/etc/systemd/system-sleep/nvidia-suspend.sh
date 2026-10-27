#!/bin/bash
# Nvidia GPU suspend/resume fix

case $1 in
	pre)
		# Before suspend
		echo "Preparing for suspend..."
		;;
	post)
		# After resume
		echo "Resuming from suspend, reinitializing GPU..."
		# Notify zlstatus first. GPU module recovery is independent and may fail;
		# it must not prevent status recovery after suspend.
		/usr/bin/pkill -USR1 -x zlstatus 2>/dev/null || true
		# Force GPU to reinitialize
		modprobe -r nvidia_drm
		modprobe -r nvidia_modeset
		modprobe -r nvidia
		modprobe nvidia
		modprobe nvidia_modeset
		modprobe nvidia_drm

		echo "GPU reinitialized"
		;;
esac
