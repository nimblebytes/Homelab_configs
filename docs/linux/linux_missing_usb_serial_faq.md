# USB Serial on Debian Cloud VMs — FAQ

> [!Important]
> Covers `/dev/ttyUSB`, `/dev/ttyACM`, and `/dev/serial` missing on Debian 13 cloud images running under KVM, QEMU, Proxmox, VirtualBox, or VMware.

> [!Note] tl;dr 
> Run the ["fix_usb_serial.sh"](/scripts/linux/fix_usb_serial.sh) script to fix this issue with the following command:
> ```console
> wget -qO fix_usb_serial.sh https://your-url/fix_usb_serial.sh && chmod +x fix_usb_serial.sh && sudo ./fix_usb_serial.sh --all
> ```

---

## Table of Contents

- [USB Serial on Debian Cloud VMs — FAQ](#usb-serial-on-debian-cloud-vms--faq)
  - [Table of Contents](#table-of-contents)
  - [1. Why are `/dev/ttyUSB` and `/dev/serial` missing?](#1-why-are-devttyusb-and-devserial-missing)
  - [2. Do I need to replace the kernel?](#2-do-i-need-to-replace-the-kernel)
  - [3. How do I check if the modules are already on disk?](#3-how-do-i-check-if-the-modules-are-already-on-disk)
  - [4. What packages do I actually need to install?](#4-what-packages-do-i-actually-need-to-install)
  - [5. How do I load the modules without rebooting?](#5-how-do-i-load-the-modules-without-rebooting)
  - [6. How do I make the modules load automatically on boot?](#6-how-do-i-make-the-modules-load-automatically-on-boot)
  - [7. Why are there still no device nodes after loading modules?](#7-why-are-there-still-no-device-nodes-after-loading-modules)
  - [8. How do I configure USB passthrough in my hypervisor?](#8-how-do-i-configure-usb-passthrough-in-my-hypervisor)
    - [KVM / QEMU (command line)](#kvm--qemu-command-line)
    - [KVM / virt-manager (GUI)](#kvm--virt-manager-gui)
    - [Proxmox](#proxmox)
    - [VirtualBox](#virtualbox)
    - [VMware Workstation / Fusion](#vmware-workstation--fusion)
  - [9. What is `/dev/serial` and why does it not exist?](#9-what-is-devserial-and-why-does-it-not-exist)
  - [10. How do I verify everything is working?](#10-how-do-i-verify-everything-is-working)
  - [11. I get "Permission denied" when accessing the port. How do I fix it?](#11-i-get-permission-denied-when-accessing-the-port-how-do-i-fix-it)
  - [12. Which module do I need for my USB-serial chip?](#12-which-module-do-i-need-for-my-usb-serial-chip)
  - [13. Can I automate all of this?](#13-can-i-automate-all-of-this)

---

## 1. Why are `/dev/ttyUSB` and `/dev/serial` missing?

Debian cloud images are intentionally stripped down for virtualised environments. Three things are typically absent:

- **USB serial kernel modules** — drivers such as `ftdi_sio`, `cp210x`, `ch341`, and `cdc_acm` are either not compiled in or not loaded at boot. These are what create `/dev/ttyUSB*` and `/dev/ttyACM*` device nodes.
- **udev serial symlink rules** — `/dev/serial/` is a directory of symlinks created by udev. If the underlying device nodes don't exist, the symlinks are never created.
- **No USB passthrough** — the hypervisor may not be forwarding the physical USB device into the VM, so there is nothing for the drivers to bind to even if they are loaded.

All three need to be addressed for serial devices to appear.

---

## 2. Do I need to replace the kernel?

**No.** You do not need to install `linux-image-amd64` or swap kernels. The correct approach is to install the extra modules package for your *existing* kernel:

```sh
sudo apt install -y linux-modules-extra-$(uname -r)
```

This adds the full set of out-of-tree and hardware-specific modules (including USB serial drivers) without touching the running kernel. Only resort to a kernel replacement if the modules package is unavailable for your kernel version.

---

## 3. How do I check if the modules are already on disk?

```sh
find /lib/modules/$(uname -r) -name '*.ko*' \
  | grep -E 'ftdi|cp210|ch34|cdc_acm|usbserial'
```

- **Output listed** — the driver files exist. They just need to be loaded (`modprobe`). Skip to [Q5](#5-how-do-i-load-the-modules-without-rebooting).
- **No output** — the cloud kernel was built without them. Install `linux-modules-extra-$(uname -r)` first.

---

## 4. What packages do I actually need to install?

| Package | Purpose | Install? |
|---|---|---|
| `usbutils` | Provides `lsusb` for diagnosing USB devices | Recommended |
| `kmod` | Provides `modprobe`, `lsmod` | Usually pre-installed |
| `linux-modules-extra-$(uname -r)` | USB serial drivers for the current kernel | **Yes, if modules are missing** |
| `linux-image-amd64` | Full replacement kernel | No — unnecessary |

```sh
sudo apt update
sudo apt install -y usbutils kmod
sudo apt install -y linux-modules-extra-$(uname -r)
```

---

## 5. How do I load the modules without rebooting?

Use `modprobe` to load the drivers immediately:

```sh
sudo modprobe usbserial
sudo modprobe cdc_acm      # CDC/ACM devices, many microcontrollers
sudo modprobe ftdi_sio     # FTDI FT232 and variants
sudo modprobe cp210x       # Silicon Labs CP2102/CP2104
sudo modprobe ch341        # CH340/CH341 chips
```

Verify they loaded:

```sh
lsmod | grep -E 'usbserial|cdc_acm|ftdi|cp210|ch34'
```

---

## 6. How do I make the modules load automatically on boot?

Create a config file in `/etc/modules-load.d/`:

```sh
sudo tee /etc/modules-load.d/usb-serial.conf <<'EOF'
cdc_acm
ftdi_sio
cp210x
ch341
EOF
```

The `systemd-modules-load` service reads all files in that directory at boot. No further configuration is needed.

---

## 7. Why are there still no device nodes after loading modules?

The most common reason: **the hypervisor is not passing the USB device through to the VM.** The kernel drivers load successfully but have no hardware to bind to, so no device node is created.

Check what USB devices the VM can see:

```sh
lsusb
```

If your serial adapter does not appear in `lsusb` output, configure USB passthrough in your hypervisor first. See [Q8](#8-how-do-i-configure-usb-passthrough-in-my-hypervisor).

After plugging in or passing through a device, check `dmesg` for binding:

```sh
dmesg | grep -iE 'usb|tty|serial' | tail -20
```

A successful bind looks like:

```
usb 1-1: new full-speed USB device
ftdi_sio 1-1:1.0: FTDI USB Serial Device converter detected
usb 1-1: FTDI USB Serial Device converter now attached to ttyUSB0
```

---

## 8. How do I configure USB passthrough in my hypervisor?

First, find your device's vendor and product ID on the **host**:

```sh
lsusb
# Example output:
# Bus 001 Device 003: ID 0403:6001 Future Technology Devices International FT232 Serial (UART) IC
#                        ^^^^ ^^^^
#                        VID  PID
```

Then configure passthrough:

### KVM / QEMU (command line)

```sh
-device usb-host,vendorid=0x0403,productid=0x6001
```

### KVM / virt-manager (GUI)

1. Open VM details → **Add Hardware** → **USB Host Device**
2. Select your device from the list → **Finish**

### Proxmox

In the VM's **Hardware** tab → **Add** → **USB Device** → select the device by vendor/product ID or port.

### VirtualBox

**Settings** → **USB** → enable USB controller → add a filter matching your device.
> Requires the VirtualBox Extension Pack for USB 2.0/3.0 passthrough.

### VMware Workstation / Fusion

**VM** → **Settings** → **USB Controller** → connect device, or use **VM** → **Removable Devices** to attach it while the VM is running.

---

## 9. What is `/dev/serial` and why does it not exist?

`/dev/serial/` is a directory of persistent symlinks maintained by udev, organised as:

```
/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_XXXXXXXX-if00-port0
/dev/serial/by-path/pci-0000:00:14.0-usb-0:1:1.0-port0
```

These symlinks are created automatically by udev rules (shipped with the `udev` package) when a serial device node appears. If `/dev/ttyUSB0` doesn't exist, `/dev/serial/` won't either.

**Fix:** resolve the missing device node first (modules + passthrough), then trigger udev:

```sh
sudo udevadm control --reload-rules
sudo udevadm trigger
```

The `by-id` symlinks are stable across reboots and re-plugging, making them preferable to `/dev/ttyUSB0` in scripts and service files.

---

## 10. How do I verify everything is working?

Run this diagnostic sequence:

```sh
# 1. Confirm the USB device is visible to the VM
lsusb

# 2. Confirm the driver module is loaded
lsmod | grep -E 'ftdi|cp210|ch34|cdc_acm'

# 3. Confirm device nodes exist
ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null

# 4. Confirm udev serial symlinks exist
ls -la /dev/serial/by-id/ 2>/dev/null

# 5. Check kernel bind messages
dmesg | grep -iE 'usb|tty|serial' | tail -20
```

All five checks should return output. If any are empty, refer to the relevant FAQ entry.

---

## 11. I get "Permission denied" when accessing the port. How do I fix it?

Serial device nodes are owned by the `dialout` group. Add your user to it:

```sh
sudo usermod -aG dialout $USER
```

**You must log out and log back in** (or start a new login shell) for the group change to take effect. Verify with:

```sh
groups
# Should include: dialout
```

To avoid logging out during a session you can use:

```sh
newgrp dialout
```

This opens a subshell with the new group active for the current session only.

---

## 12. Which module do I need for my USB-serial chip?

| Chip | Common Devices | Module |
|---|---|---|
| FTDI FT232R/FT2232 | Many USB-serial adapters, Arduino Uno (older) | `ftdi_sio` |
| Silicon Labs CP2102/CP2104 | NodeMCU, many ESP32 dev boards | `cp210x` |
| WCH CH340/CH341 | Cheap USB-serial adapters, Arduino Nano clones | `ch341` |
| CDC/ACM | Arduino Leonardo/Micro, STM32, Raspberry Pi Pico | `cdc_acm` |
| Prolific PL2303 | Older USB-serial cables | `pl2303` |

If unsure which chip your device uses, run `lsusb` and look up the vendor/product ID pair.

---

## 13. Can I automate all of this?

The shell script [fix_usb_serial.sh](/scripts/linux/fix_usb_serial.sh) covers diagnosis and resolution of this issue. The script need the 

```sh
# Run full diagnosis and fix
sudo ./fix_usb_serial.sh --all

# Diagnose only (no changes made)
sudo ./fix_usb_serial.sh --diagnose

# Install and configure only
sudo ./fix_usb_serial.sh --fix
```

> [!Important] 
> USB passthrough must be configured in your hypervisor manually — it cannot be scripted from inside the VM.
