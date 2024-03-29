#!/bin/sh -e

showdisk() {
	lsblk -nrp -o NAME,TYPE | grep -w disk | awk '{print $1}'
}

showswap() {
	fdisk -l | grep ^\/dev | grep swap | awk '{print $1}'
}

showpartition() {
	fdisk -l | grep ^\/dev | grep -Ev '(swap|Extended|EFI|BIOS|Empty)' | awk '{print $1}'
}

showkeymap() {
	if [ -d /usr/share/kbd/keymaps ]; then
		find /usr/share/kbd/keymaps/ -type f -iname "*.map.gz" -printf "%f\n" | sed 's|.map.gz||g' | sort
	else
		find /usr/share/keymaps/ -type f -iname "*.map.gz" -printf "%f\n" | sed 's|.map.gz||g' | sort
  	fi
}

showlocale() {
	grep "UTF-8" /usr/share/i18n/SUPPORTED | awk '{print $1}' | sed 's/^#//;s/\.UTF-8//'
}

get_partition_info() {
	echo -n "$1 - "
	lsblk -nrp -o NAME,SIZE,FSTYPE,LABEL | grep -v ventoy | grep -w $1 | cut -d ' ' -f2-
}

title() {
	cprint "STOCK LINUX INSTALLER"
	printline
	echo
}

cclear() {
	clear
	title
}

prompt_user() {
	echo
	cols=$(tput cols)
	text=$@
	length=${#text}
	pad=$(( (cols - length) / 2 ))
	printf "%*s%s" $pad "" "$text"
}

cprint() {
	cols=$(tput cols)
	text=$@
	length=${#text}
	pad=$(( (cols - length) / 2 ))
	printf "%*s%s\n" $pad "" "$text"
}

printline() {
	cols=$(tput cols)
	printf "%${cols}s\n" "" | tr " " "*"
}

create_chroot() {
	mount -v --bind /dev $ROOT/dev
	mount -v --bind /dev/pts $ROOT/dev/pts
	mount -vt proc proc $ROOT/proc
	mount --rbind /sys $ROOT/sys
	mount --make-rslave $ROOT/sys
	mount -vt tmpfs tmpfs $ROOT/run
	if [ -h $ROOT/dev/shm ]; then
		mkdir -pv $ROOT/$(readlink $ROOT/dev/shm)
	fi
}

choose_part() {
	unset part createpart filesystem_var
	case $1 in
		1) grep_regex=EFI;;
		2) grep_regex=BIOS;;
		3) grep_regex=swap;;
		*) grep_regex="-Ev (swap|Extended|EFI|BIOS|Empty)"
	esac
	[ "$root_var" ] && exclude_root="grep -v ^${root_var%%:*}" || exclude_root=cat
	[ "$home_var" ] && exclude_home="grep -v ^${home_var%%:*}" || exclude_home=cat
	while [ ! "$part" ]; do
		cclear
		count=0
		for i in $(fdisk -l | grep ^\/dev | grep -v ventoy | grep $grep_regex | awk '{print $1}' | sort | $exclude_root | $exclude_home); do
			count=$((count+1))
			ii=$(get_partition_info $i)
			cprint "$count. $ii"
		done
		cprint "0. back"
		prompt_user "Choose partition [1-$count]: "
		read input
		[ "$input" = 0 ] && break
		[ "$input" -gt "$count" ] && continue
		part=$(fdisk -l | grep ^\/dev | grep -v ventoy | grep $grep_regex | awk '{print $1}' | sort | $exclude_root | $exclude_home | head -n$input | tail -n1)
		case $1 in
			1|2);;
			3) 	if [ "$(lsblk -nrp -o FSTYPE $part)" = swap ]; then
					while [ ! "$createpart" ]; do
						cclear
						cprint "1. create swap"
						cprint "0. skip create swap"
						prompt_user "Create swap partition for '$part'?: "
						read input
						[ "$input" = 0 ] && createpart=$input
						[ "$input" = 1 ] && createpart=$input
					done
				else
					createpart=1
				fi;;
			*)	if [ "$(lsblk -nrp -o FSTYPE $part)" ]; then
					while [ ! "$createpart" ]; do
						cclear
						cprint "1. create filesystem"
						cprint "0. skip create filesystem"
						prompt_user "Create filesystem for '$part'?: "
						read input
						[ "$input" = 0 ] && createpart=$input
						[ "$input" = 1 ] && createpart=$input
					done
				else
					createpart=1
				fi
				if [ "$createpart" -gt 0 ]; then
					while [ ! "$filesystem_var" ]; do
						fs="ext4 ext3 ext2 btrfs reiserfs xfs"
						cclear
						count=0
						for i in $fs; do
							count=$((count+1))
							cprint "$count. $i"
						done
						prompt_user "Choose filesystem type for '$part' [1-$count]: "
						read input
						[ "$input" = 0 ] && continue
						[ "$input" -gt "$count" ] && continue
						filesystem_var=$(echo $fs | tr ' ' '\n' | head -n$input | tail -n1)
					done
				else
					filesystem_var=skip
				fi;;
		esac
	done
	if [ "$part" ]; then
		case $1 in
			1) efi_var=$part;;
			2) biosboot_var=$part;;
			3) swap_var=$part:$createpart;;
			4) root_var=$part:$filesystem_var;;
			5) home_var=$part:$filesystem_var;;
		esac
	fi
}

modify_disk() {
	unset disk disktool
	while [ ! "$disk" ]; do
		cclear
		count=0
		for i in $(showdisk); do
			count=$((count+1))
			ii=$(get_partition_info $i)
			cprint "$count. $ii"
		done
		prompt_user "Enter disk [1-$count]: "
		read input
		[ "$input" = 0 ] && continue
		[ "$input" -gt "$count" ] && continue
		disk=$(showdisk | head -n$input | tail -n1)
	done
	while [ ! "$disktool" ]; do
		cclear
		cprint "1. cfdisk"
		cprint "2. fdisk"
		prompt_user "Select tool for partitioning disk $disk: "
		read input
		case $input in
			1) disktool=cfdisk;;
			2) disktool=fdisk;;
		esac
	done
	$disktool $disk
}

config_partitioning() {
	unset done
	while [ ! "$done" ]; do
		cclear

		cprint "1. Auto partitioning"
		cprint ""
		cprint "2. Manual partitioning"
		cprint ""
		cprint ""
		cprint "0. Back to main menu"
		prompt_user "Select partitioning way [1-2]: "
		read input
		case $input in
			1) cclear; cprint "Not yet"; prompt_user "[Enter] to continue"; read;;
			2) config_rootpart;;
		esac
		[ "$input" -gt "2" ] && continue
		done="$input"


	done
}

config_rootpart() {
	unset partstatus
	print_partitioning_tips
	while [ ! "$partstatus" ]; do
		cclear
		cprint "*** NOTE ***"
		cprint "* 'EFI' only required on UEFI boot, atleast 100MB"
		cprint "* 'BIOS boot' only required on BIOS boot + gpt disk, atleast 1MB"
		cprint "* '/' is required to start installation"
		echo
		cprint "1. EFI - $efi_var"
		cprint "2. BIOS boot - $biosboot_var"
		cprint "3. swap - $swap_var"
		cprint "4. / - $root_var"
		cprint "5. /home - $home_var"
		cprint "0. done"
		cprint "00. modify disk"
		prompt_user "Choose above to configure: "
		read input
		case $input in
			1|2|3|4|5) choose_part $input;;
			0) partstatus=done;;
			00) modify_disk;;
		esac
	done
	if [ "$root_var" ]; then
		if [ "$EFI_SYSTEM" = 1 ]; then
			if [ "$(lsblk -nrp -o PTTYPE ${root_var%%:*})" != gpt ]; then
				cprint "Disk type for root (${root_var%%:*}) partition not 'gpt'!"
				partstatus=error
				sleep 2
			fi
			if [ ! "$efi_var" ]; then
				cprint "'EFI' partition not configured!"
				partstatus=error
				sleep 2
			fi
		else
			if [ "$(lsblk -nrp -o PTTYPE ${root_var%%:*})" = gpt ]; then
				if [ ! "$biosboot_var" ]; then
					cprint "'BIOS boot' partition not configured!"
					partstatus=error
					sleep 2
				fi
			fi
		fi
	else
		cprint "'/' is not set!"
		partstatus=error
		sleep 2
	fi
}

