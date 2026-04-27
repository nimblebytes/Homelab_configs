# Homelab config repository

This repository contains all the public settings for the systems running in my homelab. Each systems has it own folder and a standardized set of directories to aid in provisioning the systems using automation or scripts.

Also contains general documentation; documentation for Proxmox setup, configuration, and trouble shooting; and various automation scripts for proxmox, bootstrapping, and others.  

## Proxmox documentation

The [Proxmox general documentation, issues & links](./Proxmox/README.md) provide the starting point for documentation and resources for:
 - Proxmox installation and post-installation steps
 - Checklist of setting up a new VM/LXCs
 - Resolving Proxmox or VM issues

The following page discuss the various [Proxmox automation scripts](./Proxmox/docs/proxmox_scripts.md) that are available and how to use them.

## Setting up new VMs

> [!IMPORTANT] Run bootstrap script with:
> ```wget -q -O - https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/bootstrap/bootstrap.sh | sh```
> - Complete the [new system checklist](docs/new_system_checklist.md) first before running the script

Documentation and checklist on creating a new VM and setting it up:
 - [Checklist](docs/new_system_checklist.md) defining the setup steps for new systems.
 - [Bootstrap script documentation](scripts/bootstrap/README.md) details the various scripts to setting up a new systems. Refer to this documentation on how to run the script
 - The [main bootstrap script](scripts/bootstrap/bootstrap.sh) that provides a UI for setting some system settings and which installation scripts to execute on the new system. 

