#!/bin/bash
# ==============================================================================
# Arch Linux Interactive Rescue Script
# Designed for Omarchy
# ==============================================================================
# Run this from a live Arch environment (USB stick or ISO)
# ==============================================================================

# --- Color and utility functions ---
C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_RED="\e[31m"
C_RESET="\e[0m"

info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }
press_enter_to_continue() { read -p "Press Enter to continue..."; }

# --- Menu display ---
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

# --- Wi-Fi connection helper ---
connect_wifi() {
    info "Launching iwctl (interactive Wi-Fi tool)..."
    echo "Steps inside iwctl:"
    echo "  1. device list"
    echo "  2. station <device> scan"
    echo "  3. station <device> get-networks"
    echo "  4. station <device> connect <SSID>"
    echo "  5. exit"
    echo
    iwctl
    success "Returned from iwctl. You can test connectivity with: ping archlinux.org"
}

# --- Mount system partitions ---
mount_system() {
    info "Listing all partitions..."
    lsblk -f
    echo
    read -p "Enter the LUKS partition name (e.g., sda2, nvme0n1p2): " luks_partition_name
    local luks_partition="/dev/${luks_partition_name}"

    if [ ! -b "${luks_partition}" ]; then
        error "LUKS partition ${luks_partition} not found."
        return 1
    fi

    info "Opening LUKS container at ${luks_partition}..."
    cryptsetup open "${luks_partition}" cryptroot || {
        error "Failed to open LUKS container."
        return 1
    }
    success "LUKS container opened as /dev/mapper/cryptroot."

    info "Mounting BTRFS root subvolume..."
    mount -o subvol=@ /dev/mapper/cryptroot /mnt || {
        error "Failed to mount root subvolume."
        cryptsetup close cryptroot || true
        return 1
    }
    success "Root mounted at /mnt."

    echo
    read -p "Enter the EFI partition name (e.g., sda1, nvme0n1p1): " efi_partition_name
    local efi_partition="/dev/${efi_partition_name}"

    if [ ! -b "${efi_partition}" ]; then
        error "EFI partition ${efi_partition} not found."
        umount -R /mnt || true
        cryptsetup close cryptroot || true
        return 1
    fi

    mkdir -p /mnt/boot
    mount "${efi_partition}" /mnt/boot || {
        error "Failed to mount EFI partition."
        umount -R /mnt || true
        cryptsetup close cryptroot || true
        return 1
    }

    success "EFI partition mounted to /mnt/boot."
}

# --- Enter chroot rescue shell ---
enter_rescue_shell() {
    if ! mountpoint -q /mnt; then
        error "System partitions are not mounted. Please run option 2 first."
        return 1
    fi

    echo
    echo "Who do you want to enter the rescue shell as?"
    echo "1. Root (superuser)"
    echo "2. Normal install user"
    read -p "Enter your choice [1-2]: " user_choice

    if [ "$user_choice" == "1" ]; then
        chroot_user="root"
    else
        read -p "Enter the username of your installed system user: " chroot_user
        if [ -z "${chroot_user}" ]; then
            error "Username cannot be empty."
            return 1
        fi
    fi

    info "Creating inner rescue menu script..."
    local inner_script="/mnt/inner_rescue.sh"
    cat << EOF > "${inner_script}"
#!/bin/bash

C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_RED="\e[31m"
C_RESET="\e[0m"

info() { echo -e "\\n\${C_BLUE}INFO:\${C_RESET} \$1"; }
success() { echo -e "\${C_GREEN}SUCCESS:\${C_RESET} \$1\\n"; }
error() { echo -e "\${C_RED}ERROR:\${C_RESET} \$1" >&2; }

# Check internet connectivity
info "Checking internet connectivity..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    error "No internet connectivity detected. Some operations may fail."
else
    success "Internet connectivity confirmed."
fi

show_inner_menu() {
    echo "========================================"
    echo " Rescue Shell Menu (Running as: \$USER)"
    echo "========================================"
    echo " 1. Reinstall Kernel (linux, linux-headers)"
    echo " 2. Find and install NVIDIA drivers"
    echo " 3. Regenerate Initramfs (mkinitcpio)"
    echo " 4. Exit Rescue Shell"
    echo "----------------------------------------"
}

while true; do
    show_inner_menu
    read -p "Enter your choice [1-4]: " choice
    case \$choice in
        1)
            info "Reinstalling kernel..."
            sudo pacman -Syu linux linux-headers --noconfirm
            success "Kernel reinstallation complete."
            ;;
        2)
            info "Installing NVIDIA drivers..."
            if [ -x "/home/${chroot_user}/.local/share/omarchy/install/config/hardware/nvidia.sh" ]; then
                sudo /home/${chroot_user}/.local/share/omarchy/install/config/hardware/nvidia.sh
                success "NVIDIA driver installation complete."
            else
                error "NVIDIA installer script not found."
            fi
            ;;
        3)
            info "Regenerating initramfs..."
            sudo mkinitcpio -P
            success "Initramfs regeneration complete."
            ;;
        4)
            info "Exiting rescue shell."
            exit 0
            ;;
        *)
            error "Invalid choice."
            ;;
    esac
done
EOF

    chmod +x "${inner_script}"

    info "Entering rescue shell as user '${chroot_user}'..."
    sleep 2

    if [ "${chroot_user}" == "root" ]; then
        # Root mode
        arch-chroot /mnt /bin/bash /inner_rescue.sh
    else
        # User mode
        arch-chroot /mnt /usr/bin/script -q -c "su - ${chroot_user} -c '/bin/bash /inner_rescue.sh'" /dev/null
    fi

    rm -f "${inner_script}"
    success "Returned from rescue shell."
}

# --- Unmount and reboot ---
unmount_and_reboot() {
    info "Unmounting all partitions and closing LUKS container..."
    umount -R /mnt || true
    cryptsetup close cryptroot || true
    success "Cleanup complete. Rebooting in 3 seconds..."
    sleep 3
    reboot
}

# --- Main menu loop ---
while true; do
    show_main_menu
    read -p "Enter your choice [1-5]: " choice
    case $choice in
        1) connect_wifi; press_enter_to_continue ;;
        2) mount_system; press_enter_to_continue ;;
        3) enter_rescue_shell; press_enter_to_continue ;;
        4)
            read -p "Are you sure you want to unmount and reboot? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                unmount_and_reboot
            else
                info "Reboot cancelled."
                press_enter_to_continue
            fi
            ;;
        5)
            info "Exiting script."
            exit 0
            ;;
        *)
            error "Invalid choice."
            press_enter_to_continue
            ;;
    esac
done

