#!/bin/bash
set -e

## Debug
# set -x

# LetsEncrypt storage
acme=./traefik/acme.json
if [[ ! -f "${acme}" ]]; then
  sudo touch "${acme}"
  sudo chown www-data:www-data "${acme}"
  sudo chmod 600 "${acme}"
fi

# wp-cli permissions
sudo chown -R www-data:www-data ./wp-cli

# Generate traefik.toml
./traefik/gen.sh

# Start traefik
docker-compose -f ./traefik/docker-compose.yml up -d --remove-orphans
