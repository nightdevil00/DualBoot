#!/bin/bash

set -uo pipefail

########################################
# ROOT CHECK
########################################
require_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
}

pause() {
    read -rp "Press Enter to continue..."
}

########################################
# DISK SELECTION
########################################
select_disk() {
    echo "=== Available Disks ==="
    lsblk -d -o NAME,SIZE,MODEL

    echo
    read -rp "Select disk (e.g. sda, nvme0n1): " DISK
    DISK="/dev/$DISK"

    [[ -b "$DISK" ]] || { echo "Invalid disk."; exit 1; }
}

########################################
# DISPLAY
########################################
show_partitions() {
    echo
    echo "=== Current Layout: $DISK ==="
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE "$DISK"
    echo
}

########################################
# FORCE UNMOUNT EVERYTHING (FAT/EXT/BTRFS)
########################################
ensure_fully_unmounted() {
    local PART="$1"

    echo "Checking: $PART"

    ########################################
    # 1. SWAP HANDLING
    ########################################
    if swapon --show | grep -q "$PART"; then
        echo "⚠ Swap active on $PART → disabling"
        swapoff "$PART"
    fi

    ########################################
    # 2. NORMAL + MULTI-MOUNT UNMOUNT
    ########################################
    if findmnt -rn -S "$PART" &>/dev/null; then
        echo "⚠ Mounts found for $PART:"

        findmnt -rn -S "$PART" -o TARGET | while read -r mnt; do
            echo " - unmounting $mnt"
            umount "$mnt" 2>/dev/null || umount -l "$mnt"
        done
    fi

    ########################################
    # 3. BTRFS SPECIAL HANDLING (SUBVOLUMES)
    ########################################
    FSTYPE=$(lsblk -no FSTYPE "$PART" 2>/dev/null || true)

    if [[ "$FSTYPE" == "btrfs" ]]; then
        echo "⚠ BTRFS detected on $PART"

        # Try to find all mountpoints belonging to this FS
        if btrfs filesystem show "$PART" &>/dev/null; then
            echo "BTRFS filesystem active."

            # Find any mounts referencing it
            mountpoints=$(findmnt -rn -S "$PART" -o TARGET || true)

            if [[ -n "$mountpoints" ]]; then
                echo "$mountpoints" | while read -r mnt; do
                    echo " - unmounting subvolume mount: $mnt"
                    umount "$mnt" 2>/dev/null || umount -l "$mnt"
                done
            fi
        fi
    fi
}

########################################
# APPLY KERNEL PARTITION REFRESH
########################################
refresh_partitions() {
    echo "Refreshing kernel partition table..."
    partprobe "$DISK" || true
    udevadm settle || true
}

########################################
# WIPE SIGNATURES (OPTIONAL FULL RESET)
########################################
wipe_signatures() {
    echo "⚠ This will wipe ALL filesystem signatures on $DISK"
    read -rp "Type YES to confirm: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || return

    wipefs -a "$DISK"
    echo "Done."
}

########################################
# CREATE PARTITION TABLE
########################################
create_table() {
    echo "1) GPT"
    echo "2) MBR"
    read -rp "Choice: " CHOICE

    case "$CHOICE" in
        1) TYPE="gpt" ;;
        2) TYPE="msdos" ;;
        *) echo "Invalid"; return ;;
    esac

    echo "⚠ WARNING: This will destroy ALL data on $DISK"
    read -rp "Type YES to confirm: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || return

    parted -s "$DISK" mklabel "$TYPE"
    refresh_partitions

    echo "Partition table created."
}

########################################
# DELETE PARTITION (SAFE + UNMOUNT FIRST)
########################################
delete_partition() {
    show_partitions

    local parts
    mapfile -t parts < <(lsblk -ln -o NAME "$DISK")
    if (( ${#parts[@]} <= 1 )); then
        echo "No partitions to delete."
        return
    fi

    read -rp "Enter partition number to delete: " N

    PART=$(lsblk -ln -o NAME "$DISK" | sed -n "$((N+1))p")
    PART="/dev/$PART"

    ensure_fully_unmounted "$PART" || return

    echo "Deleting partition $N..."
    parted -s "$DISK" rm "$N"

    refresh_partitions
    echo "Deleted."
}

########################################
# CREATE PARTITION
########################################
set_flag() {
    local fs="$1"
    local part_name
    part_name=$(basename "$PART")
    local num="${part_name##*[!0-9]}"

    if [[ "$fs" == "fat32" ]]; then
        read -rp "Set as EFI System Partition? (y/n): " ESP
        if [[ "$ESP" =~ ^[Yy]$ ]]; then
            parted -s "$DISK" set "$num" esp on 2>/dev/null || true
            echo "ESP flag set on partition $num."
        fi
    elif [[ "$fs" == "linux-swap" ]]; then
        :  # no extra flag needed
    fi
}

create_partition() {
    read -rp "Start (e.g. 1MiB): " START
    read -rp "End (e.g. 100%): " END
    read -rp "Filesystem (ext4/fat32/btrfs/linux-swap): " FS

    parted -s "$DISK" mkpart primary "$FS" "$START" "$END"
    refresh_partitions

    PART=$(lsblk -ln -o NAME "$DISK" | tail -n 1)
    PART="/dev/$PART"

    ensure_fully_unmounted "$PART" || return

    echo "Formatting $PART as $FS..."

    case "$FS" in
        ext4)
            read -rp "Label (leave empty for none): " LABEL
            if [[ -n "$LABEL" ]]; then
                mkfs.ext4 -L "$LABEL" "$PART"
            else
                mkfs.ext4 "$PART"
            fi
            ;;
        fat32)
            mkfs.fat -F32 "$PART"
            ;;
        linux-swap)
            mkswap "$PART"
            ;;
        btrfs)
            read -rp "Label (leave empty for none): " LABEL
            if [[ -n "$LABEL" ]]; then
                mkfs.btrfs -f -L "$LABEL" "$PART"
            else
                mkfs.btrfs -f "$PART"
            fi
            ;;
        *) echo "Unknown FS, skipping format." ;;
    esac

    set_flag "$FS"

    refresh_partitions
    echo "Created $PART"
}

########################################
# MENU LOOP
########################################
main_menu() {
    while true; do
        clear
        echo "=== ARCH PARTITION MANAGER (SAFE MODE) ==="
        echo "Disk: $DISK"
        show_partitions

        echo "1) Create partition table"
        echo "2) Create partition"
        echo "3) Delete partition"
        echo "4) Wipe filesystem signatures"
        echo "5) Refresh"
        echo "6) Exit"

        read -rp "Choice: " C

        case "$C" in
            1) create_table ;;
            2) create_partition ;;
            3) delete_partition ;;
            4) wipe_signatures ;;
            5) refresh_partitions ;;
            6) exit 0 ;;
            *) echo "Invalid" ;;
        esac

        pause
    done
}

########################################
# START
########################################
require_root
select_disk
main_menu