config_keymap() {
	unset KEYMAP keymappart
	while [ ! "$keymappart" ]; do
		cclear
		prompt_user "Enter part of your keymap (Eg: us,fr): "
		read input
		keymappart=$(showkeymap | grep $input) || true
	done
	while [ ! "$KEYMAP" ]; do
		cclear
		count=0
		for i in $keymappart; do
			count=$((count+1))
			cprint "$count. $i"
		done
		prompt_user "Enter keymap [1-$count]: "
		read input
		[ "$input" = 0 ] && continue
		[ "$input" -gt "$count" ] && continue
		KEYMAP=$(echo $keymappart | tr ' ' '\n' | head -n$input | tail -n1)
	done
}

config_locale() {
	unset localepart LOCALE
	while [ ! "$localepart" ]; do
		cclear
		prompt_user "Enter part of your locale (Eg: en,fr): "
		read input
		localepart=$(showlocale | grep -i $input) || true
	done
	while [ ! "$LOCALE" ]; do
		cclear
		count=0
		for i in $localepart; do
			count=$((count+1))
			cprint "$count. $i"
		done
		prompt_user "Enter locale [1-$count]: "
		read input
		[ "$input" = 0 ] && continue
		[ "$input" -gt "$count" ] && continue
		LOCALE=$(echo $localepart | tr ' ' '\n' | head -n$input | tail -n1)
	done
}

config_hostname() {
	cclear
	if [ "$HOSTNAME" ]; then
		_preset=Stock
	else
		_preset=Stock
	fi
	prompt_user "Enter hostname [$_preset]: "
	read input
	if [ "$input" ]; then
		HOSTNAME=$input
	else
		HOSTNAME=$_preset
	fi
}

config_useraccount() {
	unset USER_PSWD
	while [ ! "$USER_PSWD" ]; do
		cclear
		if [ "$USERNAME" ]; then
			_preset=$USERNAME
		else
			_preset=stock
		fi
		prompt_user "Enter username [$_preset]: "
		read input
		if [ "$input" ]; then
			USERNAME=$input
		else
			USERNAME=$_preset
		fi
		prompt_user "Enter password for user '$USERNAME' (hidden): "
		stty -echo
		read input
		echo
		prompt_user "Enter password for user '$USERNAME' again (hidden): "
		read input2
		stty echo
		echo
		if [ "$input" = "$input2" ]; then
			USER_PSWD=$input
		else
			cprint "Password does not match!. Try again."
			sleep 1
		fi
	done
}

config_rootpswd() {
	unset ROOT_PSWD
	while [ ! "$ROOT_PSWD" ]; do
		cclear
		prompt_user "Enter password for root (hidden): "
		stty -echo
		read input
		echo
		prompt_user "Enter password for root again (hidden): "
		read input2
		stty echo
		echo
		if [ "$input" = "$input2" ]; then
			ROOT_PSWD=$input
		else
			cprint "Password does not match!. Try again."
			sleep 1
		fi
	done
}

config_bootloader() {
	unset BOOTLOADER
	unset done
	while [ ! "$BOOTLOADER" ]; do
		cclear
		count=0
		for i in $(showdisk); do
			count=$((count+1))
			ii=$(get_partition_info $i)
			cprint "$count. $ii"
		done
		cprint "0. skip"
		prompt_user "Enter disk [0-$count]: "
		read input
		[ "$input" -gt "$count" ] && continue
		if [ "$input" = 0 ]; then
			BOOTLOADER=skip
		else
			BOOTLOADER=$(showdisk | head -n$input | tail -n1)
		fi
	done
	[ ! "$BOOTLOADER_T" ] && BOOTLOADER_T="systemd-boot"
	while [ ! "$done" ]; do
		cclear
		cprint "Choose the bootloader (current: $BOOTLOADER_T)"
		cprint ""
		cprint "1. systemd-boot (default)"
		cprint "2. GRUB"
		cprint ""
		cprint "0. skip"
		prompt_user "Enter choice [0-2]: "
		read input
		case $input in
			1) BOOTLOADER_T="systemd-boot";;
			2) BOOTLOADER_T="GRUB";;
		esac
		[ "$input" -gt "2" ] && continue
		done="$input"
	done
}

