# Traefik - Additional Configuration and Specific Issues

Documentation of useful system configuration to resolve specific with Traefic.


## Traefik Errors

### Cannot start the provider *file.Provider error="error adding file watcher: no space left on device"

The error is a result of the inofity limits being reached and **not** as a result for folder/drive being full. (https://github.com/traefik/traefik/issues/11396#top)

Container specific solution. Add the following to the traefik compose file.
```
services:
  traefik:
    image: traefik:latest
+    sysctls:
+      - fs.inotify.max_user_watches=131072
```

Temporary solution until the system reboot. Also works for Docker-Rootless.
```
sudo sysctl -w fs.inotify.max_user_watches=131072
```

Permanent solution. Also works for Docker-Rootless.
```
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
## Increase inofity limits, to prevent the error in Traefik: "error adding file watcher: no space left on device"
fs.inotify.max_user_watches=131072
EOF
```
