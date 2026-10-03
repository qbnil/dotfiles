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
		# Force GPU to reinitialize
		modprobe -r nvidia_drm
		modprobe -r nvidia_modeset
		modprobe -r nvidia
		modprobe nvidia
		modprobe nvidia_modeset
		modprobe nvidia_drm

		# Notify systemd that resume is complete
		echo "GPU reinitialized"
		;;
esac
