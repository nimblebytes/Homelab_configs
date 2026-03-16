# Scripts to standardise Proxmox administration


- [Scripts to standardise Proxmox administration](#scripts-to-standardise-proxmox-administration)
  - [List of Scripts](#list-of-scripts)
    - [Download OS images](#download-os-images)
    - [Create Proxmox VM template](#create-proxmox-vm-template)
    - [Create a VM](#create-a-vm)
    - [Build pipeline from OS to VM](#build-pipeline-from-os-to-vm)
    - [Helper library for logging functions](#helper-library-for-logging-functions)

This folder contains several scripts to help to automate repetitive and debugging tasks.

## List of Scripts

### Download OS images

View the [download cloud VM script](/scripts/proxmox/download_cloud_vm_image.sh) or download with:

```console
wget https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/download_cloud_vm_image.sh
```

Handles downloading different OS types and versions. However, only supports _cloud AMD64_ builds, which are are best suit for headless VMs in Proxmox and support configuration via _cloud init_. Additional features:
* Downloads the _latest_ release
* Downloads the image only if it is newer than the local image (save time and bandwidth). 
* (Optional) creates a copy the OS image and patch it to request the DNS search string when using DHCP (see [DNS search issue](/proxmox/docs/proxmox_cloud_init_issue_dhcp_dns_domain.md)).
* (optional) Uses the logging helper library if available (see [Helper Library](#helper-library-for-logging-functions))

This script can be run with ``cron`` this ensure that new VMs always use the most up-to-day OS image.

### Create Proxmox VM template

View the [create PVE template script](/scripts/proxmox/create_pve_template.sh) or download with:

```console
wget https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/create_pve_template.sh
```

Uses the Proxmox APIs to safely create a template using the embedded configuration.
* The scripts has dedicated variables (hardcoded) that the most relevant template configurations that should be changes, depending the the environment.
* Additional specific changes to the template configurations should be made in the GUI once the template is created. To prevent performing these of changes continuously, the script function ``create_template()`` should be modified. A good knowledge of how to use ``qm set`` is required[^1].
  
[^1]: [Proxmox - QM set](https://pve.proxmox.com/pve-docs/qm.1.html#cli_qm_set)


   
### Create a VM

View the [create a VM script](/scripts/proxmox/create_vm.sh) or download with:

```console
wget https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/create_vm.sh
```

Build a new VM or replaces an existing VM, using the template provided as input.

### Build pipeline from OS to VM

View the [build a Test VM (labrat) script](/scripts/proxmox/build_test_labrat_vm.sh) or download with:

```console
wget https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/build_test_labrat_vm.sh
```

Example script on how to chain the scripts to create a build pipeline, so that a new OS release is automatically converted into a template and a new VM built and started.

### Helper library for logging functions

View the [prettier logs library script](/scripts/proxmox/prettier_logs.sh) or download with:

Provides additional functions and variable to standardize the structure of messaged and to used colours in the outputs.

```console
wget https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/proxmox/prettier_logs.sh
```







