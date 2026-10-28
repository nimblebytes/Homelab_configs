# USB Serial on Debian 13 Cloud VMs — FAQ

> Applies to Debian 13 (trixie) VMs built from cloud images running
> `linux-image-*-cloud-amd64` and `grub-cloud-amd64`.

> [!Important]
> Covers `/dev/ttyUSB`, `/dev/ttyACM`, and `/dev/serial` missing on Debian 13 cloud images.

> [!Note] 
> tl;dr
> 
> Run the ["fix_usb_serial.sh"](/scripts/linux/fix_usb_serial.sh) script to fix this issue with the following command:
> ```console
> wget -qO fix_usb_serial.sh https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/linux/fix_usb_serial.sh \
>   && chmod +x fix_usb_serial.sh \
>   && sudo ./fix_usb_serial.sh --all
> ```

---

## Table of Contents

- [USB Serial on Debian 13 Cloud VMs — FAQ](#usb-serial-on-debian-13-cloud-vms--faq)
  - [Table of Contents](#table-of-contents)
  - [1. Why are `/dev/ttyUSB` and `/dev/serial` missing?](#1-why-are-devttyusb-and-devserial-missing)
  - [2. Can I install extra modules to fix the cloud kernel?](#2-can-i-install-extra-modules-to-fix-the-cloud-kernel)
  - [3. What is the correct fix?](#3-what-is-the-correct-fix)
  - [4. How do I know if I am running a cloud kernel?](#4-how-do-i-know-if-i-am-running-a-cloud-kernel)
  - [5. I installed `linux-image-amd64` but still booted the cloud kernel. Why?](#5-i-installed-linux-image-amd64-but-still-booted-the-cloud-kernel-why)
  - [6. What does the `update-grub` warning about old titles mean?](#6-what-does-the-update-grub-warning-about-old-titles-mean)
  - [7. How do I correctly replace the cloud kernel?](#7-how-do-i-correctly-replace-the-cloud-kernel)
  - [8. Can I avoid this problem when building the image?](#8-can-i-avoid-this-problem-when-building-the-image)
  - [9. What is `/dev/serial` and why does it not exist?](#9-what-is-devserial-and-why-does-it-not-exist)
  - [10. After rebooting into the full kernel, still no device nodes. Why?](#10-after-rebooting-into-the-full-kernel-still-no-device-nodes-why)
  - [11. How do I configure USB passthrough in my hypervisor?](#11-how-do-i-configure-usb-passthrough-in-my-hypervisor)
  - [12. I get "Permission denied" accessing the serial port. How do I fix it?](#12-i-get-permission-denied-accessing-the-serial-port-how-do-i-fix-it)
  - [13. Which kernel module handles my USB-serial chip?](#13-which-kernel-module-handles-my-usb-serial-chip)
  - [14. How do I verify everything is working?](#14-how-do-i-verify-everything-is-working)
  - [15. Can I automate the kernel replacement?](#15-can-i-automate-the-kernel-replacement)

---

## 1. Why are `/dev/ttyUSB` and `/dev/serial` missing?

Debian cloud images ship `linux-image-*-cloud-amd64`, a stripped kernel with USB
drivers compiled out entirely. There are no `.ko` files on disk for any USB serial
driver. Because no driver exists, no device node is created, and the udev symlink
directory `/dev/serial/` never appears.

---

## 2. Can I install extra modules to fix the cloud kernel?

**No.** Debian does not publish a `linux-modules-extra-*` package for the cloud
kernel. The drivers are absent by design and cannot be added without replacing the
kernel entirely.

---

## 3. What is the correct fix?

Install `linux-image-amd64` (the full standard kernel), configure GRUB to boot it by
default, and reboot. See Q7 for the exact steps.

---

## 4. How do I know if I am running a cloud kernel?

```sh
uname -r
```

A cloud kernel version string contains `-cloud-`:

```
6.12.88+deb13-cloud-amd64    ← cloud kernel, no USB drivers
6.12.88+deb13-amd64          ← full kernel, USB drivers present
```

---

## 5. I installed `linux-image-amd64` but still booted the cloud kernel. Why?

Two things go wrong:

**Problem 1 — GRUB_DEFAULT points at a dynamic alias.**
The default `GRUB_DEFAULT='Debian GNU/Linux'` is a top-level alias that always
resolves to the newest installed kernel by version. Because `6.12.88+deb13-cloud-amd64`
sorts as a higher version than `6.12.88+deb13-amd64`, the cloud kernel wins every
time.

**Problem 2 — grub-cloud-amd64 uses submenus.**
The full kernel entry is placed inside an `Advanced options` submenu in `grub.cfg`,
not at the top level. Setting `GRUB_DEFAULT` to an entry title only works for
top-level entries. Referencing a submenu entry requires the `submenu_id>entry_id`
format, which is brittle and version-specific.

The correct fix (Q7) avoids both problems by disabling submenus entirely before
setting the default.

---

## 6. What does the `update-grub` warning about old titles mean?

```
Warning: Please don't use old title `Debian GNU/Linux, with Linux 6.12.88+deb13-amd64'
for GRUB_DEFAULT, use `Advanced options for Debian GNU/Linux>Debian GNU/Linux,
with Linux 6.12.88+deb13-amd64' (for versions before 2.00) or
`gnulinux-advanced-<uuid>>gnulinux-6.12.88+deb13-amd64-advanced-<uuid>'
(for 2.00 or later)
```

This warning appears when `GRUB_DEFAULT` is set to a bare entry title string such as
`'Debian GNU/Linux, with Linux 6.12.88+deb13-amd64'`. GRUB is telling you two things:

1. **The entry is inside a submenu.** Bare title matching only works for top-level
   entries. For submenu entries, GRUB requires the `submenu_id>entry_id` format.

2. **Title-based matching is deprecated.** Since GRUB 2.00, the stable way to
   reference an entry is by its internal `--id` value, not its display title.

The fix in Q7 avoids this warning entirely by setting `GRUB_DISABLE_SUBMENU=y` before
running `update-grub`. With submenus disabled, all kernel entries are promoted to the
top level and can be matched directly by title without the `>` separator.

---

## 7. How do I correctly replace the cloud kernel?

```sh
# 1. Install the full kernel
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64

# 2. Create the grub.d drop-in directory (standard on Debian 13)
sudo mkdir -p /etc/default/grub.d

# 3. Disable GRUB submenus — promotes all entries to the top level
echo 'GRUB_DISABLE_SUBMENU=y' | sudo tee /etc/default/grub.d/99-disable-submenus.cfg

# 4. First update-grub pass — regenerates grub.cfg with flat layout
sudo update-grub

# 5. Find the version of the newly installed full kernel
NEW_KVER=$(ls -1 /boot/vmlinuz-* \
    | awk -F'/boot/vmlinuz-' '{print $2}' \
    | grep -v cloud \
    | sort -V \
    | tail -1)
echo "New kernel: $NEW_KVER"

# 6. Extract the exact menu entry title using literal string match (safe with '+')
MENU_ENTRY=$(awk -F"'" -v ver="$NEW_KVER" '
    /^[[:space:]]*menuentry / && index($0, ver) > 0 {
        print $2; exit
    }
' /boot/grub/grub.cfg)
echo "Menu entry: $MENU_ENTRY"

# 7. Write the GRUB default drop-in
printf 'GRUB_DEFAULT="%s"\n' "$MENU_ENTRY" \
    | sudo tee /etc/default/grub.d/99-set-standard-kernel.cfg

# 8. Final update-grub pass — bakes the default into grub.cfg
sudo update-grub

# 9. Reboot
sudo reboot
```

After rebooting, verify:

```sh
uname -r    # Must NOT contain 'cloud'
```

The old cloud kernel is left installed as a fallback. If the VM fails to boot, select
it from the GRUB menu via your hypervisor's console.

---

## 8. Can I avoid this problem when building the image?

Yes. The `build-openstack-debian-image` tool accepts a `--no-cloud-kernel` flag:

```sh
build-openstack-debian-image \
    -r trixie \
    --no-cloud-kernel \
    --output debian-trixie-amd64 \
    --architecture amd64 \
    --image-size 8
```

Alternatively, build from the Debian netinstall ISO — it uses the full kernel by
default.

---

## 9. What is `/dev/serial` and why does it not exist?

`/dev/serial/` is a udev-managed directory of stable symlinks:

```
/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_XXXXXXXX-if00-port0
/dev/serial/by-path/pci-0000:00:14.0-usb-0:1:1.0-port0
```

These are created automatically when a serial device node (`/dev/ttyUSB*` or
`/dev/ttyACM*`) appears. Without USB drivers in the kernel, no device node is ever
created and the symlinks never appear.

After booting the full kernel and plugging in a USB serial device, the symlinks are
created by udev with no extra configuration. The `by-id` path is stable across reboots
and re-plugging and is preferred over `/dev/ttyUSB0` in scripts and service files.

---

## 10. After rebooting into the full kernel, still no device nodes. Why?

The kernel replacement is a prerequisite. The hypervisor must also pass the USB device
through to the VM — without that, the kernel has no hardware to bind a driver to.

```sh
lsusb    # Should list your serial adapter
```

If it does not appear, configure USB passthrough (Q11), then check `dmesg`:

```sh
dmesg | grep -iE 'usb|tty|serial' | tail -20
```

A successful bind looks like:

```
usb 1-1: new full-speed USB device number 2
ftdi_sio 1-1:1.0: FTDI USB Serial Device converter detected
usb 1-1: FTDI USB Serial Device converter now attached to ttyUSB0
```

---

## 11. How do I configure USB passthrough in my hypervisor?

Find the device VID and PID on the **host**:

```sh
lsusb
# Example: Bus 001 Device 003: ID 0403:6001 Future Technology Devices FT232
#                                  ^^^^ ^^^^
#                                  VID  PID
```

| Hypervisor | Method |
|---|---|
| **Proxmox** | VM Hardware → Add → USB Device → select by vendor/product ID |
| **virt-manager** | Add Hardware → USB Host Device → select from list |
| **QEMU CLI** | `-device usb-host,vendorid=0x0403,productid=0x6001` |
| **VirtualBox** | Settings → USB → add filter (Extension Pack required for USB 2/3) |
| **VMware** | VM → Settings → USB Controller or VM → Removable Devices |

---

## 12. I get "Permission denied" accessing the serial port. How do I fix it?

Serial ports are owned by the `dialout` group:

```sh
sudo usermod -aG dialout $USER
```

Log out and back in (or reboot) for the change to take effect:

```sh
groups    # Should include: dialout
```

---

## 13. Which kernel module handles my USB-serial chip?

| Chip | Common Devices | Module |
|---|---|---|
| FTDI FT232R / FT2232 | Most USB-serial adapters | `ftdi_sio` |
| Silicon Labs CP2102 / CP2104 | NodeMCU, many ESP32 boards | `cp210x` |
| WCH CH340 / CH341 | Cheap adapters, Arduino Nano clones | `ch341` |
| CDC/ACM | Arduino Leonardo/Micro, STM32, Pi Pico | `cdc_acm` |
| Prolific PL2303 | Older USB-serial cables | `pl2303` |

On the full kernel the correct module loads automatically via udev when the device is
plugged in. Manual `modprobe` is not required.

---

## 14. How do I verify everything is working?

```sh
# 1. Confirm not running the cloud kernel
uname -r                    # Must NOT contain 'cloud'

# 2. Confirm USB device is visible
lsusb

# 3. Confirm driver loaded automatically
lsmod | grep -E 'ftdi_sio|cp210x|ch341|cdc_acm'

# 4. Confirm device nodes exist
ls -la /dev/ttyUSB* /dev/ttyACM*

# 5. Confirm udev symlinks exist
ls -la /dev/serial/by-id/

# 6. Check kernel bind messages
dmesg | grep -iE 'usb|tty|serial' | tail -20
```

---

## 15. Can I automate the kernel replacement?

Yes. The shell script [fix_usb_serial.sh](/scripts/linux/fix_usb_serial.sh) covers diagnosis and resolution of this issue.

```sh
chmod +x fix_usb_serial.sh

sudo ./fix_usb_serial.sh --diagnose   # Read-only report, no changes
sudo ./fix_usb_serial.sh --fix        # Install kernel and configure GRUB
sudo ./fix_usb_serial.sh --all        # Diagnose then fix (default)
```

A reboot is required after `--fix` or `--all`. USB passthrough must be configured in
the hypervisor separately.
