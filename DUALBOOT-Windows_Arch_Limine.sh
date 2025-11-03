#!/usr/bin/env bash
# ==============================================================================
# Arch Linux Full Installer – Dualboot + Limine + Encryption + Snapper + Plymouth
# Windows-safe dualboot (creates separate Arch EFI)
# Production-Ready Version (2025)
# ==============================================================================

set -euo pipefail
trap 'cleanup' EXIT

HOSTNAME=${HOSTNAME:-arch}
LOCALE=${LOCALE:-en_US.UTF-8}
TIMEZONE=${TIMEZONE:-UTC}
SWAP_SIZE=${SWAP_SIZE:-4G}

LOG_FILE="/tmp/arch_install_$(date +%Y%m%d_%H%M%S).log"
TMP_MOUNT="/mnt/__tmp"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "📘 Logging to: $LOG_FILE"

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

mkdir -p "$TMP_MOUNT"

TARGET_DISK=""
EFI_DEV=""
ROOT_DEV=""
EFI_PART_NUM=""
ROOT_UUID=""
LUKS_UUID=""

# ==============================================================================
# Cleanup
# ==============================================================================
cleanup() {
    echo "🧹 Cleaning up..."
    umount -R /mnt 2>/dev/null || true
    umount "$TMP_MOUNT" 2>/dev/null || true
    cryptsetup luksClose root 2>/dev/null || true
    rm -rf "$TMP_MOUNT"
}

