#!/bin/bash
set -e

####
## Generates traefik.toml with correct hostname
####
HOSTNAME=$(hostname)
export HOSTNAME

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
config_file="${parent_path}/traefik.toml"

cp "${parent_path}/traefik-template.toml" "$config_file"
sed -i "s/%%domain%%/$(hostname -f)/" "$config_file"
