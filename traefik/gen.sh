#!/bin/bash

####
## Generates traefik.toml with correct hostname
####

set -e

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
env_file="${parent_path}"/.env
config_file="${parent_path}"/traefik.toml

# Generate hostname var (overwriting)
echo "HOSTNAME=$(hostname -f)" > "${env_file}"

cp "${parent_path}"/traefik-template.toml "${config_file}"
sed -i "s/%%hostname%%/"$(hostname -f)"/" "${config_file}"