config_timezone() {
	unset TIMEZONE location country listloc listc countrypart
	# location
	for l in /usr/share/zoneinfo/*; do
		[ -d $l ] || continue
		l=${l##*/}
		case $l in
			Etc|posix|right) continue;;
		esac
		listloc="$listloc $l"
	done
	while [ ! "$location" ]; do
		cclear
		count=0
		for l in $listloc; do
			count=$((count+1))
			cprint "$count. $l"
		done
		prompt_user "Enter location [1-$count]: "
		read input
		[ "$input" = 0 ] && continue
		[ "$input" -gt "$count" ] && continue
		location=$(echo $listloc | tr ' ' '\n' | head -n$input | tail -n1)
	done
	# country
	for c in /usr/share/zoneinfo/$location/*; do
		c=${c##*/}
		listc="$listc $c"
	done
	while [ ! "$countrypart" ]; do
		cclear
		prompt_user "Enter part of your country name (Eg: us,Paris): "
		read input
		countrypart=$(echo $listc | tr ' ' '\n' | grep -i $input)
	done
	while [ ! "$country" ]; do
		cclear
		count=0
		for c in $countrypart; do
			count=$((count+1))
			cprint "$count. $c"
		done
		prompt_user "Enter country [1-$count]: "
		read input
		[ "$input" = 0 ] && continue
		[ "$input" -gt "$count" ] && continue
		country=$(echo $countrypart | tr ' ' '\n' | head -n$input | tail -n1)
	done
	TIMEZONE=$location/$country
}

config_advanced() {
	while true; do
		cclear

		cprint "1. bootloader: $BOOTLOADER_T on $BOOTLOADER"
		cprint "2. kernel: $KERNEL"
		cprint "3. software branch: $SOFTWARE_BRANCH"
		cprint ""
		cprint "0. Back to main menu"
		cprint ""
		prompt_user "Enter choice [0-3]: "
		read input

		case $input in
			1) config_bootloader;;
			2) config_kernel;;
			3) config_software_branch;;
			0) break;;
		esac
	done
}

check_var() {
	cclear
	unset error
	[ "$root_part" ]   || { error=1; cprint "partition for / is not set up"; }
	[ "$KEYMAP" ]     || { error=1; cprint "keymap is not set up"; }
	[ "$TIMEZONE" ]   || { error=1; cprint "timezone is not set up"; }
	[ "$LOCALE" ]     || { error=1; cprint "locale is not set up"; }
	[ "$HOSTNAME" ]   || { error=1; cprint "hostname is not set up"; }
	[ "$USERNAME" ]   || { error=1; cprint "user is not set up"; }
	[ "$ROOT_PSWD" ]  || { error=1; cprint "root password is not set up"; }
	[ "$KERNEL" ]     || { error=1: cprint "kernel is not set up"; }
	[ "$BOOTLOADER" ] || { error=1; cprint "bootloader is not set up"; }
	[ "$BOOTLOADER_T" ] || { error=1; cprint "bootloder softare is not set up (how do we get there?)"; }
	if [ "$error" = 1 ]; then
		prompt_user "Press ENTER to back to main menu..."
		read input
		return 1
	fi
}

