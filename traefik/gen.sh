#!/bin/bash
set -e

####
## Generates traefik.toml with correct hostname
####
HOSTNAME=$(hostname)
export HOSTNAME

traefik_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
config_file="${traefik_path}/docker-compose.yml"

cp "${traefik_path}/docker-compose-template.yml" "$config_file"
sed -i "s/%%domain%%/$(hostname -f)/" "$config_file"
