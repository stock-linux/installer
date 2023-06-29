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

# Hostname
echo "$HOSTNAME" > /etc/hostname

# User creation
useradd -m -G users,wheel,audio,video -s /bin/bash $USERNAME
echo -e "${USER_PSWD}\n${USER_PSWD}" | passwd -q $USERNAME

if [ ! "$ROOT_PSWD" ]; then
echo -e "${ROOT_PASS}\n${ROOT_PASS}" | passwd -q
fi