# ==============================================================================
# Disk selection
# ==============================================================================
select_disk() {
    if [[ -n "${AUTO_DISK:-}" ]]; then
        TARGET_DISK="$AUTO_DISK"
        echo "⚙️  Using AUTO_DISK=$TARGET_DISK"
        return
    fi

    declare -a DEVICES=()
    declare -A DEV_MODEL DEV_SIZE DEV_TRAN

    while IFS= read -r line; do
        eval "$line"
        [[ "${TYPE:-}" == "disk" ]] || continue
        devpath="/dev/${NAME}"
        DEVICES+=("$devpath")
        DEV_MODEL["$devpath"]="${MODEL:-unknown}"
        DEV_SIZE["$devpath"]="${SIZE:-unknown}"
        DEV_TRAN["$devpath"]="${TRAN:-unknown}"
    done < <(lsblk -P -o NAME,TYPE,SIZE,MODEL,TRAN)

    echo "Available disks:"
    for i in "${!DEVICES[@]}"; do
        printf " %2d) %-12s %8s  %-15s [%s]\n" \
            "$((i+1))" "${DEVICES[i]}" "${DEV_SIZE[${DEVICES[i]}]}" \
            "${DEV_MODEL[${DEVICES[i]}]}" "${DEV_TRAN[${DEVICES[i]}]}"
    done

    read -rp "Select disk number: " num
    [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#DEVICES[@]} )) || { echo "Invalid choice."; exit 1; }
    TARGET_DISK="${DEVICES[$((num-1))]}"
    echo "Selected: $TARGET_DISK"
}

# ==============================================================================
# Partition disk
# ==============================================================================
partition_disk() {
    # Detect existing Windows EFI
    WIN_EFI_DEV=$(blkid -t TYPE=vfat -o device | while read p; do
        TMP=$(mktemp -d)
        mount -o ro "$p" "$TMP" 2>/dev/null || continue
        if [[ -d "$TMP/EFI/Microsoft" ]]; then
            echo "$p"
        fi
        umount "$TMP" 2>/dev/null
        rmdir "$TMP"
    done | head -n1)

    if [[ -n "$WIN_EFI_DEV" ]]; then
        echo "💠 Windows EFI detected on $WIN_EFI_DEV → leaving it untouched"
        parted --script "$TARGET_DISK" unit GB print free

        read -rp "Enter start of new EFI for Arch (e.g. 1GB): " EFI_START
        read -rp "Enter end of new EFI for Arch (e.g. 3GB): " EFI_END
        read -rp "Enter start of root partition (e.g. 3GB): " ROOT_START
        read -rp "Enter end of root partition (e.g. 100%): " ROOT_END

        # Determine next available partition number
        LAST_NUM=$(parted -m "$TARGET_DISK" print | awk -F: '/^Number/{next}{n=$1}END{print n}')
        EFI_PART_NUM=$((LAST_NUM + 1))
        ROOT_PART_NUM=$((EFI_PART_NUM + 1))

        echo "🧩 Creating Arch EFI as partition $EFI_PART_NUM and root as $ROOT_PART_NUM ..."

        # Create Arch EFI and root
        parted --script "$TARGET_DISK" mkpart primary fat32 "$EFI_START" "$EFI_END"
        parted --script "$TARGET_DISK" set "$EFI_PART_NUM" esp on
        parted --script "$TARGET_DISK" name "$EFI_PART_NUM" "ARCH_EFI"
        parted --script "$TARGET_DISK" mkpart primary btrfs "$ROOT_START" "$ROOT_END"
        parted --script "$TARGET_DISK" name "$ROOT_PART_NUM" "ARCH_ROOT"

        # Refresh partition table
        partprobe "$TARGET_DISK"
        sync
        sleep 3

        EFI_DEV="${TARGET_DISK}p${EFI_PART_NUM}"
        ROOT_DEV="${TARGET_DISK}p${ROOT_PART_NUM}"

        echo "✅ Partitions ready:"
        echo "   • EFI:  $EFI_DEV (part $EFI_PART_NUM)"
        echo "   • ROOT: $ROOT_DEV"
    else
        # No Windows EFI case
        read -rp "⚠️  Wipe $TARGET_DISK and create new partitions? (yes/no): " yn
        [[ "$yn" == "yes" ]] || exit 0

        parted --script "$TARGET_DISK" mklabel gpt
        parted --script "$TARGET_DISK" mkpart primary fat32 1MiB 2049MiB
        parted --script "$TARGET_DISK" set 1 esp on
        parted --script "$TARGET_DISK" name 1 "ARCH_EFI"
        parted --script "$TARGET_DISK" mkpart primary btrfs 2049MiB 100%
        parted --script "$TARGET_DISK" name 2 "ARCH_ROOT"

        partprobe "$TARGET_DISK"
        sync
        sleep 3

        EFI_DEV="${TARGET_DISK}p1"
        ROOT_DEV="${TARGET_DISK}p2"

        echo "✅ Partitions ready:"
        echo "   • EFI:  $EFI_DEV (part 1)"
        echo "   • ROOT: $ROOT_DEV (part 2)"
    fi
}



# ==============================================================================
# Encryption + Btrfs setup
# ==============================================================================
setup_encryption_btrfs() {
    local LUKS_PASS
    if [[ -n "${AUTO_LUKS_PASS:-}" ]]; then
        LUKS_PASS="$AUTO_LUKS_PASS"
    else
        while true; do
            read -rsp "LUKS passphrase: " LUKS_PASS; echo
            read -rsp "Confirm: " LUKS_PASS2; echo
            [[ "$LUKS_PASS" == "$LUKS_PASS2" ]] && break
            echo "Mismatch. Try again."
        done
    fi

    printf "%s" "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --batch-mode --force-password "$ROOT_DEV" -
    printf "%s" "$LUKS_PASS" | cryptsetup open "$ROOT_DEV" root

    mkfs.btrfs /dev/mapper/root

    mount /dev/mapper/root /mnt
    for sub in @ @home @snapshots @log @swap; do
        btrfs subvolume create "/mnt/$sub"
    done
    umount /mnt

    mount -o noatime,compress=zstd,subvol=@ /dev/mapper/root /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,boot}
    mount -o noatime,compress=zstd,subvol=@home /dev/mapper/root /mnt/home
    mount -o noatime,compress=zstd,subvol=@snapshots /dev/mapper/root /mnt/.snapshots
    mount -o noatime,compress=zstd,subvol=@log /dev/mapper/root /mnt/var/log

    # Format Arch EFI only
    read -rp "Format new Arch EFI partition $EFI_DEV? (yes/no): " fmt
    [[ "$fmt" == "yes" ]] && mkfs.fat -F32 "$EFI_DEV"
    mount "$EFI_DEV" /mnt/boot

    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
    LUKS_UUID=$(cryptsetup luksUUID "$ROOT_DEV")

    echo "EFI: $EFI_DEV | ROOT: $ROOT_DEV | LUKS_UUID=$LUKS_UUID"
}

