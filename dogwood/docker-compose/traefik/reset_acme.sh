#!/bin/sh
set -x

echo $DOCKER_VOLUMES

rm ${DOCKER_VOLUMES:?}/traefik_proxy/acme/acme.json
touch ${DOCKER_VOLUMES:?}/traefik_proxy/acme/acme.json
chmod 600 ${DOCKER_VOLUMES:?}/traefik_proxy/acme/acme.json

