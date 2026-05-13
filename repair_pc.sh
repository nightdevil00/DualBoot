#!/usr/bin/env bash
set -euo pipefail

LOG="/tmp/repair_pc_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

die() {
    log "FATAL: $*"
    exit 1
}

confirm() {
    local prompt="$1"
    local answer
    echo ""
    read -r -p "$prompt [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        log "User cancelled."
        exit 1
    fi
}

run() {
    log "Running: $*"
    if "$@" 2>&1 | tee -a "$LOG"; then
        log "OK: $*"
    else
        log "FAILED (exit code $?): $*"
        return 1
    fi
}

# --- Network setup ---
setup_network() {
    log "Checking network connectivity..."
    if ping -c 1 -W 2 archlinux.org &>/dev/null; then
        log "Network is already available."
        return 0
    fi

    log "No network detected."

    if ip link show | grep -q "wl"; then
        log "WiFi interface found. Attempting WiFi connection..."
        echo ""
        echo "=========================================="
        echo "  WiFi Setup"
        echo "=========================================="
        iwctl device list | tee -a "$LOG"
        echo ""
        read -r -p "Enter WiFi device name (e.g. wlan0): " wifi_dev
        read -r -p "Enter SSID: " wifi_ssid
        read -r -s -p "Enter passphrase: " wifi_pass
        echo ""
        log "Connecting to '$wifi_ssid' via $wifi_dev..."
        iwctl station "$wifi_dev" connect "$wifi_ssid" --passphrase "$wifi_pass" 2>&1 | tee -a "$LOG" || {
            log "Trying iwctl interactive fallback..."
            {
              echo "station $wifi_dev connect $wifi_ssid"
              sleep 2
            } | iwctl 2>&1 | tee -a "$LOG"
        }
        sleep 5
        if ping -c 1 -W 2 archlinux.org &>/dev/null; then
            log "WiFi connection successful."
        else
            die "WiFi connection failed."
        fi
    elif ip link show | grep -q "eth\|enp\|enx"; then
        log "Ethernet interface found. Running dhcpcd..."
        run dhcpcd || log "dhcpcd may already be running; continuing."
        sleep 3
        if ping -c 1 -W 2 archlinux.org &>/dev/null; then
            log "Ethernet connection successful."
        else
            die "Ethernet connection failed. Check cable and try again."
        fi
    else
        die "No WiFi or Ethernet interface detected."
    fi
}

# --- Main ---
clear
echo "=========================================="
echo "  PC Repair Script"
echo "  Kernel + Bootloader Recovery"
echo "  (BTRFS / LUKS2 / Limine)"
echo "=========================================="
echo "Log: $LOG"
echo ""

# Step 0: Network
setup_network

# Step 1: List partitions
echo ""
echo "=========================================="
echo "  Available Partitions"
echo "=========================================="
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID 2>&1 | tee -a "$LOG"

echo ""
confirm "Have you identified your root partition (BTRFS, possibly LUKS) and ESP? Ready to proceed?"

# Step 2: Open LUKS (if encrypted)
echo ""
echo "=========================================="
echo "  Step 1: Mount Root Partition"
echo "=========================================="
read -r -p "Enter root partition (e.g. /dev/nvme0n1p2): " root_dev

root_mapper="$root_dev"
is_luks=false
if cryptsetup isLuks "$root_dev" 2>/dev/null; then
    is_luks=true
    log "LUKS detected on $root_dev"
    if run cryptsetup open "$root_dev" root; then
        root_mapper="/dev/mapper/root"
        log "LUKS container opened at $root_mapper."
    else
        die "Failed to open LUKS container."
    fi
else
    log "No LUKS detected – $root_dev is a plain filesystem."
    root_mapper="$root_dev"
fi

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1 | tee -a "$LOG"

# Step 3: Mount BTRFS subvolumes
echo ""
echo "=========================================="
echo "  Step 2: Mount BTRFS Subvolumes"
echo "=========================================="
log "Mounting BTRFS subvolumes from $root_mapper..."

run mount -o subvol=@ "$root_mapper" /mnt
run mkdir -p /mnt/home
run mount -o subvol=@home "$root_mapper" /mnt/home 2>/dev/null || log "@home subvolume not found – skipping."
run mkdir -p /mnt/boot

read -r -p "Enter ESP partition (e.g. /dev/nvme0n1p1): " esp_dev
run mount "$esp_dev" /mnt/boot

echo ""
confirm "Mounts OK? Ready to arch-chroot?"

# Step 4: arch-chroot – reinstall
echo ""
echo "=========================================="
echo "  Step 3: Reinstall Kernel & Bootloader"
echo "=========================================="
log "Entering arch-chroot..."

export IS_LUKS="$is_luks"

arch-chroot /mnt /bin/bash -s <<'CHROOT_EOF' 2>&1 | tee -a "$LOG"
set -euo pipefail

log_chroot() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [chroot] $*"
}

log_chroot "Updating pacman mirrors..."
pacman -Sy --noconfirm

log_chroot "Reinstalling linux, headers, limine..."
pacman -S --noconfirm linux linux-headers limine

