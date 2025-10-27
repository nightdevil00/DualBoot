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

# =======================
# Global variable
# =======================
CHROOT_USER=""

# =======================
# Main Menu
# =======================
show_main_menu() {
    clear
    echo "========================================"
    echo " Arch Linux Rescue Script - Main Menu"
    echo "========================================"
    echo "1. Connect to Wi-Fi (Optional)"
    echo "2. Mount System Partitions"
    echo "3. Enter Rescue Shell (Chroot)"
    echo "4. Unmount and Reboot"
    echo "5. Exit"
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
# Mount System (BTRFS + LUKS2)
# =======================
mount_system() {
    info "Listing partitions..."
    lsblk -f
    read -p "Enter the LUKS partition name (e.g., sda2, nvme0n1p2): " luks_partition_name
    luks_partition="/dev/$luks_partition_name"
    [ -b "$luks_partition" ] || { error "Partition not found"; return 1; }

    info "Opening LUKS container..."
    cryptsetup open "$luks_partition" cryptroot || { error "Failed"; return 1; }
    success "Opened /dev/mapper/cryptroot"

    info "Mounting BTRFS root subvolume..."
    mkdir -p /mnt
    mount -o subvol=@ /dev/mapper/cryptroot /mnt || { error "Failed root mount"; cryptsetup close cryptroot; return 1; }

    # Mount @home if exists
    if btrfs subvolume list /mnt | grep -q "@home"; then
        mkdir -p /mnt/home
        mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
        success "Mounted @home subvolume"
    fi

    # Mount EFI
    read -p "Enter EFI partition name (e.g., sda1): " efi_partition_name
    efi_partition="/dev/$efi_partition_name"
    [ -b "$efi_partition" ] || { error "EFI partition not found"; return 1; }
    mkdir -p /mnt/boot
    mount "$efi_partition" /mnt/boot || { error "EFI mount failed"; return 1; }
    success "EFI partition mounted"

    # Bind system directories
    for dir in /dev /dev/pts /proc /sys /run; do
        mount --bind "$dir" "/mnt$dir"
    done
    success "System dirs bound"
}

# =======================
# Run commands as root
# =======================
run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "$1" | sudo -S bash -c "$2"
    else
        bash -c "$2"
    fi
}

# =======================
# Enter Rescue Shell
# =======================
enter_rescue_shell() {
    [ -d /mnt ] || { error "System not mounted"; return 1; }

    # Ask user once
    if [ -z "$CHROOT_USER" ]; then
        echo "Who to chroot as?"
        echo "1. Root"
        echo "2. Installed User"
        read -p "Choice [1-2]: " user_choice
        if [ "$user_choice" == "1" ]; then
            CHROOT_USER="root"
        else
            read -p "Enter username: " CHROOT_USER
            [ -z "$CHROOT_USER" ] && { error "Empty username"; return 1; }
        fi
    fi
    export CHROOT_USER

    # Create inner script inside chroot /tmp (accessible to all users)
    inner_script="/mnt/tmp/inner_rescue.sh"
    mkdir -p /mnt/tmp
    cat << 'EOF' > "$inner_script"
#!/bin/bash
C_BLUE="\e[34m"; C_GREEN="\e[32m"; C_RED="\e[31m"; C_RESET="\e[0m"
info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }

CHROOT_USER="${CHROOT_USER}"

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

install_nvidia_fallback() {
    info "Running built-in NVIDIA installer..."
    if lspci | grep -qi nvidia; then
        if lspci | grep -i 'nvidia' | grep -q -E "RTX [2-9][0-9]|GTX 16"; then
            NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
        else
            NVIDIA_DRIVER_PACKAGE="nvidia-dkms"
        fi
        KERNEL_HEADERS="linux-headers"
        if pacman -Q linux-zen &>/dev/null; then KERNEL_HEADERS="linux-zen-headers"
        elif pacman -Q linux-lts &>/dev/null; then KERNEL_HEADERS="linux-lts-headers"
        elif pacman -Q linux-hardened &>/dev/null; then KERNEL_HEADERS="linux-hardened-headers"
        fi
        fix_pacman_keys
        run_as_root "pacman -Syu --noconfirm"
        run_as_root "pacman -S --needed --noconfirm ${KERNEL_HEADERS} ${NVIDIA_DRIVER_PACKAGE} nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver qt5-wayland qt6-wayland"
        run_as_root "echo 'options nvidia_drm modeset=1' > /etc/modprobe.d/nvidia.conf"
        run_as_root "cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup"
        run_as_root "sed -i -E 's/ nvidia_drm//g; s/ nvidia_uvm//g; s/ nvidia_modeset//g; s/ nvidia//g;' /etc/mkinitcpio.conf"
        run_as_root "sed -i -E 's/^(MODULES=\()/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf"
        run_as_root "mkinitcpio -P"
        success "NVIDIA drivers installed"
    else
        error "No NVIDIA GPU detected"
    fi
}

show_inner_menu() {
    echo "========================================"
    echo " Rescue Shell Menu (Running as: $CHROOT_USER)"
    echo "========================================"
    echo "1. Reinstall Kernel"
    echo "2. Install NVIDIA Drivers"
    echo "3. Regenerate Initramfs"
    echo "4. Open Root Shell"
    echo "5. Exit"
}

while true; do
    show_inner_menu
    read -p "Choice [1-5]: " choice
    case "$choice" in
        1) fix_pacman_keys; run_as_root "pacman -Syu linux linux-headers --noconfirm"; success "Kernel reinstalled";;
        2) install_nvidia_fallback ;;
        3) run_as_root "mkinitcpio -P"; success "Initramfs regenerated";;
        4) run_as_root "/bin/bash";;
        5) exit 0;;
        *) error "Invalid choice";;
    esac
done
EOF

    chmod +x "$inner_script"

    info "Entering rescue shell as $CHROOT_USER..."
    if [ "$CHROOT_USER" == "root" ]; then
        arch-chroot /mnt /bin/bash "/tmp/inner_rescue.sh"
    else
        arch-chroot /mnt su - "$CHROOT_USER" -c "/tmp/inner_rescue.sh"
    fi

    rm -f /mnt/tmp/inner_rescue.sh
    success "Returned from rescue shell"
}

# =======================
# Unmount and Reboot
# =======================
unmount_and_reboot() {
    info "Unmounting system dirs..."
    for dir in /dev/pts /dev /proc /sys /run; do
        umount -lf "/mnt$dir" 2>/dev/null || true
    done
    umount -R /mnt || true
    cryptsetup close cryptroot || true
    success "Cleanup done. Rebooting..."
    sleep 3
    reboot
}

# =======================
# Main Loop
# =======================
while true; do
    show_main_menu
    read -p "Choice [1-5]: " choice
    case $choice in
        1) connect_wifi; press_enter_to_continue ;;
        2) mount_system; press_enter_to_continue ;;
        3) enter_rescue_shell; press_enter_to_continue ;;
        4) read -p "Unmount and reboot? (y/n): " confirm; [[ "$confirm" =~ ^[Yy]$ ]] && unmount_and_reboot ;;
        5) info "Exiting."; exit 0 ;;
        *) error "Invalid choice"; press_enter_to_continue ;;
    esac
done
