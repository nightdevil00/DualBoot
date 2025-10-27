#!/usr/bin/env bash
# safer-arch-install.sh
# Improved disk listing and Windows detection; safer partitioning when Windows is present.
set -euo pipefail

# check root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

TMP_MOUNT="/mnt/__arch_install_tmp"
mkdir -p "$TMP_MOUNT"

# Helper: print a parseable lsblk and return array of disks (TYPE=disk)
declare -a DEVICES=()
declare -A DEV_MODEL DEV_SIZE DEV_TRAN DEV_MOUNT

while IFS= read -r line; do
  # lsblk -P fields are KEY="VALUE"
  eval "$line"   # populates variables like NAME, KNAME, SIZE, MODEL, TRAN, MOUNTPOINT, TYPE
  if [[ "${TYPE:-}" == "disk" ]]; then
    devpath="/dev/${NAME}"
    DEVICES+=("$devpath")
    DEV_MODEL["$devpath"]="${MODEL:-unknown}"
    DEV_SIZE["$devpath"]="${SIZE:-unknown}"
    DEV_TRAN["$devpath"]="${TRAN:-unknown}"
    DEV_MOUNT["$devpath"]="${MOUNTPOINT:-}"
  fi
done < <(lsblk -P -o NAME,KNAME,TYPE,SIZE,MODEL,TRAN,MOUNTPOINT)

