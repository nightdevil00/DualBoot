#!/bin/bash
# ==============================================================================
# Arch Linux Interactive Rescue Script - Fixed ISO-ready version
# Supports BTRFS + LUKS2, Limine/GRUB, NVIDIA fallback
# ==============================================================================
# DISCLAIMER:
# This script is provided "as-is" for educational and personal use only.
# The author is NOT responsible for any damage, data loss, or system issues
# that may result from using or modifying this script. Use at your own risk.
# Always review and understand the script before running it, especially on
# production or sensitive systems.
# ==============================================================================

C_BLUE="\e[34m"; C_GREEN="\e[32m"; C_RED="\e[31m"; C_RESET="\e[0m"
info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }
press_enter_to_continue() { read -p "Press Enter to continue..."; }

# --- Global Variables ---
CHROOT_USER=""

# =======================
# Menu Functions
# =======================
show_main_menu() {
    clear
    echo "========================================"
    echo " Arch Linux Rescue Script - Main Menu"
    echo "========================================"
    echo "1. Connect to Wi-Fi (Optional)"
    echo "2. Mount System Partitions"
    echo "3. Enter Rescue Shell"
    echo "4. Full System Update & Repair"
    echo "5. Reinstall Kernel (Automatic)"
    echo "6. Install NVIDIA Drivers (Automatic)"
    echo "7. Regenerate Initramfs"
    echo "8. Repair Bootloader (Limine/GRUB)"
    echo "9. Check & Repair Filesystems"
    echo "10. Reset User Password"
    echo "11. View System Logs"
    echo "12. Open Root Shell"
    echo "13. Unmount and Reboot"
    echo "14. Exit"
    echo "----------------------------------------"
}

connect_wifi() {
    info "Launching iwctl (interactive Wi-Fi tool)..."
    echo "Steps inside iwctl:"
    echo "1. device list"
    echo "2. station <device> scan"
    echo "3. station <device> get-networks"
    echo "4. station <device> connect <SSID>"
    echo "5. exit"
    iwctl
    success "Returned from iwctl. Test with: ping archlinux.org"
}

# =======================
# Mount BTRFS + LUKS2
# =======================
mount_system() {
    info "Listing partitions..."
    lsblk -f
    read -p "Enter LUKS2 root partition (e.g., nvme0n1p2): " luks_partition
    luks_partition="/dev/$luks_partition"
    [ -b "$luks_partition" ] || { error "Partition not found"; return 1; }

    info "Opening LUKS container..."
    cryptsetup open "$luks_partition" cryptroot || { error "Failed"; return 1; }

    info "Mounting BTRFS subvolumes..."
    mkdir -p /mnt
    mount -o subvol=@ /dev/mapper/cryptroot /mnt || { error "Failed to mount root"; cryptsetup close cryptroot; return 1; }

    # Mount @home if exists
    if btrfs subvolume list /mnt | grep -q "@home"; then
        mkdir -p /mnt/home
        mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
        success "Mounted @home subvolume"
    fi

    # Mount EFI
    read -p "Enter EFI partition (e.g., nvme0n1p1): " efi_partition
    efi_partition="/dev/$efi_partition"
    [ -b "$efi_partition" ] || { error "EFI partition not found"; return 1; }
    mkdir -p /mnt/boot
    mount "$efi_partition" /mnt/boot || { error "Failed to mount EFI"; return 1; }
    success "System partitions mounted"

    # Bind system directories
    for dir in /dev /dev/pts /proc /sys /run; do
        mount --bind "$dir" "/mnt$dir"
    done
    success "System directories bound"
}

# =======================
# Run command as root helper
# =======================
run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Enter sudo password:"
        read -s SUDO_PW
        echo "$SUDO_PW" | sudo -S bash -c "$*"
        unset SUDO_PW
    else
        bash -c "$*"
    fi
}

# =======================
# Pacman keyring fix
# =======================
fix_pacman_keys() {
    info "Refreshing pacman keyring..."
    run_as_root "pacman-key --init"
    run_as_root "pacman-key --populate archlinux"
    run_as_root "pacman -Sy --noconfirm archlinux-keyring"
    success "Pacman keyring refreshed"
}

# =======================
# Enter Rescue Shell
# =======================
enter_rescue_shell() {
    if [ -z "$CHROOT_USER" ]; then
        read -p "Enter username to chroot as (root or installed user): " CHROOT_USER
        [ -z "$CHROOT_USER" ] && CHROOT_USER="root"
    fi

    # Create inner rescue script inside chroot /tmp (accessible to all users)
    inner_script="/mnt/tmp/inner_rescue.sh"
    mkdir -p /mnt/tmp
    cat << 'EOF' > "$inner_script"
#!/bin/bash
C_BLUE="\e[34m"; C_GREEN="\e[32m"; C_RED="\e[31m"; C_RESET="\e[0m"
info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }

# Run commands as root automatically
run_as_root() {
    bash -c "$1"
}

fix_pacman_keys() {
    info "Refreshing pacman keyring..."
    run_as_root "pacman-key --init"
    run_as_root "pacman-key --populate archlinux"
    run_as_root "pacman -Sy --noconfirm archlinux-keyring"
    success "Pacman keyring refreshed"
}

