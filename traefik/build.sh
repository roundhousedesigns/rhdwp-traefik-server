#!/bin/bash

####
## Generates traefik.toml with correct hostname
####

set -e

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

cp "${parent_path}"/traefik-template.toml "${parent_path}"/traefik.toml
sed -i "s/%%hostname%%/"$(hostname -f)"/" "${parent_path}"/traefik.toml