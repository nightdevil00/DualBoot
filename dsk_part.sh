#!/bin/bash

set -euo pipefail

########################################
# Utils
########################################

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Run as root."
        exit 1
    fi
}

pause() {
    read -rp "Press Enter to continue..."
}

########################################
# Disk selection
########################################

select_disk() {
    echo "=== Available Disks ==="
    lsblk -d -o NAME,SIZE,MODEL

    echo
    read -rp "Select disk (e.g. sda, nvme0n1): " DISK
    DISK="/dev/$DISK"

    if [[ ! -b "$DISK" ]]; then
        echo "Invalid disk."
        exit 1
    fi
}

########################################
# Display
########################################

show_partitions() {
    echo
    echo "=== Layout: $DISK ==="
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK"
    echo
}

########################################
# Safety: unmount + swap handling
########################################

ensure_unmounted() {
    local PART="$1"

    # Handle swap
    if swapon --show | grep -q "$PART"; then
        echo "⚠️ $PART is active swap."
        read -rp "Disable swap? [Y/n]: " CONFIRM
        CONFIRM=${CONFIRM:-Y}

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            swapoff "$PART"
            echo "Swap disabled."
        else
            echo "Aborted."
            return 1
        fi
    fi

    # Handle mountpoints
    if findmnt -rn "$PART" > /dev/null; then
        echo "⚠️ $PART is mounted:"
        findmnt "$PART"

        read -rp "Unmount it? [Y/n]: " CONFIRM
        CONFIRM=${CONFIRM:-Y}

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Unmounting..."

            if ! umount "$PART"; then
                echo "Normal unmount failed → using lazy unmount..."
                umount -l "$PART"
            fi

            echo "Unmounted."
        else
            echo "Aborted."
            return 1
        fi
    fi
}

########################################
# Operations
########################################

wipe_signatures() {
    echo "⚠️ This will wipe ALL filesystem signatures on $DISK"
    read -rp "Type YES to confirm: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || return

    wipefs -a "$DISK"
    echo "Done."
}

create_table() {
    echo "1) GPT"
    echo "2) MBR"
    read -rp "Choice: " TABLE

    case "$TABLE" in
        1) TYPE="gpt" ;;
        2) TYPE="msdos" ;;
        *) echo "Invalid."; return ;;
    esac

    echo "⚠️ This will ERASE all partitions!"
    read -rp "Type YES to confirm: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || return

    parted -s "$DISK" mklabel "$TYPE"
    echo "Partition table created."
}

delete_partition() {
    show_partitions
    read -rp "Enter partition number to delete: " PART_NUM

    PART_PATH=$(lsblk -ln -o NAME "$DISK" | sed -n "$((PART_NUM+1))p")
    PART_PATH="/dev/$PART_PATH"

    ensure_unmounted "$PART_PATH" || return

    echo "Deleting partition $PART_NUM..."
    parted -s "$DISK" rm "$PART_NUM"

    echo "Done."
}

create_partition() {
    echo "Start (e.g. 1MiB):"
    read -r START

    echo "End (e.g. 512MiB or 100%):"
    read -r END

    echo "Filesystem (ext4, fat32, linux-swap):"
    read -r FSTYPE

    parted -s "$DISK" mkpart primary "$FSTYPE" "$START" "$END"
    partprobe "$DISK"

    PART=$(lsblk -ln -o NAME "$DISK" | tail -n 1)
    PART="/dev/$PART"

    ensure_unmounted "$PART" || return

    echo "Formatting $PART..."

    case "$FSTYPE" in
        ext4) mkfs.ext4 "$PART" ;;
        fat32) mkfs.fat -F32 "$PART" ;;
        linux-swap) mkswap "$PART" ;;
        *) echo "Unknown FS, skipped formatting." ;;
    esac

    echo "Created: $PART"
}

########################################
# Menu
########################################

main_menu() {
    while true; do
        clear
        echo "=== Arch Partition Manager ==="
        echo "Disk: $DISK"

        show_partitions

        echo "1) Create partition table (wipe disk)"
        echo "2) Create partition"
        echo "3) Delete partition"
        echo "4) Wipe filesystem signatures"
        echo "5) Refresh"
        echo "6) Exit"

        echo
        read -rp "Select option: " CHOICE

        case "$CHOICE" in
            1) create_table ;;
            2) create_partition ;;
            3) delete_partition ;;
            4) wipe_signatures ;;
            5) ;;
            6) break ;;
            *) echo "Invalid option." ;;
        esac

        partprobe "$DISK"
        pause
    done
}

########################################
# Run
########################################

require_root
select_disk
main_menu
