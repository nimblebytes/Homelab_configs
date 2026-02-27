# How-to Indentify the physical network interfaces

If a computer has multiple physical network interfaces and the way that linux names and presents this information, it can be challenging to correlate the two together. 

The solution is to use `ethtool` to identify the physical network interface corresponding to a network interface name.

> [!IMPORTANT]
> - Physical Access to the machine is required
> - The phycial network interfaces must have LED indicator lights
> - Not all network card may support this this functionality

# Perparation
Installing `ethtool` on a debian system with:

```console
apt install ethtool
```

Find all the network interfaces present on the host with the following command:
```console
ip a
```

# Identification process

Executing `ethtool` will make the LED light on the physical network interface blink, until stopped by pressing `<CTRL> + C`. 

Example using the `eth0` network interface name:
```console
ethtool --identify eth0
```

## Additional Interface information

To get more information about the hardware capabilities of the network interface, than `ip a eth0` provides, run:
```console
ethtool eth0
```

Example output:
```
Settings for eth0:
    Supported ports: [ FIBRE ]
    Supported link modes:   1000baseT/Full
                            10000baseT/Full
    Supported pause frame use: Symmetric Receive-only
    Supports auto-negotiation: No
    Supported FEC modes: None
    Advertised link modes:  10000baseT/Full
    Advertised pause frame use: Symmetric
    Advertised auto-negotiation: No
    Advertised FEC modes: None
    Link partner advertised link modes:  Not reported
    Link partner advertised pause frame use: Symmetric
    Link partner advertised auto-negotiation: No
    Link partner advertised FEC modes: None
    Speed: 10000Mb/s
    Duplex: Full
    Auto-negotiation: off
    Port: Direct Attach Copper
    PHYAD: 255
    Transceiver: internal
        Current message level: 0x000000ff (255)
                               drv probe link timer ifdown ifup rx_err tx_err
    Link detected: yes
```
