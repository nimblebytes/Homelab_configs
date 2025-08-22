#!/bin/sh

NETWORK_NAME=security

## Create a network for security service to connect. Bridge network will have internet access.
docker network create \ 
  --driver bridge \ 
  --subnet=192.168.91.0/24 \ 
  --gateway=192.168.91.1 \ 
  --ip-range=192.168.91.0/24 \ 
  --label "com.docker.compose.network=${NETWORK_NAME}" \ 
  --label "internal.docker.network.description=Network for security services to exchange information (${HOSTNAME:?})" \ 
${NETWORK_NAME} 