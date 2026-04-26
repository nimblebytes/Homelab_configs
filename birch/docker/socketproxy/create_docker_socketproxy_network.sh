#!/bin/sh

NETWORK_NAME=socketproxy

## Create a network with no internet access, where access to the docker socket is proxied
# docker network create --internal --subnet 172.31.0.0/24 ${NETWORK_NAME} --label "com.docker.compose.network=${NETWORK_NAME}"
docker network create \ 
  --internal \ 
  --subnet=172.31.0.0/24 \ 
  --ip-range=172.31.0.0/24 \                                
  # --aux-address="RESERVED_01=172.31.0.2" \                  ## How to reserve an address
  --label "com.docker.compose.network=${NETWORK_NAME}" \ 
  --label "internal.docker.network.description=Docker socket network ${HOSTNAME:-no_hostname}"
  ${NETWORK_NAME} 