# ==============================================================================
# Base system
# ==============================================================================
install_base_system() {
    pacstrap /mnt base base-devel linux linux-firmware sudo networkmanager btrfs-progs \
        iwd git limine efibootmgr binutils amd-ucode intel-ucode zram-generator \
        plymouth snapper cryptsetup reflector vim dhcpcd firewalld bluez bluez-utils \
        acpid avahi rsync bash-completion pipewire pipewire-alsa pipewire-pulse wireplumber sof-firmware

    genfstab -U /mnt >> /mnt/etc/fstab
    echo "root UUID=$LUKS_UUID none luks,discard" >> /mnt/etc/crypttab
}

# ==============================================================================
# System configuration inside chroot (unchanged)
# ==============================================================================
configure_system() {
  local USERNAME PASSWORD

  USERNAME=${AUTO_USER:-$(read -rp "Username: " u; echo "$u")}
  echo "Root and user passwords will be set interactively inside chroot."

  cat > /mnt/setup.sh <<EOF
#!/usr/bin/bash
set -euo pipefail

EFI_DEV="$EFI_DEV"
ROOT_DEV="$ROOT_DEV"
EFI_PART_NUM="$EFI_PART_NUM"
TARGET_DISK="$TARGET_DISK"
LUKS_UUID="$LUKS_UUID"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

passwd
useradd -m -G wheel "$USERNAME"
passwd "$USERNAME"
sed -i '/^# %wheel ALL=(ALL:ALL) ALL$/s/^# //' /etc/sudoers

sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's|^#BINARIES=.*|BINARIES=(/usr/bin/btrfs)|' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
echo 'COMPRESSION="zstd"' >> /etc/mkinitcpio.conf
mkinitcpio -P

cat > /etc/systemd/zram-generator.conf <<ZRAM
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
ZRAM

plymouth-set-default-theme -R spinner

mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/

# Create UEFI boot entry for Arch EFI
efibootmgr --create --disk \$TARGET_DISK --part \$EFI_PART_NUM --label "Arch Linux Limine Bootloader" --loader '\\EFI\\limine\\BOOTX64.EFI' --unicode
efibootmgr -v

# Limine configuration
cat <<LIMINECONF > /boot/EFI/limine/limine.conf
timeout: 3

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: quiet cryptdevice=UUID=\$LUKS_UUID:root root=/dev/mapper/root rw rootflags=subvol=@ rootfstype=btrfs
    module_path: boot():/initramfs-linux.img

/Arch Linux (fallback)
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: quiet cryptdevice=UUID=\$LUKS_UUID:root root=/dev/mapper/root rw rootflags=subvol=@ rootfstype=btrfs
    module_path: boot():/initramfs-linux-fallback.img
LIMINECONF

systemctl enable NetworkManager iwd bluetooth avahi-daemon firewalld acpid
EOF

  chmod +x /mnt/setup.sh
  arch-chroot /mnt /setup.sh || { echo "❌ Chroot setup failed"; exit 1; }
  rm /mnt/setup.sh
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    select_disk
    partition_disk
    setup_encryption_btrfs
    install_base_system
    configure_system

    echo "✅ Installation complete!"
    echo "Reboot and select 'Arch Linux (Limine)' in UEFI menu."
    echo "Hostname: $HOSTNAME | Locale: $LOCALE | Timezone: $TIMEZONE"
}

main
