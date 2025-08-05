# Immich - Additional Configuration and Specific Issues

Documentation of useful system configuration to resolve specific with Immich.


## Redis warning used by Immich

### WARNING Memory overcommit must be enabled!

> [!IMPORTANT]  
> This configuration change is not required when using the newest release of Immich, as Redis has been replaced with valkey.
> (https://github.com/immich-app/immich/pull/17396)

- Issue Ticket: (https://github.com/immich-app/immich/issues/7547)


Temporary solution until the system reboot. Also works for Docker-Rootless.
```
sudo sysctl -w vm.overcommit_memory=1
```

Permanent solution. Also works for Docker-Rootless.
```
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
## Needed for Redis container used by Immich stack
vm.overcommit_memory=1
EOF
```
