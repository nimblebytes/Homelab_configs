#!/bin/sh

## Create network to proxy access to the docker socket. Has no internet access
NETWORK_NAME=socketproxy
docker network create \
  --internal \
  --subnet=172.31.0.0/24 \
  --ip-range=172.31.0.0/24 \
  --label "com.docker.compose.network=${NETWORK_NAME}" \
  --label "internal.docker.network.description=Docker socket network ${HOSTNAME:-no_hostname}" \
  ${NETWORK_NAME} 

## Create a network for security services to connect. These services need 
## Internet access (bridge network) to receive security updates or
## notifications.
NETWORK_NAME=security
docker network create \
  --driver bridge \
  --subnet=172.27.0.0/24 \
  --gateway=172.27.0.1 \
  --ip-range=172.27.0.0/24 \
  --label "com.docker.compose.network=${NETWORK_NAME}" \
  --label "internal.docker.network.description=Network for security services to exchange information (${HOSTNAME:?})" \
  ${NETWORK_NAME} 

## Create a network for services that needed to be proxied and can have 
## Internet access (bridge network) for public data retrieval. 
NETWORK_NAME=proxy
docker network create \
  --driver bridge \
  --subnet=172.27.1.0/24 \
  --gateway=172.27.1.1 \
  --ip-range=172.27.1.0/24 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=Proxy network for container services (${HOSTNAME:?})" \
  ${NETWORK_NAME}

## Create a network to connect service that needed to be proxied, but no 
## Internet access to prevent data leakage, such as fingerprinting, usage 
## stats, document processing (PII)
NETWORK_NAME=proxy_isolate
docker network create \
  --internal \
  --subnet=172.28.0.0/24 \
  --ip-range=172.28.0.0/24 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=Proxy network for container services that are isolated from the Internet (${HOSTNAME:?})" \
  ${NETWORK_NAME}

  ## How to define an address already in use. NOT for reserving an IP
  # --aux-address="DEVICE_NAME=172.27.0.2" \

NETWORK_NAME=mmgt_vlan
docker network create -d macvlan \
  --subnet=10.0.40.0/24 \
  --ip-range=10.0.40.64/27\
  --gateway=10.0.40.1 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=Management vlan network (${HOSTNAME:?})" \
  -o parent=eth0.40 \
  ${NETWORK_NAME}

NETWORK_NAME=dmz_vlan
docker network create -d macvlan \
  --subnet=10.0.31.0/24 \
  --ip-range=10.0.31.64/27 \
  --gateway=10.0.31.1 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=DMZ vlan network (${HOSTNAME:?})" \
  -o parent=eth0.31 \
  ${NETWORK_NAME} 

NETWORK_NAME=app_vlan
docker network create -d macvlan \
  --subnet=10.0.32.0/24 \
  --ip-range=10.0.32.64/27 \
  --gateway=10.0.32.1 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=App server vlan network (${HOSTNAME:?})" \
  -o parent=eth0.32 \
  ${NETWORK_NAME} 

NETWORK_NAME=iot_vlan
docker network create -d macvlan \
  --subnet=10.0.20.0/24 \
  --ip-range=10.0.20.64/27 \
  --gateway=10.0.20.1 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=IoT vlan network (${HOSTNAME:?})" \
  -o parent=eth0.20 \
  ${NETWORK_NAME}   

NETWORK_NAME=niot_vlan
docker network create -d macvlan \
  --subnet=10.0.22.0/24 \
  --ip-range=10.0.22.64/27 \
  --gateway=10.0.22.1 \
  --label "com.docker.compose.network=${NETWORK_NAME} " \
  --label "internal.docker.network.description=Isolated IoT vlan network (${HOSTNAME:?})" \
  -o parent=eth0.22 \
  ${NETWORK_NAME}   