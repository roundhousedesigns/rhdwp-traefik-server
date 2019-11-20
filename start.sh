#!/bin/bash

# LetsEncrypt storage
acme=./traefik/acme.json
if [[ ! -f "${acme}" ]]; then
  sudo touch "${acme}"
  sudo chown www-data:www-data "${acme}"
  sudo chmod 600 "${acme}"
fi

# Start traefik
docker-compose -f ./traefik/docker-compose.yml up -d --remove-orphans