if [ ${#DEVICES[@]} -eq 0 ]; then
  echo "No block devices found. Exiting."
  exit 1
fi

echo "Available physical disks:"
for i in "${!DEVICES[@]}"; do
  idx=$((i+1))
  d=${DEVICES[$i]}
  printf "%2d) %-12s  %8s  %-10s  transport=%s\n" \
    "$idx" "$d" "${DEV_SIZE[$d]}" "${DEV_MODEL[$d]}" "${DEV_TRAN[$d]}"
done

read -rp $'Enter the number of the disk for Arch installation (e.g., 1): ' disk_number
if ! [[ "$disk_number" =~ ^[0-9]+$ ]] || (( disk_number < 1 || disk_number > ${#DEVICES[@]} )); then
  echo "Invalid selection. Exiting."
  exit 1
fi

TARGET_DISK="${DEVICES[$((disk_number-1))]}"
echo "You selected: $TARGET_DISK"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$TARGET_DISK"

# --- Windows detection ---
echo
echo "Scanning all partitions on all disks for Windows boot files / EFI Microsoft..."
declare -A PROTECTED_PARTS  # map of partition -> reason

# Iterate partitions across all disks (not just selected) to identify Windows systems
while IFS= read -r line; do
  eval "$line"   # this yields NAME,TYPE,FSTYPE,MOUNTPOINT etc.
  if [[ "${TYPE:-}" != "part" ]]; then
    continue
  fi
  PART="/dev/${NAME}"
  # skip loop devices, zram, etc
  if [[ "$PART" =~ loop|sr|md ]]; then
    continue
  fi

  # Find filesystem type via blkid (non-interactive)
  FSTYPE=$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)

  # If VFAT/Efi, mount ro and look for EFI/Microsoft
  if [[ "$FSTYPE" == "vfat" || "$FSTYPE" == "fat32" || "$FSTYPE" == "fat" ]]; then
    mkdir -p "$TMP_MOUNT"
    if mount -o ro,noload "$PART" "$TMP_MOUNT" 2>/dev/null; then
      if [[ -d "$TMP_MOUNT/EFI/Microsoft" ]] || [[ -f "$TMP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi" ]] || [[ -f "$TMP_MOUNT/EFI/Boot/bootx64.efi" ]]; then
        PROTECTED_PARTS["$PART"]="EFI Microsoft files found"
        echo "Protected (EFI): $PART -> ${PROTECTED_PARTS[$PART]}"
      fi
      umount "$TMP_MOUNT" || true
    fi
  fi

  # If NTFS, mount ro and look for Windows folder or boot files
  if [[ "$FSTYPE" == "ntfs" ]]; then
    mkdir -p "$TMP_MOUNT"
    if mount -o ro,noload "$PART" "$TMP_MOUNT" 2>/dev/null; then
      if [[ -d "$TMP_MOUNT/Windows" ]] || [[ -f "$TMP_MOUNT/bootmgr" ]] || [[ -d "$TMP_MOUNT/Boot" ]]; then
        PROTECTED_PARTS["$PART"]="NTFS Windows files found"
        echo "Protected (NTFS): $PART -> ${PROTECTED_PARTS[$PART]}"
      fi
      umount "$TMP_MOUNT" || true
    fi
  fi

done < <(lsblk -P -o NAME,TYPE,FSTYPE,MOUNTPOINT)

# Summarize
if [ ${#PROTECTED_PARTS[@]} -gt 0 ]; then
  echo
  echo "Detected partitions that look like Windows/EFI. They will not be modified by this script:"
  for p in "${!PROTECTED_PARTS[@]}"; do
    echo "  $p -> ${PROTECTED_PARTS[$p]}"
  done
  echo
  echo "Because Windows partitions were found, the script will NOT automatically rewrite the whole partition table."
  echo "Instead, we'll show you the free space on the selected disk so you can create partitions only inside free space."
  echo
  echo "PARTITION TABLE + FREE SPACE (for $TARGET_DISK):"
  parted --script "$TARGET_DISK" unit GB print free || true

  echo
  echo "Please provide the start and end positions (in GB) for your new Arch partitions within the free area shown above."
  echo "Example: for an EFI partition you might enter start=1GB end=3GB (i.e., 2GB size)."
  read -rp "EFI start (e.g. 1GB): " EFI_START
  read -rp "EFI end (e.g. 3GB): " EFI_END
  read -rp "Root start (e.g. 3GB): " ROOT_START
  read -rp "Root end  (e.g. 60GB or 100%): " ROOT_END

  echo "Creating EFI partition..."
  parted --script "$TARGET_DISK" mkpart primary fat32 "$EFI_START" "$EFI_END"
  parted --script "$TARGET_DISK" set $(parted -s "$TARGET_DISK" print | awk '/^ /{n++; print n; exit}') boot on || true
  echo "Creating root partition..."
  parted --script "$TARGET_DISK" mkpart primary btrfs "$ROOT_START" "$ROOT_END"

  # Refresh partitions
  partprobe "$TARGET_DISK" || true

  # Determine new partition names: for nvme it's pN, for sd it's sdxN
  # We'll take the last two partitions created and set them as EFI/root heuristically
  sleep 1
  parts=($(lsblk -ln -o NAME,TYPE "$TARGET_DISK" | awk '$2=="part"{print "/dev/"$1}'))
  # assume last-1 = efi, last = root (best-effort)
  efi_partition="${parts[-2]}"
  root_partition="${parts[-1]}"
  echo "EFI partition: $efi_partition"
  echo "Root partition: $root_partition"

else
  # No Windows detected: confirm full disk wipe
  echo "No Windows partitions detected on any disk."
  read -rp "Proceed to wipe and use the entire $TARGET_DISK for Arch? (yes/no): " yn
  if [[ "$yn" != "yes" ]]; then
    echo "Aborting."
    exit 0
  fi

  echo "Creating new GPT and partitions (EFI + root) on $TARGET_DISK"
  parted --script "$TARGET_DISK" mklabel gpt
  # create 2GB EFI
  parted --script "$TARGET_DISK" mkpart primary fat32 1MiB 2049MiB
  parted --script "$TARGET_DISK" set 1 boot on
  # rest as root
  parted --script "$TARGET_DISK" mkpart primary btrfs 2049MiB 100%
  partprobe "$TARGET_DISK" || true

  # find created partitions
  parts=($(lsblk -ln -o NAME,TYPE "$TARGET_DISK" | awk '$2=="part"{print "/dev/"$1}'))
  efi_partition="${parts[0]}"
  root_partition="${parts[1]}"
  echo "EFI partition: $efi_partition"
  echo "Root partition: $root_partition"
fi

# Final safety check: ensure EFI and root variables exist
if [[ -z "${efi_partition:-}" || -z "${root_partition:-}" ]]; then
  echo "Couldn't determine new partition paths automatically. Listing partitions for manual verification:"
  lsblk -o NAME,KNAME,SIZE,FSTYPE,MOUNTPOINT "$TARGET_DISK"
  echo "Please re-run the script after confirming partition names."
  exit 1
fi

# Format EFI partition
echo "Formatting EFI partition ($efi_partition) as FAT32..."
mkfs.fat -F32 "$efi_partition"

# Ask for LUKS passphrase (interactively) then format root and open
echo "Encrypting root partition ($root_partition) with LUKS2."
echo "You will be prompted interactively by cryptsetup."
cryptsetup luksFormat "$root_partition"
cryptsetup luksOpen "$root_partition" cryptroot

# create btrfs
echo "Creating btrfs on /dev/mapper/cryptroot..."
mkfs.btrfs -f /dev/mapper/cryptroot

# mount and create subvolumes
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home

# mount efi
mkdir -p /mnt/boot
mount "$efi_partition" /mnt/boot

# pacstrap
pacstrap /mnt base linux linux-firmware linux-headers iwd networkmanager vim nano sudo grub efibootmgr btrfs-progs os-prober

# genfstab
genfstab -U /mnt >> /mnt/etc/fstab

# Save root partition path for chroot
echo "$root_partition" > /mnt/ROOT_PART_PATH

# user input for username/password
read -rp "New username: " username
read -rsp "Password for $username: " user_password; echo
read -rsp "Root password: " root_password; echo

cat > /mnt/arch_install_vars.sh <<EOF
ROOT_PART="$root_partition"
USERNAME="$username"
USER_PASS="$user_password"
ROOT_PASS="$root_password"
EOF

# chroot and finish configuration
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
# Load variables created earlier
source /arch_install_vars.sh

# find UUID of root partition (the underlying encrypted partition)
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# timezone / locale
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# hostname
echo "arch-linux" > /etc/hostname

# set root password
echo "root:$ROOT_PASS" | chpasswd

# create user
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$USER_PASS" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers

# crypttab
echo "cryptroot UUID=$ROOT_UUID none luks,discard" > /etc/crypttab

# mkinitcpio hooks
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# grub config - append cryptdevice param to default if present
if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub; then
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
else
  echo "GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot\"" >> /etc/default/grub
fi

# install grub to EFI
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# enable NetworkManager (optional)
systemctl enable NetworkManager

# cleanup
rm -f /arch_install_vars.sh
EOF

echo
echo "Install steps finished. Review output above for any errors."
echo "Reboot when ready. If Windows exists it was protected and should appear in GRUB if os-prober detected it."

