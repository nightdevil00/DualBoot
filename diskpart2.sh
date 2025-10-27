#!/usr/bin/env bash
# safer-arch-install-fixed.sh
# Improved disk listing, Windows detection, and proper free space handling
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

echo
echo "What do you want to do?"
echo "  1) Create partitions for Arch Linux"
echo "  2) Delete a partition"
read -rp "Enter your choice (1-2): " choice

case "$choice" in
  1)

# --- Windows detection ---
echo
echo "Scanning all partitions on all disks for Windows boot files / EFI Microsoft..."
declare -A PROTECTED_PARTS  # map of partition -> reason

while IFS= read -r line; do
  eval "$line"
  if [[ "${TYPE:-}" != "part" ]]; then
    continue
  fi
  PART="/dev/${NAME}"
  [[ "$PART" =~ loop|sr|md ]] && continue

  FSTYPE=$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)

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

# --- Show free space ---
echo
echo "PARTITION TABLE + FREE SPACE (for $TARGET_DISK):"
parted --script "$TARGET_DISK" unit GB print free | sed -E 's/^(Number[[:space:]]+)(Start[[:space:]]+)(End[[:space:]]+)(Size[[:space:]]+)(.*)/\1\4\2\3\5/' | sed -E 's/^([[:space:]]*[0-9]*[[:space:]]+)([0-9\.]*GB[[:space:]]+)([0-9\.]*GB[[:space:]]+)([0-9\.]*GB[[:space:]]+)(.*)/\1\4\2\3\5/' | sed '/Free Space/s/.*/\x1b[1;33m&\x1b[0m/' || true

# Extract free spaces for selection
mapfile -t FREE_SPACES < <(
  parted --script "$TARGET_DISK" unit GB print free | awk '
    BEGIN{IGNORECASE=1}
    /Free/ {
      n=0
      for(i=1;i<=NF;i++){
        if($i ~ /^[0-9.]+GB$/){
          n++
          if(n==1) start=$i
          else if(n==2) end=$i
        }
      }
      gsub("GB","",start)
      gsub("GB","",end)
      if(start+0 < end+0) print start":"end
    }
  '
)

if [ ${#FREE_SPACES[@]} -eq 0 ]; then
  echo "No free space detected on $TARGET_DISK."
  exit 1
fi

echo



echo "Available free space blocks:"

for i in "${!FREE_SPACES[@]}"; do

  start=$(echo "${FREE_SPACES[$i]}" | cut -d: -f1)

  end=$(echo "${FREE_SPACES[$i]}" | cut -d: -f2)

  size=$(awk "BEGIN {print $end - $start}")

  printf "%2d) Start: %-8s End: %-8s Size: %-8s\n" "$((i+1))" "${start}GB" "${end}GB" "${size}GB"

done



read -rp "Select the free space block to use (e.g., 1): " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#FREE_SPACES[@]} )); then

  echo "Invalid selection. Exiting."

  exit 1

fi



selected_space="${FREE_SPACES[$((choice-1))]}"

free_start=$(echo "$selected_space" | cut -d: -f1)

free_end=$(echo "$selected_space" | cut -d: -f2)

free_size=$(awk "BEGIN {print $free_end - $free_start}")



echo "You selected a block of ${free_size}GB starting at ${free_start}GB."



efi_size=""

while true; do

  read -rp "Enter the size for the EFI partition in GB (recommended: 2): " efi_size

  if ! [[ "$efi_size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then

    echo "Invalid size. Please enter a number."

    continue

  fi

  if (( $(awk "BEGIN {print ($efi_size > $free_size)}") )); then

    echo "EFI partition size cannot be larger than the available free space (${free_size}GB)."

  else

    break

  fi

done



EFI_START="$free_start"

EFI_END=$(awk "BEGIN {print $free_start + $efi_size}")

ROOT_START="$EFI_END"

ROOT_END="$free_end"

root_size=$(awk "BEGIN {print $ROOT_END - $ROOT_START}")



echo



echo "The following partitions will be created:"

echo "  - EFI Partition:  ${EFI_START}GB - ${EFI_END}GB (${efi_size}GB)"

echo "  - Root Partition: ${ROOT_START}GB - ${ROOT_END}GB (${root_size}GB)"

read -rp "Do you want to continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then

  echo "Aborting."

  exit 1

fi



echo "Creating EFI partition..."

parted --script "$TARGET_DISK" mkpart primary fat32 "${EFI_START}GB" "${EFI_END}GB"

parted --script "$TARGET_DISK" set $(parted -s "$TARGET_DISK" print | awk '/^ /{n++; print n; exit}') boot on || true



echo "Creating root partition..."

parted --script "$TARGET_DISK" mkpart primary btrfs "${ROOT_START}GB" "${ROOT_END}GB"



partprobe "$TARGET_DISK" || true
sleep 1

parts=($(lsblk -ln -o NAME,TYPE "$TARGET_DISK" | awk '$2=="part"{print "/dev/"$1}'))
efi_partition="${parts[-2]}"
root_partition="${parts[-1]}"
echo "EFI partition: $efi_partition"
echo "Root partition: $root_partition"

# Format EFI
echo "Formatting EFI partition ($efi_partition) as FAT32..."
mkfs.fat -F32 "$efi_partition"

# Encrypt root
echo "Encrypting root partition ($root_partition) with LUKS2."
cryptsetup luksFormat "$root_partition"
cryptsetup luksOpen "$root_partition" cryptroot

# Btrfs
echo "Creating btrfs on /dev/mapper/cryptroot..."
mkfs.btrfs -f /dev/mapper/cryptroot

# Mount and create subvolumes
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home

# Mount EFI
mkdir -p /mnt/boot
mount "$efi_partition" /mnt/boot

echo
echo "Partitions are ready and mounted. You can now run:"
echo "  archinstall guided --root /mnt"
    ;;
  2)
    echo "Partitions on $TARGET_DISK:"
    parted "$TARGET_DISK" print
    read -rp "Enter the number of the partition to delete: " part_num
    if ! [[ "$part_num" =~ ^[0-9]+$ ]]; then
      echo "Invalid partition number."
      exit 1
    fi

    PART_PATH="${TARGET_DISK}p${part_num}" # Construct the full partition path

    # Check if the partition is mounted
    MOUNT_POINT=$(findmnt -n -o TARGET --source "$PART_PATH" 2>/dev/null || true)
    if [[ -n "$MOUNT_POINT" ]]; then
      echo "Partition $PART_PATH is currently mounted at $MOUNT_POINT."
      read -rp "Attempt to unmount $PART_PATH? (y/N): " unmount_confirm
      if [[ "$unmount_confirm" == "y" || "$unmount_confirm" == "Y" ]]; then
        echo "Unmounting $PART_PATH..."
        if ! umount "$PART_PATH"; then
          echo "Failed to unmount $PART_PATH. Aborting deletion."
          exit 1
        fi
        echo "$PART_PATH unmounted successfully."
      else
        echo "Aborting deletion. Partition must be unmounted first."
        exit 1
      fi
    fi

    read -rp "Are you sure you want to delete partition $part_num on $TARGET_DISK? This is irreversible. (y/N): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      parted --script "$TARGET_DISK" rm "$part_num"
      echo "Partition $part_num deleted."
    else
      echo "Aborting."
    fi
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac


