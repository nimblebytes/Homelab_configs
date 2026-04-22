# New system checklist

This document provides the list of steps that need be performed for the creation a new virtual machine. The orchestration platform that is used and referenced in this documentation is Proxmox, but they concepts can be transposed to any other platform.

This list is just a guide to ensure that the most common issues are considered, and performed as required, to minimise effort troubleshooting problems later on.

1. VM creation and pre-configurations prior to first start
   1. Create the VM within Proxmox
      1. (Optional) Refer to [proxmox automation script documentation](../proxmox/docs/proxmox_scripts.md) on how to use the scripts for is.
      2. (Optional) Use this script to [download a cloud-init compatible OS image](../scripts/proxmox/download_cloud_vm_image.sh).
      3. (Optional) Use the [Proxmox template automation script](../scripts/proxmox/create_pve_template.sh).
      4. (Optional) Use the [Proxmox VM creation script](../scripts/proxmox/create_vm.sh)
      5. (Optional) Refer to this [example script](../scripts/proxmox/build_test_labrat_vm.sh) on how the chain the process of: OS Download -> Template creation -> VM Creation
2. Adjust VM configurations.
   1. Machine config: Options that should be considered are: username, password, ssh keys, core count, memory, disk size, additional disks, VLANs, IP settings (DHCP/static)
   2. Network Config: Change or add network interfaces (i.e vmbr0, vmbr32, etc.), or add VLAN tag; change IP settings (DHCP/static).
   3. Copy the MAC address of the network device
   4. (Optional) Change start at boot, startup order
3. Firewall and DNS configuration
   1. (Optional) Create a static IP assignment within DHCP for the MAC Address under the correct interface (also provide hostname and description where the host is located). Proxmox: Services -> ISC DHCP/Kea DHCP.
   2. (Optional) Create an additional domain overrides for the host. Proxmox: Services -> Unbound DNS -> Overrides.
   3. (Optional) Create Firewall alias using the hostname. Proxmox: Firewall -> Aliases. Prefix with VMs with "VM_" and physical machines with "HOST_" to make them easier to find.
   4. (Optional) Create Firewall rules to allow access to: NFS/SMB systems; git/internet; other systems.
4. NFS/SMB systems
   1. (Optional) Create a new user and password for the systems (required for SMB shares). Assign the user to specific user groups.
   2. (Optional) Assign the host to specific NFS and/or SMB shares.
5. System git repository
   1. (Optional) Create a repository or folder for the system. Refer to the [system template folder](../_system_template/). This is used to store the system and service configurations files. The VM bootstrap scripts will use this folder.
   2. (Optional) Edit the `network_mounts.yaml` file, which defines the network share that the system needs to mount. If the host will not have a repository folder, then such a file needs to be created in the user home directory before running the main [bootstrap script](../scripts/bootstrap/bootstrap.sh) or running the [mount network shares script](../scripts/bootstrap/install_host_network_shares.sh).
6. VM initial start
   1. Check for connectivity to: 
      1. Local DNS: `nslookup google.com`. Check that the local DNS IP is used. Troubleshooting:
         1. If using a dynamic IP address (DHCP) address, check that this is correctly configured on the firewall/router/DHCP server. 
         2. If using a cloud-init OS image and static IP address, check the configuration in Proxmox.
         3. If using a normal OS image and static IP address, this needs to be manually configured on the host.
      2. Other systems via host name or domainname: `ping <HOSTNAME>` or `ping <HOSTNAME>.<DOMAIN>`
      3. NFS/SMB systems: `ping <SMB_HOSTNAME>` or `ping <NFS_HOSTNAME>`
      4. Internet: `ping google.com`
      5. External DNS: `nslookup google.com 9.9.9.9`
   2. Run the main [bootstrap script](../scripts/bootstrap/bootstrap.sh). Refer to the [script documentation](../scripts/bootstrap/README.md) for additional details.
      1. Run the script with: ```wget -q -O - https://raw.githubusercontent.com/nimblebytes/Homelab_configs/master/scripts/bootstrap/bootstrap.sh | sh```
    > [!NOTE]
    >The scripts assume that the domain search parameter for DNS is configured. This allows hosts to be found using their hostname and ***not*** requiring their FQDN. This is helpful, so that the domain does not need to be hard-coded into configs or scripts files.
