#!/bin/bash

# Arch Linux Installation Script

efi_part_num=""
efi_part=""
root_part=""


# --- Logging ---
log_file="/root/arch_install_$(date +%Y-%m-%d_%H-%M-%S).log"
exec &> >(tee -a "$log_file")

log_failure() {
    error "Script failed. Log saved to $log_file"
}

trap log_failure ERR

# --- Helper Functions ---
info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
    exit 1
}

size_to_mb() {
    size=$1
    unit=${size: -1}
    value=${size%?}
    case $unit in
        G|g)
            echo $(($value * 1024))
            ;;
        M|m)
            echo $value
            ;;
        K|k)
            echo $(($value / 1024))
            ;;
        *)
            echo $size
            ;;
    esac
}

# --- Initial Setup ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script as root."
    fi
}

check_dialog() {
    if ! command -v dialog &> /dev/null; then
        info "dialog could not be found, installing it now."
        pacman -Sy --noconfirm dialog
    fi
}

# --- User Input ---
get_user_info() {
    username=$(dialog --inputbox "Enter your desired username:" 8 40 --stdout)
    if [ $? -ne 0 ]; then
        error "User cancelled. Installation aborted."
    fi
    
    while true; do
        password=$(dialog --passwordbox "Enter your password:" 8 40 --stdout)
        if [ $? -ne 0 ]; then
            error "User cancelled. Installation aborted."
        fi
        password_confirm=$(dialog --passwordbox "Confirm your password:" 8 40 --stdout)
        if [ $? -ne 0 ]; then
            error "User cancelled. Installation aborted."
        fi
        if [ "$password" == "$password_confirm" ]; then
            break
        else
            dialog --msgbox "Passwords do not match. Please try again." 8 40
        fi
    done

    locale=$(dialog --inputbox "Enter your desired locale (e.g., us):" 8 40 "us" --stdout)
    if [ $? -ne 0 ]; then
        error "User cancelled. Installation aborted."
    fi
    language=$(dialog --inputbox "Enter your desired system language (e.g., en_US.UTF-8):" 8 40 "en_US.UTF-8" --stdout)
    if [ $? -ne 0 ]; then
        error "User cancelled. Installation aborted."
    fi
}

# --- System Setup ---
setup_system() {
    info "Setting up the system..."
    timedatectl set-ntp true

    info "Updating mirrorlist..."
    reflector --verbose --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

    info "Determining timezone..."
    timezone=$(curl -s ipinfo.io/timezone)
    dialog --yesno "Your timezone is detected as $timezone. Is this correct?" 8 40
    if [ $? -ne 0 ]; then
        timezone=$(dialog --inputbox "Please enter your timezone (e.g., Europe/Bucharest):" 8 40 --stdout)
    fi
    timedatectl set-timezone "$timezone"
}

