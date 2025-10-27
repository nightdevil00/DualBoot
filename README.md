!!!!Disclaimer!!!!!

The scripts and code provided in this repository are for educational and personal use only. While every effort has been made to ensure the correctness and safety of the code, the author(s) make no guarantees regarding its functionality, security, or suitability for any particular purpose. 

Use of these scripts is at your own risk. The author(s) shall not be held liable for any damages, data loss, or other issues that may arise from running or modifying the code. It is recommended to review and understand the scripts before use, especially if running on production systems or sensitive environments.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
DUALBOOT-GRUB.SH
This script is a comprehensive Arch Linux installer with a focus on dual-booting with Windows. Here's a breakdown of its functionality:

1.  ***Prerequisites:** The script must be run with root privileges.

2.  ***Disk Selection:** It begins by listing all available physical disks and prompts the user to choose the target disk for the Arch Linux installation.

3.  ***Windows Detection:**
    *   The script intelligently scans all partitions on all connected disks to detect an existing Windows installation.
    *   It identifies Windows by looking for specific files and directories, such as the EFI/Microsoft directory on FAT32 partitions (the EFI System Partition) and the "Windows" folder or "bootmgr" file on NTFS partitions.

4.  **Partitioning Strategy:** The script's behavior changes based on whether Windows is detected:

    *   **Dual-Boot (Windows Detected):**
        *   To prevent data loss, the script protects all detected Windows-related partitions. It will not modify them.
        *   It displays the existing partition table of the selected disk, including free space.
        *   The user is then asked to manually define the start and end points (in GB) for the new EFI and root partitions within the available free space. This allows for a safe, side-by-side installation.

    *   **Clean Install (No Windows Detected):**
        *   The script asks for explicit confirmation to wipe the entire selected disk.
        *   If the user agrees, it creates a new GPT partition table.
        *   It automatically creates two partitions: a 2GB EFI partition and a root partition that uses the remaining disk space.

5.  **Encryption:** The root partition is encrypted using LUKS2 for security. The user will be prompted to set an encryption passphrase.

6.  **Filesystem and Mounting:**
    *   The EFI partition is formatted with the FAT32 filesystem.
    *   The encrypted root partition is formatted with the Btrfs filesystem.
    *   The script then creates two Btrfs subvolumes: `@` for the root filesystem (`/`) and `@home` for the user's home directory (`/home`).
    *   Finally, it mounts all the necessary partitions and subvolumes to prepare for the Arch Linux installation.

7.  **System Installation:**
    *   It uses `pacstrap` to install the base Arch Linux system, the Linux kernel, and a set of essential packages, including `grub`, `efibootmgr` (for UEFI booting), `btrfs-progs` (for Btrfs support), and `os-prober` (to detect other operating systems like Windows for the GRUB boot menu).
    *   It generates an `fstab` file to define how partitions should be mounted at boot.

8.  **User Configuration:** The script prompts the user to create a new user account and set passwords for both the new user and the root user.

9.  **System Configuration (inside chroot):** The script automates the initial system setup by:
    *   Setting the timezone and system locale.
    *   Configuring the hostname.
    *   Setting up user accounts and passwords.
    *   Configuring `/etc/crypttab` to automatically unlock the encrypted root partition during boot.
    *   Updating the `mkinitcpio` configuration to include the necessary hooks for an encrypted root filesystem.
    *   Configuring the GRUB bootloader to handle the encrypted root partition.
    *   Installing GRUB to the EFI partition, making the system bootable.
    *   Enabling the NetworkManager service for network connectivity.

10. **Completion:** After all steps are completed, the script provides a final message. If Windows was detected, `os-prober` should have added it to the GRUB boot menu, allowing the user to choose between Arch Linux and Windows at startup.

    Omarchy-Doctor.sh
    Arch Linux Interactive Rescue Script

Description:
This is an interactive rescue and recovery script for Arch Linux, designed for use in live environments (ISO) to troubleshoot, repair, or recover an installed Arch Linux system. It is particularly useful for systems with BTRFS + LUKS2 encryption, and supports GRUB or Limine bootloaders. The script is designed to be user-friendly, offering a menu-driven interface to perform common recovery tasks, even for users who may not be deeply familiar with the command line.

Key Features:

Connect to Wi-Fi via iwctl for internet access in live environments.

Mount encrypted LUKS2 partitions with BTRFS subvolumes (@ and @home) and EFI partitions.

Enter a rescue shell inside the installed system with a menu to perform:

Kernel reinstallation (including LTS, Zen, Hardened kernels)

NVIDIA driver installation (supports DKMS and fallback drivers)

Regeneration of initramfs

Bootloader repair (GRUB or Limine)

Filesystem checks and repairs

User password reset

Viewing system logs

Root shell access for advanced troubleshooting

Automatic handling of root permissions for commands requiring elevated access.

Works for both root and installed (non-root) users inside chroot.

Cleans up temporary scripts after execution to avoid leaving traces.

