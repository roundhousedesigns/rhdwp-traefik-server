#!/bin/bash
set -e

####
## Generates traefik.toml with correct hostname
####
parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
env_file="${parent_path}/.env"
config_file="${parent_path}/traefik.toml"
fqdn=$(hostname -f)

# Generate hostname var (overwriting)
echo "HOSTNAME=${fqdn}" > "${env_file}"

cp "${parent_path}/traefik-template.toml" "${config_file}"
sed -i "s/%%hostname%%/${fqdn}/" "${config_file}"