start_install() {
	cclear
 	unset done

	swap_part=${swap_var%:*}
	swap_part_create=${swap_var#*:}
	root_part=${root_var%:*}
	root_part_fs=${root_var#*:}
	home_part=${home_var%:*}
	home_part_fs=${home_var#*:}

	check_var || return 0

	# overview
	cprint "*** Partition Overview ***"
	echo
	if [ "$swap_part" ] && [ "$swap_part_create" != skip ]; then
		cprint "$swap_part will be format into swap"
	fi
	[ "$root_part_fs" != skip ] && cprint "$root_part will be format into $root_part_fs"
	if [ "$home_part" ] && [ "$home_part_fs" != skip ]; then
		cprint "$home_part will be format into $home_part_fs"
	fi

	prompt_user "Press ENTER to continue installation..."
	read input

	mountpoint -q $ROOT && umount -Rf $ROOT

	rm -fr $ROOT
	mkdir -p $ROOT

	if [ "$root_part_fs" != skip ]; then
		echo "Create filesystem $root_part_fs on $root_part"
		case $root_part_fs in
			ext4|ext3|ext2) mkfs.$root_part_fs -F -L Stock $root_part;;
			xfs) mkfs.xfs -f -m crc=0 -L Stock $root_part;;
			reiserfs) mkreiserfs -q -l Stock $root_part;;
			btrfs) mkfs.btrfs -f -L Stock $root_part;;
		esac
	fi

	echo "Mounting $root_part on $ROOT"
	mount $root_part $ROOT

	if [ "$home_part" ]; then
		if [ "$home_part_fs" != skip ]; then
			echo "Create filesystem $home_part_fs on $home_part"
			case $home_part_fs in
				ext4|ext3|ext2) mkfs.$home_part_fs -F -L Home $home_part;;
				xfs) mkfs.xfs -f -m crc=0 -L Home $home_part;;
				reiserfs) mkreiserfs -q -l Home $home_part;;
				btrfs) mkfs.btrfs -f -L Home $home_part;;
			esac
		fi
		echo "Mount $home_part to $ROOT/home"
		mkdir -p $ROOT/home
		mount $home_part $ROOT/home
	fi


	if [ "$swap_part" ] && [ "$swap_part_create" != skip ]; then
		echo "Making swap partition on $swap_part"
		mkswap $swap_part
	fi

	if [ "$EFI_SYSTEM" = 1 ]; then
		echo "Formatting partition $efi_var to fat32"
		mkfs.vfat -F32 $efi_var
		echo "Mounting $efi_var on $ROOT/boot/efi"
		mkdir -p $ROOT/boot/efi
		mount $efi_var $ROOT/boot/efi
	fi

	echo "Installing system to $root_var"
 	mkdir -p $ROOT/etc
 	cat > $ROOT/etc/squirrel.conf << EOF
stocklinux https://packages.stocklinux.org/x86_64/testing
EOF
	ROOT=$ROOT squirrel sync
	ROOT=$ROOT squirrel install base
 	create_chroot

	echo "running post-install.sh script"
 	cp post-install.sh $ROOT/post-install.sh
	chmod +x $ROOT/post-install.sh

	chroot $ROOT /usr/bin/env -i \
 	PATH="/usr/sbin:/usr/bin" \
	HOSTNAME=$HOSTNAME \
	TIMEZONE=$TIMEZONE \
	KEYMAP=$KEYMAP \
	USERNAME=$USERNAME \
	USER_PSWD=$USER_PSWD \
	ROOT_PSWD=$ROOT_PSWD \
	LOCALE=$LOCALE \
	BOOTLOADER=$BOOTLOADER \
	BOOTLOADER_T=$BOOTLOADER_T \
	EFI_SYSTEM=$EFI_SYSTEM \
	KERNEL=$KERNEL \
	DESKTOP_ENV=$DESKTOP_ENV \
 	/bin/bash /post-install.sh

	# fstab
	echo "Setup fstab"
	echo "# <device> <dir> <type> <options> <dump> <fsck>" > $ROOT/etc/fstab

	# EFI partition
	if [ "$EFI_SYSTEM" = 1 ]; then
		echo "UUID=$(blkid -o value -s UUID "$efi_var") /boot/efi vfat defaults 0 2" >> $ROOT/etc/fstab
	fi

	# swap
	if [ "$swap_part" ]; then
		echo "UUID=$(blkid -o value -s UUID "$swap_part") swap swap pri=1 0 0" >> $ROOT/etc/fstab
	fi

	# root
	echo "UUID=$(blkid -o value -s UUID "$root_part") / $(lsblk -nrp -o FSTYPE $root_part) defaults 1 1" >> $ROOT/etc/fstab

	# /home
	if [ "$home_part" ]; then
		echo "UUID=$(blkid -o value -s UUID "$home_part") /home $(lsblk -nrp -o FSTYPE $home_part) defaults 0 0" >> $ROOT/etc/fstab
	fi

	while [ ! "$done" ]; do
		cclear
		cprint "Installation complete!"
		echo
		cprint "1. exit installer"
		cprint "2. chroot into installed system"
		cprint "3. reboot"
		cprint "4. poweroff"
		prompt_user "choose option: "
		read input
		case $input in
			1) umount -R $ROOT; exit 0;;
			2) xchroot $ROOT; exit 0;;
			3) umount -R $ROOT; reboot; exit 0;;
			4) umount -R $ROOT; poweroff; exit 0;;
		esac
		[ "$input" = 0 ] && continue
		[ "$input" -gt "4" ] && continue
		done=$input
	done
}

