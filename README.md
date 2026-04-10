!!!!Disclaimer!!!!!

The scripts and code provided in this repository are for educational and personal use only. While every effort has been made to ensure correctness and safety, the author(s) make no guarantees regarding functionality, security, or suitability for any purpose.

Use of these scripts is at your own risk. The author(s) shall not be held liable for any damages, data loss, or other issues arising from running or modifying the code.

It is recommended to review and understand the scripts before use, especially on production systems or sensitive environments.

 

# Dual Boot Windows & Arch Linux with Omarchy Guide

This guide walks you through installing Arch Linux alongside Windows 11/10 using the automated DUALBOOT-Windows_Arch_Limine.sh script.

---

## Part 1: Prepare Windows

### 1.1 Shrink Windows Partition to Create Free Space

1. Press **Win + X** → **Disk Management**
2. Right-click your Windows partition (usually `C:`) → **Shrink Volume**
3. Enter the amount to shrink (recommended: **80-100 GB** for Arch Linux)
4. Click **Shrink** → You'll see "Unallocated" space

### 1.2 Disable Fast Startup

1. Press **Win + R** → `control`
2. Go to **Power Options** → **Choose what the power buttons do**
3. Click **Change settings that are currently unavailable**
4. Uncheck **Turn on fast startup**
5. Click **Save changes**

### 1.3 Disable Secure Boot (if needed)

- Access your BIOS/UEFI settings (press **Del** or **F2** at startup)
- Find **Secure Boot** and set it to **Disabled**
- This is required for Arch Linux bootloaders

---

## Part 2: Create Bootable USB

### 2.1 Download Arch Linux ISO

1. Go to: https://archlinux.org/download/
2. Download the latest ISO (e.g., `archlinux-x86_64.iso`)

### 2.2 Burn ISO with Rufus

1. Download **Rufus** from: https://rufus.ie/
2. Open Rufus
3. Select your USB drive
4. Click **SELECT** → choose the Arch ISO
5. Ensure **Partition scheme** is set to **GPT**
6. Click **START**
7. When done, click **CLOSE**

---

## Part 3: Boot into Arch Linux Live USB

1. Plug in your USB drive
2. Restart your PC
3. Enter BIOS/UEFI (press **Del** or **F2**)
4. Set **USB** as first boot priority
5. Save and exit

---

## Part 4: Connect to WiFi in Arch Live Environment

### 4.1 Check Network Devices

```bash
ip link
```

### 4.2 Connect with iwctl

```bash
iwctl
```

Inside iwctl:

```
device list
```

Find your WiFi device (e.g., `wlan0`):

```
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YourNetworkName"
exit
```

### 4.3 Unblock WiFi (if needed)

```bash
rfkill unblock all
ip link set wlan0 up
```

### 4.4 Test Connection

```bash
ping archlinux.org
```

---

## Part 5: Download and Run the Dual Boot Installer

## 5.0.1 Install Git on Archiso

```bash
pacman -Sy git

```

### 5.1 Download the Script

```bash
git clone https://github.com/nightdevil00/DualBoot.git
cd DualBoot
```

### 5.2 Make It Executable

```bash
chmod +x DUALBOOT-Windows_Arch_Limine.sh
```

### 5.3 Run the Installer

```bash
sudo ./DUALBOOT-Windows_Arch_Limine.sh
```

---

## Part 6: Installer Walkthrough

The script will guide you through these steps:

### 6.1 Select Disk
- Choose the disk where Windows is installed (usually `/dev/sda`)

### 6.2 Partition Setup
- The script detects your Windows EFI automatically
- **Enter EFI partition start** (e.g., `1GB`)
- **Enter EFI partition end** (e.g., `3GB`)
- **Enter root partition start** (e.g., `3GB`)
- **Enter root partition end** (e.g., `100%`)

### 6.3 Encryption Setup
- Create a LUKS passphrase for encrypted root partition
- **Remember this password** - you'll need it at every boot

### 6.4 System Configuration
- Enter your desired hostname
- Set root password
- Create your user account and password

The installation will proceed automatically and may take 10-20 minutes.

---

## Part 7: First Boot

### 7.1 Reboot

```bash
reboot
```

### 7.2 Select Arch Linux in UEFI Menu

- At startup, press the boot menu key (usually **F8**, **F12**, or **Esc**)
- Select **"Arch Linux Limine Bootloader"**

### 7.3 Unlock Encrypted Root

- Enter your LUKS passphrase when prompted

---

## Part 8: Connect to WiFi in Installed System

### 8.1 Start iwd

```bash
iwctl
```

### 8.2 Connect to WiFi

```
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YourNetworkName"
exit
```

### 8.3 Get IP Address

```bash
dhcpcd
```

---

## Part 9: Install Omarchy (Recommended Desktop Environment)

Omarchy provides a modern, pre-configured Arch Linux experience with Hyprland, Waybar, Walker and more,

### 9.1 Install Omarchy

```bash
curl -fsSL https://omarchy.org/install | bash
```

### 9.2 Reboot After Installation

```bash
reboot
```

---

## Part 10: Understanding the Script

The `DUALBOOT-Windows_Arch_Limine.sh` script automates:

| Feature | Description |
|---------|-------------|
| **UEFI Detection** | Finds Windows EFI partition automatically |
| **Partitioning** | Creates separate Arch EFI and root partitions |
| **LUKS Encryption** | Encrypts root partition with password |
| **Btrfs Setup** | Creates subvolumes: @, @home, @snapshots, @log, @swap |
| **Limine Bootloader** | Installs Limine as a separate UEFI entry |
| ** Plymouth** | Shows graphical boot animation |
| **Snapper** | Enables automatic snapshots for rollback |
| **ZRAM** | Configures compressed swap in RAM |

### Key Files Created

- `/boot/EFI/limine/` - Limine bootloader files
- `/boot/EFI/limine/limine.conf` - Boot menu configuration
- `/etc/crypttab` - LUKS configuration for automatic unlock

---

## Troubleshooting

### No WiFi After Boot
```bash
sudo rfkill unblock all
sudo systemctl enable --now iwd.service


sudo systemctl enable --now systemd-resolved.service

echo "Creating iwd DNS config..."
mkdir -p ~/.config/iwd
nano ~/.config/iwd/main.conf 
[Network]
EnableNetworkConfiguration=true
NameResolvingService=systemd

```

### Bootloader Not Showing
- Enter BIOS → Check boot order
- Ensure "Arch Linux Limine" is listed

### Forgot LUKS Password
- Unfortunately, there's no recovery
- You'll need to reinstall

### Windows Not Booting
- Boot into Arch → Run:
```bash
efibootmgr
```
- Check if Windows boot entry exists

---

## Next Steps

1. Update your system: `sudo pacman -Syu`
2. Install AUR helper (e.g., `yay`): `sudo pacman -S yay`
3. Explore your new Arch Linux system!

---


