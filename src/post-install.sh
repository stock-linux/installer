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
#

# systemd config
systemctl preset-all
systelctl systemd-machine-id-setup

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Timezone
ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime

# User creation
useradd -m -G users,wheel,audio,video -s /bin/bash $USERNAME
echo -e "${USER_PSWD}\n${USER_PSWD}" | passwd -q $USERNAME

if [ ! "$ROOT_PSWD" ]; then
echo -e "${ROOT_PASS}\n${ROOT_PASS}" | passwd -q
fi

# Locale
sed "s/#$LOCALE/$LOCALE/" -i /etc/locales
echo "LANG=$LOCALE.UTF-8" > /etc/locale.conf
echo "LC_ALL=$LOCALE.UTF-8" >> /etc/environment

# Bootloader
case $BOOTLOADER_T in
	"GRUB")
		squirrel install grub
		echo GRUB_DISABLE_OS_PROBER=false >> $ROOT/etc/default/grub
		if [ "$EFI_system" = 1 ]; then
			# EFI
			grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Stock Linux" --recheck $BOOTLOADER
		else
			# MBR
			grub-install --target=i386-pc $BOOTLOADER
		fi
		grub-mkconfig -o /boot/grub/grub.cfg
		;;

	"systemd-boot")
		echo "Not supported yet";;

	*)
		echo "No bootloader to install";;

