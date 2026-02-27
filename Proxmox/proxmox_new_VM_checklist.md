


1. Use cloud-init image clone
   1. setup cloud-init image
2. New VM creation
   1. _(Optional)_ [Hardware] Change VM memory, processors cores
   2. _(Optional)_ [Hardware] Change storage size; add additional storage
   3. _(Optional)_ [Hardware] Change virtual bridge (vmbr) or add VLAN tag [Network Device]
   4. _(Optional)_ [Hardware] Add network devices; assign vmbr & vlan
   5. _(Optional)_ [Cloud-init] Change username, ssh keys, upgrade packages
   6. [Cloud-init] Change IP config for network device/s: fixed IP, DHCP
   7. [Options] Change start at boot, startup order
3. Firewall configuration and changes
   1. Check connectivity (DHCP leases)
   2. Assign static IP Address
   3. Create IP Alias
   4. Create firewall rules: NAS SMB & NAS NFS
4. NAS Configurations
   1. Create machine user
   2. Setup folder access
   3. Check that NFS allows subnet to access "linux_bootstrap"
5. Start server
   1. Run bootstrap strip
      1. Copy from Github or manually create it.
      2. Create following SMB shares
         1. GitHub -> smb_eatalot_github
6. Docker installation
   1. Official installation [instructions.](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
   2. _(Optional)_ Add user to `docker` group [[Docker guide]](https://docs.docker.com/engine/install/linux-postinstall/). This is a security issues, but solve the problem that local environment variables are not passed when using `sudo docker ...`
      1. ```sudo usermod -aG docker $USER```