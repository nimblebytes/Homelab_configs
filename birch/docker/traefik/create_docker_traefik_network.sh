#!/bin/sh

docker network create --gateway 192.168.90.1 --subnet 192.168.90.0/24 traefik_net