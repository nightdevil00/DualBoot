#!/bin/bash

# ==============================================================================
#
# Arch Linux Interactive Rescue Script
#
# This script is designed to be run from an Arch Linux live environment (e.g.,
# a bootable USB) to repair a broken installation. It provides a step-by-step
# interactive menu to mount the system, chroot as a specific user, and then
# perform repair operations.
# Made for Omarchy
#
# ==============================================================================

# --- Utility Functions ---
C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_RED="\e[31m"
C_RESET="\e[0m"

info() { echo -e "${C_BLUE}INFO:${C_RESET} $1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} $1" >&2; }
press_enter_to_continue() { read -p "Press Enter to continue..."; }

# --- Main Script Functions ---

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
    info "This will launch the interactive iwctl tool."
    echo "  Follow these steps inside iwctl:"
    echo "  1. Run: device list"
    echo "  2. Run: station <device_name> scan"
    echo "  3. Run: station <device_name> get-networks"
    echo "  4. Run: station <device_name> connect <SSID>"
    echo "  5. When connected, type 'exit' to return."
    echo
    iwctl
    success "Returned from iwctl. Check connection with 'ping archlinux.org'."
}

mount_system() {
    info "Listing all partitions with their filesystems and UUIDs..."
    lsblk -f
    echo
    read -p "Enter the LUKS partition name (e.g., sda2, nvme0n1p2): " luks_partition_name
    local luks_partition="/dev/${luks_partition_name}"
    if [ ! -b "${luks_partition}" ]; then
        error "LUKS partition ${luks_partition} not found."
        return 1
    fi

    info "Opening LUKS container at ${luks_partition}..."
    cryptsetup open "${luks_partition}" cryptroot
    if [ $? -ne 0 ]; then
        error "Failed to open LUKS container."
        return 1
    fi
    success "LUKS container opened."

    info "Mounting BTRFS root subvolume to /mnt..."
    mount -o subvol=@ /dev/mapper/cryptroot /mnt
    if [ $? -ne 0 ]; then
        error "Failed to mount BTRFS root subvolume."
        cryptsetup close cryptroot || true
        return 1
    fi
    success "BTRFS root subvolume mounted under /mnt."

    echo
    read -p "Enter the EFI partition name (e.g., sda1, nvme0n1p1): " efi_partition_name
    local efi_partition="/dev/${efi_partition_name}"
    if [ ! -b "${efi_partition}" ]; then
        error "EFI partition ${efi_partition} not found."
        umount -R /mnt || true
        cryptsetup close cryptroot || true
        return 1
    fi

    info "Mounting EFI partition ${efi_partition} to /mnt/boot..."
    mkdir -p /mnt/boot
    mount "${efi_partition}" /mnt/boot
    if [ $? -ne 0 ]; then
        error "Failed to mount EFI partition."
        umount -R /mnt || true
        cryptsetup close cryptroot || true
        return 1
    fi
    success "EFI partition mounted to /mnt/boot."
}

enter_rescue_shell() {
    if ! mountpoint -q /mnt; then
        error "System partitions are not mounted. Please run option 2 first."
        return 1
    fi

    read -p "Enter the username to chroot as (e.g., your regular user): " chroot_username
    if [ -z "${chroot_username}" ]; then
        error "Username cannot be empty."
        return 1
    fi

    info "Creating inner rescue menu script..."
    local inner_script="/mnt/inner_rescue.sh"
    cat << EOF > "${inner_script}"
#!/bin/bash

C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_RED="\e[31m"
C_RESET="\e[0m"

info() { echo -e "\n${C_BLUE}INFO:${C_RESET} \$1"; }
success() { echo -e "${C_GREEN}SUCCESS:${C_RESET} \$1\n"; }
error() { echo -e "${C_RED}ERROR:${C_RESET} \$1" >&2; }

# Check for internet connectivity
info "Checking internet connectivity..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    error "No internet connectivity detected. Some operations may fail."
    sleep 3
else
    success "Internet connectivity confirmed."
fi

show_inner_menu() {
    echo "========================================"
    echo " Rescue Shell Menu (Running as: \$USER)"
    echo "========================================"
    echo " You will be prompted for your password for commands requiring sudo."
    echo "----------------------------------------"
    echo "1. Reinstall Kernel (linux, linux-headers)"
    echo "2. Find and install NVIDIA drivers"
    echo "3. Regenerate Initramfs (mkinitcpio)"
    echo "4. Exit Rescue Shell"
    echo "----------------------------------------"
}

while true; do
    show_inner_menu
    read -p "Enter your choice [1-4]: " choice
    case \$choice in
        1)
            info "Reinstalling kernel and headers..."
            sudo pacman -Syu linux linux-headers
            success "Kernel reinstallation complete."
            ;;
        2)
            info "Installing NVIDIA drivers using nvidia.sh script..."
            sudo /home/${chroot_username}/.local/share/omarchy/install/config/hardware/nvidia.sh
            success "NVIDIA driver installation complete."
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

    info "Entering rescue shell as user '${chroot_username}'. You will see a new menu."
    sleep 2
    arch-chroot /mnt -u "${chroot_username}" /bin/bash "/inner_rescue.sh"

    rm "${inner_script}"
    success "Returned from rescue shell."
}

unmount_and_reboot() {
    info "Unmounting all partitions and closing LUKS container..."
    umount -R /mnt || true
    cryptsetup close cryptroot || true
    success "Cleanup complete. Rebooting in 3 seconds..."
    sleep 3
    reboot
}

# --- Main Loop ---
while true; do
    show_main_menu
    read -p "Enter your choice [1-5]: " choice
    case $choice in
        1) connect_wifi; press_enter_to_continue ;;
        2) mount_system; press_enter_to_continue ;;
        3) enter_rescue_shell; press_enter_to_continue ;;
        4)
            read -p "Are you sure you want to unmount and reboot? (y/n): " confirm
            if [[ "\$confirm" == "y" || "\$confirm" == "Y" ]]; then
                unmount_and_reboot
            else
                info "Reboot cancelled."
                press_enter_to_continue
            fi
            ;;
        5) info "Exiting script."; exit 0 ;;
        *) error "Invalid choice."; press_enter_to_continue ;;
    esac
done
