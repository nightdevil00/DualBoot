!!!!Disclaimer!!!!!

The scripts and code provided in this repository are for educational and personal use only. While every effort has been made to ensure correctness and safety, the author(s) make no guarantees regarding functionality, security, or suitability for any purpose.

Use of these scripts is at your own risk. The author(s) shall not be held liable for any damages, data loss, or other issues arising from running or modifying the code.

It is recommended to review and understand the scripts before use, especially on production systems or sensitive environments.

 This script is a comprehensive, automated installer for Arch Linux, designed for a dual-boot setup with Windows. It
  focuses on creating a secure, modern, and robust Arch Linux installation with the following key features:

   * Windows-Safe Dualboot: It detects an existing Windows EFI partition and creates a separate EFI partition for Arch
     Linux. This prevents the Arch Linux bootloader from interfering with the Windows bootloader, making the dual-boot
     setup safer and more reliable.

   * Limine Bootloader: It uses the Limine bootloader, a modern and simple alternative to GRUB.

   * Full-Disk Encryption: The Arch Linux root filesystem is encrypted using LUKS2, providing strong security for your
     data.

   * Btrfs Filesystem: It utilizes the Btrfs filesystem, which enables advanced features like compression and snapshots.

   * System Snapshots with Snapper: It installs and configures Snapper to automatically create and manage Btrfs
     snapshots. This allows you to easily roll back your system to a previous state in case of a problem.

   * Plymouth Boot Splash: It sets up Plymouth to provide a graphical boot splash screen, hiding the kernel messages
     during startup.

  How it Works:

  The script is divided into several functions that execute in a specific order:

   1. Disk Selection (`select_disk`): The script begins by listing all available disks and prompting you to choose the
      target disk for the Arch Linux installation.

   2. Partitioning (`partition_disk`):
       * If a Windows EFI partition is detected, it remains untouched. You are then asked to define the size and
         location for a new EFI partition for Arch and a new root partition.
       * If no Windows installation is found, the script offers to wipe the selected disk and create a new GPT partition
          table with an EFI partition and a root partition for Arch.

   3. Encryption and Btrfs Setup (`setup_encryption_btrfs`):
       * You are prompted to set a passphrase to encrypt the root partition.
       * The script then formats the root partition with LUKS encryption and creates a Btrfs filesystem on top of it.
       * It creates several Btrfs subvolumes (@, @home, @snapshots, @log, @swap) for better organization and to allow
         for independent snapshotting of different parts of the system.
       * Finally, it formats the new Arch EFI partition and mounts all the filesystems correctly.

   4. Base System Installation (`install_base_system`):
       * The script uses pacstrap to install the base Arch Linux system and a curated list of essential packages,
         including the kernel, bootloader (Limine), and tools for managing the encrypted Btrfs filesystem.
       * It generates the fstab and crypttab files, which are necessary for the system to mount the filesystems and
         unlock the encrypted partition at boot.

   5. System Configuration (`configure_system`):
       * This is the final and most complex step. The script creates a configuration script and runs it inside the new
         Arch Linux installation using arch-chroot. This script performs the following actions:
           * Sets the timezone, locale, and hostname.
           * Prompts you to set the root password and create a new user account.
           * Configures the initramfs (the initial boot environment) to include the necessary modules for Btrfs and
             encryption.
           * Sets up a zram device for compressed swap in RAM.
           * Configures the Plymouth boot splash.
           * Installs the Limine bootloader to the new Arch EFI partition.
           * Creates a UEFI boot entry for "Arch Linux Limine Bootloader" so you can select it from your computer's boot
              menu.
           * Generates the limine.conf file, which tells Limine how to boot Arch Linux, including how to unlock the
             encrypted root partition.
           * Enables essential system services like NetworkManager, Bluetooth, and a firewall.

  In essence, this script automates what would otherwise be a long and complex manual installation process, resulting
  in a well-configured and feature-rich Arch Linux system that can safely coexist with a Windows installation.

  
Omarchy-Doctor.sh

Description:
Interactive Arch Linux rescue and recovery script for live environments (ISO). Ideal for BTRFS + LUKS2 systems with GRUB or Limine bootloaders. Provides a menu-driven interface for users to safely repair their system without needing advanced CLI knowledge.

Key Features:

Connect to Wi-Fi via iwctl

Mount encrypted LUKS2 partitions with BTRFS subvolumes (@ and @home)

Enter a rescue shell inside the installed system with:

Kernel reinstallation (LTS, Zen, Hardened)

NVIDIA driver installation (DKMS and fallback drivers)

Initramfs regeneration

Bootloader repair (GRUB or Limine)

Filesystem checks and repairs

User password reset

Viewing system logs

Root shell access

Automatic root permission handling

Works for root or installed users inside chroot

Cleans temporary scripts after execution

Usage:

sudo bash omarchy-doctor.sh


Intended For:
Recovering broken Arch systems, fixing drivers, kernels, or boot issues.

diskpartitioner.sh

Description:
Pre-installation disk management tool for Arch Linux. Simplifies partitioning, Windows detection, and free space handling before running archinstall.

Key Features:

Lists physical disks with size, model, transport type, and mount points

Interactive disk selection

Windows detection: Prevents accidental deletion of Windows or EFI partitions

Free space analysis and selection

Partition creation:

EFI (user-defined, FAT32)

Root (BTRFS with optional @ and @home subvolumes)

Optional LUKS2 encryption for root

Partition deletion with mount safety checks

Prepares partitions for archinstall guided --root /mnt

Usage:

sudo bash diskpartitioner.sh


Intended For: Safe disk preparation before Arch installation, especially alongside Windows.

archrescue.sh

Description:
Menu-driven Arch Linux rescue script for live ISO environments. Designed for BTRFS + LUKS2 systems and GRUB/Limine bootloaders. Simplifies recovery tasks like kernel reinstalls, NVIDIA driver fixes, and initramfs regeneration.

Key Features:

Wi-Fi connection via iwctl

Mount encrypted root partitions (LUKS2) with BTRFS subvolumes (@ and @home)

Mount EFI partitions and bind system directories for chroot

Rescue shell inside installed system with:

Kernel reinstallation

NVIDIA driver installation (automatic fallback)

Initramfs regeneration

Root shell access

Supports root and non-root users

Temporary scripts cleaned after execution

Simple, safe menu-driven interface

Usage:

sudo bash archrescue.sh


Intended For:
Recovery of Arch systems that fail to boot, driver/kernel issues, or chroot repairs.
