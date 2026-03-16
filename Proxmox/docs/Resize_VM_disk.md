# Proxmox - Resize disk of a running VM

If a VM runs out of disk space, resizing the disk in Proxmox is not sufficient to fix this problem. The filesystem of the VM needs to also be resize to make use of the larger disk. 

**tl;dr:** Steps to resolve this issue - [go to Solution](#increase-the-vm-disk)

- [Proxmox - Resize disk of a running VM](#proxmox---resize-disk-of-a-running-vm)
- [Background Information](#background-information)
  - [Linux Partitions - MBR vs GPT](#linux-partitions---mbr-vs-gpt)
- [Increase the VM Disk](#increase-the-vm-disk)
  - [1. In Proxmox - Resize the disk](#1-in-proxmox---resize-the-disk)
  - [2. In the VM - Resize the Partition](#2-in-the-vm---resize-the-partition)
    - [Resize with growpart](#resize-with-growpart)
    - [Resize with parted](#resize-with-parted)
  - [3. In the VM - Resize the filesystem on the partition](#3-in-the-vm---resize-the-filesystem-on-the-partition)


# Background Information

## Linux Partitions - MBR vs GPT 

MBR (MS-DOS) partition tables are the old style still used on many VMs, and has a structural limitation:
 - MBR can only have 4 primary partitions

To work around this limit, MBR can have a special type of partition called an **extended** partition, which acts as a container for additional partitions. There can only be one extended partition on a disk.

 - It **cannot** directly contain a filesystem.
 - Its only purpose is to hold logical partitions.
 - It counts as one of the four primary partition slots. (sda2, sda3, or sda4)
  
Logical partitions are created inside the logical partition, starting from sda5.

GPT partition table (common on UEFI systems) eliminates this problem as:
 - GPT supports 128 partitions, all equivalent
 - No need for “extended” or “logical” partitions
  

# Increase the VM Disk

> [!WARNING]
> - Always make a backup/snapshot before resizing.
> - It is not easy to shrink a disk in Proxmox
> - If using GPT partitions, `growpart` works fine, as it often used by cloud images to extends the ***last*** partition to occupy unallocated space.
> - If using MBR partitions tables, resizing beyond 2TB has limitations.
> - When there are multiple partition, only the last partition can be expanded, unless there is empty space between the partitions. 

The solutions involves 3 distinct steps:
1. In Proxmox - resize the VM disk
2. In the VM - Resize the logic or extended partition
3. In the VM - Expand the filesystems

## 1. In Proxmox - Resize the disk
1. Select the VM
2. Go to `Hardware` tab
3. Select the disk (e.g., scsi0, virtio0, etc.)
4. Click `Disk Action` → `Resize`
5. Enter the amount to increase the disk by e.g., +50G = "Add +50G"
6. Click `Resize disk`


## 2. In the VM - Resize the Partition 
The following sequence of commands needs to be followed. 

First, use `lsblk -f` to identify the which drive and partition needs to be expanded. Eg. sd**a5**, sd**b6**, etc.

```console
lsblk -f
```

```console
# Example output from a cloud OS with a single disk (mountpoint "/")
NAME    FSTYPE  FSVER FSAVAIL FSUSE% MOUNTPOINTS
sda
├─sda1  ext4    1.0     16.2G    13% /
├─sda14
└─sda15 vfat    FAT16  112.1M     9% /boot/efi
     

# Example output a desktop OS with multiple partitions
NAME                    FSTYPE      FSVER    FSAVAIL FSUSE% MOUNTPOINTS
sda
├─sda1                  ext2        1.0       310.5M    26% /boot
├─sda2                                       
└─sda5                  LVM2_member LVM2 001
  ├─server_a--vg-root   ext4        1.0         6.9G    20% /
  ├─server_a--vg-var    ext4        1.0         2.6G    17% /var
  ├─server_a--vg-swap_1 swap        1                       [SWAP]
  ├─server_a--vg-tmp    ext4        1.0       604.3M     0% /tmp
  └─server_a--vg-home   ext4        1.0        24.8G    49% /home
```

The important information is to identify the disk or partition name. From the examples, these are: 
- `/dev/sda1`
- `/dev/sda5` and `server_a--vg-home`

> [!NOTE]
> Instead of using `growpart`, `parted` can be used, as offers more advanced functionality through an interactive command-line. But it requires more precise commands, such as defining the end block size and number of the partition.
> 
> `growpart` is simpler to use as it handles the block size calculations.

### Resize with growpart

Install the following package:
```console
apt install cloud-guest-utils
```

Example: test what changes the command will perform on the disk `/dev/sda` partition `1`

```console
sudo growpart --dry-run /dev/sda 1
```

Expand the partition to use all the available space.

```console
sudo growpart /dev/sda 1
```

### Resize with parted

It is better to use `parted` for a desktop OS to handle the multiple partitions that may exist.

Install the following package:
```console
apt install parted
```

Example: change the partition size of disk `/dev/sda` partition `5`.
```console
# Run parted on disk sda
sudo parted /dev/sda              

# Print the partition information. Find the end of the partition freespace here (End column)
(parted) print

# Resize partition 5 to use all the space. Either use "End" information from the previous command or 100%.
(parted) resizepart 5 100%

# Resize partition 5 until 50GB. Use "End" information from the previous command to use all the space or 100%.
(parted) resizepart 5 50GB

# Exit "parted"
(parted) quit
```


##  3. In the VM - Resize the filesystem on the partition

Resize the Physical Volume (PV).
```
# For a desktop OS, most likely, or
sudo pvresize /dev/sda5

# For a cloud OS, most probably
sudo pvresize /dev/sda1
```

Extend the Logical Volume (LV) by allocating the additional space to it. "+100%FREE" adds all available free space in the Volume Group (VG) to the LV.
- All VGs are found under `/dev/mapper`

Only if _**using**_ a LVM, resize the LVM with:
```
sudo lvextend -l +100%FREE /dev/mapper/{HOSTNAME}--vg-home
```

Only if _**using**_ a LVM, resize the filesystem on the partition.
```
sudo resize2fs /dev/mapper/{HOSTNAME}--vg-home
```

If _**NOT**_ using a LVM, it's just a normal EXT4 partition:
```
sudo resize2fs /dev/sda1
```

Check that the volume has been resized.
```
lsblk
```