log_chroot "Regenerating initramfs..."
mkinitcpio -P

# Deploy Limine on ESP
log_chroot "Deploying Limine to ESP..."
mkdir -p /boot/EFI/arch-limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/arch-limine/

log_chroot "Identifying disk info for efibootmgr..."
BOOT_PART=$(findmnt -n -o SOURCE /boot)
DISK=$(lsblk -no PKNAME "$BOOT_PART" | head -1)
PART_NUM=$(lsblk -no PARTN "$BOOT_PART")

if [ -n "$DISK" ] && [ -n "$PART_NUM" ] && command -v efibootmgr &>/dev/null; then
    log_chroot "Creating UEFI boot entry with efibootmgr..."
    if efibootmgr --create --disk "/dev/$DISK" --part "$PART_NUM" \
        --label "Arch Linux Limine Boot Loader" \
        --loader '\EFI\arch-limine\BOOTX64.EFI' --unicode; then
        log_chroot "UEFI boot entry created successfully."
    else
        log_chroot "efibootmgr failed – installing fallback boot entry..."
        mkdir -p /boot/EFI/BOOT
        cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
        log_chroot "Fallback boot entry installed."
    fi
else
    log_chroot "Could not determine disk/partition; installing fallback boot entry."
    mkdir -p /boot/EFI/BOOT
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
    log_chroot "Fallback boot entry installed."
fi

# Detect UKI vs separate kernel+initramfs
log_chroot "Detecting boot file type..."
UKI_FILE=""
for pattern in "/boot/EFI/Linux/*.efi" "/boot/*-linux.efi" "/boot/uki.efi"; do
    for f in $pattern; do
        if [ -f "$f" ] && [ "$(basename "$f")" != "BOOTX64.EFI" ]; then
            UKI_FILE="$f"
            break 2
        fi
    done
done

if [ -n "$UKI_FILE" ]; then
    log_chroot "Unified Kernel Image detected: $UKI_FILE"
    UKI_REL="${UKI_FILE#/boot}"
    UKI_REL="boot():${UKI_REL}"

    log_chroot "Writing limine.conf (UKI mode)..."
    cat > /boot/EFI/arch-limine/limine.conf << LIMINEEOF
timeout: 5

/Arch Linux
    protocol: linux
    path: ${UKI_REL}
LIMINEEOF
else
    log_chroot "No UKI found — using separate kernel + initramfs."
    log_chroot "Getting root device UUID..."
    ROOT_SOURCE=$(findmnt -n -o SOURCE / || true)
    ROOT_DEV="${ROOT_SOURCE%%\[*}"
    [ -z "$ROOT_DEV" ] && ROOT_DEV="$ROOT_SOURCE"
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV" || true)
    if [ -z "$ROOT_UUID" ]; then
        log_chroot "WARNING: Could not auto-detect UUID. Limine.conf will need manual editing."
        ROOT_UUID="YOUR_ROOT_PARTITION_UUID"
    fi

    if [ "${IS_LUKS:-false}" = "true" ]; then
        log_chroot "LUKS mode: resolving cryptdevice UUID..."
        CRYPT_SRC=$(dmsetup info -c root 2>/dev/null | awk 'NR==2{print $2}' || true)
        if [ -n "$CRYPT_SRC" ]; then
            DEV_PATH=$(ls -l "/dev/mapper/$CRYPT_SRC" 2>/dev/null | awk '{print $NF}' || echo "")
            [ -z "$DEV_PATH" ] && DEV_PATH="/dev/$CRYPT_SRC"
            LUKS_UUID=$(blkid -s UUID -o value "$DEV_PATH" 2>/dev/null || echo "$ROOT_UUID")
        else
            LUKS_UUID="$ROOT_UUID"
        fi
        CMDLINE="cryptdevice=UUID=${LUKS_UUID}:root root=/dev/mapper/root rw rootflags=subvol=@"
    else
        log_chroot "Plain BTRFS mode."
        CMDLINE="root=UUID=${ROOT_UUID} rw rootflags=subvol=@"
    fi

    log_chroot "Writing limine.conf (separate kernel+initramfs)..."
    cat > /boot/EFI/arch-limine/limine.conf << LIMINEEOF
timeout: 5

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: ${CMDLINE}
    module_path: boot():/initramfs-linux.img
LIMINEEOF
fi

log_chroot "limine.conf written to /boot/EFI/arch-limine/limine.conf"
log_chroot "Contents:"
cat /boot/EFI/arch-limine/limine.conf

log_chroot "Chroot steps complete."
CHROOT_EOF

# Step 6: Exit and reboot
echo ""
echo "=========================================="
echo "  Step 4: Cleanup and Reboot"
echo "=========================================="
log "Exiting chroot and cleaning up mounts..."
run umount -R /mnt
if [ "$is_luks" = "true" ]; then
    run cryptsetup close root
fi

log "All operations completed successfully."
echo ""
echo "=========================================="
echo "  Repair Complete"
echo "=========================================="
echo "Log saved to: $LOG"
echo ""

confirm "Remove the live USB, then reboot?"
run reboot
