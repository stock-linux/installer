#!/bin/sh
#
# this script execute to apply changes to installed system from data from config-install.sh
#
# list variable:
#  $ROOT         - directory where system is installed
#  $HOSTNAME     - hostname
#  $TIMEZONE     - timezone (xxxx/yyyy)
#  $KEYMAP       - keymap
#  $USERNAME     - user's login name
#  $USER_PSWD    - user's password
#  $ROOT_PSWD    - root's password
#  $LOCALE       - locale
#  $BOOTLOADER   - disk to install grub (either '/dev/sdX or skip)
#  $BOOTLOADER_T - bootloader software
#  $EFI_SYSTEM   - 1 if boot in UEFI mode
#  $KERNEL       - kernel to install
#

# systemd config
systemd-machine-id-setup
systemctl preset-all

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Keymap
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Timezone
ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime

pwconv
grpconv

# User creation
useradd -m -G users,wheel,audio,video,input -s /bin/bash $USERNAME
echo -e "${USER_PSWD}\n${USER_PSWD}" | passwd -q $USERNAME

if [ "$ROOT_PSWD" != "" ]; then
echo -e "${ROOT_PSWD}\n${ROOT_PSWD}" | passwd -q
fi

# Locale
echo "LANG=$LOCALE.UTF-8" > /etc/locale.conf
echo "source /etc/environment" >> /etc/profile
echo "source /etc/environment" >> /etc/bashrc
echo "LC_ALL=$LOCALE.UTF-8" >> /etc/environment
echo "PATH=\"/usr/sbin:/usr/bin\"" >> /etc/environment

# Bootloader
case $BOOTLOADER_T in
	GRUB)
		mkdir -p /boot/grub
  		mkdir -p /etc/default
		echo GRUB_DISABLE_OS_PROBER=false >> /etc/default/grub
		if [ "$EFI_SYSTEM" = 1 ]; then
			# EFI
			grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="stock"
		else
			# MBR
			grub-install --target=i386-pc $BOOTLOADER
		fi
		;;

	systemd-boot)
		echo "Not supported yet";;

	*)
		echo "No bootloader to install";;
esac

# Kernel
case $KERNEL in
	LTS)
		squirrel install linux-lts
  		;;
  	*)
   		echo "No kernel to install"
     		;;
esac

case $DESKTOP_ENV in
	GNOME)
 		squirrel install gnome
   		;;
     	None)
      		echo "No desktop environment to install."
		;;
	*)
 		echo "No desktop environment to install."
   		;;
esac
