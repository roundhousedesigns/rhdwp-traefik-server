#!/bin/bash

# Create acme.json for LetsEncrypt storage
sudo touch traefik/acme.json
sudo chown www-data:www-data traefik/acme.json
sudo chmod 600 traefik/acme.json

# Die, and kill yourself
rm "$0"