# Cloud-Init based VMs within Proxmox

```console
ssh-keygen -t ed25519 -f /root/.ssh/cloud_init_duplicant_eddsa -C "duplicant@cloudinit"
```

```console
ssh-keygen -t rsa -b 4096 -f /root/.ssh/cloud_init_duplicant_rsa -C "duplicant@cloudinit"
```

> [!WARNING]
> Using VS Code to ssh into a remote system will fail with these generated keys. The errors will be either:
> - "Load key *: Invalid format" using ssh via the terminal, or
> - "Permission denied" using the ssh plugin
> 
> **Solution**: The priviate key needs a newline added to the end of the file. [[Reference](https://superuser.com/questions/1328512/ssh-load-key-error-invalid-format)]
 

## Setting up a Cloud-Init Images

Select a cloud cloud images

There are images that optimized for specific cloud hosting provider, environments and architectures. The following type of images are smaller and best to use with Proxmox, as drivers for generic physical harware are removed:
- debian-[VERSION]-genericcloud-[ARCH].qcow2
- [UBUNTU_VERSION]-cloudimg-[ARCH].img 


| OS     | Release                   | *Notes*                                                      |
| :----- | :------------------------ | ------------------------------------------------------------ |
| Debian | Testing - Trixie (Always) | <https://cloud.debian.org/images/cloud/trixie/daily/latest/> |
| Debian | 12 - Bookworm             | <https://cloud.debian.org/images/cloud/bookworm/latest/>     |
| Debian | 11 - Bullseye             | <https://cloud.debian.org/images/cloud/bullseye/latest/>     |
| Ubuntu | All versions              | <https://cloud-images.ubuntu.com>/                           |

Quick links to "lastest" images:

 - Debian 13 AMD64 - <https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2>
 - Debain 12 AMD64 - <https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2>
 - Debain 12 ARM64 - <https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2>
 - Ubuntu 24.04 LTS AMD64 - <https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img>
 - Ubuntu 24.04 LTS ARM64 - <https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img>

Open a shell within Proxmox and 

```console
cd /var/lib/vz/template/iso
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2
```

```console
qm create 8000 --name debian12-cloudinit-dmz-network 
## Depending on the Proxmox installation or configuration, either lvm or zfs needs to be used:
## For lvm:
  qm importdisk 8000 /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2 local-lvm
  qm set 8000 --ostype l26 --scsi0 local-lvm:0,discard=on,ssd=1,import-from=/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2
  qm set 8000 --serial0 socket --vga serial0 --machine q35 --scsihw virtio-scsi-pci --agent enabled=1
  qm set 8000 --bios ovmf --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1
  qm set 8000 --boot order=scsi0
  qm set 8000 --scsi2 local-lvm:cloudinit,media=cdrom

## For zfs
  qm importdisk 8000 /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2 local-zfs
  qm set 8000 --ostype l26 --scsi0 local-zfs:0,discard=on,ssd=1,import-from=/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2
  qm set 8000 --serial0 socket --vga serial0 --machine q35 --scsihw virtio-scsi-pci --agent enabled=1
  qm set 8000 --bios ovmf --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=1
  qm set 8000 --boot order=scsi0
  qm set 8000 --scsi2 local-zfs:cloudinit,media=cdrom


qm set 8000 --cpu host --cores 1 --memory 2048
qm set 8000 --net0 virtio,bridge=vmbr31 
qm set 8000 --ciuser duplicant --sshkeys /root/.ssh/cloud_init_duplicant_eddsa.pub
qm set 8000 --searchdomain temp.local
qm set 8000 --ipconfig0 ip=dhcp
qm template 8000
```

> [!IMPORTANT]
> If there are issues where cloud init does not run on the first boot, such as, unable to login or IP address not being set, the possible causes are: using machine type `q35` **and** bios `ovmf` together, or where the boot drive (CD-ROM) is set as an `IDE` device. Solutions are use a SCSI device for the boot drive or not use `ovmf` for the bios. [[Proxmox: Cloud init SSH issues](https://forum.proxmox.com/threads/cloudinit-ssh-error-on-startup.141845/)] 

> [!IMPORTANT] 
> **SUDO commands**
> 
> If only one user is created with "--ciuser", this user will be the default user for the OS and will have `sudo` rights. The `sudo` command will still needs to be included. If no password is specified in the cloud-init config, then no password will be required for `sudo` commands

Explanation of the commands and parameters:
1. `qm create 8000`: Creates a new VM with ID number 8000. Update this number when creating new images, or when referencing a specific image.
  1. `--name debian12-cloudinit-dmz-network`: Name of the image.
1. `qm importdisk 8000 [FILEPATH].qcow2 local-[lvm|zfs]`: Import an external disk image for the OS of the VM. Either `local-lvm` or `local-zfs` needs to be used, depending on installation and setup of Proxmox. 
  1. `[FILEPATH].qcow2`: The full filepath to local file to use as the image. `qcow2` needs to be adjusted based on the image used.
  1. `local-lvm`: Which volume to use as the backing volume. Change this based on the Proxmox storage configurations.
1. `qm set 8000 --ostype l26 --scsi0 local-lvm:vm-8000-disk-0,discard=on,ssd=1,format=qcow2,import-from=[FILEPATH]`: Use volume as scsi drive for the VM.
  1. `--ostype l26`: Define that the Guest OS type is `Linux` and version is `2.6 - 6.x`.
  1. `local-lvm:vm-8000-disk-0`: Which backing volume (`local-lvm`) to use for the VM and the name for the disk `vm-8000-disk-0`. Change this based on the Proxmox storage configurations.
  1. `discard=on`: Pass discard/trim requests to the underlying storage.
  1. `ssd=1`: Expose the storage as a ssd than a hdd to the VM.
  1. `format=qcow2`: The format to use for the backing storage. `qcow2` is the most space efficient.
  1. `import-from=[FILEPATH]`: Which ISO image to use for the new VM. 
1. `qm set 8000 --serial0 socket --vga serial0 --machine q35 --scsihw virtio-scsi-pci --agent enabled=1`: Set the system configuration properites.
  1. `--serial0 socket --vga serial0`: Configure a serial console and vga display; useful for most cloud-init images. Switch to default display if it does not work with a specific image.
  1. `--machine q35`: Machine type/chipset to use. `q35` provides a more modern chipsets, better PCI-express support, and helpful for PCI passthrough.
  1. `--scsihw virtio-scsi-pci`: Set the SCSI controller mode. `virtio-scsi-single` can be beneficial for slower CPU cores and PCI Passthrough. 
  1. `--agent enabled=1`: Enable the QEMU agent, which allowes Proxmox better control the VM, during backups, reboots, etc. 
1. `qm set 8000 --bios ovmf`: Set the system BIOS to use the `ovmf` bios which provide modern UEFI functionality. 
  1. `--efidisk0 local-lvm:1,format=qcow2,efitype=4m,pre-enrolled-keys=1`:  Use the `local-lvm` storage volume to save UEFI BIOS setting (the ID *must* be 1). Change this based on the Proxmox storage configurations. Set the storage to `qcow2` format, the EFI partition size to 4MB, and pre-enrolled keys for secure boot.
1. `qm set 8000 --boot order=scsi0`: Define the boot order for the VM to only boot from `scsi0`.
1. `qm set 8000 --scsi local-lvm:cloudinit,media=cdrom`: Add the cloud-init drive (CD-ROM), that is used to copy the cloud-init setting on start up.
  1. [[Proxmox: Cloud-init SCSI bug](https://forum.proxmox.com/threads/unable-to-parse-zfs-volume-name-cloudinit.144828/)] There is a bug, that will be patched, where a error will popup trying to use a SCSI device for cloud-init. The solution is to explicitly use `media=cdrom` tag.
1. `qm set 8000 --cpu host --cores 1 --memory 2048`: Set the type of CPU (`host`) and functionality to expose to the VM, the amount of cores and RAM it can use. 
1. `qm set 8000 --net0 virtio,bridge=vmbr2`: Use `virtio` for the network driver (recommended for Proxmox), and set the network bridge interface.
    1. `vmbr0` default bridge for Proxmox
    1. `vmbr1` currently bridge for Firewall (OPNsense). `vmbr1.30` for Management network.
    1. `vmbr2` currently the VLAN for DMZ

Update the following parameters as needs:
- `qm create 8000`: Creates a new VM with number 8000
- `--memory 2048`: How much memory to allocate by default
- `--core 1`: How many cores to allocate by default
- `--name debian12-cloud-dmz-network`: The name to give this VM
- `--net0 virtio,bridge=vmbr2`: Configures the first network interface (net0) drivers and properties
  - `virtio`: Network driver to use. "virtio" is best to proxmox VMs
  - `bridge=vmbr2`: Which network interface to use. "vmbr2" is currently VLAN for DMZ


## New VM creation process

### Adjust VM Hardware settings

1. CPU Cores
2. RAM
3. Resize VM disk / Add more disks

### Adjust cloud-init user setting





## References
 - [TechnoTim - Cloud init ](https://technotim.live/posts/cloud-init-cloud-image/)

- [Pycvala Blog - Create your own cloud init template](https://pycvala.de/blog/proxmox/create-your-own-debian-12-cloud-init-template/)
