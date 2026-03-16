# Proxmox Issues - DHCP & DNS search string

There is an issues when configuring a VM using cloud init, whereby:
* when a dynamic IP address is obtained using DHCP, the DNS search string _**is not set**_.
* when a static IP address is defined, the DNS search string _**is set**_ using the value from `DNS Domain`.

The root cause, is when the VM send out the DHCP broadcast, it is not also requesting the DNS search string (DHCP option 119). Therefore the DHCP server does not send this information along with the IP Address

tl;dr 

> [!IMPORTANT]
> Cloud OS vs Cloud init
> - A cloud OS is a type of OS build that is optimited for cloud environment; i.e. desktop manager is not install (ideal for headless environments), minimal preinstall packages, etc.
> - Cloud init is a *mechanism* to inject basic confirguration into a VM as it is starting up, such as: IP address, initial user creation, authorised ssh keys, etc.

# Identifying the issue

On the VM, to see what actual network configuration are, run the following command:
```console
resolvectl status
```

This should show the following:

```log
...
Link 2 (eth0)
Current Scopes: DNS LLMNR/IPv4 LLMNR/IPv6
     Protocols: +DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
   DNS Servers: 192.168.0.1 192.168.0.2
    DNS Domain: example.internal
```

Run the following command on the Proxmox server (replace `vmbr1` with the interface that the VM is using).

```console
tcpdump -i vmbr1 -vvv -n port 67 or port 68
```

This will capture the DHCP requests sent to the server (port 67) and the replies sent back to the client (port 68).

Start the VM. The log capture will look as follows

```log
...
Parameter-Request (55), length 10: 
  Subnet-Mask (1), Default-Gateway (3), Domain-Name-Server (6), Hostname (12)
  Domain-Name (15), MTU (26), Static-Route (33), NTP (42) Unknown (120), Classless-Static-Route (121)
...
```

Option 15 = Domain Name, but
Option 119 = Domain Search


## Cloud OS - Network configuration sequence {#boot-sequence}

It is important to understanding the sequence of how the network settings for a cloud OS are setup, to understand why the problem exists and how it needs to be fixed.

During the bootup process of the Linux cloud OS for following order of operations are performed:

