#!/bin/bash
# ==============================================================================
# Arch Linux Interactive Rescue Script
# ==============================================================================
# Fully self-contained ISO-ready version
# ==============================================================================
C_BLUE="\e[34m"; C_GREEN="\e[32m"; C_RED="\e[31m"; C_RESET="\e[0m"

info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }
press_enter_to_continue() { read -p "Press Enter to continue..."; }

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

# =======================
# Wi-Fi
# =======================
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
# Mount System
# =======================
mount_system() {
    info "Listing all partitions..."
    lsblk -f
    echo
    read -p "Enter the LUKS partition name (e.g., sda2, nvme0n1p2): " luks_partition_name
    local luks_partition="/dev/${luks_partition_name}"

    if [ ! -b "$luks_partition" ]; then
        error "LUKS partition ${luks_partition} not found."
        return 1
    fi

    info "Opening LUKS container..."
    cryptsetup open "$luks_partition" cryptroot || { error "Failed"; return 1; }
    success "Opened /dev/mapper/cryptroot"

    info "Mounting BTRFS root subvolume..."
    mount -o subvol=@ /dev/mapper/cryptroot /mnt || { error "Failed"; cryptsetup close cryptroot; return 1; }
    success "Root mounted at /mnt"

    read -p "Enter EFI partition name (e.g., sda1): " efi_partition_name
    local efi_partition="/dev/${efi_partition_name}"
    [ -b "$efi_partition" ] || { error "EFI partition not found"; umount -R /mnt; cryptsetup close cryptroot; return 1; }

    mkdir -p /mnt/boot
    mount "$efi_partition" /mnt/boot || { error "Failed to mount EFI"; umount -R /mnt; cryptsetup close cryptroot; return 1; }
    success "EFI partition mounted"

    info "Binding system dirs into chroot..."
    for dir in /dev /dev/pts /proc /sys /run; do
        mount --bind "$dir" "/mnt$dir"
    done
    success "System dirs bound"
}

# =======================
# Run commands as root helper
# =======================
run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${C_BLUE}[ROOT]${C_RESET} Running: $*"
        echo "Enter sudo password:"
        read -s sudo_pw
        echo "$sudo_pw" | sudo -S bash -c "$*"
        unset sudo_pw
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
    [ -d /mnt ] || { error "System not mounted"; return 1; }

    echo "Who to chroot as?"
    echo "1. Root"
    echo "2. Installed User"
    read -p "Choice [1-2]: " user_choice
    if [ "$user_choice" == "1" ]; then
        chroot_user="root"
    else
        read -p "Enter username: " chroot_user
        [ -z "$chroot_user" ] && { error "Empty username"; return 1; }
    fi

    inner_script="/mnt/inner_rescue.sh"
    cat << 'EOF' > "$inner_script"
#!/bin/bash
C_BLUE="\e[34m"; C_GREEN="\e[32m"; C_RED="\e[31m"; C_RESET="\e[0m"
info() { echo -e "\n${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1\n"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }

run_as_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${C_BLUE}[ROOT]${C_RESET} Running: $*"
        echo "Enter sudo password:"
        read -s sudo_pw
        echo "$sudo_pw" | sudo -S bash -c "$*"
        unset sudo_pw
    else
        bash -c "$*"
    fi
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
        echo "options nvidia_drm modeset=1" | run_as_root "tee /etc/modprobe.d/nvidia.conf >/dev/null"
        run_as_root "cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup"
        run_as_root "sed -i -E 's/ nvidia_drm//g; s/ nvidia_uvm//g; s/ nvidia_modeset//g; s/ nvidia//g;' /etc/mkinitcpio.conf"
        run_as_root "sed -i -E 's/^(MODULES=\()/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf"
        run_as_root "mkinitcpio -P"
        if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
            cat >>"$HOME/.config/hypr/hyprland.conf" <<'HYPR'
# NVIDIA environment variables
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
HYPR
        fi
        success "NVIDIA drivers installed"
    else
        error "No NVIDIA GPU detected"
    fi
}

show_inner_menu() {
    echo "========================================"
    echo " Rescue Shell Menu (Running as: $USER)"
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
        2)
            if [ -x "/home/${chroot_user}/.local/share/omarchy/install/config/hardware/nvidia.sh" ]; then
                run_as_root "/home/${chroot_user}/.local/share/omarchy/install/config/hardware/nvidia.sh"
            else
                install_nvidia_fallback
            fi
            ;;
        3) run_as_root "mkinitcpio -P"; success "Initramfs regenerated";;
        4) run_as_root "/bin/bash";;
        5) exit 0;;
        *) error "Invalid choice";;
    esac
done
EOF

    chmod +x "$inner_script"

    info "Entering rescue shell as user '$chroot_user'..."
    if [ "$chroot_user" == "root" ]; then
        arch-chroot /mnt /usr/bin/script -q -c "/bin/bash $inner_script" /dev/null
    else
        arch-chroot /mnt /usr/bin/script -q -c "su - $chroot_user -c '/bin/bash $inner_script'" /dev/null
    fi

    rm -f "$inner_script"
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
    info "Unmounting main partitions..."
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
