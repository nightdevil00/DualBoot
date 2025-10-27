!!!!Disclaimer!!!!!

The scripts and code provided in this repository are for educational and personal use only. While every effort has been made to ensure correctness and safety, the author(s) make no guarantees regarding functionality, security, or suitability for any purpose.

Use of these scripts is at your own risk. The author(s) shall not be held liable for any damages, data loss, or other issues arising from running or modifying the code.

It is recommended to review and understand the scripts before use, especially on production systems or sensitive environments.

DUALBOOT-GRUB.SH - ONLY FOR DISKS WITH WINDOWS INSTALLED - FOR FULL ARCH BOOT USE ARCHINSTALL OR OTHER SCRIPT/TOOL etc.

Description:
A comprehensive Arch Linux installer designed for dual-booting with Windows. It safely detects existing Windows installations, protects related partitions, and allows users to manually or automatically configure EFI and root partitions.

Key Features:

Disk Selection: Lists all physical disks and lets the user choose the target disk.

Windows Detection: Scans all partitions to detect Windows boot files and EFI directories.

Partitioning Strategy:

Dual-boot: Protects Windows partitions; lets users define new EFI/root partitions in free space.

Clean install: Optionally wipes the disk and creates EFI (2GB) + root partitions.

Encryption: Root partition encrypted using LUKS2.

Filesystem & Mounting:

EFI formatted FAT32

Root partition formatted BTRFS with @ (root) and @home subvolumes

Prepares partitions for installation

System Installation: Installs base Arch, kernel, essential packages, GRUB, and generates fstab.

User Configuration: Prompts to create a user and set passwords.

System Configuration (Chroot): Sets timezone, locale, hostname, user accounts, crypttab, mkinitcpio hooks, GRUB, and NetworkManager.

Completion: GRUB menu includes Windows if detected.

Usage:

sudo bash dualboot-grub.sh


Intended For: Safe dual-boot Arch installation alongside Windows.

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
