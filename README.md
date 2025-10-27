!!!!Disclaimer!!!!!

The scripts and code provided in this repository are for educational and personal use only. While every effort has been made to ensure the correctness and safety of the code, the author(s) make no guarantees regarding its functionality, security, or suitability for any particular purpose. 

Use of these scripts is at your own risk. The author(s) shall not be held liable for any damages, data loss, or other issues that may arise from running or modifying the code. It is recommended to review and understand the scripts before use, especially if running on production systems or sensitive environments.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

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
