#!/bin/sh

docker network create --driver bridge --gateway 172.27.0.1 --subnet 172.27.0.0/24 proxy
# docker network create --driver bridge --internal --gateway 172.27.0.1 --subnet 172.27.0.0/24 proxy
# docker network create --driver bridge --internal --gateway 172.27.0.1 --subnet 172.27.1.0/24 proxy_nointernet