choose_desktop_env() {
	unset done
	while [ ! "$done" ]; do
		cclear
		cprint "1. None"
		cprint "2. GNOME"
		cprint "3. KDE (not yet)"
		cprint "4. Hyprland"
		cprint ""
		cprint "0. Back to main menu"
		prompt_user "Enter choice [0-3]: "
		read input
		case $input in
			1) DESKTOP_ENV="None";;
			2) DESKTOP_ENV="GNOME";;
			3) continue;;
			4) DESKTOP_ENV="Hyprland";;

		esac
		[ "$input" -gt "4" ] && continue
		done=$input
	done
}

config_kernel() {
	unset done
	while [ ! "$done" ]; do
		cclear
		cprint "1. LTS"
		cprint "2. Current"
		cprint ""
		cprint "0. Back to main menu"
		prompt_user "Enter choice [0-2]: "
		read input
		case $input in
			1) KERNEL="LTS";;
			2) KERNEL="Current";;
		esac
		[ "$input" -gt "2" ] && continue
		done=$input
	done
}

config_software_branch() {
	unset done
	while [ ! "$done" ]; do
		cclear
		cprint "1. rolling (not ready yet)"
		cprint "'rolling' is the default branch for Stock Linux. It is the stablest"
		cprint ""
		cprint "2. testing"
		cprint "'testing' is the dev branch. Not stable as 'rolling'"
		cprint ""
		cprint "0. Back to Advanced menu"
		prompt_user "Enter choice [0-2]: "
		read input
		case $input in
			1) continue;; #SOFTWARE_BRANCH="rolling";;
			2) SOFTWARE_BRANCH="testing";;
		esac
		[ "$input" -gt "2" ] && continue
		done=$input
	done
}


print_partitioning_tips() {
	cclear
	cprint "# Partitioning Tips #"
	echo
	cprint "For BIOS systems, MBR or GPT partition tables are supported. To use GPT"
	cprint "partition in BIOS system 1MB partition must be created and set as 'BIOS"
	cprint "boot'. For EFI systems, GPT partition is required and a FAT32 partition"
	cprint "with at least 100MB set as 'EFI System' must be created. This partition"
	cprint "will be used as 'EFI System Partition' with '/boot/efi' as mountpoint."
	prompt_user "Press ENTER to continue..."
	read input
}

print_selection() {
	cprint "1. partitions: $partstatus"
	cprint ""
	cprint "2. keymap: $KEYMAP"
	cprint "3. timezone: $TIMEZONE"
	cprint "4. locale: $LOCALE"
	cprint ""
	cprint "5. hostname: $HOSTNAME"
	cprint "6. user account: $USERNAME $(echo $USER_PSWD | tr '[:alpha:]' '*' | tr '[:alnum:]' '*')"
	cprint "7. root account: $(echo $ROOT_PSWD | tr '[:alpha:]' '*' | tr '[:alnum:]' '*')"
	cprint ""
	cprint "8. desktop environement: $DESKTOP_ENV"
	cprint ""
	cprint "9. Start Installation"
	cprint ""
	cprint "10. Advanced configuration"
	cprint ""
	cprint "0. exit installer"
}

main() {
	while true; do
		cclear
		print_selection
		prompt_user "Enter choice [1-11]: "
		read input
		case $input in
			1) config_partitioning;;
			2) config_keymap;;
			3) config_timezone;;
			4) config_locale;;
			5) config_hostname;;
			6) config_useraccount;;
			7) config_rootpswd;;
			8) choose_desktop_env;;
			9) start_install;;
			10) config_advanced;;
			0) exit;;
		esac
	done
}

if [ "$(id -u)" != 0 ]; then
	echo "root access required to install!"
	exit 1
fi

ROOT=/mnt/install

if [ -e /sys/firmware/efi/systab ]; then
	EFI_SYSTEM=1
fi

KERNEL="LTS"
BOOTLOADER_T="GRUB"
SOFTWARE_BRANCH="testing"

main

exit 0