auto_install_kernel() {
    fix_pacman_keys
    run_as_root "pacman -Syu --noconfirm"
    KERNEL="linux"; HEADERS="linux-headers"
    if pacman -Q linux-zen &>/dev/null; then KERNEL="linux-zen"; HEADERS="linux-zen-headers"
    elif pacman -Q linux-lts &>/dev/null; then KERNEL="linux-lts"; HEADERS="linux-lts-headers"
    elif pacman -Q linux-hardened &>/dev/null; then KERNEL="linux-hardened"; HEADERS="linux-hardened-headers"; fi
    info "Installing kernel: $KERNEL and $HEADERS"
    run_as_root "pacman -S --needed --noconfirm $KERNEL $HEADERS"
    success "Kernel reinstalled"
}

auto_install_nvidia() {
    if lspci | grep -qi nvidia; then
        if lspci | grep -i 'nvidia' | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
            NVIDIA="nvidia-open-dkms"
        else NVIDIA="nvidia-dkms"; fi
        HEADERS="linux-headers"
        if pacman -Q linux-zen &>/dev/null; then HEADERS="linux-zen-headers"
        elif pacman -Q linux-lts &>/dev/null; then HEADERS="linux-lts-headers"
        elif pacman -Q linux-hardened &>/dev/null; then HEADERS="linux-hardened-headers"; fi
        fix_pacman_keys
        run_as_root "pacman -Syu --noconfirm"
        run_as_root "pacman -S --needed --noconfirm $HEADERS $NVIDIA nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver qt5-wayland qt6-wayland"
        run_as_root "echo 'options nvidia_drm modeset=1' > /etc/modprobe.d/nvidia.conf"
        run_as_root "cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup"
        run_as_root "sed -i -E 's/ nvidia_drm//g; s/ nvidia_uvm//g; s/ nvidia_modeset//g; s/ nvidia//g;' /etc/mkinitcpio.conf"
        run_as_root "sed -i -E 's/^(MODULES=\()/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf"
        run_as_root "mkinitcpio -P"
        success "NVIDIA drivers installed"
    else error "No NVIDIA GPU detected"; fi
}

show_inner_menu() {
    echo "========================================"
    echo " Rescue Menu (chroot user: $USER)"
    echo "========================================"
    echo "1. Reinstall Kernel"
    echo "2. Install NVIDIA Drivers"
    echo "3. Regenerate Initramfs"
    echo "4. Repair Bootloader (Limine/GRUB)"
    echo "5. Check & Repair Filesystems"
    echo "6. Reset User Password"
    echo "7. View System Logs"
    echo "8. Open Root Shell"
    echo "9. Exit"
}

while true; do
    show_inner_menu
    read -p "Choice [1-9]: " choice
    case "$choice" in
        1) auto_install_kernel ;;
        2) auto_install_nvidia ;;
        3) run_as_root "mkinitcpio -P"; success "Initramfs regenerated" ;;
        4) echo "Repair bootloader manually"; run_as_root "bash" ;;
        5) read -p "Device to check (e.g., /dev/mapper/cryptroot): " fsdev; run_as_root "fsck -f $fsdev" ;;
        6) read -p "Username to reset password: " ureset; run_as_root "passwd $ureset" ;;
        7) run_as_root "journalctl -xb" ;;
        8) run_as_root "/bin/bash" ;;
        9) exit 0 ;;
        *) error "Invalid choice" ;;
    esac
done
EOF

    chmod +x "$inner_script"

    # Run chroot inner menu as user
    if [ "$CHROOT_USER" == "root" ]; then
        arch-chroot /mnt /bin/bash "/tmp/inner_rescue.sh"
    else
        arch-chroot /mnt su - "$CHROOT_USER" -c "/tmp/inner_rescue.sh"
    fi

    # Cleanup
    rm -f "$inner_script"
    success "Returned from rescue shell"
}

# =======================
# Unmount & Reboot
# =======================
unmount_and_reboot() {
    info "Unmounting system dirs..."
    for dir in /dev/pts /dev /proc /sys /run; do
        umount -lf "/mnt$dir" 2>/dev/null || true
    done
    umount -R /mnt || true
    cryptsetup close cryptroot || true
    success "Cleanup complete. Rebooting..."
    sleep 3
    reboot
}

# =======================
# Main Loop
# =======================
while true; do
    show_main_menu
    read -p "Choice [1-14]: " choice
    case "$choice" in
        1) connect_wifi; press_enter_to_continue ;;
        2) mount_system; press_enter_to_continue ;;
        3) enter_rescue_shell; press_enter_to_continue ;;
        4) fix_pacman_keys; run_as_root "pacman -Syu --noconfirm"; press_enter_to_continue ;;
        5) enter_rescue_shell; press_enter_to_continue ;;
        6) enter_rescue_shell; press_enter_to_continue ;;
        7) enter_rescue_shell; press_enter_to_continue ;;
        8) enter_rescue_shell; press_enter_to_continue ;;
        9) enter_rescue_shell; press_enter_to_continue ;;
        10) enter_rescue_shell; press_enter_to_continue ;;
        11) enter_rescue_shell; press_enter_to_continue ;;
        12) enter_rescue_shell; press_enter_to_continue ;;
        13) read -p "Unmount and reboot? (y/n): " confirm; [[ "$confirm" =~ ^[Yy]$ ]] && unmount_and_reboot ;;
        14) info "Exiting."; exit 0 ;;
        *) error "Invalid choice"; press_enter_to_continue ;;
    esac
done
