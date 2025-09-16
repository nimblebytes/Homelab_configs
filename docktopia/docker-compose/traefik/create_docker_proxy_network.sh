#!/bin/sh

NETWORK_NAME=proxy

## Create a network to connect service that needed to be proxied. Bridge network will have internet access.
docker network create \ 
  --driver bridge \ 
  --subnet=172.27.0.0/24 \ 
  --gateway=172.27.0.1 \ 
  --ip-range=172.27.0.0/24 \ 
  # --aux-address="DEVICE_NAME=172.27.0.2" \                  ## How to define an address already in use. NOT for reserving an IP
  --label "com.docker.compose.network=${NETWORK_NAME}" \ 
  --label "internal.docker.network.description=Proxy network for container services (${HOSTNAME:?})" \ 
${NETWORK_NAME} 