(boot-sequence)=
```
Proxmox cloud-init
        ↓
cloud-init inside VM
        ↓
/etc/netplan/50-cloud-init.yaml
        ↓
netplan generate
        ↓
/run/systemd/network/*.network
        ↓
systemd-networkd
````

This means:
1. Within Proxmox certain systems setting or configuration are defined within `cloud-init` section.
2. Upon start up, `cloud-init` is used to inject the various setting into the VM. This include the dynamic generation of the `/etc/netplan/50-cloud-init.yaml` file.
3. Using this file, `netplan` then dynamically generates the network configuration files. I.e. `/run/systemd/network/*.network`.
4. `systemd-networkd` used these files to configure the network interface/s. This results in `systemd-resolved` generating the `/etc/resolv.conf` file, which is actually just a symlink to `/run/systemd/resolve/stub-resolv.conf`.



The missing DNS search string issue is a result of the dynamically created file `/etc/netplan/50-cloud-init.yaml`, which is missing the directive `use-domains: true` (regardless of if static IP or DHCP is set). 

```diff
# The missing configure line in the default `/etc/netplan/50-cloud-init.yaml` file
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
-     dhcp4-overrides:
-       use-domains: true
```

This means that when the VM requests an IP address from the DHCP server, it does _**not**_ request the DNS search string to also be sent. This results in the `/etc/resolv.conf` file being populated with `search .`, and means that suffix searches are _**not**_ formed; i.e.DNS lookups of systems on the local network cannot be done using just the hostname, but require the FQDN to work.

## Attempted fixes that failed

Different fixes were attempted to alter the boot configuration processes, so that the DNS search string is requested, but only when using DHCP to obtain the IP address. These are document here to list here, as a record of what was attempted, and why it did not work:

### ❌ Altering the `/etc/netplan/50-cloud-init.yaml` file


```diff
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      match:
        macaddress: bc:24:11:aa:bb:ee
      set-name: eth0
+     dhcp4-overrides:
+       use-domains: true
```

Implementing this fix has the problem at the following levels:
1. **Inserted into the VM Template:** Changes do not survive the first boot, as the file is automatically generated.
2. **Starting the VM and altering the file:** Afterward, running `sudo netplan apply `resolve the issue and survives a reboot. But requires a manual step for each new VM.
3. **Static MAC-Address required**: When the VM starts, cloud init injects the mac-address into netplan to configure the interfaces. This configuration approach defines a fixed mac-address for the interface, which makes it useless for automation. However, when the `match` requirement is removed the interface fails to configure properly, i.e. no network connectivity.

### ❌ Disabling netplan

Creating the file `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` with contents:

```yaml
network:
  config: disabled
```
and creating file `etc/netplan/01-netcfg.yaml` with contents:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-domains: true
```

Implementing this fix has the following problems:
1. This disables netplan network configuration, which makes the use of cloud init pointless.
2. It hard codes that any new VM using this approach must use a dynamic IP.
3. When the VM boots, the network interface is not properly configured, as the mac-address is not link to the interface.
4. If the VM has multiple network interface, only the first NIC is configured.

### ❌ Creating a systemd drop-in file with dynamic reference

Creating the file `/etc/systemd/network/90-dhcp-domains.network` with contents:
```console
[Match] 
Name=* 

[Network] 
DHCP=yes 

[DHCP] 
UseDomains=yes
```

This approach does not work because:
1. Netplan dynamically generates file `/run/systemd/network/10-netplan-eth0.network` on boot, and this takes precedence over `/etc/systemd/network/90-dhcp-domains.network`. Only interface `lo` is configured with this drop-in.
2. The `eth0` interface obtains an IP Address, but does not request the DNS Search string (option 119).


### ❌ Create a netplan override

Creating a netplan override file `/etc/netplan/01-use-domains.yaml` with contents:

```yaml
network:
  version: 2
  ethernets:
    all:
      match:
        name: "*"
      dhcp4-overrides:
        use-domains: true
```
This does not work, as it cloud init encounters an error during boot. Because netplan does not support the literal `all`. The name of the interface is required, i.e. `eth0`

Instead, attempting to create the file `/etc/cloud/cloud.cfg.d/99-dhcp-domains.cfg` with contents:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-domains: true
```

This does not work, as the interface fails to configure properly:
1. Interface `ens18` is created instead of `eth0`.
2. No IP Address is assigned to the interface.




# ✅ Solution - Patch with a systemd drop-in with a static reference

Due to the startup sequence 

Create the file `/etc/systemd/network/10-netplan-eth0.network.d/10-dhcp-options.conf`, with contents:

```yaml 
# Ensure DNS search string (option 119) is used when provided
[DHCPv4]
UseDNS=yes
UseDomains=yes

[DHCPv6]
UseDNS=yes
UseDomains=yes
"
```

This can be injected into a OS image with the following code:
```console
virt-customize \ 
  -a <PATH_TO_OS_IMAGE> \ 
  --mkdir /etc/systemd/network/10-netplan-eth0.network.d \ 
  --write /etc/systemd/network/10-netplan-eth0.network.d/10-dhcp-options.conf:"# Customization - Ensure DNS search string (option 119) is requested when using DHCP 
[DHCPv4] 
UseDNS=yes 
UseDomains=yes 
#RequestOptions=119 

[DHCPv6] 
UseDNS=yes 
UseDomains=yes "
```

This fix has the following limitations:
1. This only defines a drop-in for the first network interface, i.e. `eth0`. 
2. If the VM requires multiple interface, this fix will only be applied to the first interface, and only if DHCP is use for the interface. It is will not affect any interface that use a static IP addresses.
3. If the VM fix needs to be applied to multiple interfaces, then a drop-in needs to created within each interface's configuration directory.


```console
cat /etc/resolv.conf 
sudo cat /run/systemd/network/10-netplan-eth0.network 
```

Confirming if DHCP settings are correct, by running either:

```console
# Check how the interface was configured, including drop-ins used
journalctl -u systemd-networkd | grep -i 'dhcp'

# Check whether the "search" parameter is populated instead of "."
cat /etc/resolv.conf 

# Check that the "DNS Domain" parameter is present and populated
resolvectl status

# Check that the "Search Domain" parameter is present and populated, and
# see which drop-ins were used to configure the interface
networkctl status eth0
```