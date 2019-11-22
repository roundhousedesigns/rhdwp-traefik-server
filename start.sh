#!/bin/bash

set -x

# export HOSTNAME
export HOSTNAME=$(hostname)

# LetsEncrypt storage
acme=./traefik/acme.json
if [[ ! -f "${acme}" ]]; then
  sudo touch "${acme}"
  sudo chown www-data:www-data "${acme}"
  sudo chmod 600 "${acme}"
fi

# Generate traefik.toml
./traefik/build.sh

# Start traefik
docker-compose -f ./traefik/docker-compose.yml up -d --remove-orphans