# --- Disk Partitioning ---
partition_disk() {
    info "Partitioning the disk..."
    devices=()
    while read -r name size model; do
        if [[ $name =~ ^(sd|nvme|vd|mmcblk) ]]; then
            devices+=("/dev/$name" "$size $model")
        fi
    done < <(lsblk -d -n -o NAME,SIZE,MODEL)

    if [ ${#devices[@]} -eq 0 ]; then
        error "No disks found."
    fi

    disk=$(dialog --menu "Select a disk for installation:" 15 70 15 "${devices[@]}" --stdout)

    if [ -z "$disk" ]; then
        error "No disk selected. Installation aborted."
    fi

    # Check for Windows installation
    has_efi=false
    has_ntfs=false
    while IFS= read -r line; do
        if echo "$line" | grep -iq "fat32"; then
            has_efi=true
        fi
        if echo "$line" | grep -iq "ntfs"; then
            has_ntfs=true
        fi
    done < <(lsblk -f -n -o FSTYPE,NAME "$disk")

    if $has_efi && $has_ntfs; then
        dialog --yesno "Windows installation detected on $disk. Do you want to format the entire disk? (WARNING: THIS WILL DELETE WINDOWS)" 10 60
        if [ $? -eq 0 ]; then
            # Format entire disk
            info "Wiping all signatures from $disk..."
            wipefs -a "$disk"

            efi_size=$(dialog --inputbox "Enter the size for the EFI partition (e.g., 2200M):" 8 40 "2200M" --stdout)
            root_size=$(dialog --inputbox "Enter the size for the ROOT partition (e.g., 30G):" 8 40 "30G" --stdout)

            info "Partitioning $disk..."
            parted -s "$disk" mklabel gpt
            parted -s "$disk" mkpart ESP fat32 1MiB "$efi_size"
            parted -s "$disk" set 1 esp on
            parted -s "$disk" mkpart primary btrfs "$efi_size" 100%
        else
            # Install in free space
            free_space_info=$(parted -s --unit=MB "$disk" print free | grep "Free Space" | tail -n 1)
            if [ -z "$free_space_info" ]; then
                dialog --msgbox "No free space found on $disk." 8 40
                error "Installation aborted."
            fi

            free_space_start=$(echo "$free_space_info" | awk '{print $1}' | sed 's/MB//')
            free_space_end=$(echo "$free_space_info" | awk '{print $2}' | sed 's/MB//')
            free_space_size_mb=$(echo "$free_space_info" | awk '{print $3}' | sed 's/MB//')

            dialog --yesno "Found ${free_space_size_mb}MB of free space starting at ${free_space_start}MB. Do you want to install Arch Linux in this space?" 8 70
            if [ $? -ne 0 ]; then
                error "Installation aborted by user."
            fi

            efi_size=$(dialog --inputbox "Enter the size for the EFI partition (e.g., 2200M):" 8 40 "2200M" --stdout)
            root_size=$(dialog --inputbox "Enter the size for the ROOT partition (e.g., 30G):" 8 40 "30G" --stdout)

            efi_size_mb=$(size_to_mb "$efi_size")
            root_size_mb=$(size_to_mb "$root_size")

            if [ $(($efi_size_mb + $root_size_mb)) -gt $free_space_size_mb ]; then
                dialog --msgbox "Not enough free space for the requested partition sizes." 8 60
                error "Installation aborted."
            fi

            efi_part_end=$(awk -v start="$free_space_start" -v efi_size="$efi_size_mb" 'BEGIN {print start + efi_size}')
            root_part_end=$(awk -v efi_end="$efi_part_end" -v root_size="$root_size_mb" 'BEGIN {print efi_end + root_size}')

            info "Creating partitions in free space..."
            parted -s "$disk" mkpart ESP fat32 "${free_space_start}MB" "${efi_part_end}MB"
            parted -s "$disk" set 2 esp on
            parted -s "$disk" mkpart primary btrfs "${efi_part_end}MB" "100%"
        fi
    else
        # No Windows detected, format the entire disk
        dialog --yesno "This will format the entire disk $disk. All data will be lost. Are you sure?" 8 40
        if [ $? -ne 0 ]; then
            error "Installation aborted by user."
        fi

        info "Wiping all signatures from $disk..."
        wipefs -a "$disk"

        efi_size=$(dialog --inputbox "Enter the size for the EFI partition (e.g., 2200M):" 8 40 "2200M" --stdout)
        root_size=$(dialog --inputbox "Enter the size for the ROOT partition (e.g., 30G):" 8 40 "30G" --stdout)

        info "Partitioning $disk..."
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart ESP fat32 1MiB "$efi_size"
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary btrfs "$efi_size" 100%
    fi

    info "Informing the OS about the new partition table..."
    partprobe "$disk"
    blockdev --rereadpt "$disk"
    sleep 2

    # Get partition information
    part_info=$(parted -s "$disk" print)
    efi_part_num=$(echo "$part_info" | grep -E '\s+fat32\s+' | awk '{print $1}')
    root_part_num=$(echo "$part_info" | grep -E '\s+btrfs\s+' | awk '{print $1}')


    if [[ $disk == /dev/nvme* || $disk == /dev/mmcblk* ]]; then
        efi_part="${disk}p${efi_part_num}"
        root_part="${disk}p${root_part_num}"
    else
        efi_part="${disk}${efi_part_num}"
        root_part="${disk}${root_part_num}"
    fi
}


# --- Installation ---
install_base_system() {
    info "Installing the base system..."
    # Ensure kernel sees new partitions
    partprobe "$disk"
    sleep 2  # wait a moment

    if [ ! -b "$efi_part" ]; then
        error "EFI partition $efi_part not found."
    fi
    if [ ! -b "$root_part" ]; then
        error "Root partition $root_part not found."
    fi

    info "Encrypting the root partition..."
    echo -n "$password" | cryptsetup luksFormat --type luks2 --pbkdf argon2id --hash sha512 --key-size 512 --iter-time 10000 --use-urandom "$root_part" -
    echo -n "$password" | cryptsetup open "$root_part" cryptroot -

    info "Creating BTRFS filesystem on the encrypted partition..."
    mkfs.btrfs -f /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt || error "Failed to mount cryptroot."

    info "Creating BTRFS subvolumes..."
    btrfs su cr /mnt/@
    btrfs su cr /mnt/@home
    btrfs su cr /mnt/@pkg
    btrfs su cr /mnt/@log
    btrfs su cr /mnt/@snapshots
    btrfs su cr /mnt/@var
    umount /mnt || error "Failed to unmount cryptroot."

    info "Mounting subvolumes..."
    mount -o noatime,compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt || error "Failed to mount @ subvolume."
    mkdir -p /mnt/{boot,home,var,var/log,var/cache/pacman/pkg,.snapshots}
    mount -o noatime,compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home || error "Failed to mount @home subvolume."
    mount -o noatime,compress=zstd,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg || error "Failed to mount @pkg subvolume."
    mount -o noatime,compress=zstd,subvol=@log /dev/mapper/cryptroot /mnt/var/log || error "Failed to mount @log subvolume."
    mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots || error "Failed to mount @snapshots subvolume."
    mount -o noatime,compress=zstd,subvol=@var /dev/mapper/cryptroot /mnt/var || error "Failed to mount @var subvolume."
    
    info "Mounting boot partition..."
    mkfs.fat -F32 "$efi_part"
    mount "$efi_part" /mnt/boot || error "Failed to mount boot partition."

    info "Installing base packages..."
    pacstrap -K /mnt base base-devel linux linux-firmware btrfs-progs git cryptsetup

    genfstab -U /mnt >> /mnt/etc/fstab
}

# --- Configuration ---
configure_system() {
    info "Configuring the system..."

    if [ ! -f /mnt/bin/bash ]; then
        error "/mnt/bin/bash not found. pacstrap might have failed."
    fi

    info "Configuring mkinitcpio for encryption..."
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /mnt/etc/mkinitcpio.conf

    root_part_uuid=$(blkid -s PARTUUID -o value "$root_part")

    info "Creating Limine config file..."
    mkdir -p /mnt/boot/EFI/limine

cat > /mnt/boot/EFI/limine/limine.cfg <<EOF
TIMEOUT=5

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=boot:///vmlinuz-linux
    CMDLINE=cryptdevice=PARTUUID=$root_part_uuid:cryptroot root=/dev/mapper/cryptroot rw rootfstype=btrfs rootflags=subvol=@
    INITRD_PATH=boot:///initramfs-linux.img

:Arch Linux (fallback)
    PROTOCOL=linux
    KERNEL_PATH=boot:///vmlinuz-linux
    CMDLINE=cryptdevice=PARTUUID=$root_part_uuid:cryptroot root=/dev/mapper/cryptroot rw rootfstype=btrfs rootflags=subvol=@
    INITRD_PATH=boot:///initramfs-linux-fallback.img
EOF
  
    if $has_ntfs; then
        boot_part_uuid=$(blkid -s PARTUUID -o value "$efi_part")
        echo "" >> /mnt/boot/EFI/limine/limine.cfg
        echo ":Windows" >> /mnt/boot/EFI/limine/limine.cfg
        echo "    PROTOCOL=efi" >> /mnt/boot/EFI/limine/limine.cfg
        echo "    PATH=uuid($boot_part_uuid):/EFI/Microsoft/Boot/bootmgfw.efi" >> /mnt/boot/EFI/limine/limine.cfg
    fi

    info "Creating pacman hook for Limine..."
    mkdir -p /mnt/etc/pacman.d/hooks
    cat <<EOF > /mnt/etc/pacman.d/hooks/99-limine.hook
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Deploying Limine after upgrade...
When = PostTransaction
Exec = /usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
EOF

    arch-chroot /mnt /bin/bash -c "
        # Install additional packages
        pacman -S --noconfirm limine snapper networkmanager bluez-utils efibootmgr

        ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
        hwclock --systohc
        echo '$language UTF-8' > /etc/locale.gen
        locale-gen
        echo 'LANG=$language' > /etc/locale.conf
        echo 'KEYMAP=$locale' > /etc/vconsole.conf
        echo 'archlinux' > /etc/hostname
        {
            echo '127.0.0.1   localhost'
            echo '::1         localhost'
            echo '127.0.1.1   archlinux.localdomain archlinux'
        } >> /etc/hosts
        chpasswd <<< \"root:$password\"
        useradd -m -G wheel -s /bin/bash $username
        chpasswd <<< \"$username:$password\"
        echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers

        info \"Regenerating initramfs...\"
        mkinitcpio -P
        
        # Configure Limine
        mkdir -p /boot/EFI/limine
        cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/

        efibootmgr \
            --create \
            --disk \"$disk\" \
            --part \"$efi_part_num\" \
            --label \"Arch Linux Limine Bootloader\" \
            --loader '\\EFI\\limine\\BOOTX64.EFI' \
            --unicode
        
        # Configure Snapper
        snapper -c root create-config /
        btrfs subvolume delete /.snapshots
        mkdir /.snapshots
        mount -a
        chmod 750 /.snapshots

        # Install GPU and CPU specific packages
        if lspci | grep -i 'nvidia'; then
            pacman -S --noconfirm nvidia nvidia-utils linux-headers
        fi
        if lscpu | grep -i 'intel'; then
            pacman -S --noconfirm intel-ucode
        fi

        # Enable services
        systemctl enable NetworkManager
        systemctl enable bluetooth
        systemctl enable snapper-timeline.timer
        systemctl enable snapper-cleanup.timer
    "
}

# --- Main Function ---
main() {
    start_time=$(date +%s)
    check_root
    check_dialog
    get_user_info
    setup_system
    partition_disk
    install_base_system
    configure_system
    end_time=$(date +%s)
    installation_time=$((end_time - start_time))

    dialog --yesno "Installation finished in $installation_time seconds. Do you want to chroot into the new system? (If you say no, the system will reboot)" 10 60
    if [ $? -eq 0 ]; then
        arch-chroot /mnt
    else
        reboot
    fi
}

main