Menu-driven interface to reduce command-line complexity during recovery.

Disclaimer:
This script is provided as-is for educational and personal use only. The author is not responsible for any damage, data loss, or system issues resulting from its use. Use at your own risk. Always review and understand the script before running it, especially on production or sensitive systems.

Intended Use Cases:

Recovering Arch Linux systems that fail to boot.

Fixing broken kernels, NVIDIA drivers, or initramfs issues.

Repairing bootloaders after system corruption.

Running filesystem checks or recovering user passwords.

Performing safe updates and repairs from a live environment.

Requirements:

Arch Linux live environment or compatible ISO.

Root privileges on the live system to mount partitions and enter chroot.

Basic familiarity with Linux partitioning, filesystems, and chroot environments.

Usage:

Boot into an Arch Linux live environment.

Copy the script to the live environment.

Run the script:

sudo bash arch-rescue.sh


Follow the interactive menu to perform the desired recovery tasks.

diskpartitioner.sh

Arch Linux Pre-Installation Disk Manager

Description:
This script is a pre-installation disk management tool for Arch Linux designed to simplify partitioning, Windows detection, and free space handling before running archinstall. It is interactive and menu-driven, making it easier to prepare disks for a new Arch Linux installation while avoiding accidental data loss on existing OS partitions.

Key Features:

Lists all physical disks on the system with size, model, transport type, and mount points.

Interactive disk selection to choose the target disk for installation.

Windows detection: Scans all partitions for Windows boot files and EFI directories to prevent accidental deletion of Windows or EFI partitions.

Free space analysis: Shows available free space blocks on the target disk for safe partition creation.

Partition creation:

EFI system partition (user-defined size, FAT32 formatted)

Root partition (BTRFS, with optional subvolumes @ and @home)

Automatic LUKS2 encryption of the root partition for security

Partition deletion: Allows safely deleting partitions after checking if they are mounted.

Automatically mounts and prepares partitions for archinstall with the command:

archinstall guided --root /mnt


Handles encryption, BTRFS subvolume creation, and mounting automatically.

Disclaimer:
This script is provided as-is for educational and personal use only. The author is not responsible for any data loss, system damage, or other issues that may result from its use. Use at your own risk. Always review and understand the script before running it, especially on systems with important data.

Intended Use Cases:

Preparing a disk for a fresh Arch Linux installation.

Safely partitioning disks alongside Windows installations.

Creating encrypted BTRFS root and home subvolumes automatically.

Reviewing free space and avoiding overwriting important partitions.

Requirements:

Run as root or with sudo.

Arch Linux live environment or compatible Linux with lsblk, parted, blkid, btrfs-progs, and cryptsetup.

Basic understanding of partitions, filesystems, and disk encryption.

Usage:

Boot into a Linux live environment.

Copy the script and run it with root privileges:

sudo bash arch-disk-manager.sh


Follow the interactive prompts to select disks, detect Windows partitions, create EFI/root partitions, and prepare the system for Arch installation.

archrescue.sh

Arch Linux Interactive Rescue Script (ISO-Ready)

Description:
This is a menu-driven rescue and recovery script for Arch Linux, designed to run from a live ISO environment. It is intended for troubleshooting, repairing, or recovering Arch Linux systems with BTRFS + LUKS2 encryption and supports GRUB or Limine bootloaders. The script simplifies common recovery tasks, including kernel reinstallation, NVIDIA driver fixes, and initramfs regeneration, even for users who are not deeply familiar with chroot environments.

Key Features:

Wi-Fi connection via iwctl for internet access in live environments.

Mount encrypted root partitions (LUKS2) and BTRFS subvolumes (@ and @home).

Mount EFI partitions and bind essential system directories for chroot.

Enter a rescue shell inside the installed system with an inner script that provides:

Kernel reinstallation (including updates)

NVIDIA driver installation with automatic fallback

Initramfs regeneration

Root shell access for advanced troubleshooting

Works for both root and installed (non-root) users inside chroot.

Cleans up temporary scripts after execution to avoid leaving traces.

Simple menu-driven interface for safe and guided recovery.

Disclaimer:
This script is provided as-is for educational and personal use only. The author is not responsible for any damage, data loss, or system issues resulting from its use. Use at your own risk. Always review and understand the script before running it, especially on production or sensitive systems.

Intended Use Cases:

Recovering Arch Linux systems that fail to boot.

Fixing broken kernels, NVIDIA drivers, or initramfs issues.

Repairing bootloaders after system corruption.

Safely entering a chroot environment for system repair.

Requirements:

Arch Linux live environment or compatible ISO.

Root privileges on the live system to mount partitions and enter chroot.

Basic understanding of Linux partitions, filesystems, and chroot operations.

Usage:

Boot into an Arch Linux live environment.

Copy the script to the live system.

Run the script as root:

sudo bash arch-rescue.sh


Follow the interactive menu to perform system recovery tasks.
